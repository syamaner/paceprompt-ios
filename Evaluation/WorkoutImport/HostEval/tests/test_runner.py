from __future__ import annotations

import tempfile
import json
import logging
from pathlib import Path
import unittest
from unittest.mock import AsyncMock, patch

from inspect_ai.model import ModelOutput, ModelUsage

from paceprompt_eval.openrouter import CapturedGenerationError, load_model_specs
from paceprompt_eval.runner import LiveRun, classify_failure, compare_catalogues, measurement
from paceprompt_eval.scorer_adapter import (
    normalized_document,
    provider_transport_output,
    score_completed,
    v1_observed,
)
from paceprompt_eval.task import (
    DEVELOPMENT_CASES,
    DIAGNOSTIC_MODELS,
    FLAT_STRATEGY_DIAGNOSTIC_MODELS,
    SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS,
    HELDOUT_CASES,
    MODEL_SCHEMA,
    MODELS,
    REPOSITORY_ROOT,
    TRANSPORT_SCHEMA,
    STRATEGY_DIAGNOSTIC_MODELS,
    load_cases,
    model_messages,
    model_messages_for_strategy,
    strict_json_load,
)
from paceprompt_eval.transport_strategy import strategy_for


class RunnerTests(unittest.TestCase):
    def test_http_failure_classification_is_host_only(self) -> None:
        exchange = {"responses": [{"statusCode": 429, "body": {}}]}
        self.assertEqual(classify_failure(RuntimeError("rate"), exchange), "rateLimited")

    def test_catalogue_drift_is_rejected(self) -> None:
        before = [{
            "requestedModelID": "a/b",
            "canonicalRevision": "a/b-1",
            "configuredCanonicalRevision": "a/b-1",
            "providerEndpoint": "provider/fp8",
            "reportedProviderName": "Provider",
            "configuredQuantization": "fp8",
            "reportedQuantization": "fp8",
            "supportedParameters": ["response_format"],
        }]
        after = [dict(before[0], providerEndpoint="other/fp8")]
        with self.assertRaises(RuntimeError):
            compare_catalogues(before, after)

    def test_failure_file_redacts_credential_and_embedded_openrouter_user_id(self) -> None:
        spec = load_model_specs(MODELS)[0]
        selected = {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "reportedProviderName": "OpenAI",
            "inputPricePerToken": "0.000002",
            "outputPricePerToken": "0.00001",
        }
        captured = CapturedGenerationError(
            RuntimeError("mock-local-only failed for user_privateIdentifier123"),
            {
                "requests": [],
                "responses": [
                    {
                        "statusCode": 400,
                        "body": {"user_id": "[REDACTED]"},
                    }
                ],
            },
        )
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "redaction"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": [selected]},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=(spec,),
                messages_for_case=model_messages,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="redaction-test",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="redaction-test/v1",
                diagnostic_purpose="redaction-test",
            )
            with patch(
                "paceprompt_eval.runner.generate_with_capture",
                new=AsyncMock(side_effect=captured),
            ):
                __import__("asyncio").run(runner.execute_warmups_only())
            failure = json.loads(
                next((run_dir / "failures").glob("*.json")).read_text()
            )
        self.assertNotIn("mock-local-only", failure["message"])
        self.assertNotIn("user_privateIdentifier123", failure["message"])
        self.assertIn("[REDACTED_USER_ID]", failure["message"])

    def test_framework_warning_is_preserved_and_redacted_per_attempt(self) -> None:
        spec = load_model_specs(MODELS)[0]
        selected = {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "reportedProviderName": "OpenAI",
            "inputPricePerToken": "0.000002",
            "outputPricePerToken": "0.00001",
        }

        async def failure_with_warning(*_args, **_kwargs):
            logging.getLogger("inspect_ai.model._openrouter_reasoning").warning(
                "reasoning detail for mock-local-only and user_privateIdentifier123"
            )
            raise CapturedGenerationError(
                RuntimeError("synthetic provider failure"),
                {"requests": [], "responses": [{"statusCode": 400, "body": {}}]},
            )

        inspect_logger = logging.getLogger("inspect_ai")
        handlers_before = tuple(inspect_logger.handlers)
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "framework-log-redaction"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": [selected]},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=(spec,),
                messages_for_case=model_messages,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="framework-log-redaction-test",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="framework-log-redaction-test/v1",
                diagnostic_purpose="framework-log-redaction-test",
            )
            with patch(
                "paceprompt_eval.runner.generate_with_capture",
                new=failure_with_warning,
            ):
                __import__("asyncio").run(runner.execute_warmups_only())
            evidence = json.loads(
                next((run_dir / "framework-logs").glob("*-python-logging.json")).read_text()
            )

        self.assertEqual(tuple(inspect_logger.handlers), handlers_before)
        self.assertEqual(evidence["contractVersion"], "paceprompt-host-eval-framework-log/v1")
        self.assertEqual(len(evidence["records"]), 1)
        self.assertEqual(evidence["records"][0]["level"], "WARNING")
        self.assertEqual(
            evidence["records"][0]["logger"],
            "inspect_ai.model._openrouter_reasoning",
        )
        serialized = json.dumps(evidence)
        self.assertNotIn("mock-local-only", serialized)
        self.assertNotIn("user_privateIdentifier123", serialized)
        self.assertIn("[REDACTED]", serialized)
        self.assertIn("[REDACTED_USER_ID]", serialized)

    def test_live_measurements_fit_unchanged_normalized_envelope(self) -> None:
        case = load_cases(HELDOUT_CASES)[0]
        document = normalized_document(
            case=case,
            observed=v1_observed(case["expected"]["modelOutput"]),
            run_id="test",
            result_id="test-result",
            repetition_index=1,
            app_commit="a" * 40,
            model_id="model",
            model_revision="model-1",
            provider_id="provider",
            measurements=[
                measurement("completeResponseLatency", 0.5, "seconds"),
                measurement("reportedCost", None, "USD"),
            ],
        )
        with tempfile.TemporaryDirectory() as directory:
            report = score_completed(
                projection_root=Path(directory) / "projection",
                case=case,
                document=document,
            )
        self.assertEqual(report["status"], "complete")

    def test_live_writer_keeps_complete_mock_exchange_inside_run(self) -> None:
        case = load_cases(HELDOUT_CASES)[0]
        spec = load_model_specs(MODELS)[0]
        selected = {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "reportedProviderName": "OpenAI",
            "inputPricePerToken": "0.000002",
            "outputPricePerToken": "0.00001",
        }
        output = ModelOutput(
            model=spec.canonical_revision or spec.requested_model_id,
            completion=__import__("json").dumps(
                provider_transport_output(case["expected"]["modelOutput"])
            ),
            usage=ModelUsage(input_tokens=10, output_tokens=10, total_tokens=20, total_cost=0.001),
            time=0.1,
        )
        exchange = {
            "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
            "responses": [{
                "statusCode": 200,
                "body": {
                    "model": spec.canonical_revision,
                    "provider": "OpenAI",
                    "usage": {"cost": 0.001},
                },
            }],
        }
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "run"
            run_dir.mkdir()
            clock = [0.0]

            async def fake_sleep(seconds: float) -> None:
                clock[0] += seconds

            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": [selected]},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[case],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[{
                    "attemptID": "r01-test",
                    "repetitionIndex": 1,
                    "caseID": case["id"],
                    "modelID": spec.requested_model_id,
                    "modelPosition": 1,
                }],
                specs=(spec,),
                messages_for_case=model_messages,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-run-policy/v2.3",
                spending_limit_usd="20.00",
                sleep=fake_sleep,
                monotonic=lambda: clock[0],
            )
            with patch(
                "paceprompt_eval.runner.generate_with_capture",
                new=AsyncMock(return_value=(output, exchange)),
            ):
                report = __import__("asyncio").run(runner.execute())
            self.assertEqual(runner.attempts[-1]["interCallDelaySeconds"], 2)
            self.assertTrue((run_dir / "requests" / "r01-test.json").is_file())
            self.assertTrue((run_dir / "normalized-results" / "r01-test.json").is_file())
            self.assertEqual(runner.attempts[-1]["scorerOverall"], "passed")
            self.assertEqual(report["providerDecision"], "requiresHumanRatification")

    def test_failed_warmup_prevents_that_models_heldout_calls(self) -> None:
        case = load_cases(HELDOUT_CASES)[0]
        spec = load_model_specs(MODELS)[0]
        selected = {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "reportedProviderName": "OpenAI",
            "inputPricePerToken": "0.000002",
            "outputPricePerToken": "0.00001",
        }
        output = ModelOutput(
            model=spec.canonical_revision or spec.requested_model_id,
            completion="{}",
            usage=ModelUsage(input_tokens=1, output_tokens=1, total_tokens=2, total_cost=0.001),
            time=0.1,
        )
        exchange = {
            "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
            "responses": [{"statusCode": 200, "body": {"model": spec.canonical_revision, "provider": "OpenAI", "usage": {"cost": 0.001}}}],
        }
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "run"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": [selected]},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[case],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[{"attemptID": "r01-blocked", "repetitionIndex": 1, "caseID": case["id"], "modelID": spec.requested_model_id, "modelPosition": 1}],
                specs=(spec,),
                messages_for_case=model_messages,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-run-policy/v2.3",
                spending_limit_usd="20.00",
            )
            mocked = AsyncMock(return_value=(output, exchange))
            with patch("paceprompt_eval.runner.generate_with_capture", new=mocked):
                report = __import__("asyncio").run(runner.execute())
            self.assertEqual(mocked.await_count, 1)
            blocked = next(item for item in runner.attempts if item["attemptID"] == "r01-blocked")
            self.assertEqual(blocked["status"], "notStarted")
            self.assertFalse(report["models"][spec.requested_model_id]["hardGates"]["runIntegrity"])

    def test_two_call_diagnostic_has_no_heldout_calls_and_records_pacing(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        specs = load_model_specs(DIAGNOSTIC_MODELS)
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "reportedProviderName": "Google AI Studio",
                "inputPricePerToken": "0.0000001",
                "outputPricePerToken": "0.0000004",
            }
            for spec in specs
        ]
        clock = [0.0]

        async def fake_sleep(seconds: float) -> None:
            clock[0] += seconds

        async def successful_call(spec, *_args, **_kwargs):
            output = ModelOutput(
                model=spec.canonical_revision,
                completion=__import__("json").dumps(
                    provider_transport_output(warmup["expected"]["modelOutput"])
                ),
                usage=ModelUsage(
                    input_tokens=10, output_tokens=10, total_tokens=20, total_cost=0.001
                ),
                time=0.1,
            )
            exchange = {
                "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
                "responses": [{
                    "statusCode": 200,
                    "body": {
                        "model": spec.canonical_revision,
                        "provider": "Google AI Studio",
                        "usage": {"cost": 0.001},
                    },
                }],
            }
            return output, exchange

        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "diagnostic"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": selected},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=specs,
                messages_for_case=model_messages,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-gemini-diagnostic/v2.5",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="paceprompt-host-eval-gemini-diagnostic-report/v2.5",
                diagnostic_purpose="test-required-reasoning-without-effort-or-exclusion",
                sleep=fake_sleep,
                monotonic=lambda: clock[0],
            )
            mocked = AsyncMock(side_effect=successful_call)
            with patch("paceprompt_eval.runner.generate_with_capture", new=mocked):
                report = __import__("asyncio").run(runner.execute_warmups_only())
        self.assertEqual(mocked.await_count, 2)
        self.assertEqual(report["heldoutCalls"], 0)
        self.assertEqual(len(runner.attempts), 2)
        self.assertIsNone(runner.attempts[0]["interCallDelaySeconds"])
        self.assertEqual(runner.attempts[1]["interCallDelaySeconds"], 2)
        self.assertTrue(all(item["caseID"] == "WI-V2-D006" for item in runner.attempts))

    def test_strategy_diagnostic_uses_shared_shallow_projection_and_normalizes(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        specs = load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "reportedProviderName": "Google AI Studio",
                "inputPricePerToken": "0.0000001",
                "outputPricePerToken": "0.0000004",
            }
            for spec in specs
        ]
        clock = [0.0]

        async def fake_sleep(seconds: float) -> None:
            clock[0] += seconds

        async def successful_call(spec, schema, _messages, _api_key, **kwargs):
            strategy = strategy_for(spec)
            self.assertEqual(schema, strategy.schema())
            self.assertEqual(kwargs["schema_name"], strategy.schema_name)
            output = ModelOutput(
                model=spec.canonical_revision,
                completion=__import__("json").dumps(
                    strategy.project_output(warmup["expected"]["modelOutput"])
                ),
                usage=ModelUsage(
                    input_tokens=10, output_tokens=10, total_tokens=20, total_cost=0.001
                ),
                time=0.1,
            )
            exchange = {
                "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
                "responses": [{
                    "statusCode": 200,
                    "body": {
                        "model": spec.canonical_revision,
                        "provider": "Google AI Studio",
                        "usage": {"cost": 0.001},
                    },
                }],
            }
            return output, exchange

        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "strategy-diagnostic"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": selected},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strict_json_load(TRANSPORT_SCHEMA),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=specs,
                messages_for_case=model_messages_for_strategy,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-gemini-transport-strategy/v2.7",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="paceprompt-host-eval-gemini-transport-strategy-report/v2.7",
                diagnostic_purpose="verify-shared-shallow-step-strategy-through-inspect-before-heldout-evaluation",
                sleep=fake_sleep,
                monotonic=lambda: clock[0],
                transport_strategy_for_spec=strategy_for,
            )
            mocked = AsyncMock(side_effect=successful_call)
            with patch("paceprompt_eval.runner.generate_with_capture", new=mocked):
                report = __import__("asyncio").run(runner.execute_warmups_only())
        self.assertEqual(mocked.await_count, 2)
        self.assertTrue(all(item["schemaValid"] for item in runner.attempts))
        self.assertTrue(
            all(item["transportStrategy"] == "shallowStepV27" for item in runner.attempts)
        )
        self.assertEqual(report["heldoutCalls"], 0)

    def test_flat_strategy_diagnostic_projects_and_normalizes_both_models(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        specs = load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS)
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "reportedProviderName": "Google AI Studio",
                "inputPricePerToken": "0.0000001",
                "outputPricePerToken": "0.0000004",
            }
            for spec in specs
        ]
        clock = [0.0]

        async def fake_sleep(seconds: float) -> None:
            clock[0] += seconds

        async def successful_call(spec, schema, messages, _api_key, **kwargs):
            strategy = strategy_for(spec)
            self.assertEqual(schema, strategy.schema())
            self.assertEqual(kwargs["schema_name"], strategy.schema_name)
            assistant_values = [
                json.loads(message.content)
                for message in messages
                if message.role == "assistant"
            ]
            self.assertTrue(all("outcomeType" in value for value in assistant_values))
            output = ModelOutput(
                model=spec.canonical_revision,
                completion=json.dumps(
                    strategy.project_output(warmup["expected"]["modelOutput"])
                ),
                usage=ModelUsage(
                    input_tokens=10, output_tokens=10, total_tokens=20, total_cost=0.001
                ),
                time=0.1,
            )
            exchange = {
                "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
                "responses": [{
                    "statusCode": 200,
                    "body": {
                        "model": spec.canonical_revision,
                        "provider": "Google AI Studio",
                        "usage": {"cost": 0.001},
                    },
                }],
            }
            return output, exchange

        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "flat-strategy-diagnostic"
            run_dir.mkdir()
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": selected},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strategy_for(specs[0]).schema(),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=specs,
                messages_for_case=model_messages_for_strategy,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=strategy_for(specs[0]).schema_file_bytes(),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-gemini-flat-envelope/v2.8",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="paceprompt-host-eval-gemini-flat-envelope-report/v2.8",
                diagnostic_purpose="verify-flat-envelope-strategy-through-inspect-before-heldout-evaluation",
                sleep=fake_sleep,
                monotonic=lambda: clock[0],
                transport_strategy_for_spec=strategy_for,
            )
            mocked = AsyncMock(side_effect=successful_call)
            with patch("paceprompt_eval.runner.generate_with_capture", new=mocked):
                report = __import__("asyncio").run(runner.execute_warmups_only())
        self.assertEqual(mocked.await_count, 2)
        self.assertEqual(report["heldoutCalls"], 0)
        self.assertTrue(all(item["schemaValid"] for item in runner.attempts))
        self.assertTrue(
            all(item["transportStrategy"] == "flatEnvelopeV28" for item in runner.attempts)
        )
        self.assertIsNone(runner.attempts[0]["interCallDelaySeconds"])
        self.assertEqual(runner.attempts[1]["interCallDelaySeconds"], 2)

    def test_semantic_json_strategy_diagnostic_decodes_and_validates_both_models(self) -> None:
        warmup = next(
            case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
        )
        specs = load_model_specs(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS)
        selected = [
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "reportedProviderName": "Google AI Studio",
                "inputPricePerToken": "0.0000001",
                "outputPricePerToken": "0.0000004",
            }
            for spec in specs
        ]
        clock = [0.0]

        async def fake_sleep(seconds: float) -> None:
            clock[0] += seconds

        async def successful_call(spec, schema, messages, _api_key, **kwargs):
            strategy = strategy_for(spec)
            self.assertEqual(schema, strategy.schema())
            self.assertEqual(kwargs["schema_name"], strategy.schema_name)
            assistant_values = [
                json.loads(message.content)
                for message in messages
                if message.role == "assistant"
            ]
            self.assertTrue(all(set(value) == {"semanticJson"} for value in assistant_values))
            output = ModelOutput(
                model=spec.canonical_revision,
                completion=json.dumps(
                    strategy.project_output(warmup["expected"]["modelOutput"])
                ),
                usage=ModelUsage(
                    input_tokens=10, output_tokens=10, total_tokens=20, total_cost=0.001
                ),
                time=0.1,
            )
            exchange = {
                "requests": [{"method": "POST", "headers": {"authorization": "Bearer [REDACTED]"}, "body": {}}],
                "responses": [{
                    "statusCode": 200,
                    "body": {
                        "model": spec.canonical_revision,
                        "provider": "Google AI Studio",
                        "usage": {"cost": 0.001},
                    },
                }],
            }
            return output, exchange

        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory) / "semantic-json-strategy-diagnostic"
            run_dir.mkdir()
            strategy = strategy_for(specs[0])
            runner = LiveRun(
                run_dir=run_dir,
                gate={"selectedEndpoints": selected},
                api_key="mock-local-only",
                schema=strict_json_load(MODEL_SCHEMA),
                transport_schema=strategy.schema(),
                cases=[],
                development_cases=load_cases(DEVELOPMENT_CASES),
                queue=[],
                specs=specs,
                messages_for_case=model_messages_for_strategy,
                repository_root=REPOSITORY_ROOT,
                schema_file_bytes=strategy.schema_file_bytes(),
                execution_policy={"globalConcurrency": 1, "minimumInterCallDelaySeconds": 2, "cancelFlushSeconds": 15},
                run_configuration_id="paceprompt-host-eval-gemini-semantic-json/v2.9",
                spending_limit_usd="2.00",
                diagnostic_report_contract_version="paceprompt-host-eval-gemini-semantic-json-report/v2.9",
                diagnostic_purpose="verify-profile-validated-semantic-json-strategy-through-inspect-before-heldout-evaluation",
                sleep=fake_sleep,
                monotonic=lambda: clock[0],
                transport_strategy_for_spec=strategy_for,
            )
            mocked = AsyncMock(side_effect=successful_call)
            with patch("paceprompt_eval.runner.generate_with_capture", new=mocked):
                report = __import__("asyncio").run(runner.execute_warmups_only())
        self.assertEqual(mocked.await_count, 2)
        self.assertEqual(report["heldoutCalls"], 0)
        self.assertTrue(all(item["schemaValid"] for item in runner.attempts))
        self.assertTrue(
            all(item["transportStrategy"] == "semanticJsonV29" for item in runner.attempts)
        )
        self.assertTrue(
            all(
                item["transportSchemaProfile"] == "googleGeminiMinimalV29"
                for item in runner.attempts
            )
        )
        self.assertEqual(runner.attempts[1]["interCallDelaySeconds"], 2)


if __name__ == "__main__":
    unittest.main()
