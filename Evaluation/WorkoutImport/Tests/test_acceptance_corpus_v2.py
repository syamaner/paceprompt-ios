from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import unittest

from Evaluation.WorkoutImport.Acceptance.verify_v2 import (
    compute_corpus_hash,
    verify,
)
from Evaluation.WorkoutImport.Scoring.scorer import strict_load


ROOT = Path(__file__).resolve().parents[1]


class AcceptanceCorpusV2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = verify(ROOT)
        cls.manifest = strict_load(ROOT / "Corpus" / "v2" / "manifest.json")
        cls.cases = strict_load(ROOT / "Corpus" / "v2" / "cases.json")

    def test_reviewer_authored_acceptance_corpus_is_mechanically_valid(self) -> None:
        self.assertEqual(self.report["status"], "valid", self.report["errors"])
        self.assertEqual(self.report["caseCount"], 28)
        self.assertEqual(self.report["proposalCaseCount"], 17)
        self.assertEqual(self.report["failClosedCaseCount"], 11)
        self.assertEqual(self.report["localValidatorCounts"], {"valid": 17})
        self.assertEqual(self.report["sealedV1Assets"], 6)

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
        easy = [by_id[f"WI-V2-A00{index}"] for index in (1, 2, 3)]
        canonical = [case["expected"]["canonicalProposal"] for case in easy]
        self.assertEqual(canonical[0], canonical[1])
        self.assertEqual(canonical[1], canonical[2])
        self.assertEqual(canonical[0]["suggestedName"], "Easy Hills")
        self.assertEqual(
            by_id["WI-V2-A017"]["expected"]["reasonCategory"],
            "insufficientStepsForKindInference",
        )
        self.assertEqual(
            by_id["WI-V2-A018"]["expected"]["reasonCategory"],
            "insufficientStepsForKindInference",
        )
        self.assertEqual(
            by_id["WI-V2-A014"]["expected"]["canonicalProposal"]["steps"][2]["kind"],
            "recovery",
        )
        self.assertEqual(by_id["WI-V2-A026"]["expected"]["affectedPaths"], [])

    def test_model_visible_examples_are_required_review_sources(self) -> None:
        review = strict_load(ROOT / "Corpus" / "v2" / "semantic-review.json")
        self.assertIn(
            "PacePrompt/Import/ImportResources/examples.json",
            review["reviewedAgainst"],
        )

if __name__ == "__main__":
    unittest.main()
