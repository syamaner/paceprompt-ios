"""The accepted probe can revise a proposal, but cannot authorise live work."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_post_deepseek_11_r3 import (
    LOGICAL_ID, PROBE_EVIDENCE_SHA256, PROBE_PREAUDIT_SHA256, PROBE_RUN_ID,
    PROPOSAL_RUN_ID, _accepted_probe, _probe_outcome_valid,
    profile_material, verify_prepared_profile,
)
from paceprompt_eval.v3 import safe_run_dir


class HermeticProfileTests(unittest.TestCase):
    def test_terminal_probe_predicate_rejects_extra_wire_and_changed_audit(self) -> None:
        model_id = "deepseek/deepseek-v4-flash-0731"
        result = {"compatibilityPassed": True,
                  "reason": "native and host schema valid"}
        audit = {"runID": PROBE_RUN_ID,
                 "evidenceTreeSha256BeforeAudit": PROBE_PREAUDIT_SHA256,
                 "status": "requiresSeparateExactEvidenceReview"}
        report = {"result": {"logicalID": LOGICAL_ID, "modelID": model_id,
                             "state": "terminalComplete", **result},
                  "scoredHeldoutCalls": 0,
                  "chargedWorstCaseUSD": "0.00305826"}
        state = {"status": "completeAwaitingHumanEvidenceAcceptance"}
        wire = {"statusCode": 200, "state": "completeHTTPResponse",
                "retryDecision": {"retry": False}}
        ledger = {"chargedUSD": "0.00305826",
                  "positions": [{"wires": [wire]}]}
        kwargs = {"audit": audit, "report": report, "state": state,
                  "ledger": ledger, "checked": {"status": "valid"},
                  "result": result, "model_id": model_id}
        self.assertTrue(_probe_outcome_valid(**kwargs))
        self.assertFalse(_probe_outcome_valid(**dict(
            kwargs, ledger={"chargedUSD": "0.00305826",
                            "positions": [{"wires": [wire, wire]}]})))
        self.assertFalse(_probe_outcome_valid(**dict(
            kwargs, audit=dict(audit, status="acceptedWithoutReview"))))
        self.assertFalse(_probe_outcome_valid(**dict(
            kwargs, report=dict(report, scoredHeldoutCalls=1))))
        self.assertFalse(_probe_outcome_valid(**dict(
            kwargs, checked={"status": "invalid"})))

    def test_profile_preserves_queue_and_withholds_live_authority(self) -> None:
        parent = {
            "threeSendConservativeUSDFromSavedCatalogue": "287.514142080",
            "candidateModelIDs": ["deepseek/deepseek-v4-flash-0731"],
            "candidateRoutes": [{"requestedModelID": "deepseek/deepseek-v4-flash-0731",
                                 "providerEndpoint": "deepinfra/fp8"}],
            "excludedCandidate": {"requestedModelID": "synthetic-exclusion"},
            "stratumScoredPositions": {"synthetic": 3597},
        }
        queue = {"queueSha256": "1c0d4ce6c43c40919afc8ac7d420403bc18f67773bcf355b9c93439f0a76ea05"}
        with (patch("paceprompt_eval.issue145_post_deepseek_11_r3._parent",
                    return_value=(parent, queue)),
              patch("paceprompt_eval.issue145_post_deepseek_11_r3._accepted_probe",
                    return_value={"evidenceTreeSha256": PROBE_EVIDENCE_SHA256}),
              patch("paceprompt_eval.issue145_post_deepseek_11_r3.host_source_tree_hash",
                    return_value="s" * 64)):
            profile, actual_queue = profile_material()
        self.assertIs(actual_queue, queue)
        self.assertEqual(profile["acceptedDeepseekProbe"]["evidenceTreeSha256"],
                         PROBE_EVIDENCE_SHA256)
        self.assertEqual(profile["scoredLogicalPositions"], 3597)
        self.assertEqual(profile["maximumPhysicalSends"], 10824)
        self.assertEqual(profile["recommendedCumulativeHardLimitUSD"], "300.00")
        self.assertIsNone(profile["ratifiedCumulativeHardLimitUSD"])
        self.assertIsNone(profile["initialLiveAuthorization"])
        self.assertFalse(profile["credentialRead"])
        self.assertEqual(profile["providerCalls"], 0)
        self.assertFalse(profile["liveAuthorized"])

    def test_cost_at_cap_fails_closed(self) -> None:
        with (patch("paceprompt_eval.issue145_post_deepseek_11_r3._parent",
                    return_value=({"threeSendConservativeUSDFromSavedCatalogue": "300.00"}, {})),
              patch("paceprompt_eval.issue145_post_deepseek_11_r3._accepted_probe",
                    return_value={})):
            with self.assertRaisesRegex(RuntimeError, "exceeds proposed cap"):
                profile_material()


class LocalAcceptedEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        if not safe_run_dir(PROPOSAL_RUN_ID, create=False).is_dir():
            self.skipTest("ignored proposal evidence is not present")

    def test_accepted_probe_is_exact_and_profile_verifies(self) -> None:
        self.assertEqual(_accepted_probe()["evidenceTreeSha256"],
                         PROBE_EVIDENCE_SHA256)
        self.assertEqual(verify_prepared_profile(PROPOSAL_RUN_ID)["status"], "valid")

    def test_probe_hash_mismatch_fails_closed(self) -> None:
        with patch("paceprompt_eval.issue145_post_deepseek_11_r3.PROBE_EVIDENCE_SHA256",
                   "0" * 64):
            with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                _accepted_probe()
