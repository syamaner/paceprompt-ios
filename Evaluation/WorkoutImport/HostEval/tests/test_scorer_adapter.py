from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from paceprompt_eval.scorer_adapter import (
    flat_envelope_transport_output,
    invalid_observed,
    normalized_document,
    not_started,
    parse_model_output,
    provider_outcome,
    provider_transport_output,
    semantic_json_transport_output,
    shallow_step_transport_output,
    score_completed,
    v1_observed,
)
from paceprompt_eval.task import (
    DEVELOPMENT_CASES,
    FLAT_ENVELOPE_TRANSPORT_SCHEMA,
    HELDOUT_CASES,
    MODEL_SCHEMA,
    TRANSPORT_SCHEMA,
    SHALLOW_STEP_TRANSPORT_SCHEMA,
    SEMANTIC_JSON_TRANSPORT_SCHEMA,
    load_cases,
    strict_json_load,
)
from paceprompt_eval.transport_strategy import (
    TransportStrategyID,
    STRATEGIES,
)


class ScorerAdapterTests(unittest.TestCase):
    def document(self, case: dict, observed: dict) -> dict:
        return normalized_document(
            case=case,
            observed=observed,
            run_id="offline-test",
            result_id="result-" + case["id"],
            repetition_index=1,
            app_commit="0" * 40,
            model_id="mock/model",
            model_revision=None,
            provider_id="mock-provider",
        )

    def test_every_expected_v2_result_passes_unchanged_v1_scorer(self) -> None:
        cases = load_cases(DEVELOPMENT_CASES) + load_cases(HELDOUT_CASES)
        for case in cases:
            with self.subTest(case=case["id"]), TemporaryDirectory() as directory:
                observed = v1_observed(case["expected"]["modelOutput"])
                report = score_completed(
                    projection_root=Path(directory) / "projection",
                    case=case,
                    document=self.document(case, observed),
                )
                self.assertEqual(report["status"], "complete")
                self.assertEqual(report["caseResults"][0]["overall"], "passed")

    def test_invalid_model_json_remains_model_quality_failure(self) -> None:
        case = load_cases(HELDOUT_CASES)[0]
        observed = parse_model_output("not-json", strict_json_load(MODEL_SCHEMA))
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        with TemporaryDirectory() as directory:
            report = score_completed(
                projection_root=Path(directory) / "projection",
                case=case,
                document=self.document(case, observed),
            )
        self.assertEqual(report["status"], "complete")
        self.assertEqual(report["caseResults"][0]["pipelineClassification"], "invalidGeneratorOutput")

    def test_exact_transport_sentinels_are_removed_before_full_v2_validation(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(TRANSPORT_SCHEMA)
        for case in (load_cases(HELDOUT_CASES)[0], load_cases(HELDOUT_CASES)[8]):
            content = __import__("json").dumps(
                provider_transport_output(case["expected"]["modelOutput"])
            )
            observed = parse_model_output(content, semantic_schema, transport_schema)
            self.assertEqual(observed["structure"], "valid")

    def test_inexact_transport_sentinel_remains_a_semantic_failure(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(TRANSPORT_SCHEMA)
        case = load_cases(HELDOUT_CASES)[8]
        value = provider_transport_output(case["expected"]["modelOutput"])
        value["outcome"]["proposal"]["suggestedName"] = "not empty"
        observed = parse_model_output(
            __import__("json").dumps(value), semantic_schema, transport_schema
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")

    def test_transport_relaxes_duration_bound_but_semantic_schema_enforces_it(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(TRANSPORT_SCHEMA)
        case = next(
            item for item in load_cases(HELDOUT_CASES)
            if item["expected"]["modelOutput"]["outcome"]["type"] == "proposal"
        )
        value = provider_transport_output(case["expected"]["modelOutput"])
        value["outcome"]["proposal"]["steps"][0]["duration"]["value"] = 0
        observed = parse_model_output(
            __import__("json").dumps(value), semantic_schema, transport_schema
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertTrue(
            all(error["code"] == "strictSchemaViolation" for error in observed["errors"])
        )

    def test_shallow_step_transport_round_trips_every_v2_expected_result(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(SHALLOW_STEP_TRANSPORT_SCHEMA)
        strategy = STRATEGIES[TransportStrategyID.SHALLOW_STEP_V2_7]
        cases = load_cases(DEVELOPMENT_CASES) + load_cases(HELDOUT_CASES)
        for case in cases:
            with self.subTest(case=case["id"]):
                value = shallow_step_transport_output(case["expected"]["modelOutput"])
                observed = parse_model_output(
                    __import__("json").dumps(value),
                    semantic_schema,
                    transport_schema,
                    strategy.normalize_output,
                )
                self.assertEqual(observed["structure"], "valid", observed)

    def test_shallow_projection_does_not_weaken_semantic_duration_validation(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(SHALLOW_STEP_TRANSPORT_SCHEMA)
        strategy = STRATEGIES[TransportStrategyID.SHALLOW_STEP_V2_7]
        case = next(
            item for item in load_cases(HELDOUT_CASES)
            if item["expected"]["modelOutput"]["outcome"]["type"] == "proposal"
        )
        value = shallow_step_transport_output(case["expected"]["modelOutput"])
        value["outcome"]["proposal"]["steps"][0]["durationValue"] = 0
        observed = parse_model_output(
            __import__("json").dumps(value),
            semantic_schema,
            transport_schema,
            strategy.normalize_output,
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertTrue(
            all(error["code"] == "strictSchemaViolation" for error in observed["errors"])
        )

    def test_flat_envelope_transport_round_trips_every_v2_expected_result(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(FLAT_ENVELOPE_TRANSPORT_SCHEMA)
        strategy = STRATEGIES[TransportStrategyID.FLAT_ENVELOPE_V2_8]
        cases = load_cases(DEVELOPMENT_CASES) + load_cases(HELDOUT_CASES)
        for case in cases:
            with self.subTest(case=case["id"]):
                value = flat_envelope_transport_output(case["expected"]["modelOutput"])
                observed = parse_model_output(
                    __import__("json").dumps(value),
                    semantic_schema,
                    transport_schema,
                    strategy.normalize_output,
                )
                self.assertEqual(observed["structure"], "valid", observed)

    def test_flat_envelope_does_not_weaken_semantic_duration_validation(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(FLAT_ENVELOPE_TRANSPORT_SCHEMA)
        strategy = STRATEGIES[TransportStrategyID.FLAT_ENVELOPE_V2_8]
        case = next(
            item for item in load_cases(HELDOUT_CASES)
            if item["expected"]["modelOutput"]["outcome"]["type"] == "proposal"
        )
        value = flat_envelope_transport_output(case["expected"]["modelOutput"])
        value["steps"][0]["durationValue"] = 0
        observed = parse_model_output(
            __import__("json").dumps(value),
            semantic_schema,
            transport_schema,
            strategy.normalize_output,
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertTrue(
            all(error["code"] == "strictSchemaViolation" for error in observed["errors"])
        )

    def test_semantic_json_transport_round_trips_every_v2_expected_result(self) -> None:
        semantic_schema = strict_json_load(MODEL_SCHEMA)
        transport_schema = strict_json_load(SEMANTIC_JSON_TRANSPORT_SCHEMA)
        strategy = STRATEGIES[TransportStrategyID.SEMANTIC_JSON_V2_9]
        cases = load_cases(DEVELOPMENT_CASES) + load_cases(HELDOUT_CASES)
        for case in cases:
            with self.subTest(case=case["id"]):
                value = semantic_json_transport_output(case["expected"]["modelOutput"])
                observed = parse_model_output(
                    __import__("json").dumps(value),
                    semantic_schema,
                    transport_schema,
                    strategy.normalize_output,
                )
                self.assertEqual(observed["structure"], "valid", observed)

    def test_semantic_json_malformed_inner_json_is_model_quality_failure(self) -> None:
        observed = parse_model_output(
            __import__("json").dumps({"semanticJson": "{not-json"}),
            strict_json_load(MODEL_SCHEMA),
            strict_json_load(SEMANTIC_JSON_TRANSPORT_SCHEMA),
            STRATEGIES[TransportStrategyID.SEMANTIC_JSON_V2_9].normalize_output,
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertEqual(observed["errors"][0]["code"], "invalidJSON")
        self.assertTrue(observed["errors"][0]["path"].startswith("$.semanticJson"))

    def test_semantic_json_does_not_weaken_semantic_duration_validation(self) -> None:
        case = next(
            item for item in load_cases(HELDOUT_CASES)
            if item["expected"]["modelOutput"]["outcome"]["type"] == "proposal"
        )
        semantic = __import__("copy").deepcopy(case["expected"]["modelOutput"])
        semantic["outcome"]["proposal"]["steps"][0]["duration"]["value"] = 0
        observed = parse_model_output(
            __import__("json").dumps(semantic_json_transport_output(semantic)),
            strict_json_load(MODEL_SCHEMA),
            strict_json_load(SEMANTIC_JSON_TRANSPORT_SCHEMA),
            STRATEGIES[TransportStrategyID.SEMANTIC_JSON_V2_9].normalize_output,
        )
        self.assertEqual(observed["structure"], "invalidGeneratorOutput")
        self.assertTrue(
            all(error["code"] == "strictSchemaViolation" for error in observed["errors"])
        )

    def test_host_outcomes_and_not_started_are_closed(self) -> None:
        self.assertEqual(
            provider_outcome("providerFailure", "timeout")["outcome"]["reasonCategory"],
            "timeout",
        )
        self.assertEqual(not_started("attempt", "operatorCancelled")["status"], "notStarted")
        with self.assertRaises(ValueError):
            provider_outcome("providerFailure", "madeUp")
        with self.assertRaises(ValueError):
            not_started("attempt", "madeUp")

    def test_projection_changes_only_v1_contract_marker(self) -> None:
        case = load_cases(HELDOUT_CASES)[0]
        observed = v1_observed(case["expected"]["modelOutput"])
        proposal = observed["outcome"]["proposal"]
        self.assertEqual(proposal["contractVersion"], "workout-proposal/v1")
        expected = case["expected"]["modelOutput"]["outcome"]["proposal"]
        self.assertEqual(proposal["steps"], expected["steps"])


if __name__ == "__main__":
    unittest.main()
