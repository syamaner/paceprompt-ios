"""Synthetic, offline contract tests for durable issue #145 physical sends."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from paceprompt_eval.issue145_retry import RetryPolicy
from paceprompt_eval.issue145_lineage import admit_child
from paceprompt_eval.issue145_retry_execution import (
    RetryingWireExecutor, WireResponse, verify_wire_ledger,
)


PROFILE = "a" * 64
BODY = b'{"synthetic":"fixed-request"}'
REQUEST = hashlib.sha256(BODY).hexdigest()
NOW = datetime(2026, 9, 23, 12, tzinfo=timezone.utc)


class RetryingWireExecutorTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.run_dir = Path(self.temporary.name) / "synthetic-run"
        self.run_dir.mkdir()
        self.calls: list[tuple[str, str]] = []
        self.waits: list[int] = []
        self.responses: list[WireResponse] = []
        self.policy = RetryPolicy(
            3, frozenset({429, 502, 503, 504, 524, 529}), (30, 120), 900, 900,
        )

    async def send(self, logical_id: str, wire_id: str, body: bytes) -> WireResponse:
        self.assertIs(body, BODY)
        self.calls.append((logical_id, wire_id))
        return self.responses.pop(0)

    async def sleep(self, seconds: int) -> None:
        self.waits.append(seconds)

    def executor(self, cap: str = "0.03", ids: tuple[str, ...] = ("one", "two")) -> RetryingWireExecutor:
        return RetryingWireExecutor(
            run_dir=self.run_dir, profile_sha256=PROFILE,
            planned_position_ids=ids, hard_limit_usd=cap, policy=self.policy,
            send_once=self.send, redact_evidence=lambda item: dict(item),
            sleep=self.sleep, now=lambda: NOW,
        )

    @staticmethod
    def response(status: int | None, headers: tuple[tuple[str, str], ...] | None = ()) -> WireResponse:
        return WireResponse(status, headers, REQUEST, {"synthetic": True},
                            "0.005", status == 200)

    async def test_complete_transient_response_retries_with_visible_wires(self) -> None:
        self.responses = [
            self.response(429, (("Retry-After", "45"),)),
            self.response(200),
        ]
        executor = self.executor()
        position = await executor.run_position(
            logical_id="one", request_body=BODY, worst_case_usd="0.01",
        )
        self.assertEqual(position["state"], "terminalComplete")
        self.assertEqual(self.waits, [45])
        self.assertEqual(self.calls, [("one", "one--wire-01"), ("one", "one--wire-02")])
        self.assertEqual(executor.ledger["chargedUSD"], "0.010")
        self.assertEqual(len(position["wires"]), 2)
        self.assertEqual(position["wires"][0]["retryDecision"]["headerSource"], "Retry-After")
        first_evidence = json.loads((self.run_dir / "wire-evidence" / "one--wire-01.json").read_text())
        self.assertEqual(first_evidence["responseHeaders"], [["Retry-After", "45"]])
        self.assertEqual(verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)["status"], "valid")
        self.assertEqual(executor.lineage_attempts()[0]["actualUSD"], "0.010")
        self.assertEqual(executor.lineage_attempts()[1]["state"], "notStarted")

    async def test_budget_exhaustion_prevents_a_first_send_or_a_retry(self) -> None:
        executor = self.executor(cap="0.009")
        with self.assertRaisesRegex(ValueError, "hard limit"):
            await executor.run_position(logical_id="one", request_body=BODY,
                                        worst_case_usd="0.01")
        self.assertEqual(executor.ledger["positions"], [])
        self.assertEqual(self.calls, [])
        self.assertEqual(executor.lineage_attempts()[0]["state"], "notStarted")

        # A separate fresh run can fund one send but not its retry.
        self.run_dir = Path(self.temporary.name) / "second-run"
        self.run_dir.mkdir()
        self.responses = [self.response(429)]
        executor = self.executor(cap="0.01")
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["state"], "terminalBudgetStop")
        self.assertEqual(len(position["wires"]), 1)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.waits, [30])
        self.assertEqual(verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)["status"], "valid")

    async def test_ambiguous_send_is_never_retried_and_is_conservatively_charged(self) -> None:
        async def ambiguous(_logical: str, _wire: str, _body: bytes) -> WireResponse:
            self.calls.append((_logical, _wire))
            raise TimeoutError("synthetic timeout")

        executor = self.executor()
        executor.send_once = ambiguous
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["state"], "terminalPossiblySent")
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.waits, [])
        self.assertEqual(executor.lineage_attempts()[0]["state"], "possiblySent")
        self.assertIsNone(executor.lineage_attempts()[0]["actualUSD"])
        self.assertEqual(executor.ledger["chargedUSD"], "0.01")
        self.assertEqual(verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)["status"], "valid")

    async def test_malformed_retry_header_and_wrong_route_stop_closed(self) -> None:
        self.responses = [self.response(429, (("Retry-After", "1"), ("retry-after", "2")))]
        executor = self.executor()
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["wires"][0]["state"], "ambiguousResponseHeaders")
        self.assertEqual(position["state"], "terminalFailure")
        self.assertEqual(self.waits, [])

        self.run_dir = Path(self.temporary.name) / "third-run"
        self.run_dir.mkdir()
        self.responses = [WireResponse(200, (), REQUEST, {"synthetic": True},
                                       "0.005", False)]
        executor = self.executor()
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["wires"][0]["state"], "returnedRouteMismatch")
        self.assertEqual(len(self.calls), 2)

    async def test_evidence_tampering_and_replay_are_rejected(self) -> None:
        self.responses = [self.response(200)]
        executor = self.executor()
        await executor.run_position(logical_id="one", request_body=BODY,
                                    worst_case_usd="0.01")
        with self.assertRaisesRegex(ValueError, "next frozen"):
            await executor.run_position(logical_id="one", request_body=BODY,
                                        worst_case_usd="0.01")
        path = self.run_dir / "wire-evidence" / "one--wire-01.json"
        path.write_text(json.dumps({"synthetic": False}), encoding="utf-8")
        report = verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)
        self.assertEqual(report["status"], "invalid")
        self.assertTrue(any("evidence changed" in item for item in report["errors"]))

    async def test_no_complete_response_and_cancelled_send_never_retry(self) -> None:
        self.responses = [self.response(None, None)]
        executor = self.executor()
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["state"], "terminalPossiblySent")
        self.assertEqual(self.calls, [("one", "one--wire-01")])
        self.assertEqual(self.waits, [])

        self.run_dir = Path(self.temporary.name) / "cancelled-run"
        self.run_dir.mkdir()
        executor = self.executor()

        async def cancelled(_logical: str, _wire: str, _body: bytes) -> WireResponse:
            raise asyncio.CancelledError()

        executor.send_once = cancelled
        with self.assertRaises(asyncio.CancelledError):
            await executor.run_position(logical_id="one", request_body=BODY,
                                        worst_case_usd="0.01")
        self.assertEqual(executor.lineage_attempts()[0]["state"], "possiblySent")
        self.assertEqual(executor.ledger["chargedUSD"], "0.01")
        self.assertEqual(verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)["status"], "valid")

    async def test_third_transient_response_exhausts_send_limit(self) -> None:
        self.responses = [self.response(503), self.response(429), self.response(529)]
        executor = self.executor(cap="0.06")
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["state"], "terminalFailure")
        self.assertEqual(self.waits, [30, 120])
        self.assertEqual(len(position["wires"]), 3)
        self.assertEqual(position["wires"][-1]["retryDecision"]["reason"], "sendLimitReached")

    async def test_adapter_request_hash_mismatch_stops_without_retry(self) -> None:
        self.responses = [WireResponse(429, (), "c" * 64, {"synthetic": True},
                                       "0.005", None)]
        executor = self.executor()
        position = await executor.run_position(logical_id="one", request_body=BODY,
                                               worst_case_usd="0.01")
        self.assertEqual(position["state"], "terminalFailure")
        self.assertEqual(position["wires"][0]["state"], "contractFailure")
        self.assertEqual(self.waits, [])
        self.assertEqual(executor.ledger["chargedUSD"], "0.01")

    async def test_redaction_failure_leaves_conservative_nonreplayable_send(self) -> None:
        self.responses = [self.response(429, (("Retry-After", "30"),))]
        executor = self.executor()
        executor.redact_evidence = lambda _item: {"synthetic": True}
        with self.assertRaisesRegex(ValueError, "redacted response headers"):
            await executor.run_position(logical_id="one", request_body=BODY,
                                        worst_case_usd="0.01")
        self.assertEqual(executor.lineage_attempts()[0]["state"], "possiblySent")
        self.assertEqual(executor.ledger["chargedUSD"], "0.01")
        self.assertEqual(self.waits, [])

    async def test_journal_is_written_before_the_one_send(self) -> None:
        executor = self.executor()

        async def inspect(_logical: str, _wire: str, body: bytes) -> WireResponse:
            self.assertIs(body, BODY)
            stored = json.loads((self.run_dir / "wire-ledger.json").read_text(encoding="utf-8"))
            self.assertEqual(stored["positions"][0]["wires"][0]["state"], "possiblySent")
            self.assertEqual(stored["chargedUSD"], "0.01")
            with self.assertRaisesRegex(ValueError, "in progress"):
                await executor.run_position(logical_id="two", request_body=BODY,
                                            worst_case_usd="0.01")
            return self.response(200)

        executor.send_once = inspect
        await executor.run_position(logical_id="one", request_body=BODY,
                                    worst_case_usd="0.01")

    async def test_restart_admission_skips_the_ambiguous_position(self) -> None:
        executor = self.executor()

        async def ambiguous(_logical: str, _wire: str, _body: bytes) -> WireResponse:
            raise ConnectionError("synthetic ambiguous send")

        executor.send_once = ambiguous
        await executor.run_position(logical_id="one", request_body=BODY,
                                    worst_case_usd="0.01")
        self.assertEqual(verify_wire_ledger(self.run_dir, profile_sha256=PROFILE)["status"], "valid")
        parent = {
            "runID": self.run_dir.name, "rootRunID": self.run_dir.name,
            "profileSha256": PROFILE, "lineageHardLimitUSD": "0.03",
            "parentRunID": None, "parentEvidenceSha256": None,
            "verifiedEvidenceTreeSha256": "d" * 64,
            "attempts": executor.lineage_attempts(),
        }
        admission = admit_child(
            root_run_id=self.run_dir.name, profile_sha256=PROFILE,
            queue_ids=["one", "two"], hard_limit_usd="0.03",
            parents=[parent], child_run_id="child-run",
            child_queue_ids=["two"], child_worst_case_usd={"two": "0.01"},
        )
        self.assertEqual(admission["priorChargedUSD"], "0.01")
        with self.assertRaisesRegex(ValueError, "never-sent"):
            admit_child(
                root_run_id=self.run_dir.name, profile_sha256=PROFILE,
                queue_ids=["one", "two"], hard_limit_usd="0.03",
                parents=[parent], child_run_id="wrong-child",
                child_queue_ids=["one"], child_worst_case_usd={"one": "0.01"},
            )


if __name__ == "__main__":
    unittest.main()
