"""One physical OpenRouter send for the unwired issue #145 retry journal.

The caller supplies a credential and independently sealed per-position request
hashes and route pins. This module has no environment lookup or live entrypoint.
Retries, budget admission, pacing and evidence persistence belong to the
application-layer executor and its separately authorised caller.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re
from typing import Any, Mapping

import httpx2

from .issue145_retry_execution import WireResponse
from .openrouter import OPENROUTER_URL


_SHA = re.compile(r"[0-9a-f]{64}\Z")
_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,179}\Z")


@dataclass(frozen=True)
class WireRouteBinding:
    request_sha256: str
    requested_model_id: str
    canonical_revision: str
    provider_endpoint: str
    reported_provider_name: str

    def __post_init__(self) -> None:
        if not isinstance(self.request_sha256, str) or not _SHA.fullmatch(self.request_sha256):
            raise ValueError("an exact request SHA-256 is required")
        if any(not isinstance(value, str) or not value for value in (
            self.requested_model_id, self.canonical_revision,
            self.provider_endpoint, self.reported_provider_name,
        )):
            raise ValueError("exact model and provider route pins are required")


class OpenRouterOneSend:
    """Send exactly one immutable body; never retry, redirect or choose a route."""

    def __init__(
        self,
        *,
        bindings: Mapping[str, WireRouteBinding],
        api_key: str,
        timeout: httpx2.Timeout,
        transport: httpx2.AsyncBaseTransport | None = None,
    ) -> None:
        if not bindings or any(
            not isinstance(logical_id, str) or not _ID.fullmatch(logical_id)
            or not isinstance(binding, WireRouteBinding)
            for logical_id, binding in bindings.items()
        ):
            raise ValueError("non-empty exact logical position bindings are required")
        if not isinstance(api_key, str) or not api_key or "\r" in api_key or "\n" in api_key:
            raise ValueError("a process-supplied credential is required")
        if not isinstance(timeout, httpx2.Timeout):
            raise ValueError("an explicitly selected HTTP timeout is required")
        self.bindings = dict(bindings)
        self.api_key = api_key
        self.timeout = timeout
        self.transport = transport

    async def send_once(self, logical_id: str, wire_id: str, request_body: bytes) -> WireResponse:
        binding = self.bindings.get(logical_id)
        if binding is None or not isinstance(wire_id, str) or not re.fullmatch(
            re.escape(logical_id) + r"--wire-[0-9]{2}", wire_id
        ):
            raise ValueError("physical send is outside the bound logical position")
        if not isinstance(request_body, bytes) or hashlib.sha256(request_body).hexdigest() != binding.request_sha256:
            raise ValueError("physical send request bytes changed")
        async with httpx2.AsyncClient(
            timeout=self.timeout,
            transport=self.transport or httpx2.AsyncHTTPTransport(retries=0),
            follow_redirects=False,
            trust_env=False,
        ) as client:
            response = await client.post(
                OPENROUTER_URL,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                content=request_body,
            )
            raw = await response.aread()
            header_pairs = tuple(response.headers.multi_items())
            try:
                decoded: Any = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                decoded = {"undecodableUtf8ByteCount": len(raw)}
            body = decoded if isinstance(decoded, dict) else {"nonObjectBody": decoded}
            matching = (
                body.get("model") in {binding.requested_model_id, binding.canonical_revision}
                and body.get("provider") in {binding.provider_endpoint, binding.reported_provider_name}
            )
            return WireResponse(
                status_code=response.status_code,
                header_pairs=header_pairs,
                request_sha256=binding.request_sha256,
                evidence={"logicalID": logical_id, "wireID": wire_id, "body": body},
                # A missing or unverified usage cost remains conservatively charged
                # at the executor's per-send worst-case reservation.
                reported_cost_usd=None,
                returned_route_matches=matching,
            )
