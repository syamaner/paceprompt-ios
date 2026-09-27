"""Contract checks for the Sol comparison aggregate boundary."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
import unittest

from verify_sol_comparison_publication import BASE, verify


class SolComparisonPublicationTests(unittest.TestCase):
    def test_publication_is_pinned_and_non_selecting(self) -> None:
        result = verify()
        self.assertEqual(result["status"], "valid", result["errors"])
        self.assertEqual(result["aggregateArtifactCount"], 3)

    def test_changed_aggregate_fails(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_name = "issue145-sol56-vs-sol6-publication-manifest.json"
            manifest = json.loads((BASE / manifest_name).read_text(encoding="utf-8"))
            names = {manifest_name, *manifest["protectedHistoricalArtifacts"], *manifest["proposedAggregateArtifacts"]}
            for name in names:
                shutil.copyfile(BASE / name, root / name)
            data = root / "issue145-sol56-vs-sol6-2026-09-22-data.json"
            report = json.loads(data.read_text(encoding="utf-8"))
            report["automaticWinner"] = "openai/gpt-6-sol"
            data.write_text(json.dumps(report), encoding="utf-8")
            result = verify(root, enforce_manifest_hash=False)
            self.assertEqual(result["status"], "invalid")
            self.assertTrue(any("aggregate artifact changed" in error for error in result["errors"]))


if __name__ == "__main__":
    unittest.main()
