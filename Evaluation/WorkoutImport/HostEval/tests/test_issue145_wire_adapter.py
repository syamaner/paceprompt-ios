"""Offline one-send adapter checks; no provider or credential lookup."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest

import httpx2

from paceprompt_eval.issue145_wire_adapter import OpenRouterOneSend, WireRouteBinding
from paceprompt_eval.issue145_retry import RetryPolicy
from paceprompt_eval.issue145_retry_execution import RetryingWireExecutor
from paceprompt_eval.openrouter import OPENROUTER_URL


BODY = b'{"model":"synthetic/model","provider":{"order":["synthetic-route"]}}'
REQUEST_SHA = hashlib.sha256(BODY).hexdigest()
BINDING = WireRouteBinding(
    REQUEST_SHA, "synthetic/model", "synthetic/model-revision", "synthetic-route", "Synthetic",
)
KEY = "synthetic-mock-token"


class OpenRouterOneSendTests(unittest.IsolatedAsyncioTestCase):
    def adapter(self, handler: httpx2.MockTransport) -> OpenRouterOneSend:
        return OpenRouterOneSend(
            bindings={"position-1": BINDING}, api_key=KEY,
            timeout=httpx2.Timeout(3.0, connect=1.0), transport=handler,
        )

    async def test_exactly_one_send_preserves_bytes_headers_and_route_identity(self) -> None:
        requests: list[httpx2.Request] = []

        def handle(request: httpx2.Request) -> httpx2.Response:
            requests.append(request)
            return httpx2.Response(
                429,
                headers=[("Retry-After", "12"), ("Retry-After", "20")],
                json={"model": "synthetic/model-revision", "provider": "Synthetic"},
            )

        result = await self.adapter(httpx2.MockTransport(handle)).send_once(
            "position-1", "position-1--wire-01", BODY,
        )
        self.assertEqual(len(requests), 1)
        self.assertEqual(str(requests[0].url), OPENROUTER_URL)
        self.assertEqual(requests[0].content, BODY)
        self.assertEqual(requests[0].headers["authorization"], f"Bearer {KEY}")
        self.assertEqual(result.status_code, 429)
        self.assertEqual([value for key, value in result.header_pairs if key == "retry-after"],
                         ["12", "20"])
        self.assertTrue(result.returned_route_matches)
        self.assertEqual(result.request_sha256, REQUEST_SHA)
        self.assertIsNone(result.reported_cost_usd)
        self.assertNotIn(KEY, json.dumps(result.evidence))

    async def test_wrong_route_and_missing_identity_fail_closed(self) -> None:
        for body in ({"model": "synthetic/model", "provider": "other"},
                     {"model": "synthetic/model"}):
            with self.subTest(body=body):
                adapter = self.adapter(httpx2.MockTransport(
                    lambda _request: httpx2.Response(200, json=body),
                ))
                result = await adapter.send_once("position-1", "position-1--wire-01", BODY)
                self.assertFalse(result.returned_route_matches)

    async def test_changed_body_and_unknown_position_cannot_reach_transport(self) -> None:
        calls = 0

        def handle(_request: httpx2.Request) -> httpx2.Response:
            nonlocal calls
            calls += 1
            return httpx2.Response(200)

        adapter = self.adapter(httpx2.MockTransport(handle))
        with self.assertRaisesRegex(ValueError, "request bytes changed"):
            await adapter.send_once("position-1", "position-1--wire-01", BODY + b" ")
        with self.assertRaisesRegex(ValueError, "bound logical position"):
            await adapter.send_once("other", "other--wire-01", BODY)
        self.assertEqual(calls, 0)

    async def test_transport_failure_does_not_retry(self) -> None:
        calls = 0

        def handle(_request: httpx2.Request) -> httpx2.Response:
            nonlocal calls
            calls += 1
            raise httpx2.ConnectError("synthetic connection failure")

        adapter = self.adapter(httpx2.MockTransport(handle))
        with self.assertRaises(httpx2.ConnectError):
            await adapter.send_once("position-1", "position-1--wire-01", BODY)
        self.assertEqual(calls, 1)

    async def test_executor_retries_only_complete_transient_response(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "synthetic-run"
            run_dir.mkdir()
            calls = 0

            def handle(_request: httpx2.Request) -> httpx2.Response:
                nonlocal calls
                calls += 1
                if calls == 1:
                    return httpx2.Response(429, headers={"Retry-After": "4"},
                                           json={"synthetic": "transient"})
                return httpx2.Response(200, json={
                    "model": "synthetic/model-revision", "provider": "Synthetic",
                })

            adapter = self.adapter(httpx2.MockTransport(handle))
            waits: list[int] = []

            async def sleep(seconds: int) -> None:
                waits.append(seconds)

            executor = RetryingWireExecutor(
                run_dir=run_dir, evidence_root=run_dir.parent,
                profile_sha256="a" * 64, planned_position_ids=("position-1",),
                hard_limit_usd="0.03",
                policy=RetryPolicy(3, frozenset({429, 502, 503, 504, 524, 529}),
                                   (30, 120), 900, 900),
                send_once=adapter.send_once, redact_evidence=lambda item: item,
                sleep=sleep, now=lambda: datetime(2026, 9, 23, tzinfo=timezone.utc),
            )
            result = await executor.run_position(
                logical_id="position-1", request_body=BODY, worst_case_usd="0.01",
            )
            self.assertEqual(result["state"], "terminalComplete")
            self.assertEqual(calls, 2)
            self.assertEqual(waits, [30])
            self.assertEqual([wire["wireID"] for wire in result["wires"]], [
                "position-1--wire-01", "position-1--wire-02",
            ])
            self.assertNotIn(KEY, (run_dir / "wire-ledger.json").read_text())


if __name__ == "__main__":
    unittest.main()
