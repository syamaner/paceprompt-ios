"""Zero-spend r3 replacement-route probe proposal contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_full_matrix_r3 import RATIFICATION, materialized_models
from paceprompt_eval.issue145_r3_route_probe_profile import (
    ORDERED_MODELS, prepare_proposal, verify_prepared_proposal,
)
from paceprompt_eval.runner import write_json
from paceprompt_eval.v3 import strict_json_load


class R3RouteProbeProposalTests(unittest.TestCase):
    def test_two_warmups_are_separate_from_scored_matrix_and_have_finite_bound(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.dict(
            os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}
        ):
            root = Path(directory)
            ratification = strict_json_load(RATIFICATION)
            parent = root / ratification["preparedRunID"]
            parent.mkdir()
            write_json(parent / "r3-proposal.json", {"profileSha256": ratification["profileSha256"]})
            write_json(parent / "models-r3-materialized.json", materialized_models())
            catalogue = parent / "catalogue"
            catalogue.mkdir()
            write_json(catalogue / "selected.json", {"selected": [
                {
                    "requestedModelID": model_id,
                    "inputPricePerToken": "0.00000015",
                    "outputPricePerToken": "0.0000006",
                }
                for model_id in ORDERED_MODELS
            ]})
            mocks = parent / "mock-payloads"
            mocks.mkdir()
            for model_id in ORDERED_MODELS:
                write_json(mocks / f"{model_id.replace('/', '--')}.json", {
                    "body": {"model": model_id, "messages": [{"role": "user", "content": "warmup"}]}
                })

            def safe_dir(run_id: str, *, create: bool) -> Path:
                candidate = root / run_id
                if create:
                    candidate.mkdir(exist_ok=False)
                return candidate

            with patch(
                "paceprompt_eval.issue145_r3_route_probe_profile.verify_ratification",
                return_value={"status": "valid", "errors": []},
            ), patch(
                "paceprompt_eval.issue145_r3_route_probe_profile.safe_run_dir", safe_dir
            ):
                proposal = prepare_proposal("offline-r3-probes")
                self.assertEqual(tuple(item["requestedModelID"] for item in proposal["orderedCalls"]),
                                 ORDERED_MODELS)
                self.assertEqual(proposal["logicalPositions"], 2)
                self.assertEqual(proposal["maximumPhysicalSends"], 6)
                self.assertEqual(proposal["scoredHeldoutCalls"], 0)
                self.assertFalse(proposal["credentialRead"])
                self.assertFalse(proposal["liveAuthorized"])
                self.assertIsNone(proposal["ratifiedProbeHardLimitUSD"])
                self.assertGreater(float(proposal["recommendedProbeHardLimitUSD"]), 0)
                report = verify_prepared_proposal("offline-r3-probes")
                self.assertEqual(report["status"], "valid", report["errors"])
                persisted = root / "offline-r3-probes" / "r3-route-probe-proposal.json"
                self.assertNotIn("must-not-be-read", persisted.read_text())
                mutated = json.loads(persisted.read_text())
                mutated["orderedCalls"][0]["providerEndpoint"] = "mistral/zdr"
                write_json(persisted, mutated)
                self.assertEqual(verify_prepared_proposal("offline-r3-probes")["status"],
                                 "invalid")


if __name__ == "__main__":
    unittest.main()
