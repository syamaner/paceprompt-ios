from __future__ import annotations

import asyncio
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, call, patch

from paceprompt_eval.issue145_route_probes import (
    FAILED_EVIDENCE_SHA256, FAILED_EVIDENCE_TREE_SHA256, FAILED_RUN_ID,
    RouteProbeRun, _failed_run_evidence,
    _profile, _validate_outbound_messages, prepare_gate, prepare_recovery_gate,
    run_live, seal_gate, seal_recovery_gate, verify,
)
from paceprompt_eval.issue145 import PRODUCTION_PROMPT, model_messages
from paceprompt_eval.transport_strategy import strategy_for
from paceprompt_eval.v3 import asset_paths, load_cases, strict_json_load


class RouteProbeTests(unittest.TestCase):
    @staticmethod
    def _fake_parent(proposal, ratification, specs):
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "inputPricePerToken": item["inputPricePerTokenUSD"],
                "outputPricePerToken": item["outputPricePerTokenUSD"],
            }
            for item, spec in zip(proposal["orderedCalls"], specs)
        ]
        return Path("/unused-parent"), selected, {}

    def test_profile_freezes_two_ordered_calls_and_zero_spend_authority(self):
        proposal, ratification, specs = _profile()
        self.assertEqual(
            [spec.requested_model_id for spec in specs],
            [item["requestedModelID"] for item in proposal["orderedCalls"]],
        )
        self.assertEqual(proposal["execution"]["totalProviderCalls"], 2)
        self.assertEqual(proposal["execution"]["scoredHeldoutCalls"], 0)
        self.assertEqual(ratification["ratifiedSpendingLimitUSD"], "0.01192791")
        self.assertFalse(ratification["authority"]["credentialRead"])
        self.assertFalse(ratification["authority"]["liveRun"])

    def test_live_messages_use_the_issue130_r2_production_prompt(self):
        _, _, specs = _profile()
        warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                      if case["id"] == "WI-V3-D020")
        runner = object.__new__(RouteProbeRun)
        runner.messages_for_case = model_messages
        runner.transport_strategy_for_spec = strategy_for
        messages = runner.messages(warmup, specs[0])
        self.assertEqual(messages[0].content, PRODUCTION_PROMPT.read_text(encoding="utf-8"))
        templates = {
            spec.requested_model_id: {
                "messages": [
                    {"role": message.role, "content": message.content}
                    for message in model_messages(warmup, strategy_for(spec))
                ]
            }
            for spec in specs
        }
        _validate_outbound_messages(specs, templates, warmup)
        templates[specs[0].requested_model_id]["messages"][0]["content"] = "older prompt"
        with self.assertRaisesRegex(RuntimeError, "differ from sealed mock"):
            _validate_outbound_messages(specs, templates, warmup)

    def test_actual_parent_evidence_verifies_when_present(self):
        proposal, ratification, _ = _profile()
        from paceprompt_eval.v3 import RUNS_ROOT

        if not (RUNS_ROOT / ratification["parentPreparedRunID"] / "operator-gate.json").exists():
            self.skipTest("ignored prepared parent evidence is not in this checkout")
        report = verify()
        self.assertEqual(report["status"], "valid")
        self.assertEqual(report["callCount"], 2)
        self.assertFalse(report["liveAuthorized"])

    def test_failed_run_is_exact_and_immutable(self):
        from paceprompt_eval.v3 import RUNS_ROOT

        if not (RUNS_ROOT / FAILED_RUN_ID / "operator-gate.json").exists():
            self.skipTest("ignored failed-run evidence is not in this checkout")
        self.assertEqual(_failed_run_evidence(FAILED_RUN_ID), dict(
            FAILED_EVIDENCE_SHA256, evidenceTreeSha256=FAILED_EVIDENCE_TREE_SHA256,
        ))
        with patch(
            "paceprompt_eval.issue145_route_probes.sha256_file", return_value="tampered"
        ):
            with self.assertRaisesRegex(RuntimeError, "evidence changed"):
                _failed_run_evidence(FAILED_RUN_ID)

    def test_recovery_creates_new_linked_gate_without_provider_or_credential(self):
        run_id = "issue145-route-probes-recovery-test"
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._failed_run_evidence",
            return_value=FAILED_EVIDENCE_SHA256,
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepared = prepare_recovery_gate(run_id, FAILED_RUN_ID)
            self.assertEqual(prepared["recoveryOf"]["runID"], FAILED_RUN_ID)
            self.assertEqual(prepared["recoveryOf"]["evidenceSha256"], FAILED_EVIDENCE_SHA256)
            self.assertEqual(prepared["providerCalls"], 0)
            self.assertFalse(prepared["credentialRead"])
            self.assertIsNone(prepared["authorizationPhrase"])
            sealed = seal_recovery_gate(run_id)
            self.assertEqual(sealed["ratifiedSpendingLimitUSD"], "0.01192791")
            with self.assertRaises(FileExistsError):
                prepare_recovery_gate(run_id, FAILED_RUN_ID)
            with self.assertRaises(RuntimeError):
                seal_recovery_gate(run_id)
            with patch("paceprompt_eval.issue145_route_probes.os.environ") as environment:
                with self.assertRaisesRegex(RuntimeError, "authorization"):
                    asyncio.run(run_live(
                        run_id=run_id, authorization="wrong",
                        spending_limit_usd="0.01192791",
                    ))
                self.assertNotIn(call("OPENROUTER_API_KEY"), environment.get.call_args_list)
            catalogue.assert_not_called()

    def test_recovery_rejects_parent_drift_and_gate_tampering(self):
        run_id = "issue145-route-probes-recovery-test"
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._failed_run_evidence",
            return_value=FAILED_EVIDENCE_SHA256,
        ) as parent, patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepare_recovery_gate(run_id, FAILED_RUN_ID)
            sealed = seal_recovery_gate(run_id)
            parent.return_value = dict(FAILED_EVIDENCE_SHA256, **{"live-state.json": "drift"})
            with self.assertRaisesRegex(RuntimeError, "recovery gate differs"):
                asyncio.run(run_live(
                    run_id=run_id, authorization=sealed["authorizationPhrase"],
                    spending_limit_usd="0.01192791",
                ))
            parent.return_value = FAILED_EVIDENCE_SHA256
            path = Path(directory) / run_id / "operator-gate.json"
            changed = deepcopy(sealed)
            changed["selectedEndpoints"][0]["providerEndpoint"] = "wrong-route"
            path.write_text(json.dumps(changed), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "recovery gate differs"):
                asyncio.run(run_live(
                    run_id=run_id, authorization=sealed["authorizationPhrase"],
                    spending_limit_usd="0.01192791",
                ))
            catalogue.assert_not_called()

    def test_failed_recovery_can_be_restarted_again_without_new_code(self):
        from paceprompt_eval.issue145_route_probes import _failed_run_evidence as actual_evidence

        first, second = "issue145-probe-recovery-1", "issue145-probe-recovery-2"

        def evidence(parent_run_id, ancestry=frozenset()):
            return (FAILED_EVIDENCE_SHA256 if parent_run_id == FAILED_RUN_ID
                    else actual_evidence(parent_run_id, ancestry))

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._failed_run_evidence",
            side_effect=evidence,
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ):
            prepare_recovery_gate(first, FAILED_RUN_ID)
            gate = seal_recovery_gate(first)
            first_dir = Path(directory) / first
            attempt_id = "warmup-mistralai--mistral-small-2603"
            model_id = "mistralai/mistral-small-2603"
            (first_dir / "diagnostic-report.json").write_text(json.dumps({
                "runID": first, "providerCalls": 1, "stoppedAfterFailure": True,
                "attempts": [{"modelID": model_id, "hostClassification": "rateLimited",
                              "compatibilityPassed": False}],
            }), encoding="utf-8")
            (first_dir / "live-state.json").write_text(json.dumps({
                "runID": first, "status": "completeAwaitingHumanEvidenceAcceptance",
                "attempts": [{"attemptID": attempt_id, "modelID": model_id,
                              "hostClassification": "rateLimited", "compatibilityPassed": False,
                              "terminal": True}],
                "guardChargedUSD": "0.00886965", "guardReservedUSD": "0.00",
            }), encoding="utf-8")
            (first_dir / "evidence-integrity-audit.json").write_text(json.dumps({
                "passed": True, "errors": [],
            }), encoding="utf-8")
            selected = first_dir / "live-catalogue" / "selected.json"
            selected.parent.mkdir()
            selected.write_text("{}", encoding="utf-8")
            from paceprompt_eval.v3 import sha256_file

            (first_dir / "operator-ratification.json").write_text(json.dumps({
                "runID": first, "authorizationPhrase": gate["authorizationPhrase"],
                "spendingLimitUSD": gate["ratifiedSpendingLimitUSD"],
                "providerCallLimit": 2, "credentialAvailable": True,
                "credentialPersisted": False, "liveCatalogueSha256": sha256_file(selected),
                "liveCostPreflightUSD": "0.01192791",
            }), encoding="utf-8")
            for directory_name, suffix in (
                ("requests", ".json"), ("responses", ".json"),
                ("transcripts", ".json"), ("framework-logs", ".json"),
                ("framework-logs", "-python-logging.json"),
            ):
                evidence_dir = first_dir / directory_name
                evidence_dir.mkdir(exist_ok=True)
                (evidence_dir / f"{attempt_id}{suffix}").write_text("{}", encoding="utf-8")
            prepared = prepare_recovery_gate(second, first)
            self.assertEqual(prepared["recoveryOf"]["runID"], first)
            self.assertEqual(seal_recovery_gate(second)["status"],
                             "awaitingFinalLiveRunAuthorization")
            with self.assertRaisesRegex(RuntimeError, "fresh run ID"):
                prepare_recovery_gate(first, first)

    def test_descendant_requires_parent_live_admission_and_raw_attempts(self):
        from paceprompt_eval.issue145_route_probes import _failed_run_evidence as actual_evidence

        first, second = "issue145-probe-recovery-1", "issue145-probe-recovery-2"

        def evidence(parent_run_id, ancestry=frozenset()):
            return (FAILED_EVIDENCE_SHA256 if parent_run_id == FAILED_RUN_ID
                    else actual_evidence(parent_run_id, ancestry))

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._failed_run_evidence",
            side_effect=evidence,
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ):
            prepare_recovery_gate(first, FAILED_RUN_ID)
            seal_recovery_gate(first)
            first_dir = Path(directory) / first
            (first_dir / "diagnostic-report.json").write_text(json.dumps({
                "runID": first, "providerCalls": 1, "stoppedAfterFailure": True,
            }), encoding="utf-8")
            (first_dir / "live-state.json").write_text(json.dumps({
                "runID": first, "status": "completeAwaitingHumanEvidenceAcceptance",
                "attempts": [{}],
            }), encoding="utf-8")
            (first_dir / "evidence-integrity-audit.json").write_text(json.dumps({
                "passed": True, "errors": [],
            }), encoding="utf-8")
            with self.assertRaises(FileNotFoundError):
                _failed_run_evidence(first)

    def test_prepare_and_seal_are_local_and_exact_run_bound(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepared = prepare_gate(run_id)
            self.assertEqual(prepared["status"], "awaitingZeroSpendSealing")
            self.assertFalse(prepared["credentialRead"])
            self.assertEqual(prepared["providerCalls"], 0)
            self.assertIsNone(prepared["authorizationPhrase"])
            sealed = seal_gate(run_id)
            self.assertEqual(sealed["status"], "awaitingFinalLiveRunAuthorization")
            self.assertEqual(sealed["ratifiedSpendingLimitUSD"], "0.01192791")
            self.assertTrue(sealed["authorizationPhrase"].startswith("AUTHORIZE_PACEPROMPT_"))
            self.assertEqual(strict_json_load(Path(directory) / run_id / "operator-gate.json"), sealed)
            with self.assertRaises(RuntimeError):
                seal_gate(run_id)
            with self.assertRaises(RuntimeError):
                prepare_gate("different-run")
            catalogue.assert_not_called()

    def test_tampered_gate_rejected_before_catalogue_or_key(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepare_gate(run_id)
            sealed = seal_gate(run_id)
            gate_path = Path(directory) / run_id / "operator-gate.json"
            tampered = deepcopy(sealed)
            tampered["selectedEndpoints"][0]["providerEndpoint"] = "wrong-route"
            gate_path.write_text(json.dumps(tampered), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                asyncio.run(run_live(
                    run_id=run_id, authorization=sealed["authorizationPhrase"],
                    spending_limit_usd="0.01192791",
                ))
            catalogue.assert_not_called()

    def test_source_drift_rejected_before_catalogue_or_key(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepare_gate(run_id)
            sealed = seal_gate(run_id)
            with patch("paceprompt_eval.issue145_route_probes.host_source_tree_hash", return_value="drift"):
                with self.assertRaises(RuntimeError):
                    asyncio.run(run_live(
                        run_id=run_id, authorization=sealed["authorizationPhrase"],
                        spending_limit_usd="0.01192791",
                    ))
            catalogue.assert_not_called()

    def test_live_price_increase_rejected_before_credential_read(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ):
            prepare_gate(run_id)
            sealed = seal_gate(run_id)
            current = deepcopy(sealed["selectedEndpoints"])
            current[0]["inputPricePerToken"] = "1"
            with patch(
                "paceprompt_eval.issue145_route_probes.snapshot_catalogue",
                return_value={"selected": current},
            ), patch("paceprompt_eval.issue145_route_probes.os.environ") as environment:
                with self.assertRaisesRegex(RuntimeError, "price increased"):
                    asyncio.run(run_live(
                        run_id=run_id, authorization=sealed["authorizationPhrase"],
                        spending_limit_usd="0.01192791",
                    ))
                self.assertNotIn(call("OPENROUTER_API_KEY"), environment.get.call_args_list)

    def test_invalid_live_prices_rejected_before_credential_read(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ):
            prepare_gate(run_id)
            sealed = seal_gate(run_id)
            for price in ("-1", "-Infinity", "Infinity", "NaN"):
                with self.subTest(price=price):
                    current = deepcopy(sealed["selectedEndpoints"])
                    current[0]["outputPricePerToken"] = price
                    with patch(
                        "paceprompt_eval.issue145_route_probes.snapshot_catalogue",
                        return_value={"selected": current},
                    ), patch("paceprompt_eval.issue145_route_probes.os.environ") as environment:
                        with self.assertRaisesRegex(RuntimeError, "not finite and non-negative"):
                            asyncio.run(run_live(
                                run_id=run_id, authorization=sealed["authorizationPhrase"],
                                spending_limit_usd="0.01192791",
                            ))
                        self.assertNotIn(call("OPENROUTER_API_KEY"), environment.get.call_args_list)

    def test_missing_exact_live_authorization_never_refreshes_catalogue(self):
        _, ratification, _ = _profile()
        run_id = ratification["ratifiedRunID"]
        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch(
            "paceprompt_eval.issue145_route_probes._parent_evidence", self._fake_parent
        ), patch("paceprompt_eval.issue145_route_probes.snapshot_catalogue") as catalogue:
            prepare_gate(run_id)
            seal_gate(run_id)
            with self.assertRaisesRegex(RuntimeError, "authorization"):
                asyncio.run(run_live(
                    run_id=run_id, authorization="not-authorized",
                    spending_limit_usd="0.01192791",
                ))
            catalogue.assert_not_called()

    def test_probe_stops_after_first_incompatible_warmup(self):
        _, _, specs = _profile()
        with tempfile.TemporaryDirectory() as directory:
            runner = object.__new__(RouteProbeRun)
            runner.run_dir = Path(directory)
            runner.specs = {spec.requested_model_id: spec for spec in specs}
            runner.warmup = {"id": "WI-V3-D020"}
            runner.setup = lambda: None
            runner.save_state = AsyncMock()
            runner.call = AsyncMock(return_value={
                "modelID": specs[0].requested_model_id,
                "hostClassification": "schemaViolation",
                "schemaValid": False,
                "compatibilityPassed": False,
            })
            runner._evidence_integrity = lambda: {"passed": True, "errors": []}
            report = asyncio.run(runner.execute())
            self.assertEqual(runner.call.await_count, 1)
            self.assertTrue(report["stoppedAfterFailure"])
            self.assertEqual(report["providerCalls"], 1)
            self.assertIsNone(report["automaticWinner"])


if __name__ == "__main__":
    unittest.main()
