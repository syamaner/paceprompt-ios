"""The DeepSeek probe profile is inert, exact and testable without local runs."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_deepseek_probe_profile import (
    CATALOGUE_EVIDENCE_SHA256, CATALOGUE_RUN_ID, EXAMPLES_SHA256,
    PROFILE_RUN_ID, PROMPT_SHA256,
    _fresh_catalogue,
    profile_material, verify_prepared_profile,
)
from paceprompt_eval.issue145_deepseek_probe_gate import PROFILE_SOURCE_SHA256
from paceprompt_eval.issue145 import EXAMPLES, PRODUCTION_PROMPT
from paceprompt_eval.catalogue import conservative_call_cost
from paceprompt_eval.openrouter import ModelSpec
from paceprompt_eval.v3 import safe_run_dir


class HermeticDeepSeekProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = ModelSpec(
            requested_model_id="deepseek/deepseek-v4-flash-0731",
            canonical_revision="deepseek/deepseek-v4-flash-20260731",
            provider_endpoint="deepinfra/fp8", quantization="fp8",
            role="openWeightCandidate", temperature=None, top_p=None,
            reasoning=None, required_parameters=(
                "max_tokens", "response_format", "structured_outputs",
            ), zdr=True, max_output_tokens=8192,
        )
        self.body = {
            "model": self.spec.requested_model_id,
            "provider": {"order": ["deepinfra/fp8"], "only": ["deepinfra/fp8"],
                         "allow_fallbacks": False, "require_parameters": True,
                         "data_collection": "deny", "quantizations": ["fp8"],
                         "zdr": True},
            "max_tokens": 8192, "response_format": {"type": "json_schema"},
        }
        self.endpoint = {
            "requestedModelID": self.spec.requested_model_id,
            "providerEndpoint": self.spec.provider_endpoint,
            "canonicalRevision": self.spec.canonical_revision,
            "reportedQuantization": "fp8",
            "status": 0,
            "inputPricePerToken": "0.00000006",
            "outputPricePerToken": "0.00000018",
        }

    def material(self, *, input_price: str = "0.00000006",
                 historical_price: str | None = None,
                 accepted_hash: str | None = None,
                 accepted_length: int | None = None) -> dict:
        self.endpoint["inputPricePerToken"] = input_price
        request = json.dumps(self.body).encode()
        one_send = conservative_call_cost(
            input_utf8_bytes=len(request), input_price=input_price,
            output_price=self.endpoint["outputPricePerToken"], output_tokens=8192,
        )
        old_probe = ({}, {}, [self.spec], {})
        with (patch("paceprompt_eval.issue145_deepseek_probe_profile._accepted_parent",
                    return_value={"recommendedHardLimitUSD": format(one_send * 3, "f")}),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.old_probe_parent",
                    return_value=old_probe),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.old_probe_request_bytes",
                    return_value={"warmup-deepseek--deepseek-v4-flash-0731": request}),
              patch("paceprompt_eval.issue145_deepseek_probe_profile._accepted_request_identity",
                    return_value=(accepted_hash or hashlib.sha256(request).hexdigest(),
                                  accepted_length if accepted_length is not None
                                  else len(request))),
              patch("paceprompt_eval.issue145_deepseek_probe_profile._fresh_catalogue",
                    return_value={"modelsSha256": "m" * 64,
                                  "selected": [self.endpoint]}),
              patch("paceprompt_eval.issue145_deepseek_probe_profile._historical_deepseek_call",
                    return_value={"oneSendWorstCaseUSD": historical_price or format(one_send, "f")}),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.sha256_file",
                    side_effect=lambda path: (
                        PROMPT_SHA256 if path == PRODUCTION_PROMPT else
                        EXAMPLES_SHA256 if path == EXAMPLES else "s" * 64
                    ))):
            return profile_material(preparation_source_sha256="a" * 64)

    def test_no_evidence_profile_freezes_request_and_withholds_authority(self) -> None:
        profile = self.material()
        request = json.dumps(self.body).encode()
        self.assertEqual(profile["requestSha256"], hashlib.sha256(request).hexdigest())
        self.assertEqual(profile["requestUTF8Bytes"], len(request))
        self.assertEqual(profile["maximumLogicalPositions"], 1)
        self.assertEqual(profile["maximumPhysicalSends"], 3)
        self.assertEqual(profile["scoredHeldoutCalls"], 0)
        self.assertEqual(profile["threeSendConservativeUSD"],
                         profile["recommendedHardLimitUSD"])
        self.assertEqual(profile["retryPolicy"]["fallbackBackoffSeconds"], [30, 120])
        self.assertEqual(profile["transport"]["hiddenSDKRetries"], 0)
        self.assertTrue(profile["responseAcceptance"]["returnedModelAndProviderIdentityRequired"])
        self.assertTrue(profile["responseAcceptance"]["nativeAndHostSchemaRequired"])
        self.assertIsNone(profile["ratifiedHardLimitUSD"])
        self.assertFalse(profile["credentialRead"])
        self.assertEqual(profile["providerCalls"], 0)
        self.assertFalse(profile["liveAuthorized"])

    def test_price_increase_and_route_change_stop_closed(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "cost exceeds"):
            self.material(input_price="0.00000007", historical_price="0.000001")
        self.body["provider"]["only"] = ["wrong-route"]
        with self.assertRaisesRegex(RuntimeError, "request controls changed"):
            self.material()

    def test_invalid_source_hash_stops_before_any_evidence(self) -> None:
        with self.assertRaisesRegex(ValueError, "source SHA"):
            profile_material(preparation_source_sha256="not-a-hash")

    def test_accepted_request_identity_drift_stops_closed(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "differs from accepted gate"):
            self.material(accepted_hash="0" * 64)
        with self.assertRaisesRegex(RuntimeError, "differs from accepted gate"):
            self.material(accepted_length=22299)

    def test_unavailable_catalogue_endpoint_stops_closed(self) -> None:
        # Replay can succeed with an unavailable endpoint; the profile must not.
        selected = {"selected": [{**self.endpoint, "status": 1}]}
        with (patch("paceprompt_eval.issue145_deepseek_probe_profile.safe_run_dir",
                    return_value=Path("/virtual-catalogue")),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.evidence_tree_sha256",
                    return_value=CATALOGUE_EVIDENCE_SHA256),
              patch("pathlib.Path.read_bytes", return_value=b"{}"),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.snapshot_catalogue",
                    return_value=selected),
              patch("paceprompt_eval.issue145_deepseek_probe_profile.strict_json_load",
                    return_value=selected)):
            with self.assertRaisesRegex(RuntimeError, "route differs"):
                _fresh_catalogue(self.spec)


class LocalEvidenceProfileTests(unittest.TestCase):
    def test_prepared_profile_rebuilds_when_local_evidence_is_available(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored exact profile is not prepared")
        # The profile remains sealed to its original preparation source; the
        # additive live gate changes the current HostEval source tree.
        with patch("paceprompt_eval.issue145_deepseek_probe_profile.host_source_tree_hash",
                   return_value=PROFILE_SOURCE_SHA256):
            self.assertEqual(verify_prepared_profile()["status"], "valid")
        with self.assertRaisesRegex(RuntimeError, "source tree changed"):
            verify_prepared_profile()
        with patch("paceprompt_eval.issue145_deepseek_probe_profile.host_source_tree_hash",
                   return_value="0" * 64):
            with self.assertRaisesRegex(RuntimeError, "source tree changed"):
                verify_prepared_profile()

    def test_catalogue_tree_hash_is_mandatory(self) -> None:
        if not safe_run_dir(CATALOGUE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored public catalogue is absent")
        spec = SimpleNamespace(canonical_revision="deepseek/deepseek-v4-flash-20260731")
        with patch("paceprompt_eval.issue145_deepseek_probe_profile.CATALOGUE_EVIDENCE_SHA256",
                   "0" * 64):
            with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                _fresh_catalogue(spec)
