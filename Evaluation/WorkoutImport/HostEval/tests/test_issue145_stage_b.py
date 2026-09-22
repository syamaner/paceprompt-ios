from __future__ import annotations

import asyncio
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_stage_a import queue_document as stage_a_queue
from paceprompt_eval.issue145_stage_b import (
    AUTHORIZATION_PREFIX,
    MODELS,
    RUN_POLICY,
    _admit_live_cost_preflight,
    prepare_gate,
    queue_document,
    run_live,
    seal_gate,
    verify,
)
from paceprompt_eval.openrouter import load_model_specs
from paceprompt_eval.v3 import sha256_file, strict_json_load


class Issue145StageBTests(unittest.TestCase):
    @staticmethod
    def _fake_catalogue(specs):
        models_body = {
            "data": [
                {"id": spec.requested_model_id, "canonical_slug": spec.canonical_revision}
                for spec in specs
            ]
        }

        def fake_fetch(url: str) -> bytes:
            if url == "https://openrouter.ai/api/v1/models":
                return json.dumps(models_body).encode()
            spec = next(item for item in specs if item.canonical_revision in url)
            parameters = set(spec.required_parameters)
            if spec.temperature is not None:
                parameters.update({"temperature", "top_p"})
            if spec.reasoning is not None:
                parameters.add("reasoning")
            return json.dumps(
                {
                    "data": {
                        "endpoints": [
                            {
                                "tag": spec.provider_endpoint,
                                "provider_name": spec.provider_endpoint,
                                "supported_parameters": sorted(parameters),
                                "quantization": spec.quantization,
                                "pricing": {
                                    "prompt": "0.00000001",
                                    "completion": "0.00000002",
                                },
                                "status": 0,
                            }
                        ]
                    }
                }
            ).encode()

        return fake_fetch

    def test_profile_is_exactly_three_compatible_models_and_657_calls(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["models"], 3)
        self.assertEqual(report["scoredAttempts"], 654)
        self.assertEqual(report["warmups"], 3)
        self.assertEqual(report["totalProviderCalls"], 657)
        specs = load_model_specs(MODELS)
        self.assertEqual(
            [spec.requested_model_id for spec in specs],
            [
                "openai/gpt-5.6-sol",
                "qwen/qwen3.8-27b",
                "openai/gpt-5.6-luna",
            ],
        )
        self.assertTrue(all(spec.max_output_tokens == 6144 for spec in specs))

    def test_queue_is_deterministic_balanced_and_disjoint_from_stage_a(self) -> None:
        queue = queue_document()
        self.assertEqual(queue, queue_document())
        self.assertEqual(len(queue["entries"]), 654)
        self.assertEqual(
            Counter(item["modelID"] for item in queue["entries"]),
            {
                "openai/gpt-5.6-sol": 218,
                "qwen/qwen3.8-27b": 218,
                "openai/gpt-5.6-luna": 218,
            },
        )
        self.assertEqual(
            Counter(item["stratumID"] for item in queue["entries"]),
            {"v3-heldout-regression": 474, "issue130-acceptance-r2": 180},
        )
        self.assertEqual(
            Counter(item["repetitionIndex"] for item in queue["entries"]),
            {2: 327, 3: 327},
        )
        self.assertTrue(
            {item["attemptID"] for item in queue["entries"]}.isdisjoint(
                {item["attemptID"] for item in stage_a_queue()["entries"]}
            )
        )

    def test_reviewed_scoring_and_execution_controls_are_explicit(self) -> None:
        policy = strict_json_load(RUN_POLICY)
        self.assertEqual(policy["execution"]["automaticRetries"], 0)
        self.assertEqual(policy["execution"]["connectTimeoutSeconds"], 15)
        self.assertEqual(policy["execution"]["attemptTimeoutSeconds"], 180)
        self.assertFalse(policy["execution"]["resumable"])
        self.assertEqual(policy["hardGates"]["strictSchemaAndSemanticValidity"], "1.00")
        self.assertEqual(policy["categoryFloors"]["majorityCorrectAttemptsAcrossStagesAAndB"], 2)
        self.assertFalse(policy["decision"]["automaticWinner"])
        self.assertIsNone(policy["spending"]["hardLimit"])

    def test_zero_spend_gate_does_not_read_credential_or_authorize_live_run(self) -> None:
        specs = load_model_specs(MODELS)
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(
                prepare_gate(
                    "issue145-top3-stage-b-v5-test",
                    fetch=self._fake_catalogue(specs),
                )
            )
            run_dir = Path(directory) / "issue145-top3-stage-b-v5-test"
            serialized = b"".join(
                path.read_bytes() for path in run_dir.rglob("*") if path.is_file()
            )
            proposal = strict_json_load(run_dir / "proposal-material.json")

        self.assertEqual(gate["status"], "awaitingExactProfileAndSpendingLimitRatification")
        self.assertEqual(gate["providerCalls"], 0)
        self.assertFalse(gate["credentialRead"])
        self.assertEqual(gate["spendUSD"], "0.00")
        self.assertIsNone(gate["authorizationPhrase"])
        self.assertTrue(gate["liveExecutionImplemented"])
        self.assertEqual(gate["costPreflight"]["callCount"], 657)
        self.assertIsNone(gate["costPreflight"]["hardLimitUSD"])
        self.assertFalse(gate["costPreflight"]["admitted"])
        self.assertEqual(proposal["profile"]["scoredAttempts"], 654)
        self.assertEqual(proposal["profile"]["maxOutputTokens"], 6144)
        self.assertNotIn(b"must-not-be-read", serialized)

    def test_ratified_gate_seals_exact_limit_but_wrong_live_authority_fails_closed(self) -> None:
        specs = load_model_specs(MODELS)
        run_id = "issue145-top3-stage-b-v5-20260921-01"
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            asyncio.run(prepare_gate(run_id, fetch=self._fake_catalogue(specs)))
            gate = seal_gate(run_id)
            with self.assertRaisesRegex(RuntimeError, "exact Stage B authorization"):
                asyncio.run(
                    run_live(
                        run_id=run_id,
                        authorization="wrong",
                        spending_limit_usd="32.07052912",
                    )
                )

        self.assertEqual(gate["status"], "awaitingFinalLiveRunAuthorization")
        self.assertEqual(gate["ratifiedSpendingLimitUSD"], "32.07052912")
        self.assertEqual(gate["costPreflight"]["hardLimitUSD"], "32.07052912")
        self.assertTrue(gate["costPreflight"]["admitted"])
        self.assertTrue(gate["authorizationPhrase"].startswith(AUTHORIZATION_PREFIX))

    def test_live_current_price_admission_binds_exact_ratified_limit(self) -> None:
        preflight = {
            "hardLimitUSD": None,
            "callCount": 657,
            "estimatedUSD": "32.07052912",
            "admitted": False,
            "status": "awaitingSeparateHardLimitRatification",
            "perModelEstimatedUSD": {},
        }

        admitted = _admit_live_cost_preflight(preflight, "32.07052912")

        self.assertIsNone(preflight["hardLimitUSD"])
        self.assertFalse(preflight["admitted"])
        self.assertEqual(admitted["hardLimitUSD"], "32.07052912")
        self.assertTrue(admitted["admitted"])
        self.assertEqual(
            admitted["status"], "admittedUnderExactRatifiedHardLimit"
        )
        with self.assertRaisesRegex(RuntimeError, "current Stage B prices exceed"):
            _admit_live_cost_preflight(preflight, "32.07052911")

    def test_copied_sealed_gate_cannot_replay_exact_live_authorization(self) -> None:
        specs = load_model_specs(MODELS)
        run_id = "issue145-top3-stage-b-v5-20260921-01"
        copied_run_id = "copied-stage-b-run"
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            asyncio.run(prepare_gate(run_id, fetch=self._fake_catalogue(specs)))
            gate = seal_gate(run_id)
            shutil.copytree(
                Path(directory) / run_id,
                Path(directory) / copied_run_id,
            )
            with patch(
                "paceprompt_eval.issue145_stage_b.snapshot_catalogue"
            ) as live_catalogue, self.assertRaisesRegex(
                RuntimeError, "exact run directory"
            ):
                asyncio.run(
                    run_live(
                        run_id=copied_run_id,
                        authorization=gate["authorizationPhrase"],
                        spending_limit_usd="32.07052912",
                    )
                )

        live_catalogue.assert_not_called()

    def test_successful_live_admission_is_recorded_before_execution(self) -> None:
        specs = load_model_specs(MODELS)
        run_id = "issue145-top3-stage-b-v5-20260921-01"

        async def fake_execute(_runner):
            return {"status": "test-complete"}

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "synthetic-test-key"}):
            asyncio.run(prepare_gate(run_id, fetch=self._fake_catalogue(specs)))
            gate = seal_gate(run_id)

            def fake_live_snapshot(root: Path, *_args, **_kwargs):
                root.mkdir(parents=True, exist_ok=True)
                selected = gate["selectedEndpoints"]
                (root / "selected.json").write_text(
                    json.dumps(selected, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                return {"selected": selected}

            with patch(
                "paceprompt_eval.issue145_stage_b.snapshot_catalogue",
                side_effect=fake_live_snapshot,
            ), patch(
                "paceprompt_eval.issue145_stage_b.StageBLiveRun.execute",
                new=fake_execute,
            ):
                result = asyncio.run(
                    run_live(
                        run_id=run_id,
                        authorization=gate["authorizationPhrase"],
                        spending_limit_usd="32.07052912",
                    )
                )
            operator_record = json.loads(
                (Path(directory) / run_id / "operator-ratification.json").read_text()
            )

        self.assertEqual(result, {"status": "test-complete"})
        self.assertEqual(operator_record["providerCallLimit"], 657)
        live_preflight = operator_record["liveCostPreflight"]
        self.assertEqual(live_preflight["hardLimitUSD"], "32.07052912")
        self.assertTrue(live_preflight["admitted"])
        self.assertEqual(
            live_preflight["status"], "admittedUnderExactRatifiedHardLimit"
        )

    def test_stage_a_evidence_tampering_fails_closed(self) -> None:
        source = (
            Path(__file__).resolve().parents[2]
            / "Summaries"
            / "issue145-stage-a-data.json"
        )
        with tempfile.TemporaryDirectory() as directory:
            tampered = Path(directory) / source.name
            data = json.loads(source.read_text())
            data["stage"] = "tampered"
            tampered.write_text(json.dumps(data), encoding="utf-8")
            with patch(
                "paceprompt_eval.issue145_stage_b.STAGE_A_AGGREGATE", tampered
            ):
                report = verify()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("Stage B Stage A aggregate hash changed", report["errors"])


if __name__ == "__main__":
    unittest.main()
