from __future__ import annotations

import asyncio
from collections import Counter
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145 import (
    BASETEN_MODEL_ID,
    MODELS,
    cost_preflight,
    prepare_gate,
    queue_document,
    scored_strata,
    verify,
)
from paceprompt_eval.openrouter import FORCED_TOOL_ARGUMENTS, load_model_specs
from paceprompt_eval.transport_strategy import ISSUE145_V5_REGISTRY_ID, strategy_for


class Issue145V5Tests(unittest.TestCase):
    def test_ratified_configuration_and_two_stratum_queue_are_exact(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["models"], 12)
        self.assertEqual(report["distinctScoredCases"], 109)
        self.assertEqual(report["scoredAttempts"], 3924)
        self.assertEqual(report["warmups"], 12)
        self.assertEqual(report["totalProviderCalls"], 3936)
        self.assertEqual(
            report["queueSha256"],
            "3327dd619bf13eac0eb6ec7de3c5f5d43ee3d2959ff5323d9b4d18fb50466f53",
        )

        first = queue_document()
        second = queue_document()
        self.assertEqual(first, second)
        self.assertEqual(len(first["entries"]), 3924)
        self.assertEqual(
            Counter(item["stratumID"] for item in first["entries"]),
            {"v3-heldout-regression": 2844, "issue130-acceptance-r2": 1080},
        )
        self.assertEqual(
            set(Counter(item["modelID"] for item in first["entries"]).values()),
            {327},
        )
        self.assertEqual(len({item["attemptID"] for item in first["entries"]}), 3924)

    def test_all_questions_and_answers_remain_in_distinct_sealed_strata(self) -> None:
        strata = scored_strata()
        self.assertEqual([(name, len(cases)) for name, cases in strata], [
            ("v3-heldout-regression", 79),
            ("issue130-acceptance-r2", 30),
        ])
        all_cases = [case for _, cases in strata for case in cases]
        self.assertEqual(len({case["id"] for case in all_cases}), 109)
        self.assertTrue(all("expected" in case for case in all_cases))

    def test_replacement_routes_are_additive_and_not_live_authority(self) -> None:
        specs = load_model_specs(MODELS)
        self.assertTrue(
            all(spec.transport_registry_id == ISSUE145_V5_REGISTRY_ID for spec in specs)
        )
        by_id = {spec.requested_model_id: spec for spec in specs}
        self.assertEqual(
            by_id["mistralai/mistral-small-2603"].provider_endpoint,
            "mistral/zdr",
        )
        self.assertIsNone(by_id["mistralai/mistral-small-2603"].quantization)
        self.assertEqual(
            by_id["deepseek/deepseek-v4-flash-0731"].provider_endpoint,
            "deepinfra/fp8",
        )
        self.assertEqual(strategy_for(by_id["google/gemini-3.7-flash"]).identifier.value, "semanticJsonV29")
        self.assertEqual(by_id[BASETEN_MODEL_ID].response_contract, FORCED_TOOL_ARGUMENTS)

    def test_gate_is_zero_spend_and_withholds_live_authorization(self) -> None:
        specs = load_model_specs(MODELS)
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
            endpoint = {
                "tag": spec.provider_endpoint,
                "provider_name": spec.provider_endpoint,
                "supported_parameters": sorted(parameters),
                "quantization": spec.quantization,
                "pricing": {"prompt": "0.00000001", "completion": "0.00000002"},
                "status": 0,
            }
            endpoints = (
                [endpoint, dict(endpoint)]
                if spec.requested_model_id == BASETEN_MODEL_ID
                else [endpoint]
            )
            return json.dumps({"data": {"endpoints": endpoints}}).encode()

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(prepare_gate("offline-issue145-v5", fetch=fake_fetch))
            run_dir = Path(directory) / "offline-issue145-v5"
            serialized = b"".join(
                path.read_bytes() for path in run_dir.rglob("*") if path.is_file()
            )

        self.assertEqual(gate["status"], "awaitingReplacementRouteCompatibilityProofAndSpendingRatification")
        self.assertEqual(gate["providerCalls"], 0)
        self.assertFalse(gate["credentialRead"])
        self.assertEqual(gate["spendUSD"], "0.00")
        self.assertIsNone(gate["authorizationPhrase"])
        self.assertEqual(gate["costPreflight"]["callCount"], 3936)
        self.assertFalse(gate["costPreflight"]["admitted"])
        self.assertIsNone(gate["costPreflight"]["hardLimitUSD"])
        self.assertNotIn(b"must-not-be-read", serialized)
        self.assertNotIn(b'"rationale"', serialized)
        self.assertNotIn(b'"conventionTags"', serialized)

        selected = next(
            item
            for item in gate["selectedEndpoints"]
            if item["requestedModelID"] == BASETEN_MODEL_ID
        )
        self.assertEqual(selected["matchingEndpointCount"], 2)
        self.assertTrue(selected["equivalentDuplicateEndpointTag"])

    def test_cost_preflight_cannot_admit_without_a_ratified_limit(self) -> None:
        specs = load_model_specs(MODELS)
        snapshot = {
            "selected": [
                {
                    "requestedModelID": spec.requested_model_id,
                    "inputPricePerToken": "0.00000001",
                    "outputPricePerToken": "0.00000002",
                }
                for spec in specs
            ]
        }
        templates = {
            spec.requested_model_id: {
                "messages": [{"role": "user", "content": "placeholder"}]
            }
            for spec in specs
        }
        report = cost_preflight(snapshot, templates)
        self.assertEqual(report["callCount"], 3936)
        self.assertGreater(float(report["estimatedUSD"]), 0)
        self.assertFalse(report["admitted"])
        self.assertIsNone(report["hardLimitUSD"])


if __name__ == "__main__":
    unittest.main()
