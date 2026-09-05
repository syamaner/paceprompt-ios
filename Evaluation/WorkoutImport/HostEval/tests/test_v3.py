from __future__ import annotations

import asyncio
from collections import Counter
from decimal import Decimal
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

import httpx2

from paceprompt_eval.catalogue import conservative_call_cost
from paceprompt_eval.openrouter import CapturedGenerationError, generate_with_capture, load_model_specs
from paceprompt_eval.runner import (
    affected_paths_equal,
    authority_preserved,
    classify_failure,
    parse_completed_output,
    route_matches,
)
from paceprompt_eval.task import SpendGuard, SpendingLimitReached
from paceprompt_eval.v3 import (
    HOST_EVAL_ROOT,
    MODELS,
    RUN_POLICY,
    V3LiveRun,
    _payload_templates,
    aggregate,
    prepare_gate,
    queue_document,
    sha256_file,
    strict_json_load,
    verify,
)


FABLE_ASSET_ROOT = Path(
    "/private/tmp/paceprompt-issue15-v3-fable.3ghckR/worktree/"
    "Evaluation/WorkoutImport/HostEval"
)


def synthetic_cases() -> list[dict]:
    counts = {
        "proposal": 12,
        "ambiguousRequiredField": 5,
        "contradictoryRequest": 5,
        "excessiveComplexity": 5,
        "knownCapabilityUnsupported": 6,
        "medicalRequest": 5,
        "missingRequiredField": 5,
        "outOfDomain": 5,
        "promptInjection": 5,
        "unsafeRequest": 5,
        "unsupportedActivity": 6,
        "unsupportedOperation": 5,
        "unsupportedTarget": 5,
        "unsupportedUnit": 5,
    }
    cases = []
    index = 1
    for category, count in counts.items():
        for _ in range(count):
            cases.append({"id": f"case-{index:03d}", "category": category})
            index += 1
    return cases


def perfect_attempts(cases: list[dict]) -> list[dict]:
    attempts = []
    costs = {
        "openai/gpt-5.6-sol": "0.003",
        "openai/gpt-5.6-luna": "0.001",
        "google/gemini-3.7-flash": "0.002",
    }
    for spec in load_model_specs(MODELS):
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
                        "reportedCostUSD": costs[spec.requested_model_id],
                    }
                )
    return attempts


