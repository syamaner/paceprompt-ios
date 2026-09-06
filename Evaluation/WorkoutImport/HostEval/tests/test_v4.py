from __future__ import annotations

import asyncio
from collections import Counter
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import httpx2

from paceprompt_eval.openrouter import (
    FORCED_TOOL_ARGUMENTS,
    NATIVE_JSON_SCHEMA,
    ModelSpec,
    assert_payload_controls,
    capture_wire_payload,
    generate_with_capture,
    load_model_specs,
)
from paceprompt_eval.runner import (
    authority_preserved,
    completed_content,
    parse_completed_output,
)
from paceprompt_eval.transport_strategy import strategy_for
from paceprompt_eval.v3 import V3LiveRun, asset_paths, load_cases, model_messages_for_strategy
from paceprompt_eval.v4 import (
    BASETEN_MODEL_ID,
    MODELS,
    V4LiveRun,
    aggregate,
    mock_payloads,
    prepare_gate,
    queue_document,
    required_parameter_contracts,
    verify,
)


def selected_endpoints() -> list[dict]:
    return [
        {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision,
            "configuredCanonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "reportedProviderName": (
                "BaseTen" if spec.requested_model_id == BASETEN_MODEL_ID else spec.provider_endpoint
            ),
            "configuredQuantization": spec.quantization,
            "reportedQuantization": spec.quantization or "unreported",
            "inputPricePerToken": "0.00000001",
            "outputPricePerToken": "0.00000002",
            "supportedParameters": list(spec.required_parameters),
            "status": "active",
            "rawEndpointSha256": "0" * 64,
        }
        for spec in load_model_specs(MODELS)
    ]


