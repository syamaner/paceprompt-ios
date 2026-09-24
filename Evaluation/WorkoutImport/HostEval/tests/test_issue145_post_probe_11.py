"""Additive eleven-candidate plan preserves the sealed twelve-model evidence."""

from __future__ import annotations

from collections import Counter
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145 import queue_document
from paceprompt_eval.issue145_post_probe_11 import (
    ACCEPTED_RUN_ID, EXCLUDED_MODEL, PROPOSAL_RUN_ID, _accepted_probe,
    _filtered_queue, proposal_material, verify_prepared_proposal,
)
from paceprompt_eval.v3 import safe_run_dir


class PostProbeElevenCandidateTests(unittest.TestCase):
    def test_filtered_queue_preserves_other_attempts_and_reindexes_positions(self) -> None:
        original = queue_document()
        filtered = _filtered_queue()
        self.assertEqual(
            [item["attemptID"] for item in filtered["entries"]],
            [item["attemptID"] for item in original["entries"]
             if item["modelID"] != EXCLUDED_MODEL],
        )
        self.assertEqual(len(filtered["entries"]), 3597)
        self.assertEqual(filtered["parentQueueSha256"], original["queueSha256"])
        self.assertNotIn(EXCLUDED_MODEL, {item["modelID"] for item in filtered["entries"]})
        self.assertEqual(
            Counter(item["stratumID"] for item in filtered["entries"]),
            {"v3-heldout-regression": 2607, "issue130-acceptance-r2": 990},
        )
        by_case: dict[tuple[str, int, str], list[int]] = {}
        for item in filtered["entries"]:
            key = item["stratumID"], item["repetitionIndex"], item["caseID"]
            by_case.setdefault(key, []).append(item["modelPosition"])
        self.assertEqual(len(by_case), 327)
        self.assertTrue(all(positions == list(range(1, 12))
                            for positions in by_case.values()))

    def test_accepted_evidence_hash_is_mandatory(self) -> None:
        if not safe_run_dir(ACCEPTED_RUN_ID, create=False).is_dir():
            self.skipTest("ignored accepted run evidence is not present")
        with patch(
            "paceprompt_eval.issue145_post_probe_11.ACCEPTED_EVIDENCE_SHA256",
            "0" * 64,
        ):
            with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                _accepted_probe()

    def test_local_proposal_requires_deepseek_proof_and_new_authority(self) -> None:
        if not safe_run_dir(ACCEPTED_RUN_ID, create=False).is_dir():
            self.skipTest("ignored accepted run evidence is not present")
        proposal, queue = proposal_material()
        self.assertEqual(proposal["queueSha256"], queue["queueSha256"])
        self.assertEqual(len(proposal["candidateModelIDs"]), 11)
        self.assertNotIn(EXCLUDED_MODEL, proposal["candidateModelIDs"])
        self.assertIn("mistralai/mistral-small-3.2-24b-instruct",
                      proposal["candidateModelIDs"])
        self.assertEqual(
            next(route for route in proposal["candidateRoutes"]
                 if route["requestedModelID"] == "deepseek/deepseek-v4-flash-0731")
            ["providerEndpoint"],
            "deepinfra/fp8",
        )
        self.assertEqual(proposal["excludedCandidate"]["disposition"],
                         "route-unavailable-not-scored")
        self.assertEqual(proposal["scoredLogicalPositions"], 3597)
        self.assertEqual(proposal["maximumPhysicalSends"], 10824)
        self.assertEqual(proposal["threeSendConservativeUSDFromSavedCatalogue"],
                         "287.514142080")
        self.assertIsNone(proposal["deepseekRouteCompatibilityProof"])
        self.assertIsNone(proposal["hardLimitUSD"])
        self.assertFalse(proposal["liveAuthorized"])
        self.assertFalse(proposal["credentialRead"])
        self.assertEqual(proposal["providerCalls"], 0)

    def test_prepared_proposal_rebuilds_from_parent_and_accepted_evidence(self) -> None:
        if not safe_run_dir(PROPOSAL_RUN_ID, create=False).is_dir():
            self.skipTest("ignored prepared proposal is not present")
        self.assertEqual(verify_prepared_proposal(PROPOSAL_RUN_ID)["status"], "valid")
