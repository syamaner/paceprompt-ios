from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from paceprompt_eval.catalogue import MODELS_URL, endpoint_url, snapshot_catalogue
from paceprompt_eval.curl_probe import CurlProbeRun
from paceprompt_eval.open_weight_probe import (
    BASETEN_TOOL_EXPECTED_MODELS,
    BASETEN_TOOL_PROFILE,
    EXPECTED_MODELS,
    MODELS,
    REPLACEMENT_PROFILE,
    REPROBE_EXPECTED_MODELS,
    REPORT_CONTRACT,
    RUN_POLICY,
    cost_preflight,
    verify_configuration,
    verify_prior_evidence,
    write_probe_payloads,
)
from paceprompt_eval.openrouter import ModelSpec, load_model_specs
from paceprompt_eval.v3 import sha256_file


def selected_endpoints(expected_models=EXPECTED_MODELS) -> list[dict]:
    return [
        {
            "requestedModelID": requested,
            "canonicalRevision": revision,
            "configuredCanonicalRevision": revision,
            "providerEndpoint": endpoint,
            "reportedProviderName": endpoint.split("/", 1)[0].title(),
            "configuredQuantization": quantization,
            "reportedQuantization": quantization or "unknown",
            "inputPricePerToken": "0.0000005",
            "outputPricePerToken": "0.000003125",
            "supportedParameters": ["max_tokens", "response_format", "structured_outputs"],
            "status": 0,
        }
        for requested, revision, endpoint, quantization in expected_models
    ]


