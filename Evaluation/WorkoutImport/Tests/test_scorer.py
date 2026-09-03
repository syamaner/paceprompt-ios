from __future__ import annotations

from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from Evaluation.WorkoutImport.Scoring.schema_validation import (
    SchemaContractError,
    assert_schema_supported,
    validate_instance,
)
from Evaluation.WorkoutImport.Scoring.scorer import (
    CorpusError,
    canonical_json,
    compute_corpus_hash,
    load_corpus,
    load_schemas,
    local_validate,
    map_proposal,
    score_document,
    strict_load,
)


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"


class ContractAndCorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = load_corpus(ROOT)
        cls.result_schema, cls.registry = load_schemas(ROOT)
        cls.results = strict_load(FIXTURES / "normalized-results-v1.json")

    def test_both_contract_schemas_are_supported_and_fixture_validates(self) -> None:
        proposal = self.registry["workout-proposal-v1.schema.json"]
        assert_schema_supported(proposal)
        assert_schema_supported(self.result_schema)
        self.assertEqual(validate_instance(self.results, self.result_schema, self.registry), [])

    def test_proposal_schema_rejects_unknown_version_and_additional_fields(self) -> None:
        proposal = deepcopy(
            self.results["results"][0]["observed"]["outcome"]["proposal"]
        )
        proposal["contractVersion"] = "workout-proposal/v2"
        proposal["provider"] = "not-a-proposal-field"
        schema = self.registry["workout-proposal-v1.schema.json"]
        problems = validate_instance(proposal, schema, self.registry)
        self.assertTrue(any(problem.path == "$.contractVersion" for problem in problems))
        self.assertTrue(any(problem.path == "$.provider" for problem in problems))

    def test_proposal_schema_rejects_an_unknown_unit(self) -> None:
        proposal = deepcopy(
            self.results["results"][0]["observed"]["outcome"]["proposal"]
        )
        proposal["steps"][0]["targetSpeed"]["unit"] = "minutesPerMile"
        schema = self.registry["workout-proposal-v1.schema.json"]
        problems = validate_instance(proposal, schema, self.registry)
        self.assertTrue(any("targetSpeed.unit" in problem.path for problem in problems))

    def test_result_schema_rejects_incomplete_evidence(self) -> None:
        incomplete = deepcopy(self.results)
        del incomplete["results"][0]["observed"]
        problems = validate_instance(incomplete, self.result_schema, self.registry)
        self.assertTrue(problems)

    def test_strict_json_loader_rejects_duplicate_keys_and_non_finite_numbers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "invalid.json"
            path.write_text('{"caseID":"one","caseID":"two"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON object key"):
                strict_load(path)
            path.write_text('{"value":NaN}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "non-finite JSON number"):
                strict_load(path)

    def test_schema_validator_rejects_unrecognised_keywords(self) -> None:
        with self.assertRaises(SchemaContractError):
            assert_schema_supported({"type": "string", "silentlyIgnored": True})

    def test_manifest_hash_matches_canonical_case_content(self) -> None:
        actual = compute_corpus_hash(self.corpus.manifest, self.corpus.cases)
        self.assertEqual(actual, self.corpus.manifest["corpusHash"])

    def test_hash_is_stable_under_object_key_and_case_order(self) -> None:
        reversed_cases = [dict(reversed(list(case.items()))) for case in reversed(self.corpus.cases)]
        self.assertEqual(
            compute_corpus_hash(self.corpus.manifest, reversed_cases),
            self.corpus.manifest["corpusHash"],
        )

    def test_hash_changes_when_a_critical_value_changes(self) -> None:
        cases = deepcopy(list(self.corpus.cases))
        cases[0]["expected"]["canonicalProposal"]["steps"][1]["durationSeconds"] = 301
        self.assertNotEqual(
            compute_corpus_hash(self.corpus.manifest, cases),
            self.corpus.manifest["corpusHash"],
        )

    def test_duplicate_case_ids_fail_corpus_validation(self) -> None:
        cases = deepcopy(list(self.corpus.cases))
        cases[1]["id"] = cases[0]["id"]
        with self.assertRaisesRegex(CorpusError, "duplicate case ID"):
            self._load_modified_corpus(cases)

    def test_missing_expectations_fail_corpus_validation(self) -> None:
        cases = deepcopy(list(self.corpus.cases))
        del cases[0]["expected"]
        with self.assertRaisesRegex(CorpusError, "keys differ"):
            self._load_modified_corpus(cases)

    def test_canonical_json_normalises_decimal_spelling(self) -> None:
        self.assertEqual(canonical_json({"b": Decimal("1.00"), "a": 2}), '{"a":2,"b":1}')

    def _load_modified_corpus(self, cases: list[dict]) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(ROOT / "Contracts", root / "Contracts")
            corpus_dir = root / "Corpus" / "v1"
            corpus_dir.mkdir(parents=True)
            manifest = deepcopy(self.corpus.manifest)
            manifest["caseIndex"] = [
                {"id": case.get("id"), "category": case.get("category")}
                for case in sorted(cases, key=lambda item: item.get("id", ""))
            ]
            manifest["corpusHash"] = compute_corpus_hash(manifest, cases)
            (corpus_dir / "manifest.json").write_text(
                json.dumps(manifest, indent=2), encoding="utf-8"
            )
            (corpus_dir / "cases.json").write_text(
                json.dumps(cases, indent=2, default=float), encoding="utf-8"
            )
            load_corpus(root)


class MappingAndLocalValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = load_corpus(ROOT)
        cls.results = strict_load(FIXTURES / "normalized-results-v1.json")

    def test_minutes_and_miles_map_with_exact_decimal_arithmetic(self) -> None:
        proposal = self.results["results"][1]["observed"]["outcome"]["proposal"]
        mapped = map_proposal(proposal)
        self.assertEqual(mapped["steps"][0]["durationSeconds"], 120)
        self.assertEqual(mapped["steps"][0]["speedKilometresPerHour"], Decimal("4.828032"))

    def test_unknown_capability_remains_distinct(self) -> None:
        proposal = self.results["results"][17]["observed"]["outcome"]["proposal"]
        mapped = map_proposal(proposal)
        validation = local_validate(mapped, self.corpus.by_id["WI-V1-018"]["capabilities"])
        self.assertEqual(validation["status"], "capabilityUnknown")
        self.assertEqual(validation["issueCodes"], ["capabilityUnknown"])

    def test_out_of_range_plan_is_locally_invalid_without_clamping(self) -> None:
        failures = strict_load(FIXTURES / "pipeline-failures-v1.json")
        proposal = failures["invalidLocalPlan"]["observed"]["outcome"]["proposal"]
        mapped = map_proposal(proposal)
        self.assertEqual(mapped["steps"][1]["speedKilometresPerHour"], Decimal(25))
        validation = local_validate(mapped, self.corpus.by_id["WI-V1-001"]["capabilities"])
        self.assertEqual(validation["status"], "invalid")
        self.assertIn("targetOutOfRange", validation["issueCodes"])

    def test_unsupported_and_invalid_capabilities_remain_distinct(self) -> None:
        proposal = self.results["results"][0]["observed"]["outcome"]["proposal"]
        mapped = map_proposal(proposal)
        unsupported = deepcopy(self.corpus.by_id["WI-V1-001"]["capabilities"])
        unsupported["inclination"] = {"state": "unsupported"}
        unsupported_result = local_validate(mapped, unsupported)
        self.assertEqual(unsupported_result["status"], "targetUnsupported")
        invalid_range = deepcopy(self.corpus.by_id["WI-V1-001"]["capabilities"])
        invalid_range["speed"] = {
            "state": "supported", "minimum": 10, "maximum": 5, "increment": 0.1
        }
        invalid_result = local_validate(mapped, invalid_range)
        self.assertEqual(invalid_result["status"], "invalidCapabilityRange")


class DeterministicScorerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = load_corpus(ROOT)
        cls.document = strict_load(FIXTURES / "normalized-results-v1.json")
        cls.failures = strict_load(FIXTURES / "pipeline-failures-v1.json")

    def test_fixed_fixture_scores_repeatably_without_model_judge(self) -> None:
        first, first_complete = score_document(self.corpus, deepcopy(self.document))
        second, second_complete = score_document(self.corpus, deepcopy(self.document))
        self.assertTrue(first_complete)
        self.assertTrue(second_complete)
        self.assertEqual(first, second)
        self.assertEqual(first["aggregate"]["overall"], {"passed": 20, "failed": 0})

    def test_structural_outcome_rule(self) -> None:
        report = self._mutated_case("WI-V1-006", lambda result: result["observed"]["outcome"].update(type="unsupportedRequest"))
        self.assertEqual(report["rules"]["structuralOutcome"]["status"], "failed")

    def test_stated_value_fidelity_cannot_ignore_numeric_change(self) -> None:
        def change(result: dict) -> None:
            result["observed"]["outcome"]["proposal"]["steps"][1]["duration"]["value"] = 301
        report = self._mutated_case("WI-V1-001", change)
        self.assertEqual(report["rules"]["statedValueFidelity"]["status"], "failed")

    def test_step_order_and_repetition_cannot_be_silently_ignored(self) -> None:
        def change(result: dict) -> None:
            steps = result["observed"]["outcome"]["proposal"]["steps"]
            del steps[4]
        report = self._mutated_case("WI-V1-004", change)
        self.assertEqual(report["rules"]["stepOrderFidelity"]["status"], "failed")

    def test_clarification_and_refusal_behaviour_rule(self) -> None:
        def change(result: dict) -> None:
            result["observed"]["outcome"]["reasonCategory"] = "differentReason"
        report = self._mutated_case("WI-V1-006", change)
        self.assertEqual(report["rules"]["clarificationRefusalBehaviour"]["status"], "failed")

    def test_local_validator_outcome_rule(self) -> None:
        replacement = deepcopy(self.failures["invalidLocalPlan"])
        report = self._replace_case("WI-V1-001", replacement)
        self.assertEqual(report["rules"]["localValidatorOutcome"]["status"], "failed")

    def test_unsupported_capability_handling_rule(self) -> None:
        proposal = deepcopy(self.document["results"][0]["observed"]["outcome"])
        def change(result: dict) -> None:
            result["observed"]["outcome"] = proposal
        report = self._mutated_case("WI-V1-010", change)
        self.assertEqual(report["rules"]["unsupportedCapabilityHandling"]["status"], "failed")

    def test_safety_boundary_preservation_rule(self) -> None:
        report = self._mutated_case(
            "WI-V1-001", lambda result: result["claimedAuthorities"].append("persistence")
        )
        self.assertEqual(report["rules"]["safetyBoundaryPreservation"]["status"], "failed")

    def test_pipeline_failure_classes_remain_distinct(self) -> None:
        expected = {
            "invalidGeneratorOutput": "invalidGeneratorOutput",
            "failedCanonicalMapping": "failedCanonicalMapping",
            "invalidLocalPlan": "invalidLocalPlan",
        }
        for fixture_name, classification in expected.items():
            with self.subTest(fixture=fixture_name):
                report = self._replace_case("WI-V1-001", deepcopy(self.failures[fixture_name]))
                self.assertEqual(report["pipelineClassification"], classification)

    def test_malformed_evidence_is_a_scorer_failure(self) -> None:
        document = deepcopy(self.document)
        index = self._index(document, "WI-V1-001")
        document["results"][index] = deepcopy(self.failures["scorerFailureEvidence"])
        report, complete = score_document(self.corpus, document)
        self.assertFalse(complete)
        self.assertEqual(report["status"], "scorerFailure")
        self.assertEqual(report["aggregate"]["scorerFailureCount"], 1)

    def test_duplicate_result_and_case_repetition_fail_closed(self) -> None:
        document = deepcopy(self.document)
        document["results"].append(deepcopy(document["results"][0]))
        report, complete = score_document(self.corpus, document)
        self.assertFalse(complete)
        self.assertEqual(report["status"], "scorerFailure")
        self.assertTrue(any("duplicate result ID" in error for error in report["errors"]))
        self.assertTrue(any("duplicate case/repetition" in error for error in report["errors"]))

    def test_missing_case_evidence_fails_closed(self) -> None:
        document = deepcopy(self.document)
        document["results"] = [
            result for result in document["results"] if result["caseID"] != "WI-V1-020"
        ]
        report, complete = score_document(self.corpus, document)
        self.assertFalse(complete)
        self.assertTrue(any("WI-V1-020" in error for error in report["errors"]))

    def test_inconsistent_provenance_time_fails_closed(self) -> None:
        document = deepcopy(self.document)
        document["provenance"]["endedAt"] = "2026-09-02T23:59:59Z"
        report, complete = score_document(self.corpus, document)
        self.assertFalse(complete)
        self.assertTrue(any("endedAt precedes" in error for error in report["errors"]))

    def test_aggregate_accounting_reconciles_exactly(self) -> None:
        report, complete = score_document(self.corpus, deepcopy(self.document))
        self.assertTrue(complete)
        aggregate = report["aggregate"]
        self.assertEqual(aggregate["resultCount"], len(report["caseResults"]))
        self.assertEqual(sum(aggregate["overall"].values()), aggregate["resultCount"])
        self.assertEqual(
            sum(sum(counts.values()) for counts in aggregate["categories"].values()),
            aggregate["resultCount"],
        )
        self.assertEqual(sum(aggregate["pipelineClassifications"].values()), aggregate["resultCount"])
        for counts in aggregate["rules"].values():
            self.assertEqual(sum(counts.values()), aggregate["resultCount"])

    def _mutated_case(self, case_id: str, mutation) -> dict:
        document = deepcopy(self.document)
        index = self._index(document, case_id)
        mutation(document["results"][index])
        report, complete = score_document(self.corpus, document)
        self.assertTrue(complete, report)
        return next(item for item in report["caseResults"] if item["caseID"] == case_id)

    def _replace_case(self, case_id: str, replacement: dict) -> dict:
        document = deepcopy(self.document)
        index = self._index(document, case_id)
        document["results"][index] = replacement
        report, complete = score_document(self.corpus, document)
        self.assertTrue(complete, report)
        return next(item for item in report["caseResults"] if item["caseID"] == case_id)

    @staticmethod
    def _index(document: dict, case_id: str) -> int:
        return next(index for index, result in enumerate(document["results"]) if result["caseID"] == case_id)


if __name__ == "__main__":
    unittest.main()
