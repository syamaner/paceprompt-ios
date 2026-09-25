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

from paceprompt_eval import issue145_11model_gate as gate_module
from paceprompt_eval.issue145_11model_gate import (
    HARD_LIMIT_USD, PROFILE_SHA256, _verify_frozen_eval_inputs, cases_by_id,
    checked_run_dir, model_specs, planned_calls, prepare_gate, ratified_profile,
    seal_gate, verify_sealed_gate,
)
from paceprompt_eval.issue145 import _body_for_case
from paceprompt_eval.issue145 import scored_strata
from paceprompt_eval.catalogue import MODELS_URL, endpoint_url
from paceprompt_eval.v3 import RUN_POLICY as V3_RUN_POLICY, aggregate, safe_run_dir, strict_json_load
from paceprompt_eval.issue145_11model_run import (
    CompletionPacer, _conservative_charges, _diagnostic_stratum_report,
    _score_one, run_live,
)
from paceprompt_eval.issue145_retry_execution import WireResponse
from paceprompt_eval.issue145_source_repair import verify_source_chain
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
                {"state": "terminalComplete", "wires": [{"wireID": wire_id,
                                                       "reportedCostUSD": "0.003"}]},
                request, spec, "a" * 40,
            )
            self.assertEqual(result["hostClassification"], "modelQuality")
            self.assertTrue(result["schemaValid"])
            self.assertTrue(result["authorityPreserved"])
            self.assertEqual(result["scorerOverall"], "passed")
            self.assertEqual(result["reportedCostUSD"], "0.003")

    def test_reviewed_source_bridge_chain_is_required_and_ordered(self) -> None:
        old, middle, current = (character * 64 for character in "abc")
        first = {"path": "Evaluation/WorkoutImport/SourceRepairBridges/one.json",
                 "sha256": "1" * 64}
        second = {"path": "Evaluation/WorkoutImport/SourceRepairBridges/two.json",
                  "sha256": "2" * 64}
        records = [
            {"oldSourceTreeSha256": old, "newSourceTreeSha256": middle},
            {"oldSourceTreeSha256": middle, "newSourceTreeSha256": current},
        ]
        with patch("paceprompt_eval.issue145_source_repair._validated_record",
                   side_effect=records):
            verify_source_chain(old, current, [first, second])
        with self.assertRaisesRegex(RuntimeError, "reviewed repair bridge"):
            verify_source_chain(old, current, [])
        with patch("paceprompt_eval.issue145_source_repair._validated_record",
                   side_effect=list(reversed(records))):
            with self.assertRaisesRegex(RuntimeError, "gap"):
                verify_source_chain(old, current, [first, second])

    def test_external_scorer_or_contract_change_fails_before_credential(self) -> None:
        _verify_frozen_eval_inputs()
        from paceprompt_eval.issue145_11model_gate import sha256_file
        original = sha256_file

        def changed(path: Path) -> str:
            if path.name == "scorer.py":
                return "0" * 64
            return original(path)

        with patch("paceprompt_eval.issue145_11model_gate.sha256_file", side_effect=changed):
            with self.assertRaisesRegex(RuntimeError, "scorerSha256"):
                _verify_frozen_eval_inputs()

        def changed_contract(path: Path) -> str:
            if path.name == "workout-proposal-v1.schema.json":
                return "0" * 64
            return original(path)

        with patch("paceprompt_eval.issue145_11model_gate.sha256_file",
                   side_effect=changed_contract):
            with self.assertRaisesRegex(RuntimeError, "frozen scorer contract"):
                _verify_frozen_eval_inputs()

    def test_restart_ancestry_verifies_each_child_once_in_order(self) -> None:
        root = gate_module.PROPOSED_ROOT_RUN_ID
        runs = [root, "child-one", "child-two"]
        seals = [{"runID": name, "gateSha256": str(index) * 64,
                  "evidenceTreeSha256": str(index + 3) * 64}
                 for index, name in enumerate(runs)]
        gates = {}
        for index, name in enumerate(runs[1:], 1):
            gates[name] = {
                "gateVersion": gate_module.CHILD_GATE_VERSION,
                "status": "awaitingFinalLiveRunAuthorization",
                "ancestorSeals": seals[:index], "rootRunID": root,
                "profileSha256": PROFILE_SHA256,
                "cumulativeHardLimitUSD": HARD_LIMIT_USD,
                "hostSourceTreeSha256": "a" * 64,
                "sourceRepairSeals": [],
                "instanceHardLimitUSD": "300.00",
                "authorizationPhrase": "exact",
            }
        seen_parent_counts: list[int] = []

        def load(path: Path) -> object:
            if path.name == "operator-gate.json":
                return gates.get(path.parent.name, {})
            if path.name == "planned-calls.json":
                return [{"attemptID": "warmup-synthetic"}, {"attemptID": "scored"}]
            raise AssertionError(path)

        def child_material(name: str, _seals: object, _directory: Path,
                           **kwargs: object) -> dict[str, object]:
            verified = kwargs["verified_parents"]
            seen_parent_counts.append(len(verified[0]))
            return dict(gates[name], status="awaitingZeroSpendSealing",
                        authorizationPhrase=None)

        with (patch.object(gate_module, "ratified_profile", return_value=(
                {"candidateModelIDs": ["synthetic"]},
                {"entries": [{"attemptID": "scored"}]},
              )),
              patch.object(gate_module, "checked_run_dir",
                           side_effect=lambda name, create: Path("/tmp") / name),
              patch.object(gate_module, "sha256_file",
                           side_effect=lambda path: seals[runs.index(path.parent.name)]["gateSha256"]),
              patch.object(gate_module, "evidence_tree_sha256",
                           side_effect=lambda path: seals[runs.index(path.name)]["evidenceTreeSha256"]),
              patch.object(gate_module, "strict_json_load", side_effect=load),
              patch.object(gate_module, "verify_sealed_gate", return_value={
                  "gateSha256": seals[0]["gateSha256"], "authorizationPhrase": "exact",
              }),
              patch.object(gate_module, "verify_sealed_child_gate",
                           side_effect=AssertionError("recursive verification")),
              patch.object(gate_module, "verify_source_chain"),
              patch.object(gate_module, "host_source_tree_hash", return_value="a" * 64),
              patch.object(gate_module, "_child_material", side_effect=child_material),
              patch.object(gate_module, "verify_wire_ledger", return_value={
                  "status": "valid", "attempts": [],
              })):
            parents, ids = gate_module._verified_ancestors(seals, repair_seals=[])
        self.assertEqual(len(parents), 3)
        self.assertEqual(ids, ["warmup-synthetic", "scored"])
        self.assertEqual(seen_parent_counts, [1, 2])

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
            diagnostic = _diagnostic_stratum_report(attempts, cases, specs, policy)
            self.assertFalse(diagnostic["costTieBreakAvailable"])
            self.assertIsNone(diagnostic["tieBreakTrace"])
            for model in profile["candidateModelIDs"]:
                model_report = report["models"][model]
                self.assertEqual(model_report["preservedAttempts"], len(cases) * 3)
                self.assertTrue(model_report["hardGates"]["runIntegrity"])
                self.assertFalse(model_report["decisionEligible"])


