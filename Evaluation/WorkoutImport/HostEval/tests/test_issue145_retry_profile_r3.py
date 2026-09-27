"""The operator's synthetic-evaluation privacy decision is an additive revision."""

from copy import deepcopy
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_retry_profile_r3 import PROPOSAL, verify
from paceprompt_eval.v3 import strict_json_load


class Issue145RetryProfileR3Tests(unittest.TestCase):
    def test_r3_is_valid_and_has_no_live_authority(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertFalse(report["liveAuthorized"])
        proposal = strict_json_load(PROPOSAL)
        self.assertFalse(proposal["privacyDecision"]["zdrRequired"])
        self.assertTrue(proposal["privacyDecision"]["dataCollectionDenied"])
        self.assertEqual(proposal["routeDelta"]["proposedZdrRequestField"], "omit")
        self.assertIsNone(proposal["spending"]["finiteLineageHardLimitUSD"])

    def test_other_privacy_or_authority_changes_fail(self) -> None:
        original = strict_json_load(PROPOSAL)
        for section, field, value in (
            ("routeDelta", "retainDataCollectionDenied", False),
            ("routeDelta", "retainExactRouteAndNoFallback", False),
            ("routeDelta", "proposedZdrRequestField", "false"),
            ("privacyDecision", "scope", "production"),
            ("spending", "finiteLineageHardLimitUSD", "300.00"),
            ("authority", "providerInference", True),
        ):
            changed = deepcopy(original)
            changed[section][field] = value
            with patch(
                "paceprompt_eval.issue145_retry_profile_r3.strict_json_load",
                side_effect=lambda path: changed if path == PROPOSAL else strict_json_load(path),
            ):
                report = verify()
            self.assertEqual(report["status"], "invalid", (section, field))


if __name__ == "__main__":
    unittest.main()