class V3ContractTests(unittest.TestCase):
    def test_preflight_and_runtime_cost_allowances_are_distinct(self) -> None:
        preflight = conservative_call_cost(
            input_utf8_bytes=100,
            input_price="0.000001",
            output_price="0.00001",
            output_tokens=5448,
        )
        runtime = conservative_call_cost(
            input_utf8_bytes=100,
            input_price="0.000001",
            output_price="0.00001",
        )
        self.assertLess(preflight, runtime)
        with self.assertRaises(ValueError):
            conservative_call_cost(
                input_utf8_bytes=100,
                input_price="0.000001",
                output_price="0.00001",
                output_tokens=8193,
            )

    def test_output_limit_finish_reason_is_a_complete_invalid_response(self) -> None:
        observed = parse_completed_output(
            '{}',
            {},
            {},
            lambda value: value,
            finish_reason="length",
            output_limit_is_invalid=True,
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertEqual(observed["errors"][0]["code"], "outputTokenLimitReached")

    def test_live_preflight_rejects_a_changed_mock_payload_template(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            mock_dir = run_dir / "mock-payloads"
            mock_dir.mkdir()
            hashes = {}
            for spec in load_model_specs(MODELS):
                path = mock_dir / f"{spec.requested_model_id.replace('/', '--')}.json"
                path.write_text('{"body":{"messages":[]}}\n', encoding="utf-8")
                hashes[spec.requested_model_id] = sha256_file(path)
            _payload_templates(run_dir, hashes)
            changed = next(mock_dir.iterdir())
            changed.write_text('{"body":{"messages":[{}]}}\n', encoding="utf-8")
            with self.assertRaises(RuntimeError):
                _payload_templates(run_dir, hashes)

    def test_affected_path_comparison_matches_the_unchanged_scorer(self) -> None:
        self.assertTrue(
            affected_paths_equal(
                {"affectedPaths": ["steps.duration", "steps.targetSpeed"]},
                {"affectedPaths": ["steps.targetSpeed", "steps.duration"]},
            )
        )

    def test_spend_guard_includes_settled_actual_before_next_reservation(self) -> None:
        guard = SpendGuard("20.00")
        guard.reserve("first", Decimal("12.00"))
        guard.settle("first", Decimal("11.00"))
        with self.assertRaises(SpendingLimitReached):
            guard.reserve("second", Decimal("9.01"))
        guard.reserve("second", Decimal("9.00"))
        self.assertEqual(guard.actual + guard.reserved, Decimal("20.00"))

    def test_structural_authority_and_returned_identity_are_exact(self) -> None:
        selected = {
            "requestedModelID": "a/model",
            "canonicalRevision": "a/model-1",
            "providerEndpoint": "provider",
            "reportedProviderName": "Provider",
        }
        exchange = {
            "requests": [{"body": {"model": "a/model", "tool_choice": "none"}}],
            "responses": [{"body": {"model": "a/model-1", "provider": "Provider", "choices": [{"message": {"content": "{}"}}]}}],
        }
        self.assertTrue(authority_preserved(exchange))
        self.assertTrue(route_matches(exchange, selected, require_identity=True))
        self.assertFalse(authority_preserved({**exchange, "requests": [{"body": {"tools": []}}]}))
        no_identity = {**exchange, "responses": [{"body": {"choices": [{"message": {"content": "{}"}}]}}]}
        self.assertFalse(route_matches(no_identity, selected, require_identity=True))

    def test_exact_denominators_floors_p95_and_tie_breaks(self) -> None:
        cases = synthetic_cases()
        self.assertEqual(len(cases), 79)
        attempts = perfect_attempts(cases)
        policy = strict_json_load(RUN_POLICY)
        specs = load_model_specs(MODELS)
        report = aggregate(attempts, cases, specs, policy)
        self.assertEqual(report["eligibleModels"], [spec.requested_model_id for spec in specs])
        self.assertEqual(set(report["topAnchoredCompositeTieGroup"]), set(report["eligibleModels"]))
        self.assertEqual(report["tieBreakTrace"]["afterExactObservedCost"], ["openai/gpt-5.6-luna"])
        self.assertEqual(report["automaticWinner"], None)
        for model in report["models"].values():
            self.assertEqual(model["scheduledAttempts"], 237)
            self.assertEqual(model["developmentHostOpenRouterP95Milliseconds"], 1000)
            self.assertEqual(model["metrics"]["weightedComposite"]["displayPercent"], "100.0000")

        one_category = next(case["category"] for case in cases if case["category"] != "proposal")
        affected_case = next(case for case in cases if case["category"] == one_category)
        sol_items = [
            item for item in attempts
            if item["modelID"] == "openai/gpt-5.6-sol" and item["caseID"] == affected_case["id"]
        ]
        for item in sol_items:
            item["reasonExact"] = False
        tolerant = aggregate(attempts, cases, specs, policy)["models"]["openai/gpt-5.6-sol"]
        self.assertEqual(tolerant["categoryAttemptFloors"][one_category]["ratio"]["displayPercent"], "80.0000")
        self.assertTrue(tolerant["categoryAttemptFloors"][one_category]["passed"])

    def test_invalid_and_rate_limited_attempts_never_leave_denominators(self) -> None:
        cases = synthetic_cases()
        attempts = perfect_attempts(cases)
        policy = strict_json_load(RUN_POLICY)
        specs = load_model_specs(MODELS)
        sol = [item for item in attempts if item["modelID"] == "openai/gpt-5.6-sol"]
        sol[0].update(schemaValid=False, outcomeExact=False, reasonExact=False, pathsExact=False)
        invalid_report = aggregate(attempts, cases, specs, policy)["models"]["openai/gpt-5.6-sol"]
        self.assertFalse(invalid_report["hardGates"]["strictSchemaAndSemanticValidity"])
        self.assertTrue(invalid_report["hardGates"]["minimumCompletionCoverage"])
        self.assertEqual(invalid_report["metrics"]["outcomeTypeAccuracy"]["denominator"], 237)

        sol[0].update(
            hostClassification="infrastructure",
            schemaValid=None,
            reasonCategory="rateLimited",
            providerLatencyMilliseconds=1500,
        )
        for item in sol[1:]:
            item.update(
                status="notStarted",
                reasonCategory="rateLimitPause",
                hostClassification=None,
                providerLatencyMilliseconds=None,
                reportedCostUSD=None,
            )
        paused = aggregate(attempts, cases, specs, policy)["models"]["openai/gpt-5.6-sol"]
        self.assertTrue(paused["rateLimitPaused"])
        self.assertFalse(paused["hardGates"]["minimumCompletionCoverage"])
        self.assertFalse(paused["decisionEligible"])
        self.assertFalse(paused["partialRankingPermitted"])
        self.assertIsNone(paused["developmentHostOpenRouterP95Milliseconds"])

    @unittest.skipUnless(
        (FABLE_ASSET_ROOT / "prompts" / "v3" / "system.md").is_file(),
        "sibling prompt/corpus worktree is unavailable",
    )
    def test_sealed_sibling_assets_verify_and_queue_with_hashes(self) -> None:
        report = verify(FABLE_ASSET_ROOT)
        self.assertEqual(report["status"], "valid", report["errors"])
        queue = queue_document(asset_root=FABLE_ASSET_ROOT)
        self.assertEqual(len(queue["entries"]), 711)
        self.assertEqual(Counter(item["modelID"] for item in queue["entries"]), Counter({
            "openai/gpt-5.6-sol": 237,
            "openai/gpt-5.6-luna": 237,
            "google/gemini-3.7-flash": 237,
        }))
        self.assertEqual(queue["corpusHashes"]["heldoutCases"], "645b17e90a8096fe56c766221288fda4e588f8fa45b1b650638970d5449c1159")

    def test_rate_limit_pauses_only_that_model_without_requeue(self) -> None:
        class Spec:
            def __init__(self, model_id: str) -> None:
                self.requested_model_id = model_id
                self.provider_endpoint = "provider"

        sol = Spec("sol")
        luna = Spec("luna")
        runner = V3LiveRun.__new__(V3LiveRun)
        runner.specs = {"sol": sol, "luna": luna}
        runner.warmup = {"id": "warm"}
        runner.cases = {"c1": {"id": "c1"}, "c2": {"id": "c2"}}
        runner.queue = [
            {"attemptID": "sol-1", "caseID": "c1", "modelID": "sol", "repetitionIndex": 1},
            {"attemptID": "luna-1", "caseID": "c1", "modelID": "luna", "repetitionIndex": 1},
            {"attemptID": "sol-2", "caseID": "c2", "modelID": "sol", "repetitionIndex": 1},
            {"attemptID": "luna-2", "caseID": "c2", "modelID": "luna", "repetitionIndex": 1},
        ]
        runner.attempts = []
        called: list[str] = []

        async def call(*, attempt_id, kind, case, spec, repetition):
            called.append(attempt_id)
            if kind == "warmup":
                return {"modelID": spec.requested_model_id, "compatibilityPassed": True}
            result = {"attemptID": attempt_id, "modelID": spec.requested_model_id}
            if attempt_id == "sol-1":
                result["reasonCategory"] = "rateLimited"
            runner.attempts.append({**result, "kind": "scored", "caseID": case["id"], "terminal": True})
            return result

        runner.call = call
        runner.setup = lambda: None
        runner.save_state = AsyncMock()
        runner._evidence_integrity = lambda: {"passed": True}
        with tempfile.TemporaryDirectory() as directory:
            runner.run_dir = Path(directory)
            with patch("paceprompt_eval.v3.aggregate", return_value={"providerDecision": "requiresHumanRatification"}), patch("paceprompt_eval.v3.write_json"):
                asyncio.run(runner.execute())
        self.assertEqual(called, ["warmup-sol", "warmup-luna", "sol-1", "luna-1", "luna-2"])
        skipped = next(item for item in runner.attempts if item["attemptID"] == "sol-2")
        self.assertEqual(skipped["reasonCategory"], "rateLimitPause")

    def test_nearest_rank_p95_uses_the_226th_of_237_attempts(self) -> None:
        cases = synthetic_cases()
        attempts = perfect_attempts(cases)
        sol = [item for item in attempts if item["modelID"] == "openai/gpt-5.6-sol"]
        for duration, item in enumerate(sol, start=1):
            item["providerLatencyMilliseconds"] = duration
        report = aggregate(
            attempts, cases, load_model_specs(MODELS), strict_json_load(RUN_POLICY)
        )
        self.assertEqual(
            report["models"]["openai/gpt-5.6-sol"]["developmentHostOpenRouterP95Milliseconds"],
            226,
        )

    def test_transport_timeout_records_monotonic_request_duration(self) -> None:
        spec = load_model_specs(MODELS)[0]
        schema = {"type": "object", "properties": {}, "additionalProperties": False}

        async def handler(request: httpx2.Request) -> httpx2.Response:
            raise httpx2.ReadTimeout("synthetic timeout", request=request)

        times = iter((10.0, 10.125))
        with self.assertRaises(CapturedGenerationError) as raised:
            asyncio.run(
                generate_with_capture(
                    spec,
                    schema,
                    [],
                    "mock-local-only",
                    transport=httpx2.MockTransport(handler),
                    monotonic=lambda: next(times),
                )
            )
        self.assertEqual(raised.exception.exchange["providerLatencyMilliseconds"], 125)
        self.assertEqual(
            classify_failure(raised.exception, raised.exception.exchange), "timeout"
        )

    def test_cancellation_marks_every_unstarted_queue_entry(self) -> None:
        class Spec:
            requested_model_id = "sol"
            provider_endpoint = "provider"

        runner = V3LiveRun.__new__(V3LiveRun)
        runner.specs = {"sol": Spec()}
        runner.warmup = {"id": "warm"}
        runner.cases = {"c1": {"id": "c1"}, "c2": {"id": "c2"}}
        runner.queue = [
            {"attemptID": "sol-1", "caseID": "c1", "modelID": "sol", "repetitionIndex": 1},
            {"attemptID": "sol-2", "caseID": "c2", "modelID": "sol", "repetitionIndex": 1},
        ]
        runner.attempts = []

        async def call(*, attempt_id, kind, case, spec, repetition):
            if kind == "warmup":
                return {"modelID": "sol", "compatibilityPassed": True}
            raise asyncio.CancelledError

        runner.call = call
        runner.setup = lambda: None
        runner.save_state = AsyncMock()
        runner.cancel_flush_seconds = 15
        with self.assertRaises(asyncio.CancelledError):
            asyncio.run(runner.execute())
        self.assertEqual(
            [item["reasonCategory"] for item in runner.attempts],
            ["operatorCancelled", "operatorCancelled"],
        )
        runner.save_state.assert_awaited_with("cancelledNonResumable")

    def test_warmup_cancellation_also_marks_the_scored_queue(self) -> None:
        class Spec:
            requested_model_id = "sol"
            provider_endpoint = "provider"

        runner = V3LiveRun.__new__(V3LiveRun)
        runner.specs = {"sol": Spec()}
        runner.warmup = {"id": "warm"}
        runner.cases = {"c1": {"id": "c1"}}
        runner.queue = [
            {
                "attemptID": "sol-1",
                "caseID": "c1",
                "modelID": "sol",
                "repetitionIndex": 1,
            }
        ]
        runner.attempts = []

        async def call(**_):
            raise asyncio.CancelledError

        runner.call = call
        runner.setup = lambda: None
        runner.save_state = AsyncMock()
        runner.cancel_flush_seconds = 15
        with self.assertRaises(asyncio.CancelledError):
            asyncio.run(runner.execute())
        self.assertEqual(runner.attempts[0]["reasonCategory"], "operatorCancelled")
        runner.save_state.assert_awaited_with("cancelledNonResumable")

    def test_warmup_spend_stop_also_marks_the_scored_queue(self) -> None:
        class Spec:
            requested_model_id = "sol"
            provider_endpoint = "provider"

        runner = V3LiveRun.__new__(V3LiveRun)
        runner.specs = {"sol": Spec()}
        runner.warmup = {"id": "warm"}
        runner.cases = {"c1": {"id": "c1"}}
        runner.queue = [
            {
                "attemptID": "sol-1",
                "caseID": "c1",
                "modelID": "sol",
                "repetitionIndex": 1,
            }
        ]
        runner.attempts = []

        async def call(**_):
            raise SpendingLimitReached("warmup-sol")

        runner.call = call
        runner.setup = lambda: None
        runner.save_state = AsyncMock()
        runner._evidence_integrity = lambda: {"passed": True}
        with tempfile.TemporaryDirectory() as directory:
            runner.run_dir = Path(directory)
            with patch(
                "paceprompt_eval.v3.aggregate",
                return_value={"providerDecision": "requiresHumanRatification"},
            ), patch("paceprompt_eval.v3.write_json"):
                asyncio.run(runner.execute())
        self.assertEqual(
            runner.attempts[0]["reasonCategory"], "spendingLimitReached"
        )
        self.assertIn(
            "runtimeSpendingLimitReached",
            [call.args[0] for call in runner.save_state.await_args_list],
        )

    @unittest.skipUnless(
        (FABLE_ASSET_ROOT / "prompts" / "v3" / "system.md").is_file(),
        "sibling prompt/corpus worktree is unavailable",
    )
    def test_complete_v3_gate_is_mocked_without_credential_or_spend(self) -> None:
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
            parameters = ["max_tokens", "response_format", "structured_outputs"]
            if spec.temperature is not None:
                parameters.extend(["temperature", "top_p"])
            if spec.reasoning is not None:
                parameters.append("reasoning")
            return json.dumps(
                {
                    "data": {
                        "endpoints": [
                            {
                                "tag": spec.provider_endpoint,
                                "provider_name": "OpenAI" if spec.provider_endpoint == "openai" else "Google AI Studio",
                                "supported_parameters": parameters,
                                "quantization": None,
                                "pricing": {"prompt": "0.0000001", "completion": "0.0000004"},
                                "status": "active",
                            }
                        ]
                    }
                }
            ).encode()

        with tempfile.TemporaryDirectory() as directory, patch(
            "paceprompt_eval.v3.RUNS_ROOT", Path(directory)
        ), patch.dict(os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}):
            gate = asyncio.run(
                prepare_gate(
                    "offline-v3-gate",
                    asset_root=FABLE_ASSET_ROOT,
                    fetch=fake_fetch,
                )
            )
            run_dir = Path(directory) / "offline-v3-gate"
            serialized = b"".join(path.read_bytes() for path in run_dir.rglob("*") if path.is_file())
        self.assertEqual(gate["providerCalls"], 0)
        self.assertFalse(gate["credentialRead"])
        self.assertEqual(gate["spendUSD"], "0.00")
        self.assertEqual(gate["costPreflight"]["callCount"], 714)
        self.assertEqual(gate["costPreflight"]["repetitions"], 3)
        self.assertEqual(gate["costPreflight"]["hardLimitUSD"], "25.00")
        self.assertTrue(gate["costPreflight"]["admitted"])
        self.assertIsNotNone(gate["authorizationPhrase"])
        self.assertEqual(
            set(gate["costPreflight"]["perModelEstimatedInputTokens"]),
            {spec.requested_model_id for spec in specs},
        )
        self.assertIsNone(gate["costPreflight"]["fallbackRepetitions"])
        self.assertNotIn(b"must-not-be-read", serialized)
        self.assertNotIn(b'"rationale"', serialized)
        self.assertNotIn(b'"conventionTags"', serialized)


if __name__ == "__main__":
    unittest.main()