class ElevenModelLiveBoundaryTests(unittest.IsolatedAsyncioTestCase):
    def test_child_charge_keeps_instance_and_cumulative_values_distinct(self) -> None:
        self.assertEqual(
            _conservative_charges(
                {"priorChargedUSD": "2.25"}, {"chargedUSD": "0.75"},
            ),
            ("0.75", "3.00"),
        )
        with self.assertRaisesRegex(RuntimeError, "cumulative cap"):
            _conservative_charges(
                {"priorChargedUSD": "299.50"}, {"chargedUSD": "0.51"},
            )

    async def test_pacing_measures_from_completion_even_after_slow_send(self) -> None:
        clock = [0.0]
        starts: list[float] = []
        sleeps: list[float] = []

        class SlowSender:
            async def send_once(self, _logical: str, _wire: str, _body: bytes) -> WireResponse:
                starts.append(clock[0])
                clock[0] += 5.0
                return WireResponse(200, (), "a" * 64, {"body": {}})

        async def advance(seconds: float) -> None:
            sleeps.append(seconds)
            clock[0] += seconds

        pacer = CompletionPacer(SlowSender(), now=lambda: clock[0], sleep=advance)
        await pacer.send_once("first", "first--wire-01", b"{}")
        await pacer.send_once("second", "second--wire-01", b"{}")
        self.assertEqual(starts, [0.0, 7.0])
        self.assertEqual(sleeps, [2.0])

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
                repair_seal = {"path": "Evaluation/WorkoutImport/SourceRepairBridges/review.json",
                               "sha256": "a" * 64}
                with (patch("paceprompt_eval.issue145_11model_gate.host_source_tree_hash",
                            return_value="b" * 64),
                      patch("paceprompt_eval.issue145_11model_gate.verify_source_chain")
                      as bridge):
                    historical = await asyncio.to_thread(
                        verify_sealed_gate, "issue145-11model-matrix-20260925-01",
                        repair_seals=[repair_seal],
                    )
                    self.assertEqual(historical["gateSha256"], checked["gateSha256"])
                    bridge.assert_called_once_with(
                        sealed["hostSourceTreeSha256"], "b" * 64, [repair_seal],
                    )

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
