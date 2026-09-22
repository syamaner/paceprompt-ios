from __future__ import annotations

import asyncio
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, call, patch

from paceprompt_eval.issue145_route_probes import (
    RouteProbeRun, _profile, _validate_outbound_messages,
    prepare_gate, run_live, seal_gate, verify,
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
