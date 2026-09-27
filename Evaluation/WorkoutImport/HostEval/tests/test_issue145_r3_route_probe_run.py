"""Local-only admission and compatibility checks for the r3 route probes."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_r3_route_probe_run import (
    PREVIOUS_RUN_ID, RUN_ID, _complete_probe_results, _inspect_success,
    _previous_failed_gate, _sealed_gate,
    prepare_gate, run_live, seal_gate,
)
from paceprompt_eval.runner import write_json
from paceprompt_eval.v3 import sha256_file


class R3RouteProbeGateTests(unittest.TestCase):
    def test_previous_failed_instance_is_hash_bound_and_has_no_wire_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            previous = Path(directory)
            gate_path = previous / "operator-gate.json"
            write_json(gate_path, {
                "runID": PREVIOUS_RUN_ID,
                "status": "awaitingFinalLiveRunAuthorization",
                "credentialRead": False, "providerCalls": 0,
                "spendUSD": "0.00", "hardLimitUSD": "0.03577518",
                "routeCompatibilityProof": None,
            })
            with patch("paceprompt_eval.issue145_r3_route_probe_run.PREVIOUS_RUN_DIR", previous), patch(
                "paceprompt_eval.issue145_r3_route_probe_run.PREVIOUS_GATE_SHA256",
                sha256_file(gate_path),
            ):
                self.assertEqual(_previous_failed_gate()["providerCalls"], 0)
                write_json(previous / "wire-ledger.json", {})
                with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                    _previous_failed_gate()

    def test_gate_seals_exact_run_without_live_authority(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepared = {
                "runID": RUN_ID, "status": "awaitingZeroSpendSealing",
                "hardLimitUSD": "0.03577518", "authorizationPhrase": None,
                "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
            }

            def safe_dir(run_id: str, *, create: bool) -> Path:
                candidate = root / run_id
                if create:
                    candidate.mkdir(exist_ok=False)
                return candidate

            with patch("paceprompt_eval.issue145_r3_route_probe_run._prepared_gate",
                       return_value=prepared), patch(
                "paceprompt_eval.issue145_r3_route_probe_run.safe_run_dir", safe_dir
            ):
                with self.assertRaisesRegex(RuntimeError, "run ID"):
                    prepare_gate("wrong-instance")
                self.assertEqual(prepare_gate(RUN_ID), prepared)
                sealed = seal_gate(RUN_ID)
                self.assertEqual(sealed, _sealed_gate(prepared))
                self.assertFalse(sealed["credentialRead"])
                self.assertTrue(sealed["authorizationPhrase"].startswith(
                    "AUTHORIZE_PACEPROMPT_ISSUE145_R3_ROUTE_PROBES_"
                ))
                with self.assertRaisesRegex(RuntimeError, "gate differs"):
                    seal_gate(RUN_ID)

    def test_wrong_authorization_cannot_fetch_catalogue_or_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            gate = {"authorizationPhrase": "exact-phrase", "hardLimitUSD": "0.03577518"}
            def forbidden(*_args: object, **_kwargs: object) -> None:
                raise AssertionError("catalogue or credential was accessed")

            with patch("paceprompt_eval.issue145_r3_route_probe_run._validate_gate",
                       return_value=(run_dir, gate)), patch(
                "paceprompt_eval.issue145_r3_route_probe_run.snapshot_catalogue", forbidden
            ):
                for phrase, limit in (("wrong", "0.03577518"),
                                      ("exact-phrase", "0.03577519")):
                    with self.assertRaisesRegex(RuntimeError, "authorization"):
                        asyncio.run(run_live(
                            run_id=RUN_ID, authorization=phrase,
                            spending_limit_usd=limit, api_key_lookup=forbidden,
                        ))

    def test_lineage_audit_runs_outside_live_event_loop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            gate = {"authorizationPhrase": "exact-phrase", "hardLimitUSD": "0.03577518"}

            def audit(_run_id: str, *, sealed: bool) -> tuple[Path, dict[str, str]]:
                self.assertTrue(sealed)
                asyncio.run(asyncio.sleep(0))
                return run_dir, gate

            def parent_audit() -> None:
                asyncio.run(asyncio.sleep(0))
                raise RuntimeError("parent audit completed outside live loop")

            with patch("paceprompt_eval.issue145_r3_route_probe_run._validate_gate", audit), patch(
                "paceprompt_eval.issue145_r3_route_probe_run._parent", parent_audit
            ):
                with self.assertRaisesRegex(RuntimeError, "authorization"):
                    asyncio.run(run_live(
                        run_id=RUN_ID, authorization="wrong",
                        spending_limit_usd="0.03577518",
                    ))
                with self.assertRaisesRegex(RuntimeError, "parent audit completed"):
                    asyncio.run(run_live(
                        run_id=RUN_ID, authorization="exact-phrase",
                        spending_limit_usd="0.03577518",
                    ))

    def test_success_inspection_rejects_truncated_or_invalid_response(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            evidence = run_dir / "wire-evidence"
            evidence.mkdir()
            position = {"wires": [{"wireID": "first--wire-01"}]}
            path = evidence / "first--wire-01.json"
            spec = SimpleNamespace(response_contract="nativeJsonSchema",
                                   required_parameters=())
            write_json(path, {"body": {"choices": [{"finish_reason": "length",
                                                    "message": {"content": "{}"}}]}})
            self.assertFalse(_inspect_success(run_dir, position, spec, b"{}")["compatibilityPassed"])
            write_json(path, {"body": {"choices": [{"finish_reason": "stop",
                                                    "message": {"content": "not JSON"}}]}})
            with patch("paceprompt_eval.issue145_r3_route_probe_run.strategy_for") as strategy:
                strategy.return_value.schema.return_value = {}
                strategy.return_value.normalize_output = lambda value: value
                self.assertFalse(_inspect_success(run_dir, position, spec, b"{}")["compatibilityPassed"])

    def test_valid_first_choice_cannot_hide_extra_choice_or_tool_call(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            evidence = run_dir / "wire-evidence"
            evidence.mkdir()
            path = evidence / "first--wire-01.json"
            position = {"wires": [{"wireID": "first--wire-01"}]}
            spec = SimpleNamespace(response_contract="nativeJsonSchema",
                                   required_parameters=())
            first = {"finish_reason": "stop", "message": {"content": "{}"}}
            request = json.dumps({"provider": {"allow_fallbacks": False}}).encode()
            with patch("paceprompt_eval.issue145_r3_route_probe_run.strategy_for") as strategy, patch(
                "paceprompt_eval.issue145_r3_route_probe_run.parse_model_output",
                return_value={"structure": "valid"},
            ):
                strategy.return_value.schema.return_value = {}
                strategy.return_value.normalize_output = lambda value: value
                for choices in ([first, first], [
                    {"finish_reason": "stop", "message": {
                        "content": "{}", "tool_calls": [{"function": {"name": "bypass"}}]
                    }}
                ]):
                    with self.subTest(choices=choices):
                        write_json(path, {"body": {"choices": choices}})
                        result = _inspect_success(run_dir, position, spec, request)
                        self.assertFalse(result["compatibilityPassed"])
                        self.assertIn("authority", result["reason"])

    def test_failed_first_warmup_keeps_second_position_not_started(self) -> None:
        planned = [
            {"logicalID": "mistral", "requestedModelID": "mistralai/mistral-small-2603"},
            {"logicalID": "deepseek", "requestedModelID": "deepseek/deepseek-v4-flash-0731"},
        ]
        first = {"logicalID": "mistral", "modelID": planned[0]["requestedModelID"],
                 "state": "terminalFailure", "compatibilityPassed": False}
        results = _complete_probe_results(planned, [first])
        self.assertEqual([item["logicalID"] for item in results], ["mistral", "deepseek"])
        self.assertEqual(results[1]["state"], "notStarted")
        self.assertFalse(results[1]["compatibilityPassed"])
        with self.assertRaisesRegex(ValueError, "prefix"):
            _complete_probe_results(planned, [dict(first, logicalID="deepseek")])


if __name__ == "__main__":
    unittest.main()
