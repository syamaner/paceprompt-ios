"""The follow-on proposals stay source-bound and cannot execute a send."""

from __future__ import annotations

from decimal import Decimal
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_deepseek_11_r2 import (
    DEEPSEEK_MODEL, LINEAGE_CEILING_USD, MATRIX_RUN_ID, PARENT_RUN_ID,
    _historical_deepseek_call, _parent, deepseek_material, matrix_material,
    verify_prepared_proposals,
)
from paceprompt_eval.v3 import safe_run_dir


class HermeticProposalTests(unittest.TestCase):
    """Exercise proposal rules even when ignored historical runs are absent."""

    def test_material_and_authority_without_local_run_evidence(self) -> None:
        parent = {
            "candidateRoutes": [{"requestedModelID": DEEPSEEK_MODEL,
                                 "providerEndpoint": "deepinfra/fp8"}],
            "candidateModelIDs": [DEEPSEEK_MODEL],
            "excludedCandidate": {"requestedModelID": "synthetic-exclusion"},
            "scoredLogicalPositions": 3597,
            "warmupLogicalPositions": 11,
            "maximumPhysicalSends": 10824,
            "stratumScoredPositions": {"synthetic": 3597},
            "threeSendConservativeUSDFromSavedCatalogue": "287.514142080",
        }
        queue = {"queueSha256": "q" * 64}
        call = {"oneSendWorstCaseUSD": "0.00305826"}
        with (patch("paceprompt_eval.issue145_deepseek_11_r2._parent",
                    return_value=(parent, queue)),
              patch("paceprompt_eval.issue145_deepseek_11_r2._historical_deepseek_call",
                    return_value=call),
              patch("paceprompt_eval.issue145_deepseek_11_r2.host_source_tree_hash",
                    return_value="s" * 64)):
            probe = deepseek_material()
            matrix, actual_queue = matrix_material()
            self.assertEqual(actual_queue, queue)
            self.assertEqual(probe["route"]["providerEndpoint"], "deepinfra/fp8")
            self.assertEqual(probe["recommendedHardLimitUSD"], "0.00917478")
            self.assertEqual(probe["scoredHeldoutCalls"], 0)
            self.assertIsNone(probe["ratifiedHardLimitUSD"])
            self.assertFalse(probe["liveAuthorized"])
            self.assertEqual(matrix["queueSha256"], queue["queueSha256"])
            self.assertEqual(matrix["operatorApprovedCumulativeCeilingUSD"],
                             LINEAGE_CEILING_USD)
            self.assertIsNone(matrix["ratifiedHardLimitUSD"])
            self.assertIsNone(matrix["deepseekRouteCompatibilityProof"])
            self.assertFalse(matrix["credentialRead"])
            self.assertEqual(matrix["providerCalls"], 0)

    def test_wrong_route_and_cost_above_ceiling_fail_closed(self) -> None:
        parent = {
            "candidateRoutes": [{"requestedModelID": DEEPSEEK_MODEL,
                                 "providerEndpoint": "wrong-route"}],
        }
        with patch("paceprompt_eval.issue145_deepseek_11_r2._parent",
                   return_value=(parent, {})):
            with self.assertRaisesRegex(RuntimeError, "route changed"):
                deepseek_material()
        parent["candidateRoutes"][0]["providerEndpoint"] = "deepinfra/fp8"
        parent.update(scoredLogicalPositions=3597, warmupLogicalPositions=11,
                      maximumPhysicalSends=10824,
                      threeSendConservativeUSDFromSavedCatalogue="300.00")
        with (patch("paceprompt_eval.issue145_deepseek_11_r2._parent",
                    return_value=(parent, {})),
              patch("paceprompt_eval.issue145_deepseek_11_r2._historical_deepseek_call",
                    return_value={"oneSendWorstCaseUSD": "0.00305826"})):
            with self.assertRaisesRegex(RuntimeError, "cost ceiling changed"):
                matrix_material()


class DeepSeekElevenR2Tests(unittest.TestCase):
    def setUp(self) -> None:
        if not safe_run_dir(PARENT_RUN_ID, create=False).is_dir():
            self.skipTest("ignored accepted parent proposal is not present")

    def test_parent_is_immutable_and_deepseek_route_is_only_warmup(self) -> None:
        with patch(
            "paceprompt_eval.issue145_deepseek_11_r2.PARENT_EVIDENCE_SHA256",
            "0" * 64,
        ):
            with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                _parent()
        proposal = deepseek_material()
        self.assertEqual(proposal["requestedModelID"], DEEPSEEK_MODEL)
        self.assertEqual(proposal["route"]["providerEndpoint"], "deepinfra/fp8")
        self.assertEqual(proposal["logicalPositions"], 1)
        self.assertEqual(proposal["scoredHeldoutCalls"], 0)
        self.assertEqual(proposal["maximumPhysicalSends"], 3)
        self.assertEqual(proposal["recommendedHardLimitUSD"], "0.00917478")
        self.assertIsNone(proposal["ratifiedHardLimitUSD"])
        self.assertFalse(proposal["liveAuthorized"])

    def test_historical_cost_requires_accepted_gate_bytes(self) -> None:
        with patch(
            "paceprompt_eval.issue145_deepseek_11_r2.ACCEPTED_GATE_SHA256",
            "0" * 64,
        ):
            with self.assertRaisesRegex(RuntimeError, "gate bytes changed"):
                _historical_deepseek_call()

    def test_matrix_preserves_queue_and_does_not_convert_ceiling_to_authority(self) -> None:
        proposal, queue = matrix_material()
        self.assertEqual(proposal["queueSha256"], queue["queueSha256"])
        self.assertEqual(len(proposal["candidateModelIDs"]), 11)
        self.assertEqual(proposal["scoredLogicalPositions"], 3597)
        self.assertEqual(proposal["maximumPhysicalSends"], 10824)
        self.assertEqual(proposal["operatorApprovedCumulativeCeilingUSD"],
                         LINEAGE_CEILING_USD)
        self.assertLess(
            Decimal(proposal["threeSendConservativeUSDFromSavedCatalogue"]),
            Decimal(LINEAGE_CEILING_USD),
        )
        self.assertIsNone(proposal["deepseekRouteCompatibilityProof"])
        self.assertIsNone(proposal["ratifiedHardLimitUSD"])
        self.assertFalse(proposal["liveAuthorized"])
        self.assertFalse(proposal["credentialRead"])
        self.assertEqual(proposal["providerCalls"], 0)

    def test_prepared_artifacts_rebuild_exactly(self) -> None:
        if not safe_run_dir(MATRIX_RUN_ID, create=False).is_dir():
            self.skipTest("ignored r2 proposal not prepared")
        self.assertEqual(verify_prepared_proposals()["status"], "valid")