class OpenWeightProbeTests(unittest.IsolatedAsyncioTestCase):
    def test_equivalent_duplicate_endpoint_tags_require_explicit_admission(self) -> None:
        spec = ModelSpec(
            requested_model_id="nvidia/nemotron-3-ultra-550b-a55b",
            canonical_revision="nvidia/nemotron-3-ultra-550b-a55b-20260604",
            provider_endpoint="baseten/fp4",
            quantization="fp4",
            role="compatibilityDiagnostic",
            temperature=None,
            top_p=None,
            reasoning=None,
        )
        endpoint = {
            "model_id": spec.requested_model_id,
            "name": "BaseTen | Nemotron Ultra",
            "provider_name": "BaseTen",
            "tag": "baseten/fp4",
            "quantization": "fp4",
            "pricing": {"prompt": "0.0000006", "completion": "0.0000024"},
            "supported_parameters": ["max_tokens", "tools", "tool_choice"],
            "status": 0,
        }
        documents = {
            MODELS_URL: {
                "data": [
                    {
                        "id": spec.requested_model_id,
                        "canonical_slug": spec.canonical_revision,
                    }
                ]
            },
            endpoint_url(spec.canonical_revision): {
                "data": {
                    "endpoints": [
                        dict(endpoint, uptime_last_30m=100),
                        dict(endpoint, uptime_last_30m=99),
                    ]
                }
            },
        }

        def fetch(url: str) -> bytes:
            return json.dumps(documents[url]).encode()

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "found 2"):
                snapshot_catalogue(
                    root / "rejected",
                    (spec,),
                    fetch=fetch,
                    required_parameters={"max_tokens", "tools", "tool_choice"},
                )
            snapshot = snapshot_catalogue(
                root / "accepted",
                (spec,),
                fetch=fetch,
                required_parameters={"max_tokens", "tools", "tool_choice"},
                allow_equivalent_duplicate_tags=True,
            )
            selected = snapshot["selected"][0]
            self.assertEqual(selected["matchingEndpointCount"], 2)
            self.assertTrue(selected["equivalentDuplicateEndpointTag"])
            self.assertIn("materialEndpointSha256", selected)

    def test_ratified_configuration_is_exact(self) -> None:
        report = verify_configuration()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(len(load_model_specs(MODELS)), 9)
        self.assertEqual(json.loads(RUN_POLICY.read_text())["spending"]["hardLimit"], "0.25")

    def test_ratified_replacement_configuration_is_exact(self) -> None:
        report = verify_configuration(profile=REPLACEMENT_PROFILE)
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(len(load_model_specs(REPLACEMENT_PROFILE.models)), 4)
        policy = json.loads(REPLACEMENT_PROFILE.run_policy.read_text())
        self.assertEqual(policy["scope"]["maximumCalls"], 4)
        self.assertEqual(
            policy["priorEvidence"]["reportSha256"],
            "e86c80119c187546f0fedb9862f73a612e2e194ad5130b643481914869be14c0",
        )
        self.assertEqual(len(policy["priorEvidence"]["lockedPassingRoutes"]), 5)

    def test_ratified_baseten_tool_configuration_is_exact(self) -> None:
        report = verify_configuration(profile=BASETEN_TOOL_PROFILE)
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(len(load_model_specs(BASETEN_TOOL_PROFILE.models)), 1)
        policy = json.loads(BASETEN_TOOL_PROFILE.run_policy.read_text())
        self.assertEqual(policy["scope"]["maximumCalls"], 1)
        self.assertEqual(policy["request"]["forcedToolName"], "submit_probe_result")
        self.assertEqual(
            policy["priorEvidence"]["gateSha256"],
            "58e8b5f6727c05786d0d32bf8750d0f83d1864919628b55ceacb1548857e9e59",
        )

    def test_four_replacement_payloads_are_strict_and_route_pinned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints(REPROBE_EXPECTED_MODELS)
            manifest = write_probe_payloads(
                run_dir, selected, profile=REPLACEMENT_PROFILE
            )
            self.assertEqual(len(manifest), 4)
            for item, spec in zip(
                manifest,
                load_model_specs(REPLACEMENT_PROFILE.models),
                strict=True,
            ):
                body = json.loads((run_dir / item["payloadPath"]).read_text())
                self.assertEqual(body["provider"]["only"], [spec.provider_endpoint])
                self.assertEqual(body["provider"]["quantizations"], [spec.quantization])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertTrue(body["provider"]["require_parameters"])
                self.assertEqual(body["provider"]["data_collection"], "deny")
                self.assertTrue(body["provider"]["zdr"])
            preflight = cost_preflight(
                {"selected": selected},
                run_dir,
                manifest,
                profile=REPLACEMENT_PROFILE,
            )
            self.assertTrue(preflight["admitted"])
            self.assertEqual(preflight["callCount"], 4)

    def test_replacement_prior_evidence_is_reverified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            locked = REPLACEMENT_PROFILE.prior_evidence["lockedPassingRoutes"]
            report = {
                "attempts": [
                    {
                        "modelID": item["requestedModelID"],
                        "statusCode": 200,
                        "routeIdentityMatches": True,
                        "strictSchemaSatisfied": True,
                    }
                    for item in locked
                ]
            }
            (run_dir / "curl-probe-report.json").write_text(json.dumps(report))
            gate = {
                "selectedEndpoints": [
                    {
                        "requestedModelID": item["requestedModelID"],
                        "canonicalRevision": item["canonicalRevision"],
                        "providerEndpoint": item["providerEndpoint"],
                        "configuredQuantization": item["quantization"],
                    }
                    for item in locked
                ]
            }
            (run_dir / "operator-gate.json").write_text(json.dumps(gate))
            prior = dict(
                REPLACEMENT_PROFILE.prior_evidence,
                reportSha256=sha256_file(run_dir / "curl-probe-report.json"),
            )
            profile = replace(REPLACEMENT_PROFILE, prior_evidence=prior)
            with patch(
                "paceprompt_eval.open_weight_probe.safe_run_dir",
                return_value=run_dir,
            ):
                verify_prior_evidence(profile)
                (run_dir / "curl-probe-report.json").write_text("{}")
                with self.assertRaisesRegex(RuntimeError, "report hash changed"):
                    verify_prior_evidence(profile)

    def test_baseten_payload_forces_one_schema_shaped_tool(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints(BASETEN_TOOL_EXPECTED_MODELS)
            manifest = write_probe_payloads(
                run_dir, selected, profile=BASETEN_TOOL_PROFILE
            )
            self.assertEqual(len(manifest), 1)
            self.assertEqual(manifest[0]["stageID"], "01-minimal-forced-tool")
            self.assertEqual(manifest[0]["schema"], "trivialToolArguments")
            body = json.loads((run_dir / manifest[0]["payloadPath"]).read_text())
            self.assertNotIn("response_format", body)
            self.assertEqual(
                body["tool_choice"],
                {
                    "type": "function",
                    "function": {"name": "submit_probe_result"},
                },
            )
            self.assertEqual(
                body["tools"][0]["function"]["parameters"],
                {
                    "type": "object",
                    "properties": {"ok": {"type": "boolean", "const": True}},
                    "required": ["ok"],
                    "additionalProperties": False,
                },
            )
            self.assertEqual(body["provider"]["only"], ["baseten/fp4"])
            self.assertFalse(body["provider"]["allow_fallbacks"])

    async def test_baseten_tool_arguments_are_diagnosed_and_validated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints(BASETEN_TOOL_EXPECTED_MODELS)
            manifest = write_probe_payloads(
                run_dir, selected, profile=BASETEN_TOOL_PROFILE
            )
            preflight = cost_preflight(
                {"selected": selected},
                run_dir,
                manifest,
                profile=BASETEN_TOOL_PROFILE,
            )
            gate = {
                "reportContractVersion": BASETEN_TOOL_PROFILE.report_contract,
                "purpose": "test",
                "scope": {"heldoutCalls": 0},
                "probeManifest": manifest,
                "selectedEndpoints": selected,
                "diagnosticTransport": "forcedToolArguments",
                "diagnosticToolName": "submit_probe_result",
                "diagnosticExpectedOutput": {"ok": True},
                "costPreflight": preflight,
            }
            response = {
                "model": selected[0]["canonicalRevision"],
                "provider": selected[0]["reportedProviderName"],
                "choices": [
                    {
                        "message": {
                            "content": None,
                            "tool_calls": [
                                {
                                    "type": "function",
                                    "function": {
                                        "name": "submit_probe_result",
                                        "arguments": "{\"ok\":true}",
                                    },
                                }
                            ],
                        }
                    }
                ],
                "usage": {"cost": 0.0001},
            }
            runner = CurlProbeRun(
                run_dir=run_dir,
                gate=gate,
                api_key="mock-local-only",
                execution_policy={
                    "minimumInterCallDelaySeconds": 0,
                    "connectTimeoutSeconds": 15,
                    "attemptTimeoutSeconds": 120,
                    "abortHTTPStatusCodes": [401, 402, 403],
                },
                spending_limit_usd="0.25",
            )
            with patch(
                "paceprompt_eval.curl_probe.invoke_curl",
                new=AsyncMock(return_value=(200, 0.1, response, "", 0)),
            ):
                report = await runner.execute()
            attempt = report["attempts"][0]
            self.assertTrue(attempt["routeIdentityMatches"])
            self.assertEqual(attempt["toolCallCount"], 1)
            self.assertTrue(attempt["toolNameMatches"])
            self.assertTrue(attempt["toolArgumentsJSONValid"])
            self.assertTrue(attempt["strictSchemaSatisfied"])

    def test_nine_payloads_are_minimal_strict_and_route_pinned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints()
            manifest = write_probe_payloads(run_dir, selected)
            self.assertEqual(len(manifest), 9)
            for item, spec in zip(manifest, load_model_specs(MODELS), strict=True):
                body = json.loads((run_dir / item["payloadPath"]).read_text())
                self.assertEqual(
                    set(body),
                    {"model", "messages", "provider", "response_format", "max_tokens", "stream"},
                )
                self.assertEqual(body["model"], spec.requested_model_id)
                self.assertEqual(body["messages"], [{
                    "role": "user",
                    "content": "Return a JSON object whose ok property is true.",
                }])
                self.assertEqual(body["max_tokens"], 1024)
                self.assertFalse(body["stream"])
                self.assertEqual(body["provider"]["order"], [spec.provider_endpoint])
                self.assertEqual(body["provider"]["only"], [spec.provider_endpoint])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertTrue(body["provider"]["require_parameters"])
                self.assertEqual(body["provider"]["data_collection"], "deny")
                self.assertTrue(body["provider"]["zdr"])
                self.assertEqual(
                    body["provider"].get("quantizations"),
                    None if spec.quantization is None else [spec.quantization],
                )
                self.assertEqual(
                    body["response_format"]["json_schema"]["schema"],
                    {
                        "type": "object",
                        "properties": {"ok": {"type": "boolean", "const": True}},
                        "required": ["ok"],
                        "additionalProperties": False,
                    },
                )
                self.assertNotIn("reasoning", body)
                self.assertNotIn("temperature", body)
                self.assertNotIn("top_p", body)
            snapshot = {"selected": selected}
            preflight = cost_preflight(snapshot, run_dir, manifest)
            self.assertTrue(preflight["admitted"])
            self.assertEqual(preflight["callCount"], 9)
            self.assertLessEqual(float(preflight["worstCaseUSD"]), 0.25)

    async def test_success_diagnostics_capture_exact_json_and_route_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints()
            manifest = write_probe_payloads(run_dir, selected)
            preflight = cost_preflight({"selected": selected}, run_dir, manifest)
            gate = {
                "reportContractVersion": REPORT_CONTRACT,
                "purpose": "test",
                "scope": {"heldoutCalls": 0},
                "probeManifest": manifest,
                "selectedEndpoints": selected,
                "diagnosticExpectedOutput": {"ok": True},
                "costPreflight": preflight,
            }
            responses = [
                (
                    200,
                    0.1,
                    {
                        "model": endpoint["canonicalRevision"],
                        "provider": endpoint["reportedProviderName"],
                        "choices": [{"message": {"content": "{\"ok\":true}"}}],
                        "usage": {"cost": 0.0001},
                    },
                    "",
                    0,
                )
                for endpoint in selected
            ]
            runner = CurlProbeRun(
                run_dir=run_dir,
                gate=gate,
                api_key="mock-local-only",
                execution_policy={
                    "minimumInterCallDelaySeconds": 0,
                    "connectTimeoutSeconds": 15,
                    "attemptTimeoutSeconds": 120,
                    "abortHTTPStatusCodes": [401, 402, 403],
                },
                spending_limit_usd="0.25",
            )
            with patch(
                "paceprompt_eval.curl_probe.invoke_curl",
                new=AsyncMock(side_effect=responses),
            ):
                report = await runner.execute()
            self.assertEqual(report["status"], "completeAwaitingHumanEvidenceRatification")
            self.assertEqual(len(report["attempts"]), 9)
            self.assertTrue(all(item["routeIdentityMatches"] for item in report["attempts"]))
            self.assertTrue(all(item["contentJSONValid"] for item in report["attempts"]))
            self.assertTrue(all(item["strictSchemaSatisfied"] for item in report["attempts"]))

    async def test_global_auth_failure_preserves_remaining_attempts_without_retry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            selected = selected_endpoints()
            manifest = write_probe_payloads(run_dir, selected)
            preflight = cost_preflight({"selected": selected}, run_dir, manifest)
            gate = {
                "reportContractVersion": REPORT_CONTRACT,
                "purpose": "test",
                "scope": {"heldoutCalls": 0},
                "probeManifest": manifest,
                "selectedEndpoints": selected,
                "diagnosticExpectedOutput": {"ok": True},
                "costPreflight": preflight,
            }
            runner = CurlProbeRun(
                run_dir=run_dir,
                gate=gate,
                api_key="mock-local-only",
                execution_policy={
                    "minimumInterCallDelaySeconds": 0,
                    "connectTimeoutSeconds": 15,
                    "attemptTimeoutSeconds": 120,
                    "abortHTTPStatusCodes": [401, 402, 403],
                },
                spending_limit_usd="0.25",
            )
            mocked = AsyncMock(return_value=(401, 0.1, {"error": "unauthorized"}, "", 0))
            with patch("paceprompt_eval.curl_probe.invoke_curl", new=mocked):
                report = await runner.execute()
            self.assertEqual(mocked.await_count, 1)
            self.assertEqual(
                report["status"],
                "abortedByGlobalHTTPStatusAwaitingHumanEvidenceRatification",
            )
            self.assertEqual(len(report["attempts"]), 9)
            self.assertEqual(report["attempts"][0]["statusCode"], 401)
            self.assertTrue(
                all(
                    item.get("reasonCategory") == "globalHTTPAbort"
                    for item in report["attempts"][1:]
                )
            )


if __name__ == "__main__":
    unittest.main()
