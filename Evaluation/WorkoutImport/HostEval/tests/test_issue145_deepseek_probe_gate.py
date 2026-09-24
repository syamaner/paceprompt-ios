"""Zero-spend and fail-closed contracts for the ratified DeepSeek probe."""

from __future__ import annotations

import asyncio
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import httpx2

from paceprompt_eval.issue145_deepseek_probe_gate import (
    AUTH_PREFIX, HARD_LIMIT_USD, LOGICAL_ID, PROFILE_SHA256, RUN_ID,
    _inspect_success, _prepared_gate, _ratified, _sealed_gate,
    run_live, verify_ratification,
)
from paceprompt_eval.issue145_deepseek_probe_profile import PROFILE_RUN_ID
from paceprompt_eval.transport_strategy import strategy_for
from paceprompt_eval.v3 import asset_paths, load_cases, safe_run_dir


class DeepSeekGateTests(unittest.TestCase):
    def test_ratification_is_exact_and_withholds_live_authority(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored ratified profile is absent")
        result = verify_ratification()
        self.assertEqual(result["status"], "valid")
        self.assertEqual(result["profileSha256"], PROFILE_SHA256)
        self.assertEqual(result["hardLimitUSD"], HARD_LIMIT_USD)
        self.assertFalse(result["credentialRead"])
        self.assertEqual(result["providerCalls"], 0)
        self.assertFalse(result["liveAuthorized"])

    def test_prepared_gate_is_inert_and_seal_is_exact(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored ratified profile is absent")
        prepared = _prepared_gate()
        self.assertEqual(prepared["runID"], RUN_ID)
        self.assertEqual(prepared["maximumLogicalPositions"], 1)
        self.assertEqual(prepared["maximumPhysicalSends"], 3)
        self.assertEqual(prepared["scoredHeldoutCalls"], 0)
        self.assertEqual(prepared["hardLimitUSD"], HARD_LIMIT_USD)
        self.assertIsNone(prepared["authorizationPhrase"])
        self.assertFalse(prepared["credentialRead"])
        self.assertEqual(prepared["providerCalls"], 0)
        sealed = _sealed_gate(prepared)
        self.assertTrue(sealed["authorizationPhrase"].startswith(AUTH_PREFIX))
        self.assertEqual(sealed["status"], "awaitingFinalLiveRunAuthorization")
        self.assertEqual(sealed["providerCalls"], 0)

    def test_profile_hash_and_ratification_tampering_fail_closed(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored ratified profile is absent")
        with patch("paceprompt_eval.issue145_deepseek_probe_gate.PROFILE_MODULE_SHA256",
                   "0" * 64):
            with self.assertRaisesRegex(RuntimeError, "implementation changed"):
                _ratified()
        with patch("paceprompt_eval.issue145_deepseek_probe_gate.RATIFICATION_SHA256",
                   "0" * 64):
            with self.assertRaisesRegex(RuntimeError, "ratification bytes changed"):
                _ratified()

    def test_response_requires_one_choice_stop_no_tool_calls(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence_dir = root / "wire-evidence"
            evidence_dir.mkdir()
            wire_id = f"{LOGICAL_ID}--wire-01"
            position = {"wires": [{"wireID": wire_id}]}
            request = b"{}"
            body = {"choices": [{"finish_reason": "stop", "message": {
                "content": "{}", "tool_calls": [{"id": "not-allowed"}],
            }}]}
            (evidence_dir / f"{wire_id}.json").write_text(json.dumps({"body": body}))
            self.assertFalse(_inspect_success(root, position, object(), request)[
                "compatibilityPassed"])
            body["choices"][0]["message"].pop("tool_calls")
            body["choices"].append(deepcopy(body["choices"][0]))
            (evidence_dir / f"{wire_id}.json").write_text(json.dumps({"body": body}))
            self.assertFalse(_inspect_success(root, position, object(), request)[
                "compatibilityPassed"])

    def test_valid_native_schema_response_is_only_diagnostic_compatibility(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored ratified profile is absent")
        _, request, spec = _ratified()
        case = next(item for item in load_cases(asset_paths()["developmentCases"])
                    if item["id"] == "WI-V3-D020")
        native_output = strategy_for(spec).project_output(case["expected"]["modelOutput"])
        body = {
            "model": spec.requested_model_id,
            "provider": spec.provider_endpoint,
            "choices": [{"finish_reason": "stop", "message": {
                "content": json.dumps(native_output),
            }}],
        }
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence_dir = root / "wire-evidence"
            evidence_dir.mkdir()
            wire_id = f"{LOGICAL_ID}--wire-01"
            (evidence_dir / f"{wire_id}.json").write_text(json.dumps({"body": body}))
            checked = _inspect_success(root, {"wires": [{"wireID": wire_id}]}, spec,
                                       request)
        self.assertEqual(checked, {"compatibilityPassed": True,
                                   "reason": "native and host schema valid"})


class DeepSeekLiveBoundaryTests(unittest.IsolatedAsyncioTestCase):
    async def test_wrong_authorization_stops_before_catalogue_and_key(self) -> None:
        with TemporaryDirectory() as temporary:
            run_dir = Path(temporary) / RUN_ID
            run_dir.mkdir()
            gate = {"authorizationPhrase": AUTH_PREFIX + "ABCDEF0123456789",
                    "hardLimitUSD": HARD_LIMIT_USD}
            calls = {"catalogue": 0, "key": 0}

            def forbidden_catalogue(*args: object, **kwargs: object) -> object:
                calls["catalogue"] += 1
                raise AssertionError("catalogue must not be fetched")

            def forbidden_key() -> str:
                calls["key"] += 1
                raise AssertionError("credential must not be read")

            with (patch("paceprompt_eval.issue145_deepseek_probe_gate._validate_gate",
                        return_value=(run_dir, gate)),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate.snapshot_catalogue",
                        side_effect=forbidden_catalogue)):
                with self.assertRaisesRegex(RuntimeError, "exact DeepSeek live authorization"):
                    await run_live(run_id=RUN_ID, authorization="wrong",
                                   spending_limit_usd=HARD_LIMIT_USD,
                                   api_key_lookup=forbidden_key)
            self.assertEqual(calls, {"catalogue": 0, "key": 0})
            self.assertEqual(list(run_dir.iterdir()), [])

    async def test_price_increase_stops_before_key(self) -> None:
        with TemporaryDirectory() as temporary:
            run_dir = Path(temporary) / RUN_ID
            run_dir.mkdir()
            gate = {"authorizationPhrase": "exact", "hardLimitUSD": HARD_LIMIT_USD,
                    "selectedEndpoint": {"requestedModelID": "deepseek/deepseek-v4-flash-0731",
                                         "inputPricePerToken": "0.00000006",
                                         "outputPricePerToken": "0.00000018"}}
            endpoint = {**gate["selectedEndpoint"], "inputPricePerToken": "0.00000007",
                        "status": 0}
            profile = {"oneSendConservativeUSD": "0.00305826"}
            request = b"{}"
            spec = type("Spec", (), {"requested_model_id": endpoint["requestedModelID"],
                                     "required_parameters": (), "temperature": None,
                                     "reasoning": None})()
            key_calls = []
            with (patch("paceprompt_eval.issue145_deepseek_probe_gate._validate_gate",
                        return_value=(run_dir, gate)),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate._ratified",
                        return_value=(profile, request, spec)),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate.snapshot_catalogue",
                        return_value={"selected": [endpoint]}),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate.compare_catalogues")):
                with self.assertRaisesRegex(RuntimeError, "price is invalid or increased"):
                    await run_live(run_id=RUN_ID, authorization="exact",
                                   spending_limit_usd=HARD_LIMIT_USD,
                                   api_key_lookup=lambda: key_calls.append(1))
            self.assertEqual(key_calls, [])

    async def test_mocked_one_send_preserves_budget_and_manual_decision(self) -> None:
        if not safe_run_dir(PROFILE_RUN_ID, create=False).is_dir():
            self.skipTest("ignored ratified profile is absent")
        profile, request, spec = await asyncio.to_thread(_ratified)
        endpoint = profile["selectedEndpoint"]
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_dir = root / RUN_ID
            run_dir.mkdir()
            gate = await asyncio.to_thread(lambda: _sealed_gate(_prepared_gate()))
            sends = []

            def handler(outbound: httpx2.Request) -> httpx2.Response:
                sends.append(outbound)
                self.assertEqual(hashlib.sha256(outbound.content).hexdigest(),
                                 profile["requestSha256"])
                self.assertEqual(outbound.headers["Authorization"], "Bearer synthetic-key")
                return httpx2.Response(200, json={
                    "model": spec.requested_model_id,
                    "provider": endpoint["reportedProviderName"],
                    "choices": [{"finish_reason": "stop", "message": {"content": "{}"}}],
                })

            with (patch("paceprompt_eval.issue145_deepseek_probe_gate._validate_gate",
                        return_value=(run_dir, gate)),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate._ratified",
                        return_value=(profile, request, spec)),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate.RUNS_ROOT", root),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate.snapshot_catalogue",
                        return_value={"selected": [endpoint]}),
                  patch("paceprompt_eval.issue145_deepseek_probe_gate._inspect_success",
                        return_value={"compatibilityPassed": True, "reason": "synthetic-valid"})):
                report = await run_live(
                    run_id=RUN_ID, authorization=gate["authorizationPhrase"],
                    spending_limit_usd=HARD_LIMIT_USD,
                    api_key_lookup=lambda: "synthetic-key",
                    transport=httpx2.MockTransport(handler),
                )
            self.assertEqual(len(sends), 1)
            self.assertEqual(report["scoredHeldoutCalls"], 0)
            self.assertEqual(report["providerDecision"],
                             "requiresSeparateHumanEvidenceAcceptance")
            self.assertEqual(Decimal(report["chargedWorstCaseUSD"]),
                             Decimal(profile["oneSendConservativeUSD"]))
            self.assertNotIn("synthetic-key", json.dumps(report))
            self.assertEqual(json.loads((run_dir / "live-state.json").read_text())[
                "status"], "completeAwaitingHumanEvidenceAcceptance")
