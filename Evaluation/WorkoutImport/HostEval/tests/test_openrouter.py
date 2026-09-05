from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import httpx2

from paceprompt_eval.openrouter import (
    MOCK_API_KEY,
    CapturedGenerationError,
    assert_payload_controls,
    capture_wire_payload,
    generate_with_capture,
    load_model_specs,
    redact,
)
from paceprompt_eval.task import (
    DEVELOPMENT_CASES,
    DIAGNOSTIC_MODELS,
    FLAT_STRATEGY_DIAGNOSTIC_MODELS,
    FLAT_STRATEGY_MODELS,
    SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS,
    SEMANTIC_JSON_STRATEGY_MODELS,
    MODEL_SCHEMA,
    MODELS,
    TRANSPORT_SCHEMA,
    STRATEGY_DIAGNOSTIC_MODELS,
    STRATEGY_MODELS,
    _write_curl_probe_payloads,
    load_cases,
    model_messages,
    model_messages_for_strategy,
    strict_json_load,
)
from paceprompt_eval.transport_strategy import strategy_for


class OpenRouterPayloadTests(unittest.IsolatedAsyncioTestCase):
    async def test_curl_probe_ladder_is_frozen_and_contains_no_credential(self) -> None:
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "inputPricePerToken": "0.0000003",
                "outputPricePerToken": "0.0000025",
            }
            for spec in load_model_specs(DIAGNOSTIC_MODELS)
        ]
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            manifest = await _write_curl_probe_payloads(run_dir, selected)
            self.assertEqual(len(manifest), 10)
            self.assertEqual(
                [item["stageID"] for item in manifest],
                [stage for stage in (
                    "01-minimal-unstructured",
                    "02-minimal-trivial-schema",
                    "03-minimal-full-schema",
                    "04-full-prompt-trivial-schema",
                    "05-full-prompt-full-schema",
                ) for _ in range(2)],
            )
            for item in manifest:
                body = json.loads((run_dir / item["payloadPath"]).read_text())
                expected_effort = (
                    "minimal" if item["modelID"].endswith("flash-lite") else "medium"
                )
                self.assertEqual(body["reasoning"], {"effort": expected_effort})
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertEqual(body["provider"]["only"], ["google-ai-studio"])
                self.assertNotIn(MOCK_API_KEY, json.dumps(body))
                if item["stageID"] == "01-minimal-unstructured":
                    self.assertNotIn("response_format", body)
                if item["stageID"] == "05-full-prompt-full-schema":
                    self.assertEqual(len(body["messages"]), 18)
                    self.assertEqual(
                        body["response_format"]["json_schema"]["schema"],
                        strict_json_load(TRANSPORT_SCHEMA),
                    )

    async def test_redaction_removes_credentials_response_cookies_and_user_ids(self) -> None:
        value = {
            "headers": {
                "authorization": "Bearer secret-key",
                "set-cookie": "opaque-cookie",
            },
            "body": {
                "user_id": "opaque-user",
                "message": "failed for user_privateIdentifier123 and secret-key",
            },
        }
        redacted = redact(value, ("secret-key",))
        self.assertEqual(redacted["headers"]["authorization"], "Bearer [REDACTED]")
        self.assertEqual(redacted["headers"]["set-cookie"], "[REDACTED]")
        self.assertEqual(redacted["body"]["user_id"], "[REDACTED]")
        self.assertEqual(
            redacted["body"]["message"],
            "failed for [REDACTED_USER_ID] and [REDACTED]",
        )

    async def test_complete_wire_body_for_every_ratified_model(self) -> None:
        schema = strict_json_load(TRANSPORT_SCHEMA)
        messages = model_messages(load_cases(DEVELOPMENT_CASES)[0])
        max_price = {"prompt": 2.0, "completion": 10.0}
        for spec in load_model_specs(MODELS):
            with self.subTest(model=spec.requested_model_id):
                payload = await capture_wire_payload(
                    spec, schema, messages, max_price_per_million=max_price
                )
                assert_payload_controls(payload, spec, schema, max_price)
                body = payload["body"]
                expected_keys = {"model", "messages", "provider", "response_format"}
                expected_keys.add("max_tokens")
                if spec.reasoning is not None:
                    expected_keys.add("reasoning")
                if spec.temperature is not None:
                    expected_keys.update({"temperature", "top_p"})
                self.assertEqual(set(body), expected_keys)
                self.assertEqual(len(body["messages"]), 18)
                self.assertEqual(
                    body["response_format"]["json_schema"]["schema"], schema
                )
                self.assertEqual(body["provider"]["max_price"], max_price)
                self.assertNotIn(MOCK_API_KEY, json.dumps(payload))

    async def test_gemini_diagnostic_enables_reasoning_without_effort_or_exclusion(self) -> None:
        schema = strict_json_load(TRANSPORT_SCHEMA)
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(DIAGNOSTIC_MODELS):
            with self.subTest(model=spec.requested_model_id):
                payload = await capture_wire_payload(spec, schema, model_messages(warmup))
                assert_payload_controls(payload, spec, schema)
                body = payload["body"]
                self.assertEqual(body["reasoning"], {"enabled": True})
                self.assertEqual(body["temperature"], 0)
                self.assertEqual(body["top_p"], 1)
                self.assertEqual(body["response_format"]["json_schema"]["schema"], schema)
                self.assertEqual(body["provider"]["order"], ["google-ai-studio"])
                self.assertFalse(body["provider"]["allow_fallbacks"])

    async def test_v2_7_strategy_payload_is_flattened_hashed_and_route_pinned(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(STRATEGY_DIAGNOSTIC_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                schema = strategy.schema()
                messages = model_messages_for_strategy(warmup, strategy)
                payload = await capture_wire_payload(
                    spec,
                    schema,
                    messages,
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload, spec, schema, schema_name=strategy.schema_name
                )
                body = payload["body"]
                self.assertEqual(body["provider"]["only"], ["google-ai-studio"])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertEqual(
                    body["response_format"]["json_schema"]["name"],
                    "paceprompt_workout_import_transport_shallow_step_v2_7",
                )
                step_properties = schema["properties"]["outcome"]["properties"]["proposal"]["properties"]["steps"]["items"]["properties"]
                self.assertIn("durationValue", step_properties)
                self.assertNotIn("duration", step_properties)
                assistant_values = [
                    json.loads(message.content)
                    for message in messages
                    if message.role == "assistant"
                ]
                proposal_steps = [
                    step
                    for value in assistant_values
                    for step in value["outcome"]["proposal"]["steps"]
                ]
                self.assertTrue(proposal_steps)
                self.assertTrue(all("durationValue" in step for step in proposal_steps))
                self.assertTrue(all("duration" not in step for step in proposal_steps))

    async def test_v2_7_full_matrix_payloads_use_only_the_registered_strategy(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(STRATEGY_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                payload = await capture_wire_payload(
                    spec,
                    strategy.schema(),
                    model_messages_for_strategy(warmup, strategy),
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload,
                    spec,
                    strategy.schema(),
                    schema_name=strategy.schema_name,
                )
                self.assertEqual(
                    payload["body"]["response_format"]["json_schema"]["name"],
                    strategy.schema_name,
                )

    async def test_v2_8_gemini_payload_flattens_the_complete_envelope(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                schema = strategy.schema()
                messages = model_messages_for_strategy(warmup, strategy)
                payload = await capture_wire_payload(
                    spec,
                    schema,
                    messages,
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload, spec, schema, schema_name=strategy.schema_name
                )
                body = payload["body"]
                self.assertEqual(body["provider"]["only"], ["google-ai-studio"])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertEqual(
                    body["response_format"]["json_schema"]["name"],
                    "paceprompt_workout_import_transport_flat_envelope_v2_8",
                )
                self.assertTrue(body["response_format"]["json_schema"]["strict"])
                self.assertIn("outcomeType", schema["properties"])
                self.assertIn("proposalPresent", schema["properties"])
                self.assertNotIn("outcome", schema["properties"])
                self.assertNotIn("proposal", schema["properties"])
                self.assertEqual(len(body["messages"]), 18)
                assistant_values = [
                    json.loads(message.content)
                    for message in messages
                    if message.role == "assistant"
                ]
                self.assertEqual(len(assistant_values), 8)
                self.assertTrue(all("outcomeType" in value for value in assistant_values))
                self.assertTrue(all("outcome" not in value for value in assistant_values))
                self.assertTrue(all("proposal" not in value for value in assistant_values))
                self.assertTrue(
                    all(
                        "durationValue" in step and "duration" not in step
                        for value in assistant_values
                        for step in value["steps"]
                    )
                )

    async def test_v2_8_full_matrix_uses_only_registered_route_strategies(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(FLAT_STRATEGY_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                schema = strategy.schema()
                payload = await capture_wire_payload(
                    spec,
                    schema,
                    model_messages_for_strategy(warmup, strategy),
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload, spec, schema, schema_name=strategy.schema_name
                )
                self.assertEqual(
                    payload["body"]["response_format"]["json_schema"]["name"],
                    strategy.schema_name,
                )

    async def test_v2_9_gemini_payload_uses_profile_validated_string_envelope(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                schema = strategy.schema()
                self.assertEqual(strategy.schema_profile.validate(schema), ())
                messages = model_messages_for_strategy(warmup, strategy)
                payload = await capture_wire_payload(
                    spec,
                    schema,
                    messages,
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload, spec, schema, schema_name=strategy.schema_name
                )
                body = payload["body"]
                self.assertEqual(body["provider"]["only"], ["google-ai-studio"])
                self.assertFalse(body["provider"]["allow_fallbacks"])
                self.assertEqual(
                    body["response_format"]["json_schema"]["name"],
                    "paceprompt_workout_import_transport_semantic_json_v2_9",
                )
                self.assertTrue(body["response_format"]["json_schema"]["strict"])
                self.assertEqual(set(schema["properties"]), {"semanticJson"})
                self.assertEqual(len(body["messages"]), 18)
                assistant_values = [
                    json.loads(message.content)
                    for message in messages
                    if message.role == "assistant"
                ]
                self.assertEqual(len(assistant_values), 8)
                decoded = [json.loads(value["semanticJson"]) for value in assistant_values]
                self.assertTrue(
                    all(
                        value["contractVersion"] == "workout-import-model-output/v2"
                        for value in decoded
                    )
                )

    async def test_v2_9_full_matrix_uses_strategy_owned_schema_profiles(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        for spec in load_model_specs(SEMANTIC_JSON_STRATEGY_MODELS):
            with self.subTest(model=spec.requested_model_id):
                strategy = strategy_for(spec)
                schema = strategy.schema()
                self.assertEqual(strategy.schema_profile.validate(schema), ())
                payload = await capture_wire_payload(
                    spec,
                    schema,
                    model_messages_for_strategy(warmup, strategy),
                    schema_name=strategy.schema_name,
                    mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
                )
                assert_payload_controls(
                    payload, spec, schema, schema_name=strategy.schema_name
                )

    async def test_model_visible_payload_excludes_heldout_metadata(self) -> None:
        schema = strict_json_load(TRANSPORT_SCHEMA)
        messages = model_messages(load_cases(DEVELOPMENT_CASES)[0])
        spec = load_model_specs(MODELS)[0]
        payload = await capture_wire_payload(spec, schema, messages)
        visible = json.dumps(payload["body"]["messages"])
        for forbidden in (
            "scenarioFamily",
            "scorerAlias",
            "localValidatorOutcome",
            "unsupportedCapabilityHandling",
        ):
            self.assertNotIn(forbidden, visible)

    async def test_http_failure_is_preserved_without_retry_or_credential(self) -> None:
        calls = 0

        async def fail(request: httpx2.Request) -> httpx2.Response:
            nonlocal calls
            calls += 1
            return httpx2.Response(
                429,
                request=request,
                json={"error": {"message": "bounded mock rate limit", "type": "rate_limit"}},
            )

        schema = strict_json_load(TRANSPORT_SCHEMA)
        messages = model_messages(load_cases(DEVELOPMENT_CASES)[0])
        spec = load_model_specs(MODELS)[0]
        with self.assertRaises(CapturedGenerationError) as caught:
            await generate_with_capture(
                spec,
                schema,
                messages,
                MOCK_API_KEY,
                transport=httpx2.MockTransport(fail),
            )
        self.assertEqual(calls, 1)
        evidence = caught.exception.exchange
        self.assertEqual(evidence["responses"][0]["statusCode"], 429)
        self.assertNotIn(MOCK_API_KEY, json.dumps(evidence))


if __name__ == "__main__":
    unittest.main()
