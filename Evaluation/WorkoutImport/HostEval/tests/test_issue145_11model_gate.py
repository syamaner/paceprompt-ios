"""Offline identity and fail-closed checks for the ratified eleven-model gate."""

from __future__ import annotations

import asyncio
from decimal import Decimal
import inspect
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from paceprompt_eval.issue145_11model_gate import (
    HARD_LIMIT_USD, PROFILE_SHA256, cases_by_id, checked_run_dir, model_specs, planned_calls,
    prepare_gate, ratified_profile, seal_gate, verify_sealed_gate,
)
from paceprompt_eval.issue145 import _body_for_case
from paceprompt_eval.issue145 import scored_strata
from paceprompt_eval.catalogue import MODELS_URL, endpoint_url
from paceprompt_eval.v3 import RUN_POLICY as V3_RUN_POLICY, aggregate, safe_run_dir, strict_json_load
from paceprompt_eval.issue145_11model_run import _score_one, run_live
from paceprompt_eval.runner import write_json
from paceprompt_eval.transport_strategy import strategy_for


class ElevenModelGateTests(unittest.TestCase):
    def setUp(self) -> None:
        old = safe_run_dir("issue145-r3-profile-prep-20260923-01", create=False)
        if not (old / "mock-payloads").is_dir():
            self.skipTest("ignored historical proposal evidence is unavailable")

    def test_ratification_queue_requests_and_conservative_bound(self) -> None:
        profile, queue = ratified_profile()
        self.assertEqual(profile["profileSha256"], PROFILE_SHA256)
        self.assertEqual(len(model_specs(profile)), 11)
        self.assertEqual(len(cases_by_id()), 110)
        old = safe_run_dir("issue145-r3-profile-prep-20260923-01", create=False)
        selected = strict_json_load(old / "catalogue" / "selected.json")
        templates = {model: strict_json_load(
            old / "mock-payloads" / f"{model.replace('/', '--')}.json"
        )["body"] for model in profile["candidateModelIDs"]}
        prices = [item for item in selected["selected"]
                  if item["requestedModelID"] in profile["candidateModelIDs"]]
        calls, requests = planned_calls(profile, queue, templates, prices)
        self.assertEqual(len(calls), 3608)
        self.assertEqual(len(requests), 3608)
        self.assertEqual(sum(call["kind"] == "warmup" for call in calls), 11)
        self.assertEqual(sum(call["kind"] == "scored" for call in calls), 3597)
        self.assertEqual(len({call["attemptID"] for call in calls}), 3608)
        self.assertLessEqual(
            sum((Decimal(call["oneSendWorstCaseUSD"]) * 3 for call in calls), Decimal("0")),
            Decimal(HARD_LIMIT_USD),
        )

    def test_scored_synthetic_response_uses_unchanged_scorer(self) -> None:
        profile, _ = ratified_profile()
        spec = model_specs(profile)[0]
        case = next(item for item in cases_by_id().values() if item["id"] == "WI-V3-H056")
        old = safe_run_dir("issue145-r3-profile-prep-20260923-01", create=False)
        template = strict_json_load(
            old / "mock-payloads" / f"{spec.requested_model_id.replace('/', '--')}.json"
        )["body"]
        request = json.dumps(_body_for_case(template, case), ensure_ascii=False,
                             sort_keys=True, separators=(",", ":")).encode()
        output = strategy_for(spec).project_output(case["expected"]["modelOutput"])
        wire_id = "synthetic--wire-01"
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("wire-evidence", "normalized-results", "scorer-reports", "projections"):
                (directory / name).mkdir()
            write_json(directory / "wire-evidence" / f"{wire_id}.json", {
                "body": {"choices": [{"finish_reason": "stop",
                                      "message": {"content": json.dumps(output)}}]},
            })
            result = _score_one(
                directory,
                {"attemptID": "synthetic", "kind": "scored", "caseID": case["id"],
                 "modelID": spec.requested_model_id, "stratumID": "v3-heldout-regression",
                 "repetitionIndex": 1},
                {"state": "terminalComplete", "wires": [{"wireID": wire_id}]},
                request, spec, "a" * 40,
            )
            self.assertEqual(result["hostClassification"], "modelQuality")
            self.assertTrue(result["schemaValid"])
            self.assertTrue(result["authorityPreserved"])
            self.assertEqual(result["scorerOverall"], "passed")

    def test_two_strata_keep_full_fixed_denominators_on_not_started(self) -> None:
        profile, queue = ratified_profile()
        specs = model_specs(profile)
        policy = strict_json_load(V3_RUN_POLICY)
        for stratum_id, cases in scored_strata():
            attempts = [
                {**item, "kind": "scored", "status": "notStarted", "terminal": True,
                 "reasonCategory": "operatorCancelled"}
                for item in queue["entries"] if item["stratumID"] == stratum_id
            ]
            report = aggregate(attempts, cases, specs, policy)
            for model in profile["candidateModelIDs"]:
                model_report = report["models"][model]
                self.assertEqual(model_report["preservedAttempts"], len(cases) * 3)
                self.assertTrue(model_report["hardGates"]["runIntegrity"])
                self.assertFalse(model_report["decisionEligible"])


