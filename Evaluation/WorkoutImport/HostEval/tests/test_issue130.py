from __future__ import annotations

import asyncio
from collections import Counter
from copy import deepcopy
from decimal import Decimal
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue130 import (
    MODELS,
    SEALED,
    aggregate,
    cost_preflight,
    prepare_gate,
    projected_cases,
    queue_document,
    run_live,
    seal_gate,
    verify,
)
from paceprompt_eval.openrouter import load_model_specs
from paceprompt_eval.runner import write_json
from paceprompt_eval.v3 import sha256_file


def fake_catalogue(url: str) -> bytes:
    spec = load_model_specs(MODELS)[0]
    if url == "https://openrouter.ai/api/v1/models":
        return json.dumps({"data": [{"id": spec.requested_model_id, "canonical_slug": spec.canonical_revision}]}).encode()
    return json.dumps(
        {
            "data": {
                "endpoints": [
                    {
                        "tag": "openai",
                        "provider_name": "OpenAI",
                        "supported_parameters": ["max_tokens", "response_format", "structured_outputs", "reasoning"],
                        "quantization": None,
                        "pricing": {"prompt": "0.000004", "completion": "0.000020"},
                        "status": "active",
                    }
                ]
            }
        }
    ).encode()


class Issue130GateTests(unittest.TestCase):
    def test_profile_verifies_and_queue_is_balanced(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        queue = queue_document()
        self.assertEqual(len(queue["entries"]), 180)
        self.assertEqual(
            Counter(item["promptArm"] for item in queue["entries"]),
            {"production-v3": 90, "issue130-r1": 90},
        )
        self.assertEqual(len({item["attemptID"] for item in queue["entries"]}), 180)

    def test_acceptance_projection_preserves_outcomes_and_name_modes(self) -> None:
        cases = projected_cases()
        self.assertEqual(len(cases), 30)
        self.assertEqual(sum(case["category"] == "proposal" for case in cases), 19)
        self.assertEqual(sum(case["suggestedNameExpectation"] is not None for case in cases), 19)
        exact = next(case for case in cases if case["id"] == "WI-V3-A001")
        generated = next(case for case in cases if case["id"] == "WI-V3-A004")
        self.assertEqual(exact["suggestedNameExpectation"], {"mode": "exact", "value": "Easy Hills"})
        self.assertEqual(generated["suggestedNameExpectation"], {"mode": "nonEmpty"})

    def test_preflight_has_no_implicit_spending_limit(self) -> None:
        bodies = {
            arm: {"messages": [{"role": "user", "content": "placeholder"}]}
            for arm in ("production-v3", "issue130-r1")
        }
        selected = {"inputPricePerToken": "0.000004", "outputPricePerToken": "0.000020"}
        report = cost_preflight(selected, bodies)
        self.assertEqual(report["callCount"], 182)
        self.assertIsNone(report["hardLimitUSD"])
        self.assertFalse(report["admitted"])
        self.assertGreater(Decimal(report["worstCaseUSD"]), 0)
        with self.assertRaisesRegex(RuntimeError, "finite and non-negative"):
            cost_preflight(
                {"inputPricePerToken": "-0.1", "outputPricePerToken": "0.000020"},
                bodies,
            )

    def test_gate_preparation_is_zero_spend_and_does_not_read_credential(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda run_id, create: self._run_dir(Path(directory), run_id, create),
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(prepare_gate("issue130-offline", fetch=fake_catalogue))
            run_dir = Path(directory) / "issue130-offline"
            serialized = b"".join(path.read_bytes() for path in run_dir.rglob("*") if path.is_file())
            self.assertEqual(gate["providerCalls"], 0)
            self.assertFalse(gate["credentialRead"])
            self.assertEqual(gate["spendUSD"], "0.00")
            self.assertEqual(gate["status"], "awaitingSeparateOperatorSpendingLimitRatification")
            self.assertIsNone(gate["authorizationPhrase"])
            self.assertNotIn(b"must-not-be-read", serialized)

    def test_sealing_requires_limit_at_or_above_worst_case(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda run_id, create: self._run_dir(Path(directory), run_id, create),
        ):
            gate = asyncio.run(prepare_gate("issue130-seal", fetch=fake_catalogue))
            worst = Decimal(gate["costPreflight"]["worstCaseUSD"])
            with self.assertRaises(RuntimeError):
                seal_gate("issue130-seal", format(worst - Decimal("0.000001"), "f"))
            with self.assertRaises(RuntimeError):
                seal_gate("issue130-seal", "Infinity")
            sealed = seal_gate("issue130-seal", format(worst, "f"))
            self.assertEqual(sealed["status"], "awaitingFinalLiveRunRatification")
            self.assertTrue(sealed["authorizationPhrase"].startswith("AUTHORIZE_PACEPROMPT_ISSUE130_"))
            self.assertEqual(sealed["ratifiedSpendingLimitUSD"], format(worst, "f"))

    def test_sealing_rejects_a_queue_and_gate_tampered_together(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda run_id, create: self._run_dir(Path(directory), run_id, create),
        ):
            gate = asyncio.run(prepare_gate("issue130-tamper", fetch=fake_catalogue))
            run_dir = Path(directory) / "issue130-tamper"
            queue_path = run_dir / "planned-queue.json"
            queue = json.loads(queue_path.read_text(encoding="utf-8"))
            queue["entries"].append(deepcopy(queue["entries"][0]))
            queue["queueSha256"] = "tampered"
            write_json(queue_path, queue)
            gate["queueSha256"] = "tampered"
            gate["plannedQueueFileSha256"] = sha256_file(queue_path)
            write_json(run_dir / "operator-gate.json", gate)
            with self.assertRaisesRegex(RuntimeError, "canonical ratified queue"):
                seal_gate("issue130-tamper", "100")

    def test_sealing_rejects_a_tampered_cost_preflight(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda run_id, create: self._run_dir(Path(directory), run_id, create),
        ):
            gate = asyncio.run(prepare_gate("issue130-cost-tamper", fetch=fake_catalogue))
            gate["costPreflight"]["worstCaseUSD"] = "0.01"
            write_json(Path(directory) / "issue130-cost-tamper" / "operator-gate.json", gate)
            with self.assertRaisesRegex(RuntimeError, "canonical preflight"):
                seal_gate("issue130-cost-tamper", "100")

    def test_run_policy_is_a_sealed_verification_asset(self) -> None:
        with patch.dict(SEALED, {"runPolicy": "0" * 64}):
            report = verify()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("sealed runPolicy hash changed", report["errors"])

    def test_live_price_drift_is_rejected_before_credential_read(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda run_id, create: self._run_dir(Path(directory), run_id, create),
        ):
            gate = asyncio.run(prepare_gate("issue130-price-drift", fetch=fake_catalogue))
            sealed = seal_gate("issue130-price-drift", gate["costPreflight"]["worstCaseUSD"])

            def drifted_snapshot(path: Path, specs: object) -> dict[str, object]:
                path.mkdir()
                selected = deepcopy(gate["selectedEndpoints"])
                selected[0]["inputPricePerToken"] = "0.004"
                selected[0]["outputPricePerToken"] = "0.020"
                snapshot = {"selected": selected}
                write_json(path / "selected.json", snapshot)
                return snapshot

            with patch(
                "paceprompt_eval.issue130.snapshot_catalogue",
                side_effect=drifted_snapshot,
            ), patch("paceprompt_eval.issue130._read_api_key") as credential:
                with self.assertRaisesRegex(RuntimeError, "current prices no longer fit"):
                    asyncio.run(
                        run_live(
                            run_id="issue130-price-drift",
                            authorization=sealed["authorizationPhrase"],
                            spending_limit_usd=sealed["ratifiedSpendingLimitUSD"],
                        )
                    )
                credential.assert_not_called()

    def test_aggregate_keeps_prompt_decision_human(self) -> None:
        cases = projected_cases()
        attempts = []
        for arm in ("production-v3", "issue130-r1"):
            for repetition in range(1, 4):
                for case in cases:
                    attempts.append(
                        {
                            "attemptID": f"{arm}-{repetition}-{case['id']}",
                            "kind": "scored", "caseID": case["id"], "promptArm": arm,
                            "terminal": True, "hostClassification": "modelQuality",
                            "schemaValid": True, "outcomeExact": True, "reasonExact": True,
                            "pathsExact": True, "authorityPreserved": True,
                            "acceptancePassed": True, "suggestedNameExpectationPassed": True,
                            "reportedCostUSD": "0.001",
                        }
                    )
        from paceprompt_eval.issue130 import POLICY
        from paceprompt_eval.v3 import strict_json_load

        report = aggregate(attempts, cases, strict_json_load(POLICY))
        self.assertIsNone(report["automaticPromptSelection"])
        self.assertTrue(report["promptArms"]["production-v3"]["allHardGatesPassed"])
        self.assertTrue(report["promptArms"]["issue130-r1"]["allHardGatesPassed"])
        for item in attempts:
            if next(case for case in cases if case["id"] == item["caseID"])["category"] == "proposal":
                item["acceptancePassed"] = False
        failed = aggregate(attempts, cases, strict_json_load(POLICY))
        self.assertFalse(failed["promptArms"]["production-v3"]["hardGates"]["strictSchemaAndSemanticValidity"])
        self.assertFalse(failed["promptArms"]["issue130-r1"]["allHardGatesPassed"])

    @staticmethod
    def _run_dir(root: Path, run_id: str, create: bool) -> Path:
        path = root / run_id
        if create:
            path.mkdir()
        return path


if __name__ == "__main__":
    unittest.main()
