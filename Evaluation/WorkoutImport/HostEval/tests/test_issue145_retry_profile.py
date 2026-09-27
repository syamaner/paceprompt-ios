"""Fail-closed checks for the inert issue #145 route/retry proposal."""

from copy import deepcopy
from pathlib import Path
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_retry_profile import EVIDENCE, PROPOSAL, verify
from paceprompt_eval.v3 import strict_json_load


class Issue145RetryProfileTests(unittest.TestCase):
    def test_proposal_is_exact_and_inert(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertFalse(report["liveAuthorized"])
        self.assertIsNone(strict_json_load(PROPOSAL)["spending"]["finiteLineageHardLimitUSD"])

    def test_clean_checkout_remains_verifiable(self) -> None:
        with patch("paceprompt_eval.issue145_retry_profile.safe_run_dir",
                   return_value=Path("/nonexistent-paceprompt-issue145-catalogue")):
            report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["localCatalogue"], "notPresentInCheckout")

    def test_committed_terminal_evidence_and_endpoint_are_required(self) -> None:
        original = strict_json_load(EVIDENCE)
        for section, field, value in (
            ("priorProbeRuns", "evidenceTreeSha256", "0" * 64),
            ("publicCatalogueSelectedEndpoint", "sourceResponseSha256", "0" * 64),
            ("sealedProbeContract", "proposalSha256", "0" * 64),
        ):
            changed = deepcopy(original)
            if section == "priorProbeRuns":
                changed[section][0][field] = value
            else:
                changed[section][field] = value
            with patch("paceprompt_eval.issue145_retry_profile.strict_json_load",
                       side_effect=lambda path: changed if path == EVIDENCE else strict_json_load(path)):
                report = verify()
            self.assertEqual(report["status"], "invalid", (section, field))

    def test_route_retry_or_authority_drift_fails(self) -> None:
        original = strict_json_load(PROPOSAL)
        for section, field, value in (
            ("routeDelta", "proposedProviderEndpoint", "mistral/zdr"),
            ("routeDelta", "retainZdrRequirement", False),
            ("retryDelta", "maxPhysicalSendsPerLogicalPosition", 10),
            ("retryDelta", "fallbackRoutesOrModels", True),
            ("spending", "finiteLineageHardLimitUSD", "300.00"),
            ("supportingEvidence", "sealedProbeRatificationSha256", "0" * 64),
            ("authority", "providerInference", True),
        ):
            changed = deepcopy(original)
            changed[section][field] = value
            with patch("paceprompt_eval.issue145_retry_profile.strict_json_load",
                       side_effect=lambda path: changed if path == PROPOSAL else strict_json_load(path)):
                report = verify()
            self.assertEqual(report["status"], "invalid", (section, field))


if __name__ == "__main__":
    unittest.main()
