from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import unittest

from Evaluation.WorkoutImport.Acceptance.verify_v3 import (
    compute_corpus_hash,
    non_proposal_contract_errors,
    verify,
)
from Evaluation.WorkoutImport.Scoring.scorer import strict_load


ROOT = Path(__file__).resolve().parents[1]


class AcceptanceCorpusV3Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = verify(ROOT)
        cls.manifest = strict_load(ROOT / "Corpus" / "v3" / "manifest.json")
        cls.cases = strict_load(ROOT / "Corpus" / "v3" / "cases.json")

    def test_reviewer_authored_acceptance_corpus_is_mechanically_valid(self) -> None:
        self.assertEqual(self.report["status"], "valid", self.report["errors"])
        self.assertEqual(self.report["caseCount"], 30)
        self.assertEqual(self.report["proposalCaseCount"], 19)
        self.assertEqual(self.report["failClosedCaseCount"], 11)
        self.assertEqual(
            self.report["localValidatorCounts"], {"invalid": 2, "valid": 17}
        )
        self.assertEqual(self.report["sealedV1Assets"], 6)
        self.assertEqual(self.report["sealedV2Assets"], 5)

    def test_hash_changes_with_case_content_but_not_object_or_case_order(self) -> None:
        self.assertEqual(
            compute_corpus_hash(self.manifest, reversed(self.cases)),
            self.manifest["corpusHash"],
        )
        changed = deepcopy(self.cases)
        changed[0]["prompt"] += " changed"
        self.assertNotEqual(
            compute_corpus_hash(self.manifest, changed),
            self.manifest["corpusHash"],
        )
        changed_manifest = deepcopy(self.manifest)
        changed_manifest["capabilityProfiles"]["standardTreadmillV1"]["speed"]["maximum"] = 19
        self.assertNotEqual(
            compute_corpus_hash(changed_manifest, self.cases),
            self.manifest["corpusHash"],
        )

    def test_easy_hills_equivalence_and_boundary_decisions_are_frozen(self) -> None:
        by_id = {case["id"]: case for case in self.cases}
        easy = [by_id[f"WI-V3-A00{index}"] for index in (1, 2, 3)]
        canonical = [case["expected"]["canonicalProposal"] for case in easy]
        self.assertEqual(canonical[0], canonical[1])
        self.assertEqual(canonical[1], canonical[2])
        self.assertTrue(
            all(
                case["expected"]["suggestedNameExpectation"]
                == {"mode": "exact", "value": "Easy Hills"}
                for case in easy
            )
        )
        self.assertEqual(
            by_id["WI-V3-A017"]["expected"]["reasonCategory"],
            "missingRequiredField",
        )
        self.assertEqual(
            by_id["WI-V3-A018"]["expected"]["reasonCategory"],
            "missingRequiredField",
        )
        self.assertEqual(
            by_id["WI-V3-A017"]["expected"]["affectedPaths"], ["steps.kind"]
        )
        self.assertEqual(
            by_id["WI-V3-A018"]["expected"]["affectedPaths"], ["steps.kind"]
        )
        self.assertEqual(
            by_id["WI-V3-A014"]["expected"]["canonicalProposal"]["steps"][2]["kind"],
            "recovery",
        )
        self.assertEqual(by_id["WI-V3-A026"]["expected"]["affectedPaths"], [])

    def test_fail_closed_answers_use_production_reason_and_path_vocabulary(self) -> None:
        by_id = {case["id"]: case for case in self.cases}
        self.assertEqual(
            by_id["WI-V3-A021"]["expected"]["affectedPaths"],
            ["steps.targetSpeed"],
        )
        self.assertEqual(
            by_id["WI-V3-A022"]["expected"]["affectedPaths"],
            ["steps.targetInclination"],
        )
        self.assertEqual(
            by_id["WI-V3-A023"]["expected"],
            {
                "outcome": "clarificationRequired",
                "reasonCategory": "missingRequiredField",
                "affectedPaths": ["steps.targetInclination.value"],
            },
        )
        self.assertEqual(
            by_id["WI-V3-A024"]["expected"]["affectedPaths"],
            ["steps.targetSpeed.value"],
        )
        self.assertEqual(
            by_id["WI-V3-A028"]["expected"]["affectedPaths"],
            ["steps.targetInclination.value"],
        )

    def test_names_and_explicit_short_plan_boundaries_are_frozen(self) -> None:
        proposals = [case for case in self.cases if case["expected"]["outcome"] == "proposal"]
        exact = [
            case for case in proposals
            if case["expected"]["suggestedNameExpectation"]["mode"] == "exact"
        ]
        non_empty = [
            case for case in proposals
            if case["expected"]["suggestedNameExpectation"]["mode"] == "nonEmpty"
        ]
        self.assertEqual([case["id"] for case in exact], [
            "WI-V3-A001", "WI-V3-A002", "WI-V3-A003", "WI-V3-A029", "WI-V3-A030"
        ])
        self.assertEqual(len(non_empty), 14)

        by_id = {case["id"]: case for case in self.cases}
        self.assertEqual(
            by_id["WI-V3-A029"]["expected"]["localValidatorIssueCodes"],
            ["invalidStepOrder"],
        )
        self.assertEqual(
            by_id["WI-V3-A030"]["expected"]["localValidatorIssueCodes"],
            ["missingInterval"],
        )

    def test_non_proposal_contract_rejects_r1_vocabulary_defects(self) -> None:
        by_id = {case["id"]: case for case in self.cases}

        unsupported_reason = deepcopy(by_id["WI-V3-A017"])
        unsupported_reason["expected"]["reasonCategory"] = (
            "insufficientStepsForKindInference"
        )
        self.assertTrue(non_proposal_contract_errors(unsupported_reason))

        indexed_path = deepcopy(by_id["WI-V3-A024"])
        indexed_path["expected"]["affectedPaths"] = [
            "steps[1].targetSpeed.value"
        ]
        self.assertTrue(non_proposal_contract_errors(indexed_path))

        wrong_outcome_pairing = deepcopy(by_id["WI-V3-A027"])
        wrong_outcome_pairing["expected"]["outcome"] = "clarificationRequired"
        self.assertTrue(non_proposal_contract_errors(wrong_outcome_pairing))

    def test_model_visible_examples_are_required_review_sources(self) -> None:
        review = strict_load(ROOT / "Corpus" / "v3" / "semantic-review.json")
        self.assertIn(
            "PacePrompt/Import/ImportResources/examples.json",
            review["reviewedAgainst"],
        )

if __name__ == "__main__":
    unittest.main()
