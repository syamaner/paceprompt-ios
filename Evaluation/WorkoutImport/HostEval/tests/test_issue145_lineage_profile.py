from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_lineage_profile import PROPOSAL, SELECTED_MANIFEST, verify
from paceprompt_eval.v3 import strict_json_load


class Issue145LineageProfileTests(unittest.TestCase):
    def test_proposal_is_exact_inert_and_bound_to_sealed_v5(self):
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertFalse(report["liveAuthorized"])
        self.assertIn(report["localPreparation"], {
            "exactLocalZeroSpendEvidence", "notPresentInCheckout"
        })
        proposal = strict_json_load(PROPOSAL)
        self.assertIsNone(proposal["unresolvedBeforeLive"]["finiteLineageHardLimitUSD"])
        self.assertIsNone(proposal["unresolvedBeforeLive"]["replacementRouteCompatibilityProof"])

    def test_clean_checkout_recomputes_embedded_public_cost(self):
        with patch(
            "paceprompt_eval.issue145_lineage_profile.safe_run_dir",
            return_value=Path("/nonexistent-paceprompt-issue145-preparation"),
        ):
            report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["localPreparation"], "notPresentInCheckout")

    def test_live_authority_or_changed_execution_fails_closed(self):
        original = strict_json_load(PROPOSAL)
        for section, field, value in (
            ("authority", "providerInference", True),
            ("unresolvedBeforeLive", "finiteLineageHardLimitUSD", "100.00"),
            ("proposedDelta", "automaticRetryOrFallback", True),
            ("unchangedV5Execution", "totalProviderCalls", 3935),
            ("baseProfile", "queueSha256", "0" * 64),
            ("publicCataloguePreparation", "conservativeWorstCaseUSD", "1.00"),
            ("purpose", None, "authorize live execution"),
            ("unexpectedAuthority", None, True),
        ):
            changed = deepcopy(original)
            if field is None:
                changed[section] = value
            else:
                changed[section][field] = value
            with patch(
                "paceprompt_eval.issue145_lineage_profile.strict_json_load",
                side_effect=lambda path: changed if path == PROPOSAL else strict_json_load(path),
            ):
                report = verify()
            self.assertEqual(report["status"], "invalid", (section, field))

    def test_embedded_price_drift_fails_offline_recalculation(self):
        selected = strict_json_load(SELECTED_MANIFEST)
        selected["selected"][0]["inputPricePerToken"] = "0.00000001"
        with patch(
            "paceprompt_eval.issue145_lineage_profile.strict_json_load",
            side_effect=lambda path: selected if path == SELECTED_MANIFEST else strict_json_load(path),
        ):
            report = verify()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("committed public-catalogue cost cannot be reproduced offline", report["errors"])


if __name__ == "__main__":
    unittest.main()
