"""Durable, zero-spend-testable physical-send orchestration for issue #145.

This is an application-layer component, not a live authorization entrypoint.
The caller supplies a separately gated one-send provider adapter, exact queue,
request hash, USD bound, redactor, clock and sleeper. No credential is read here.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Any, Awaitable, Callable

from .issue145_lineage import usd
from .issue145_retry import RetryPolicy, decide_retry, reserve_wire_send
from .v3 import sha256_file, strict_json_load


_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,179}\Z")
_SHA = re.compile(r"[0-9a-f]{64}\Z")
_R3_POLICY = RetryPolicy(3, frozenset({429, 502, 503, 504, 524, 529}), (30, 120), 900, 900)
_WIRE_STATES = frozenset({
    "possiblySent", "ambiguousFailure", "contractFailure", "costContractFailure",
    "noCompleteHTTPResponse", "completeHTTPResponse", "returnedRouteMismatch",
    "ambiguousResponseHeaders",
})
_POSITION_STATES = frozenset({
    "inProgress", "terminalPossiblySent", "terminalBudgetStop",
    "terminalComplete", "terminalFailure",
})


@dataclass(frozen=True)
class WireResponse:
    """One physical response, or an unambiguous lack of complete response."""

    status_code: int | None
    header_pairs: tuple[tuple[str, str], ...] | None
    request_sha256: str
    evidence: dict[str, Any]
    reported_cost_usd: str | None = None
    returned_route_matches: bool | None = None


def _atomic_json(path: Path, value: dict[str, Any]) -> None:
    """Persist a journal transition before a send or before the next send."""
    encoded = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class RetryingWireExecutor:
    """Run each frozen logical position with bounded visible physical sends.

    A journal entry is charged at worst case and marked possibly-sent before
    invoking `send_once`. Any interruption leaves that position unreplayable.
    A fresh instance may audit the ledger, but cannot resume this run in place.
    """

    def __init__(
        self,
        *,
        run_dir: Path,
        profile_sha256: str,
        planned_position_ids: tuple[str, ...],
        hard_limit_usd: str,
        policy: RetryPolicy,
        send_once: Callable[[str, str, bytes], Awaitable[WireResponse]],
        redact_evidence: Callable[[dict[str, Any]], dict[str, Any]],
        sleep: Callable[[int], Awaitable[None]],
        now: Callable[[], datetime],
    ) -> None:
        if not _SHA.fullmatch(profile_sha256):
            raise ValueError("an exact profile SHA-256 is required")
        if not planned_position_ids or len(set(planned_position_ids)) != len(planned_position_ids):
            raise ValueError("the frozen logical queue is empty or duplicated")
        if any(not _ID.fullmatch(item) for item in planned_position_ids):
            raise ValueError("a logical position ID is unsafe")
        if usd(hard_limit_usd) <= 0:
            raise ValueError("a positive finite USD limit is required")
        if policy != _R3_POLICY:
            raise ValueError("the issue #145 r3 retry policy is required")
        if not run_dir.is_dir() or (run_dir / "wire-ledger.json").exists():
            raise ValueError("a fresh existing run directory is required")
        evidence_dir = run_dir / "wire-evidence"
        evidence_dir.mkdir(exist_ok=False)
        self.run_dir = run_dir
        self.ledger_path = run_dir / "wire-ledger.json"
        self.evidence_dir = evidence_dir
        self.policy = policy
        self.send_once = send_once
        self.redact_evidence = redact_evidence
        self.sleep = sleep
        self.now = now
        self.ledger: dict[str, Any] = {
            "contractVersion": "paceprompt-host-eval-wire-ledger/issue145-r1",
            "runID": run_dir.name,
            "profileSha256": profile_sha256,
            "plannedPositionIDs": list(planned_position_ids),
            "hardLimitUSD": hard_limit_usd,
            "chargedUSD": "0",
            "positions": [],
        }
        _atomic_json(self.ledger_path, self.ledger)

    def _persist(self) -> None:
        _atomic_json(self.ledger_path, self.ledger)

    async def run_position(
        self, *, logical_id: str, request_body: bytes, worst_case_usd: str
    ) -> dict[str, Any]:
        positions = self.ledger["positions"]
        planned = self.ledger["plannedPositionIDs"]
        if len(positions) >= len(planned) or logical_id != planned[len(positions)]:
            raise ValueError("logical position is not the next frozen queue entry")
        if any(item["state"] == "inProgress" for item in positions):
            raise ValueError("another logical position remains in progress")
        if not isinstance(request_body, bytes) or not request_body:
            raise ValueError("a non-empty immutable request body is required")
        request_sha256 = hashlib.sha256(request_body).hexdigest()
        if usd(worst_case_usd) <= 0:
            raise ValueError("a positive per-send bound is required")
        # No journal position is created when the first send cannot be funded.
        reserve_wire_send(
            hard_limit_usd=self.ledger["hardLimitUSD"],
            charged_usd=self.ledger["chargedUSD"],
            reserved_usd="0",
            worst_case_usd=worst_case_usd,
        )
        position: dict[str, Any] = {
            "logicalID": logical_id,
            "requestSha256": request_sha256,
            "state": "inProgress",
            "wires": [],
        }
        positions.append(position)
        self._persist()
        waited = 0
        try:
            for number in range(1, self.policy.max_sends_per_position + 1):
                try:
                    reserve_wire_send(
                        hard_limit_usd=self.ledger["hardLimitUSD"],
                        charged_usd=self.ledger["chargedUSD"],
                        reserved_usd="0",
                        worst_case_usd=worst_case_usd,
                    )
                except ValueError:
                    position["state"] = "terminalBudgetStop"
                    self._persist()
                    return position
                wire_id = f"{logical_id}--wire-{number:02d}"
                wire: dict[str, Any] = {
                    "wireID": wire_id,
                    "state": "possiblySent",
                    "reservedWorstCaseUSD": worst_case_usd,
                    "chargedUSD": worst_case_usd,
                    "requestSha256": request_sha256,
                }
                position["wires"].append(wire)
                self.ledger["chargedUSD"] = format(
                    usd(self.ledger["chargedUSD"]) + usd(worst_case_usd), "f"
                )
                self._persist()
                try:
                    response = await self.send_once(logical_id, wire_id, request_body)
                except asyncio.CancelledError:
                    raise
                except BaseException as error:
                    wire["state"] = "ambiguousFailure"
                    wire["exceptionType"] = type(error).__name__
                    position["state"] = "terminalPossiblySent"
                    self._persist()
                    return position
                if not isinstance(response, WireResponse):
                    wire["state"] = "ambiguousFailure"
                    wire["exceptionType"] = "InvalidWireResponse"
                    position["state"] = "terminalPossiblySent"
                    self._persist()
                    return position

                raw_evidence = dict(response.evidence)
                raw_evidence["responseHeaders"] = (
                    [{key: value} for key, value in response.header_pairs]
                    if response.header_pairs is not None else None
                )
                evidence = self.redact_evidence(raw_evidence)
                if not isinstance(evidence, dict) or "responseHeaders" not in evidence:
                    raise ValueError("wire evidence redactor must preserve redacted response headers")
                evidence_path = self.evidence_dir / f"{wire_id}.json"
                _atomic_json(evidence_path, evidence)
                wire["evidenceSha256"] = sha256_file(evidence_path)
                wire["statusCode"] = response.status_code
                complete = response.status_code is not None and response.header_pairs is not None
                if (
                    response.request_sha256 != request_sha256
                    or (complete and type(response.status_code) is not int)
                ):
                    wire["state"] = "contractFailure"
                    position["state"] = "terminalFailure"
                    self._persist()
                    return position
                if not complete:
                    wire["state"] = "noCompleteHTTPResponse"
                    position["state"] = "terminalPossiblySent"
                    self._persist()
                    return position
                if response.reported_cost_usd is not None:
                    actual = usd(response.reported_cost_usd)
                    if actual > usd(worst_case_usd):
                        wire["state"] = "costContractFailure"
                        position["state"] = "terminalFailure"
                        self._persist()
                        return position
                    self.ledger["chargedUSD"] = format(
                        usd(self.ledger["chargedUSD"]) - usd(worst_case_usd) + actual,
                        "f",
                    )
                    wire["chargedUSD"] = format(actual, "f")
                    wire["reportedCostUSD"] = format(actual, "f")
                wire["state"] = "completeHTTPResponse"
                if 200 <= response.status_code < 300 and response.returned_route_matches is not True:
                    wire["state"] = "returnedRouteMismatch"
                    position["state"] = "terminalFailure"
                    self._persist()
                    return position
                headers: dict[str, str] = {}
                for key, value in response.header_pairs:
                    folded = key.casefold()
                    if folded in headers:
                        wire["state"] = "ambiguousResponseHeaders"
                        position["state"] = "terminalFailure"
                        self._persist()
                        return position
                    headers[folded] = value
                decision = decide_retry(
                    self.policy,
                    status_code=response.status_code,
                    response_headers=headers,
                    completed_sends=number,
                    cumulative_wait_seconds=waited,
                    received_at=self.now(),
                )
                wire["retryDecision"] = {
                    "retry": decision.retry,
                    "waitSeconds": decision.wait_seconds,
                    "reason": decision.reason,
                    "headerSource": decision.header_source,
                }
                if not decision.retry:
                    position["state"] = (
                        "terminalComplete" if 200 <= response.status_code < 300
                        else "terminalFailure"
                    )
                    self._persist()
                    return position
                self._persist()
                await self.sleep(decision.wait_seconds or 0)
                waited += decision.wait_seconds or 0
        except asyncio.CancelledError:
            position["state"] = "terminalPossiblySent"
            self._persist()
            raise
        except BaseException:
            position["state"] = "terminalPossiblySent"
            self._persist()
            raise
        raise AssertionError("retry policy send bound was bypassed")

    def lineage_attempts(self) -> list[dict[str, Any]]:
        """Project one logical record per position for a verified child plan."""
        attempts = []
        for logical_id in self.ledger["plannedPositionIDs"]:
            position = next(
                (item for item in self.ledger["positions"] if item["logicalID"] == logical_id),
                None,
            )
            if position is None:
                attempts.append({"attemptID": logical_id, "state": "notStarted",
                                 "reservedWorstCaseUSD": None, "actualUSD": None})
                continue
            wires = position["wires"]
            worst = sum((usd(item["reservedWorstCaseUSD"]) for item in wires), usd("0"))
            known = all("reportedCostUSD" in item for item in wires)
            attempts.append({
                "attemptID": logical_id,
                "state": (
                    "possiblySent" if position["state"] in {"inProgress", "terminalPossiblySent"}
                    else "completed" if position["state"] == "terminalComplete"
                    else "failed"
                ),
                "reservedWorstCaseUSD": format(worst, "f"),
                "actualUSD": (
                    format(sum((usd(item["chargedUSD"]) for item in wires), usd("0")), "f")
                    if known and wires else None
                ),
            })
        return attempts


def verify_wire_ledger(run_dir: Path, *, profile_sha256: str) -> dict[str, Any]:
    """Audit immutable evidence without permitting an in-place restart."""
    ledger = strict_json_load(run_dir / "wire-ledger.json")
    errors: list[str] = []
    if ledger.get("contractVersion") != "paceprompt-host-eval-wire-ledger/issue145-r1":
        errors.append("ledger contract changed")
    if ledger.get("profileSha256") != profile_sha256:
        errors.append("profile changed")
    if ledger.get("runID") != run_dir.name:
        errors.append("run ID changed")
    planned = ledger.get("plannedPositionIDs")
    if (
        not isinstance(planned, list)
        or not planned
        or any(not isinstance(item, str) or not _ID.fullmatch(item) for item in planned)
        or len(set(planned)) != len(planned)
    ):
        errors.append("frozen queue invalid")
        planned = []
    positions = ledger.get("positions")
    if not isinstance(positions, list) or len(positions) > len(planned):
        errors.append("position list invalid")
        positions = []
    charged = usd("0")
    for index, position in enumerate(positions):
        if not isinstance(position, dict) or position.get("logicalID") != planned[index]:
            errors.append(f"position order invalid: {index}")
            continue
        if position.get("state") not in _POSITION_STATES:
            errors.append(f"position state invalid: {index}")
        wires = position.get("wires")
        if not isinstance(wires, list) or len(wires) > 3:
            errors.append(f"wire list invalid: {index}")
            continue
        if not wires and position.get("state") != "terminalBudgetStop":
            errors.append(f"unsent position state invalid: {index}")
        for number, wire in enumerate(wires, start=1):
            if not isinstance(wire, dict):
                errors.append(f"wire invalid: {index}/{number}")
                continue
            expected_id = f"{planned[index]}--wire-{number:02d}"
            if wire.get("wireID") != expected_id or wire.get("requestSha256") != position.get("requestSha256"):
                errors.append(f"wire identity invalid: {index}/{number}")
            if wire.get("state") not in _WIRE_STATES:
                errors.append(f"wire state invalid: {expected_id}")
            if not isinstance(position.get("requestSha256"), str) or not _SHA.fullmatch(position["requestSha256"]):
                errors.append(f"request hash invalid: {index}")
            try:
                worst = usd(wire["reservedWorstCaseUSD"])
                charge = usd(wire["chargedUSD"])
                if worst <= 0 or charge > worst:
                    errors.append(f"wire charge invalid: {expected_id}")
                if "reportedCostUSD" in wire and usd(wire["reportedCostUSD"]) != charge:
                    errors.append(f"reported charge changed: {expected_id}")
                charged += charge
            except (KeyError, ValueError, TypeError):
                errors.append(f"wire charge malformed: {expected_id}")
            evidence_sha = wire.get("evidenceSha256")
            if evidence_sha is not None:
                path = run_dir / "wire-evidence" / f"{expected_id}.json"
                if not _SHA.fullmatch(str(evidence_sha)) or not path.is_file() or sha256_file(path) != evidence_sha:
                    errors.append(f"wire evidence changed: {expected_id}")
            elif wire.get("state") not in {"possiblySent", "ambiguousFailure"}:
                errors.append(f"completed wire lacks evidence: {expected_id}")
    try:
        accounting_invalid = charged != usd(ledger.get("chargedUSD")) or charged > usd(ledger.get("hardLimitUSD"))
    except (ValueError, TypeError):
        accounting_invalid = True
    if accounting_invalid:
        errors.append("ledger charge or hard limit changed")
    return {"status": "valid" if not errors else "invalid", "errors": errors}