class OpenWeightV4Tests(unittest.TestCase):
    def test_v4_runner_inherits_v3_terminal_preservation_helpers(self) -> None:
        self.assertTrue(issubclass(V4LiveRun, V3LiveRun))
        self.assertTrue(callable(V4LiveRun._not_started))
        self.assertTrue(callable(V4LiveRun._evidence_integrity))

    def test_configuration_and_queue_are_closed_over_nine_routes(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["models"], 9)
        self.assertEqual(report["warmups"], 9)
        self.assertEqual(report["scoredAttempts"], 2133)
        self.assertEqual(report["totalProviderCalls"], 2142)
        queue = queue_document()
        self.assertEqual(len(queue["entries"]), 2133)
        self.assertEqual(set(Counter(item["modelID"] for item in queue["entries"]).values()), {237})

    def test_response_and_parameter_contracts_are_per_route(self) -> None:
        specs = load_model_specs(MODELS)
        contracts = required_parameter_contracts(specs)
        baseten = next(spec for spec in specs if spec.requested_model_id == BASETEN_MODEL_ID)
        native = [spec for spec in specs if spec.requested_model_id != BASETEN_MODEL_ID]
        self.assertEqual(baseten.response_contract, FORCED_TOOL_ARGUMENTS)
        self.assertEqual(contracts[BASETEN_MODEL_ID], {"max_tokens", "tools", "tool_choice"})
        self.assertEqual(baseten.forced_tool_name, "submit_workout_import_result")
        self.assertTrue(all(spec.response_contract == NATIVE_JSON_SCHEMA for spec in native))
        self.assertTrue(
            all(
                contracts[spec.requested_model_id]
                == {"max_tokens", "response_format", "structured_outputs"}
                for spec in native
            )
        )
        with self.assertRaises(ValueError):
            ModelSpec.from_json(
                {
                    "requestedModelID": "unknown/model",
                    "canonicalRevision": "unknown/model-1",
                    "providerEndpoint": "provider",
                    "quantization": None,
                    "role": "candidate",
                    "temperature": None,
                    "topP": None,
                    "reasoning": None,
                    "responseContract": "invented",
                }
            )

    def test_forced_tool_response_has_structural_authority_only_when_exact(self) -> None:
        spec = next(
            spec for spec in load_model_specs(MODELS) if spec.requested_model_id == BASETEN_MODEL_ID
        )
        arguments = '{"contractVersion":"workout-import-model-output/v2"}'
        exchange = {
            "requests": [
                {
                    "body": {
                        "tools": [
                            {
                                "type": "function",
                                "function": {"name": spec.forced_tool_name, "parameters": {}},
                            }
                        ],
                        "tool_choice": {
                            "type": "function",
                            "function": {"name": spec.forced_tool_name},
                        },
                    }
                }
            ],
            "responses": [
                {
                    "body": {
                        "choices": [
                            {
                                "message": {
                                    "role": "assistant",
                                    "content": None,
                                    "tool_calls": [
                                        {
                                            "type": "function",
                                            "function": {
                                                "name": spec.forced_tool_name,
                                                "arguments": arguments,
                                            },
                                        }
                                    ],
                                }
                            }
                        ]
                    }
                }
            ],
        }
        self.assertEqual(completed_content(exchange, {}, spec), arguments)
        self.assertTrue(authority_preserved(exchange, arguments, spec))
        changed = json.loads(json.dumps(exchange))
        changed["responses"][0]["body"]["choices"][0]["message"]["tool_calls"][0]["function"]["name"] = "wrong"
        self.assertEqual(completed_content(changed, {}, spec), "")
        self.assertFalse(authority_preserved(changed, "", spec))

    def test_every_complete_mock_payload_matches_its_contract(self) -> None:
        async def exercise() -> None:
            specs = load_model_specs(MODELS)
            warmup = next(
                case for case in load_cases(asset_paths()["developmentCases"])
                if case["id"] == "WI-V3-D020"
            )
            for spec in specs:
                strategy = strategy_for(spec)
                payload = await capture_wire_payload(
                    spec,
                    strategy.schema(),
                    model_messages_for_strategy(warmup, strategy),
                    max_price_per_million={"prompt": 0.01, "completion": 0.02},
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload,
                    spec,
                    strategy.schema(),
                    {"prompt": 0.01, "completion": 0.02},
                    schema_name=strategy.schema_name,
                )
                body = payload["body"]
                self.assertEqual(body["provider"]["only"], [spec.provider_endpoint])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertTrue(body["provider"]["zdr"])
                self.assertNotIn("temperature", body)
                self.assertNotIn("top_p", body)
                self.assertNotIn("reasoning", body)
                if spec.response_contract == FORCED_TOOL_ARGUMENTS:
                    self.assertNotIn("response_format", body)
                    self.assertEqual(body["tools"][0]["function"]["parameters"], strategy.schema())
                else:
                    self.assertNotIn("tools", body)
                    self.assertEqual(
                        body["response_format"]["json_schema"]["schema"], strategy.schema()
                    )

        asyncio.run(exercise())

    def test_forced_tool_wire_response_normalizes_through_unchanged_schema(self) -> None:
        async def exercise() -> None:
            spec = next(
                item
                for item in load_model_specs(MODELS)
                if item.requested_model_id == BASETEN_MODEL_ID
            )
            strategy = strategy_for(spec)
            warmup = next(
                case
                for case in load_cases(asset_paths()["developmentCases"])
                if case["id"] == "WI-V3-D020"
            )
            projected = strategy.project_output(warmup["expected"]["modelOutput"])

            async def handler(request: httpx2.Request) -> httpx2.Response:
                return httpx2.Response(
                    200,
                    request=request,
                    json={
                        "id": "mock-forced-tool",
                        "object": "chat.completion",
                        "created": 0,
                        "model": spec.canonical_revision,
                        "provider": "BaseTen",
                        "choices": [
                            {
                                "index": 0,
                                "finish_reason": "tool_calls",
                                "message": {
                                    "role": "assistant",
                                    "content": None,
                                    "tool_calls": [
                                        {
                                            "id": "call-1",
                                            "type": "function",
                                            "function": {
                                                "name": spec.forced_tool_name,
                                                "arguments": json.dumps(projected),
                                            },
                                        }
                                    ],
                                },
                            }
                        ],
                        "usage": {
                            "prompt_tokens": 1,
                            "completion_tokens": 1,
                            "total_tokens": 2,
                            "cost": 0,
                        },
                    },
                )

            output, exchange = await generate_with_capture(
                spec,
                strategy.schema(),
                model_messages_for_strategy(warmup, strategy),
                "mock-local-only",
                transport=httpx2.MockTransport(handler),
                schema_name=strategy.schema_name,
            )
            content = completed_content(exchange, output.model_dump(mode="json"), spec)
            observed = parse_completed_output(
                content,
                json.loads(asset_paths()["modelSchema"].read_text(encoding="utf-8")),
                strategy.schema(),
                strategy.normalize_output,
                finish_reason="tool_calls",
                output_limit_is_invalid=True,
            )
            self.assertEqual(observed["structure"], "valid")
            self.assertTrue(authority_preserved(exchange, content, spec))

        asyncio.run(exercise())

    def test_complete_gate_is_mocked_without_credential_or_provider_call(self) -> None:
        specs = load_model_specs(MODELS)
        models_body = {
            "data": [
                {"id": spec.requested_model_id, "canonical_slug": spec.canonical_revision}
                for spec in specs
            ]
        }

        def fake_fetch(url: str) -> bytes:
            if url == "https://openrouter.ai/api/v1/models":
                return json.dumps(models_body).encode()
            spec = next(item for item in specs if item.canonical_revision in url)
            endpoint = {
                "tag": spec.provider_endpoint,
                "provider_name": "BaseTen" if spec.requested_model_id == BASETEN_MODEL_ID else spec.provider_endpoint,
                "supported_parameters": list(spec.required_parameters),
                "quantization": spec.quantization,
                "pricing": {"prompt": "0.00000001", "completion": "0.00000002"},
                "status": "active",
            }
            endpoints = [endpoint, dict(endpoint)] if spec.requested_model_id == BASETEN_MODEL_ID else [endpoint]
            return json.dumps({"data": {"endpoints": endpoints}}).encode()

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(prepare_gate("offline-open-weight-v4", fetch=fake_fetch))
            run_dir = Path(directory) / "offline-open-weight-v4"
            serialized = b"".join(
                path.read_bytes() for path in run_dir.rglob("*") if path.is_file()
            )
        self.assertEqual(gate["providerCalls"], 0)
        self.assertFalse(gate["credentialRead"])
        self.assertEqual(gate["spendUSD"], "0.00")
        self.assertEqual(gate["costPreflight"]["callCount"], 2142)
        self.assertTrue(gate["costPreflight"]["admitted"])
        self.assertIsNotNone(gate["authorizationPhrase"])
        self.assertEqual(gate["responseContracts"][BASETEN_MODEL_ID], FORCED_TOOL_ARGUMENTS)
        selected = next(
            item for item in gate["selectedEndpoints"]
            if item["requestedModelID"] == BASETEN_MODEL_ID
        )
        self.assertEqual(selected["matchingEndpointCount"], 2)
        self.assertTrue(selected["equivalentDuplicateEndpointTag"])
        self.assertNotIn(b"must-not-be-read", serialized)
        self.assertNotIn(b'"rationale"', serialized)
        self.assertNotIn(b'"conventionTags"', serialized)

    def test_aggregate_reports_contract_complexity_and_keeps_sol_selected(self) -> None:
        cases = load_cases(asset_paths()["heldoutCases"])
        specs = load_model_specs(MODELS)
        attempts = []
        for spec in specs:
            for repetition in range(1, 4):
                for case in cases:
                    attempts.append(
                        {
                            "attemptID": f"r{repetition}-{case['id']}-{spec.requested_model_id}",
                            "kind": "scored",
                            "caseID": case["id"],
                            "modelID": spec.requested_model_id,
                            "repetitionIndex": repetition,
                            "terminal": True,
                            "hostClassification": "modelQuality",
                            "schemaValid": True,
                            "outcomeExact": True,
                            "reasonExact": True,
                            "pathsExact": True,
                            "proposalFidelity": case["category"] == "proposal",
                            "mappingValidatorAgreement": case["category"] == "proposal",
                            "authorityPreserved": True,
                            "providerLatencyMilliseconds": 1000,
                            "reportedCostUSD": "0.001",
                        }
                    )
        report = aggregate(attempts, cases, specs)
        self.assertEqual(report["currentHumanSelectedProvider"], "openai/gpt-5.6-sol")
        self.assertFalse(report["productionProviderChanged"])
        self.assertIsNone(report["automaticWinner"])
        self.assertEqual(
            report["models"][BASETEN_MODEL_ID]["transportSimplicityRank"], 2
        )
        native = next(spec for spec in specs if spec.response_contract == NATIVE_JSON_SCHEMA)
        self.assertEqual(report["models"][native.requested_model_id]["transportSimplicityRank"], 1)
        self.assertNotIn(BASETEN_MODEL_ID, report["tieBreakTrace"]["afterResponseContractSimplicity"])


if __name__ == "__main__":
    unittest.main()
