from __future__ import annotations

import asyncio
from collections import Counter
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_stage_a import (
    AUTHORIZATION_PREFIX,
    MODELS,
    _admit_live_cost_preflight,
    prepare_gate,
    queue_document,
    run_live,
    seal_gate,
    verify,
)
from paceprompt_eval.openrouter import load_model_specs


class Issue145StageATests(unittest.TestCase):
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

    def test_profile_selects_exact_sealed_top_four_and_one_repetition(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["models"], 4)
        self.assertEqual(report["scoredAttempts"], 436)
        self.assertEqual(report["warmups"], 4)
        self.assertEqual(report["totalProviderCalls"], 440)

        specs = load_model_specs(MODELS)
        self.assertEqual(
            [spec.requested_model_id for spec in specs],
            [
                "openai/gpt-5.6-sol",
                "google/gemini-3.7-flash",
                "qwen/qwen3.8-27b",
                "openai/gpt-5.6-luna",
            ],
        )
        self.assertTrue(all(spec.max_output_tokens == 8192 for spec in specs))

    def test_queue_is_deterministic_balanced_and_keeps_strata_separate(self) -> None:
        first = queue_document()
        self.assertEqual(first, queue_document())
        self.assertEqual(len(first["entries"]), 436)
        self.assertEqual(
            Counter(item["stratumID"] for item in first["entries"]),
            {"v3-heldout-regression": 316, "issue130-acceptance-r2": 120},
        )
        self.assertEqual(
            set(Counter(item["modelID"] for item in first["entries"]).values()),
            {109},
        )
        self.assertEqual(len({item["attemptID"] for item in first["entries"]}), 436)

    def test_gate_is_zero_spend_and_cannot_continue_automatically(self) -> None:
        specs = load_model_specs(MODELS)
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(
                prepare_gate(
                    "offline-issue145-stage-a",
                    fetch=self._fake_catalogue(specs),
                )
            )
            run_dir = Path(directory) / "offline-issue145-stage-a"
            serialized = b"".join(
                path.read_bytes() for path in run_dir.rglob("*") if path.is_file()
            )

        self.assertEqual(gate["status"], "awaitingExactProfileAndSpendingLimitRatification")
        self.assertEqual(gate["providerCalls"], 0)
        self.assertFalse(gate["credentialRead"])
        self.assertEqual(gate["spendUSD"], "0.00")
        self.assertIsNone(gate["authorizationPhrase"])
        self.assertEqual(gate["costPreflight"]["callCount"], 440)
        self.assertFalse(gate["costPreflight"]["admitted"])
        self.assertIsNone(gate["costPreflight"]["hardLimitUSD"])
        self.assertFalse(gate["stageB"]["automaticContinuation"])
        self.assertNotIn(b"must-not-be-read", serialized)

    def test_ratified_gate_seals_exact_limit_but_wrong_live_authority_fails_closed(self) -> None:
        specs = load_model_specs(MODELS)
        run_id = "issue145-top4-stage-a-v5-20260920-01"
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            asyncio.run(prepare_gate(run_id, fetch=self._fake_catalogue(specs)))
            gate = seal_gate(run_id)
            with self.assertRaisesRegex(RuntimeError, "exact Stage A authorization"):
                asyncio.run(
                    run_live(
                        run_id=run_id,
                        authorization="wrong",
                        spending_limit_usd="24.65417240",
                    )
                )

        self.assertEqual(gate["status"], "awaitingFinalLiveRunAuthorization")
        self.assertEqual(gate["ratifiedSpendingLimitUSD"], "24.65417240")
        self.assertEqual(gate["costPreflight"]["hardLimitUSD"], "24.65417240")
        self.assertTrue(gate["costPreflight"]["admitted"])
        self.assertTrue(gate["authorizationPhrase"].startswith(AUTHORIZATION_PREFIX))

    def test_live_current_price_admission_binds_exact_ratified_limit(self) -> None:
        preflight = {
            "method": "utf8BytesAsInputTokensPlusConfiguredMaximumOutputTokens",
            "hardLimitUSD": None,
            "callCount": 440,
            "estimatedUSD": "24.65417240",
            "admitted": False,
            "status": "awaitingSeparateHardLimitRatification",
            "perModelEstimatedUSD": {},
        }

        admitted = _admit_live_cost_preflight(preflight, "24.65417240")

        self.assertIsNone(preflight["hardLimitUSD"])
        self.assertFalse(preflight["admitted"])
        self.assertEqual(admitted["hardLimitUSD"], "24.65417240")
        self.assertTrue(admitted["admitted"])
        self.assertEqual(
            admitted["status"], "admittedUnderExactRatifiedHardLimit"
        )
        with self.assertRaisesRegex(RuntimeError, "current Stage A prices exceed"):
            _admit_live_cost_preflight(preflight, "24.65417239")

    def test_successful_live_admission_is_recorded_before_execution(self) -> None:
        specs = load_model_specs(MODELS)
        run_id = "issue145-top4-stage-a-v5-20260920-01"

        async def fake_execute(_runner):
            return {"status": "test-complete"}

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "process-only-test-key"}):
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
                "paceprompt_eval.issue145_stage_a.snapshot_catalogue",
                side_effect=fake_live_snapshot,
            ), patch(
                "paceprompt_eval.issue145_stage_a.StageALiveRun.execute",
                new=fake_execute,
            ):
                result = asyncio.run(
                    run_live(
                        run_id=run_id,
                        authorization=gate["authorizationPhrase"],
                        spending_limit_usd="24.65417240",
                    )
                )
            operator_record = json.loads(
                (Path(directory) / run_id / "operator-ratification.json").read_text()
            )

        self.assertEqual(result, {"status": "test-complete"})
        live_preflight = operator_record["liveCostPreflight"]
        self.assertEqual(live_preflight["hardLimitUSD"], "24.65417240")
        self.assertTrue(live_preflight["admitted"])
        self.assertEqual(
            live_preflight["status"], "admittedUnderExactRatifiedHardLimit"
        )


if __name__ == "__main__":
    unittest.main()
