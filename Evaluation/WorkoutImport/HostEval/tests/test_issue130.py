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

import paceprompt_eval.issue130 as issue130
from paceprompt_eval.issue130 import (
    CASES,
    HOST_EVAL_ROOT,
    MODELS,
    POLICY,
    R2_PROFILE,
    R2_RATIFICATION,
    R2_RETRY_PROFILE,
    R2_RETRY_PROPOSAL,
    SEALED,
    aggregate,
    cost_preflight,
    prepare_gate,
    prepare_gate_r2,
    prepare_gate_r2_retry,
    projected_cases,
    queue_document,
    queue_document_r2,
    run_live,
    seal_gate,
    seal_gate_r2,
    verify,
    verify_r2,
    verify_r2_retry,
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


def fake_catalogue_r2(url: str) -> bytes:
    value = json.loads(fake_catalogue(url))
    if "data" in value and isinstance(value["data"], dict):
        value["data"]["endpoints"][0]["pricing"] = {
            "prompt": "0.000002",
            "completion": "0.00001",
        }
    return json.dumps(value).encode()


class Issue130GateTests(unittest.TestCase):
    def test_r2_retry_instance_reuses_the_frozen_comparison_and_is_zero_spend_only(self) -> None:
        proposal = json.loads(R2_RETRY_PROPOSAL.read_text(encoding="utf-8"))
        self.assertEqual(proposal["proposedRunID"], "issue130-prompt-gate-r2-20260920-02")
        self.assertEqual(
            proposal["credentialLoading"],
            {
                "source": "operator-designated-checkout-root-dotenv",
                "ambientOpenRouterApiKey": "must-be-unset-before-dotenv-load",
                "persistCredential": False,
            },
        )
        self.assertEqual(proposal["baseQueueSha256"], queue_document_r2()["queueSha256"])
        self.assertEqual(proposal["recommendedHardLimitUSD"], "24.102774")
        self.assertFalse(proposal["authority"]["gateSealing"])
        self.assertFalse(proposal["authority"]["credentialRead"])
        self.assertFalse(proposal["authority"]["providerInference"])
        self.assertFalse(proposal["authority"]["evaluationSpend"])
        self.assertFalse(proposal["authority"]["liveRun"])
        report = verify_r2_retry()
        self.assertEqual(report["status"], "valid", report["errors"])

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda requested, create: self._run_dir(Path(directory), requested, create),
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}), patch(
            "paceprompt_eval.issue130._read_api_key"
        ) as credential:
            gate = asyncio.run(
                prepare_gate_r2_retry(proposal["proposedRunID"], fetch=fake_catalogue_r2)
            )
            self.assertEqual(gate["runInstanceProposal"], proposal)
            self.assertEqual(gate["status"], "awaitingSeparateOperatorSpendingLimitRatification")
            self.assertEqual(gate["providerCalls"], 0)
            self.assertFalse(gate["credentialRead"])
            self.assertEqual(gate["spendUSD"], "0.00")
            credential.assert_not_called()

    def test_r2_retry_instance_rejects_any_other_run_id(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "run ID differs"):
            asyncio.run(prepare_gate_r2_retry("issue130-prompt-gate-r2-20260920-03", fetch=fake_catalogue_r2))

    def test_r2_comparison_profile_proposal_is_exact_offline_and_inert(self) -> None:
        r1_policy = json.loads(POLICY.read_text(encoding="utf-8"))
        r2_policy_path = HOST_EVAL_ROOT / "run-policy-issue130-r2-proposal.json"
        r2_models_path = HOST_EVAL_ROOT / "models-issue130-r2-proposal.json"
        r2_prompt = HOST_EVAL_ROOT / "prompts" / "issue130-r2" / "system.md"
        r2_policy = json.loads(r2_policy_path.read_text(encoding="utf-8"))

        self.assertEqual(r2_policy["ratificationStatus"], "awaiting-separate-operator-ratification")
        self.assertEqual(r2_policy["proposedRunID"], "issue130-prompt-gate-r2-20260920-01")
        for unchanged in ("framework", "dataset", "generation", "routing", "hardGates", "scoring"):
            self.assertEqual(r2_policy[unchanged], r1_policy[unchanged])
        self.assertEqual(
            {key: r2_policy["execution"][key] for key in r1_policy["execution"] if key != "promptArmOrder"},
            {key: value for key, value in r1_policy["execution"].items() if key != "promptArmOrder"},
        )
        self.assertEqual(r2_policy["execution"]["promptArmOrder"], ["production-v3", "issue130-r2"])
        self.assertEqual([arm["id"] for arm in r2_policy["promptArms"]], ["production-v3", "issue130-r2"])

        expected_hashes = {
            "productionPromptSha256": SEALED["productionPrompt"],
            "candidatePromptSha256": "5e27496875f6fd20d737d8c190fc938bfdc2b2cd3658e48f606dccf64bbdf007",
            "examplesSha256": SEALED["examples"],
            "acceptanceCasesSha256": SEALED["acceptanceCases"],
            "acceptanceManifestSha256": SEALED["acceptanceManifest"],
            "acceptanceSemanticReviewSha256": SEALED["acceptanceSemanticReview"],
            "modelOutputSchemaSha256": SEALED["modelSchema"],
            "transportSchemaSha256": SEALED["transportSchema"],
            "v1ScorerSha256": SEALED["v1Scorer"],
            "schemaValidationSha256": SEALED["schemaValidation"],
            "modelsSha256": "cb03f348250aee339035f0082f73c846c015add8eecf77048b77fe5a3da86145",
            "sealedR1RunPolicySha256": SEALED["runPolicy"],
        }
        for field, expected in expected_hashes.items():
            self.assertEqual(r2_policy["artifacts"][field], expected)
        self.assertEqual(sha256_file(r2_prompt), expected_hashes["candidatePromptSha256"])
        self.assertEqual(sha256_file(r2_models_path), expected_hashes["modelsSha256"])
        self.assertEqual(sha256_file(POLICY), expected_hashes["sealedR1RunPolicySha256"])

        specs = load_model_specs(r2_models_path)
        self.assertEqual(len(specs), 1)
        spec = specs[0]
        self.assertEqual(
            (
                spec.requested_model_id,
                spec.canonical_revision,
                spec.provider_endpoint,
                spec.temperature,
                spec.top_p,
                spec.reasoning,
            ),
            (
                "openai/gpt-5.6-sol",
                "openai/gpt-5.6-sol-20260709",
                "openai",
                None,
                None,
                {"enabled": False, "effort": "none", "exclude": False},
            ),
        )

        selected = {"inputPricePerToken": "0.000002", "outputPricePerToken": "0.00001"}
        with tempfile.TemporaryDirectory() as directory:
            queue = queue_document_r2()
            self.assertEqual(len(queue["entries"]), 180)
            self.assertEqual(
                Counter(item["promptArm"] for item in queue["entries"]),
                {"production-v3": 90, "issue130-r2": 90},
            )
            self.assertEqual(queue["queueSha256"], r2_policy["queue"]["queueSha256"])
            _, bodies = asyncio.run(issue130._mock_payloads(Path(directory), selected, profile=R2_PROFILE))
            preflight = issue130.cost_preflight(selected, bodies, profile=R2_PROFILE)

        basis = r2_policy["spending"]["recommendationBasis"]
        self.assertEqual(preflight["callCount"], r2_policy["queue"]["totalProviderCallLimit"])
        self.assertEqual(preflight["worstCaseUSD"], basis["totalWorstCaseUSD"])
        self.assertEqual(preflight["perPromptArmWorstCaseUSD"]["production-v3"], basis["productionPromptWorstCaseUSD"])
        self.assertEqual(preflight["perPromptArmWorstCaseUSD"]["issue130-r2"], basis["candidatePromptWorstCaseUSD"])
        self.assertEqual(r2_policy["spending"]["recommendedHardLimit"], preflight["worstCaseUSD"])
        self.assertIsNone(r2_policy["spending"]["hardLimit"])
        self.assertFalse(r2_policy["authorization"]["providerRunAuthorized"])
        self.assertFalse(r2_policy["authorization"]["credentialReadAuthorized"])
        self.assertIsNone(r2_policy["authorization"]["authorizationPhrase"])
        report = verify_r2()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["queueSha256"], r2_policy["queue"]["queueSha256"])

    def test_r2_ratification_prepares_and_seals_only_the_exact_zero_spend_gate(self) -> None:
        ratification = json.loads(R2_RATIFICATION.read_text(encoding="utf-8"))
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.issue130.safe_run_dir",
            side_effect=lambda requested, create: self._run_dir(Path(directory), requested, create),
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}), patch(
            "paceprompt_eval.issue130._read_api_key"
        ) as credential:
            gate = asyncio.run(prepare_gate_r2(run_id, fetch=fake_catalogue_r2))
            self.assertEqual(gate["providerCalls"], 0)
            self.assertFalse(gate["credentialRead"])
            self.assertEqual(gate["spendUSD"], "0.00")
            self.assertEqual(gate["queueSha256"], ratification["ratifiedQueueSha256"])
            self.assertEqual(gate["profileRatification"], ratification)
            sealed = seal_gate_r2(run_id)
            self.assertEqual(sealed["status"], "awaitingFinalLiveRunRatification")
            self.assertEqual(sealed["ratifiedSpendingLimitUSD"], "24.102774")
            self.assertTrue(sealed["authorizationPhrase"].startswith("AUTHORIZE_PACEPROMPT_ISSUE130_R2_"))
            credential.assert_not_called()

    def test_r2_gate_rejects_an_unratified_run_id(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "run ID differs"):
            asyncio.run(prepare_gate_r2("issue130-r2-unratified", fetch=fake_catalogue))

    def test_r2_candidate_preserves_sealed_r1_and_strengthens_observed_boundaries(self) -> None:
        r1 = HOST_EVAL_ROOT / "prompts" / "issue130-r1" / "system.md"
        r2 = HOST_EVAL_ROOT / "prompts" / "issue130-r2" / "system.md"
        r2_text = r2.read_text(encoding="utf-8")
        compact_r2 = " ".join(r2_text.split())

        self.assertEqual(sha256_file(r1), SEALED["candidatePrompt"])
        self.assertEqual(
            sha256_file(r2),
            "5e27496875f6fd20d737d8c190fc938bfdc2b2cd3658e48f606dccf64bbdf007",
        )
        self.assertIn(
            "Two or more different explicit numeric values assigned to the same semantic field",
            compact_r2,
        )
        self.assertIn(
            "A missing non-kind field does not make an inferable step kind missing and must not add `steps.kind` to `affectedPaths`",
            compact_r2,
        )
        self.assertIn(
            "They are never `ambiguousRequiredField`.",
            compact_r2,
        )
        for case in json.loads(CASES.read_text(encoding="utf-8")):
            self.assertNotIn(case["prompt"], r2_text)

        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        self.assertEqual(
            [arm["id"] for arm in policy["promptArms"]],
            ["production-v3", "issue130-r1"],
        )

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
