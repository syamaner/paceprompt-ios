from __future__ import annotations

from decimal import Decimal
import os
import unittest
from dataclasses import replace

from paceprompt_eval.openrouter import load_model_specs
from paceprompt_eval.task import (
    FLAT_STRATEGY_DIAGNOSTIC_MODELS,
    FLAT_STRATEGY_MODELS,
    MODELS,
    SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS,
    SEMANTIC_JSON_STRATEGY_MODELS,
    STRATEGY_DIAGNOSTIC_MODELS,
    STRATEGY_MODELS,
)
from paceprompt_eval.transport_strategy import (
    PROVIDER_SCHEMA_PROFILES,
    SchemaProfileID,
    strategy_for,
)

from paceprompt_eval.task import (
    SpendGuard,
    SpendingLimitReached,
    canonical_hash,
    deterministic_queue,
    deterministic_flat_strategy_queue,
    deterministic_semantic_json_strategy_queue,
    deterministic_strategy_queue,
    operator_gate,
    validate_gate_authorization,
    verify,
)


class ContractTests(unittest.TestCase):
    def test_v2_artifacts_and_leakage_are_valid(self) -> None:
        report = verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual(report["developmentCases"], 17)
        self.assertEqual(report["heldoutCases"], 34)
        self.assertEqual(report["fewShotCases"], 8)

    def test_deterministic_queues_have_frozen_sizes_and_unique_attempts(self) -> None:
        one = deterministic_queue(1)
        five = deterministic_queue(5)
        self.assertEqual(len(one), 170)
        self.assertEqual(len(five), 850)
        self.assertEqual(len({item["attemptID"] for item in five}), 850)
        self.assertEqual(deterministic_strategy_queue(1), one)
        self.assertEqual(deterministic_strategy_queue(5), five)
        self.assertEqual(deterministic_flat_strategy_queue(1), one)
        self.assertEqual(deterministic_flat_strategy_queue(5), five)
        self.assertEqual(deterministic_semantic_json_strategy_queue(1), one)
        self.assertEqual(deterministic_semantic_json_strategy_queue(5), five)

    def test_spend_guard_reserves_worst_case_before_calls(self) -> None:
        guard = SpendGuard("20.00")
        guard.reserve("first", Decimal("12.00"))
        with self.assertRaises(SpendingLimitReached):
            guard.reserve("second", Decimal("8.01"))
        guard.settle("first", Decimal("3.00"))
        guard.reserve("second", Decimal("8.01"))
        self.assertEqual(guard.actual + guard.reserved, Decimal("11.01"))

    def test_operator_gate_does_not_read_or_reveal_credential(self) -> None:
        previous = os.environ.get("OPENROUTER_API_KEY")
        os.environ["OPENROUTER_API_KEY"] = "must-not-appear"
        try:
            report = operator_gate()
        finally:
            if previous is None:
                os.environ.pop("OPENROUTER_API_KEY", None)
            else:
                os.environ["OPENROUTER_API_KEY"] = previous
        self.assertFalse(report["credentialRead"])
        self.assertNotIn("must-not-appear", str(report))

    def test_operator_authorization_seals_the_complete_gate(self) -> None:
        gate = {"runID": "diagnostic", "spendUSD": "0.00", "liveCallsMade": 0}
        phrase = "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
        gate["authorizationPhrase"] = phrase
        validate_gate_authorization(gate, phrase)
        gate["liveCallsMade"] = 1
        with self.assertRaises(RuntimeError):
            validate_gate_authorization(gate, phrase)

    def test_transport_strategy_registry_is_exact_and_fails_closed(self) -> None:
        assignments = {
            spec.requested_model_id: strategy_for(spec).identifier.value
            for spec in load_model_specs(MODELS)
        }
        self.assertEqual(
            assignments,
            {
                "openai/gpt-5.6-sol": "nestedV23",
                "anthropic/claude-sonnet-5": "nestedV23",
                "openai/gpt-5.6-luna": "nestedV23",
                "google/gemini-3.5-flash-lite": "shallowStepV27",
                "google/gemini-3.7-flash": "shallowStepV27",
            },
        )
        declared = {
            spec.requested_model_id: spec.transport_strategy_id
            for spec in load_model_specs(STRATEGY_MODELS)
        }
        self.assertEqual(declared, assignments)
        gemini = load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)[0]
        with self.assertRaises(ValueError):
            strategy_for(replace(gemini, canonical_revision=gemini.canonical_revision + "-drift"))
        with self.assertRaises(ValueError):
            strategy_for(replace(gemini, transport_strategy_id="nestedV23"))

    def test_v2_8_transport_registry_is_exact_and_fails_closed(self) -> None:
        expected = {
            "openai/gpt-5.6-sol": "nestedV23",
            "anthropic/claude-sonnet-5": "nestedV23",
            "openai/gpt-5.6-luna": "nestedV23",
            "google/gemini-3.5-flash-lite": "flatEnvelopeV28",
            "google/gemini-3.7-flash": "flatEnvelopeV28",
        }
        specs = load_model_specs(FLAT_STRATEGY_MODELS)
        self.assertEqual(
            {spec.requested_model_id: strategy_for(spec).identifier.value for spec in specs},
            expected,
        )
        diagnostic = load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS)
        self.assertEqual(
            {spec.requested_model_id: strategy_for(spec).identifier.value for spec in diagnostic},
            {model_id: expected[model_id] for model_id in expected if model_id.startswith("google/")},
        )
        gemini = diagnostic[0]
        with self.assertRaises(ValueError):
            strategy_for(replace(gemini, transport_registry_id="unknownRegistry"))
        with self.assertRaises(ValueError):
            strategy_for(replace(gemini, transport_strategy_id="shallowStepV27"))

    def test_v2_9_registry_selects_profile_owned_strategies(self) -> None:
        expected = {
            "openai/gpt-5.6-sol": ("nestedV23", "portableStrictV23"),
            "anthropic/claude-sonnet-5": ("nestedV23", "portableStrictV23"),
            "openai/gpt-5.6-luna": ("nestedV23", "portableStrictV23"),
            "google/gemini-3.5-flash-lite": (
                "semanticJsonV29",
                "googleGeminiMinimalV29",
            ),
            "google/gemini-3.7-flash": (
                "semanticJsonV29",
                "googleGeminiMinimalV29",
            ),
        }
        specs = load_model_specs(SEMANTIC_JSON_STRATEGY_MODELS)
        self.assertEqual(
            {
                spec.requested_model_id: (
                    strategy_for(spec).identifier.value,
                    strategy_for(spec).schema_profile.identifier.value,
                )
                for spec in specs
            },
            expected,
        )
        diagnostic = load_model_specs(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS)
        self.assertTrue(
            all(strategy_for(spec).identifier.value == "semanticJsonV29" for spec in diagnostic)
        )

    def test_gemini_profile_rejects_schema_expansion_before_payload_build(self) -> None:
        profile = PROVIDER_SCHEMA_PROFILES[
            SchemaProfileID.GOOGLE_GEMINI_MINIMAL_V2_9
        ]
        expanded = {
            "type": "object",
            "required": ["semanticJson", "extra"],
            "properties": {
                "semanticJson": {"type": "string"},
                "extra": {"type": "string", "enum": ["one"]},
            },
            "additionalProperties": False,
        }
        problems = profile.validate(expanded)
        self.assertTrue(any("2 properties" in problem for problem in problems))
        self.assertTrue(any("unsupported keyword enum" in problem for problem in problems))
        self.assertTrue(any("1 enum values" in problem for problem in problems))


if __name__ == "__main__":
    unittest.main()