class ElevenModelLiveBoundaryTests(unittest.IsolatedAsyncioTestCase):
    def test_rejects_run_directory_symlink_alias(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "target").mkdir()
            (root / "alias").symlink_to(root / "target")
            with patch("paceprompt_eval.issue145_11model_gate.RUNS_ROOT", root):
                with self.assertRaisesRegex(RuntimeError, "symlink alias"):
                    checked_run_dir("alias", create=False)

    def test_live_entrypoint_cannot_inject_catalogue_or_transport(self) -> None:
        parameters = inspect.signature(run_live).parameters
        self.assertNotIn("public_fetch", parameters)
        self.assertNotIn("sender_factory", parameters)

    async def test_offline_gate_prepares_and_seals_with_exact_request_mapping(self) -> None:
        old = safe_run_dir("issue145-r3-profile-prep-20260923-01", create=False)
        if not (old / "mock-payloads").is_dir():
            self.skipTest("ignored historical proposal evidence is unavailable")
        profile, queue = await asyncio.to_thread(ratified_profile)
        routes = {endpoint_url(spec.canonical_revision):
                  old / "catalogue" / f"{spec.requested_model_id.replace('/', '--')}.json"
                  for spec in model_specs(profile)}

        def fetch(url: str) -> bytes:
            if url == MODELS_URL:
                return (old / "catalogue" / "models.json").read_bytes()
            return routes[url].read_bytes()

        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with (patch("paceprompt_eval.issue145_11model_gate.checked_run_dir",
                        return_value=directory),
                  patch("paceprompt_eval.issue145_11model_gate.ratified_profile",
                        return_value=(profile, queue))):
                gate = await prepare_gate("issue145-11model-matrix-20260925-01", fetch=fetch)
                self.assertEqual(gate["maximumLogicalPositions"], 3608)
                self.assertLessEqual(Decimal(gate["threeSendConservativeUSD"]),
                                     Decimal(HARD_LIMIT_USD))
                sealed = await asyncio.to_thread(
                    seal_gate, "issue145-11model-matrix-20260925-01"
                )
                self.assertEqual(sealed["status"], "awaitingFinalLiveRunAuthorization")
                checked = await asyncio.to_thread(
                    verify_sealed_gate, "issue145-11model-matrix-20260925-01"
                )
                self.assertEqual(checked["status"], "valid")

    async def test_wrong_authorization_cannot_read_key_or_fetch_public_catalogue(self) -> None:
        def forbidden(*_args: object) -> None:
            raise AssertionError("no lookup is allowed")

        with patch(
            "paceprompt_eval.issue145_11model_run.verify_sealed_gate",
            return_value={"authorizationPhrase": "EXACT_PHRASE"},
        ):
            with self.assertRaisesRegex(RuntimeError, "exact reviewed"):
                await run_live(
                    run_id="issue145-11model-matrix-20260925-01",
                    authorization="WRONG", spending_limit_usd=HARD_LIMIT_USD,
                    api_key_lookup=forbidden,
                )
