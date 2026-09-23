"""Offline r3 profile overlay and public-catalogue preparation contracts."""

from __future__ import annotations

import asyncio
from decimal import Decimal
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145 import MODELS, cost_preflight, queue_document
from paceprompt_eval.issue145_full_matrix_r3 import (
    MISTRAL_ID, materialized_models, prepare_proposal, verify,
    verify_prepared_proposal, verify_ratification,
)
from paceprompt_eval.openrouter import ModelSpec
from paceprompt_eval.runner import write_json
from paceprompt_eval.transport_strategy import (
    ISSUE145_R3_REGISTRY_ID, ISSUE145_V5_REGISTRY_ID, strategy_for,
)
from paceprompt_eval.v3 import canonical_hash, sha256_file, strict_json_load


class Issue145FullMatrixR3Tests(unittest.TestCase):
    def test_ratification_binds_only_profile_and_finite_cap(self) -> None:
        report = verify_ratification()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["profileSha256"],
                         "f58b5f76356d48e954ad257123b9f44c3ab0f870d85023fe6813cf78e71ed720")
        self.assertEqual(report["finiteCumulativeLineageHardLimitUSD"], "300.00")
        self.assertFalse(report["preparedEvidenceRequired"])
        self.assertFalse(report["liveAuthorized"])

    def test_versioned_overlay_preserves_sealed_v5_except_proposed_route(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertFalse(report["liveAuthorized"])
        self.assertEqual(report["queueSha256"], queue_document()["queueSha256"])
        sealed = strict_json_load(MODELS)
        derived = materialized_models()
        self.assertEqual(len(derived["models"]), 12)
        for before, after in zip(sealed["models"], derived["models"]):
            expected = dict(before, transportRegistry=ISSUE145_R3_REGISTRY_ID)
            if before["requestedModelID"] == MISTRAL_ID:
                expected["providerEndpoint"] = "mistral"
                expected.pop("zdr", None)
            self.assertEqual(after, expected)
            self.assertEqual(strategy_for(ModelSpec.from_json(after)).identifier.value,
                             after["transportStrategy"])
        self.assertEqual(sealed["models"][4]["transportRegistry"], ISSUE145_V5_REGISTRY_ID)
        self.assertEqual(sealed["models"][4]["providerEndpoint"], "mistral/zdr")

    def test_offline_preparation_never_reads_a_credential_or_calls_a_model(self) -> None:
        specs = tuple(ModelSpec.from_json(item) for item in materialized_models()["models"])
        models_response = json.dumps({"data": [
            {"id": item.requested_model_id, "canonical_slug": item.canonical_revision}
            for item in specs
        ]}).encode()

        def fake_fetch(url: str) -> bytes:
            if url == "https://openrouter.ai/api/v1/models":
                return models_response
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
            endpoints = ([endpoint, dict(endpoint)]
                         if spec.requested_model_id == "nvidia/nemotron-3-ultra-550b-a55b"
                         else [endpoint])
            return json.dumps({"data": {"endpoints": endpoints}}).encode()

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            proposal = asyncio.run(prepare_proposal("offline-r3-test", fetch=fake_fetch))
            run_dir = Path(directory) / "offline-r3-test"
            persisted = json.loads((run_dir / "r3-proposal.json").read_text())
            self.assertEqual(proposal, persisted)
            self.assertEqual(proposal["providerCalls"], 0)
            self.assertFalse(proposal["credentialRead"])
            self.assertFalse(proposal["liveAuthorized"])
            self.assertIsNone(proposal["recommendedHardLimitUSD"])
            self.assertIsNone(proposal["ratifiedHardLimitUSD"])
            self.assertEqual(proposal["queueSha256"], queue_document()["queueSha256"])
            self.assertEqual(Decimal(proposal["threeSendConservativeUSD"]),
                             3 * Decimal(proposal["oneSendConservativeUSD"]))
            all_bytes = b"".join(path.read_bytes() for path in run_dir.rglob("*")
                                 if path.is_file())
            self.assertNotIn(b"must-not-be-read", all_bytes)
            self.assertEqual(len(proposal["mockPayloadHashes"]), 12)
            audit = verify_prepared_proposal("offline-r3-test")
            self.assertEqual(audit["status"], "valid", audit["errors"])
            self.assertEqual(audit["profileSha256"], proposal["profileSha256"])
            self.assertEqual(len(audit["evidenceTreeSha256"]), 64)
            selected_path = run_dir / "catalogue" / "selected.json"
            mock_path = run_dir / "mock-payloads" / "openai--gpt-5.6-sol.json"
            summary_path = run_dir / "mock-summary.json"
            profile_path = run_dir / "r3-proposal.json"
            originals = {
                path: path.read_bytes()
                for path in (selected_path, mock_path, summary_path, profile_path)
            }
            selected = strict_json_load(selected_path)
            selected["selected"][0]["inputPricePerToken"] = "0.000000001"
            write_json(selected_path, selected)
            mock = strict_json_load(mock_path)
            mock["body"]["tampered"] = True
            write_json(mock_path, mock)
            summary = strict_json_load(summary_path)
            summary["payloadHashes"]["openai/gpt-5.6-sol"] = sha256_file(mock_path)
            write_json(summary_path, summary)
            templates = {
                spec.requested_model_id: strict_json_load(
                    run_dir / "mock-payloads" /
                    f"{spec.requested_model_id.replace('/', '--')}.json"
                )["body"]
                for spec in specs
            }
            preflight = cost_preflight(
                selected, templates, models_path=run_dir / "models-r3-materialized.json"
            )
            profile = strict_json_load(profile_path)
            profile["catalogueSelectedSha256"] = sha256_file(selected_path)
            profile["mockPayloadHashes"] = summary["payloadHashes"]
            profile["oneSendConservativeUSD"] = preflight["estimatedUSD"]
            profile["threeSendConservativeUSD"] = format(
                3 * Decimal(preflight["estimatedUSD"]), "f"
            )
            profile.pop("profileSha256")
            profile["profileSha256"] = canonical_hash(profile)
            write_json(profile_path, profile)
            self.assertEqual(verify_prepared_proposal("offline-r3-test")["status"], "invalid")
            for path, original in originals.items():
                path.write_bytes(original)
            endpoint_path = run_dir / "catalogue" / "mistralai--mistral-small-2603.json"
            original_endpoint = endpoint_path.read_bytes()
            endpoint_path.write_bytes(b'{"tampered":true}')
            self.assertEqual(verify_prepared_proposal("offline-r3-test")["status"], "invalid")
            endpoint_path.write_bytes(original_endpoint)
            mock_path.write_text('{"tampered":true}', encoding="utf-8")
            self.assertEqual(verify_prepared_proposal("offline-r3-test")["status"], "invalid")


if __name__ == "__main__":
    unittest.main()
