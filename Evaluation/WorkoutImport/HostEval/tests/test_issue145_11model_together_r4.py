"""Hermetic, zero-spend checks for the proposed MiniMax Together route."""

from __future__ import annotations

import asyncio
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from paceprompt_eval.catalogue import MODELS_URL, endpoint_url
from paceprompt_eval.issue145_11model_gate import HARD_LIMIT_USD, ratified_profile
from paceprompt_eval.issue145_full_matrix_r3 import materialized_models
from paceprompt_eval.issue145_11model_together_r4 import (
    MINIMAX_ID, NEW_ROUTE, PROPOSAL_RUN_ID, materialized_models_r4,
    prepare_proposal, profile_material_r4, verify_proposal,
)
from paceprompt_eval.runner import write_json
from paceprompt_eval.v3 import RUNS_ROOT, canonical_hash, sha256_file, strict_json_load


class TogetherProfileTests(unittest.TestCase):
    def test_together_route_transform_is_hermetic(self) -> None:
        ids = [item["requestedModelID"] for item in materialized_models()["models"]
               if item["requestedModelID"] != "mistralai/mistral-small-2603"]
        models = materialized_models_r4({"candidateModelIDs": ids})["models"]
        self.assertEqual([item["requestedModelID"] for item in models], ids)
        mini = next(item for item in models if item["requestedModelID"] == MINIMAX_ID)
        self.assertEqual(mini["providerEndpoint"], NEW_ROUTE)
        self.assertIsNone(mini["quantization"])
        self.assertNotIn("zdr", mini)

    def test_only_minimax_route_changes_and_queue_is_identical(self) -> None:
        if not (RUNS_ROOT / "issue145-11model-profile-r3-20260925-02").is_dir():
            self.skipTest("ignored ratified profile evidence is unavailable")
        old, old_queue = ratified_profile()
        profile, queue = profile_material_r4()
        self.assertEqual(queue, old_queue)
        self.assertEqual(profile["candidateModelIDs"], old["candidateModelIDs"])
        self.assertEqual(profile["queueSha256"], old["queueSha256"])
        self.assertEqual(profile["profileSha256"], canonical_hash({
            key: value for key, value in profile.items() if key != "profileSha256"
        }))
        old_routes = {item["requestedModelID"]: item for item in old["candidateRoutes"]}
        new_routes = {item["requestedModelID"]: item for item in profile["candidateRoutes"]}
        self.assertEqual(set(old_routes), set(new_routes))
        for model_id in old_routes:
            if model_id != MINIMAX_ID:
                self.assertEqual(new_routes[model_id], old_routes[model_id])
        self.assertEqual(new_routes[MINIMAX_ID]["providerEndpoint"], NEW_ROUTE)
        self.assertIsNone(new_routes[MINIMAX_ID]["quantization"])
        self.assertFalse(profile["liveAuthorized"])
        models = materialized_models_r4()["models"]
        self.assertEqual(len(models), 11)
        mini = next(item for item in models if item["requestedModelID"] == MINIMAX_ID)
        self.assertNotIn("zdr", mini)
        self.assertEqual(mini["providerEndpoint"], NEW_ROUTE)


class TogetherProposalTests(unittest.IsolatedAsyncioTestCase):
    async def test_mocked_public_catalogue_prepares_reproducible_inert_proposal(self) -> None:
        saved = RUNS_ROOT / "issue145-11model-matrix-20260925-01" / "catalogue"
        if (not saved.is_dir()
                or not (RUNS_ROOT / "issue145-11model-profile-r3-20260925-02").is_dir()):
            self.skipTest("ignored public catalogue or ratified profile is unavailable")
        profile, _ = await asyncio.to_thread(profile_material_r4)
        revisions = {item["requestedModelID"]: item["canonicalRevision"]
                     for item in profile["candidateRoutes"]}
        urls = {endpoint_url(revision): saved / f"{model.replace('/', '--')}.json"
                for model, revision in revisions.items()}

        def fetch(url: str) -> bytes:
            if url == MODELS_URL:
                return (saved / "models.json").read_bytes()
            return urls[url].read_bytes()

        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with patch("paceprompt_eval.issue145_11model_together_r4.safe_run_dir",
                       return_value=directory):
                proposal = await prepare_proposal(PROPOSAL_RUN_ID, fetch=fetch)
                checked = await asyncio.to_thread(verify_proposal, PROPOSAL_RUN_ID)
            self.assertEqual(checked["status"], "valid")
            self.assertEqual(checked["profileSha256"], proposal["profileSha256"])
            self.assertEqual(checked["proposalSha256"], proposal["proposalSha256"])
            self.assertEqual(proposal["logicalPositions"], 3608)
            self.assertEqual(proposal["maximumPhysicalSends"], 10824)
            self.assertLessEqual(Decimal(proposal["threeSendConservativeUSD"]),
                                 Decimal(HARD_LIMIT_USD))
            self.assertFalse(proposal["credentialRead"])
            self.assertEqual(proposal["providerCalls"], 0)
            selected = strict_json_load(directory / "catalogue" / "selected.json")
            mini = next(item for item in selected["selected"]
                        if item["requestedModelID"] == MINIMAX_ID)
            self.assertEqual(mini["providerEndpoint"], NEW_ROUTE)
            with patch("paceprompt_eval.issue145_11model_together_r4.safe_run_dir",
                       return_value=directory), patch(
                           "paceprompt_eval.issue145_11model_together_r4.HARD_LIMIT_USD",
                           "0.01",
                       ):
                with self.assertRaisesRegex(RuntimeError, "exceeds proposed cap"):
                    await asyncio.to_thread(verify_proposal, PROPOSAL_RUN_ID)
            mini["inputPricePerToken"] = "0.000001"
            write_json(directory / "catalogue" / "selected.json", selected)
            proposal["catalogueSelectedSha256"] = sha256_file(
                directory / "catalogue" / "selected.json"
            )
            proposal["proposalSha256"] = canonical_hash({
                key: value for key, value in proposal.items()
                if key != "proposalSha256"
            })
            write_json(directory / "proposal.json", proposal)
            with patch("paceprompt_eval.issue145_11model_together_r4.safe_run_dir",
                       return_value=directory):
                with self.assertRaisesRegex(RuntimeError, "diverge from raw catalogue"):
                    await asyncio.to_thread(verify_proposal, PROPOSAL_RUN_ID)
