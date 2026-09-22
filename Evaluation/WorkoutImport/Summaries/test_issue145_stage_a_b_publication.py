from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from verify_issue145_stage_a_b_publication import BASE, HOST_EVAL, MANIFEST, verify


class Issue145StageABPublicationTests(unittest.TestCase):
    def test_committed_publication_is_valid(self) -> None:
        result = verify()
        self.assertEqual(result["status"], "valid", result["errors"])
        self.assertEqual(result["publishedArtifactCount"], 4)
        self.assertEqual(result["protectedArtifactCount"], 7)

    def test_every_new_publication_artifact_is_hash_bound(self) -> None:
        manifest = json.loads((BASE / MANIFEST).read_text())
        names = tuple(manifest["publishedArtifacts"])
        for name in names:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                base, host_eval = self._copy_publication(Path(directory))
                with (base / name).open("ab") as handle:
                    handle.write(b"\n")
                result = verify(base, host_eval, enforce_manifest_hash=False)
                self.assertEqual(result["status"], "invalid")
                self.assertIn(
                    f"published artifact hash changed: {name}", result["errors"]
                )

    def test_proposal_and_ratification_are_hash_bound(self) -> None:
        for name, expected in (
            (
                "issue145-stage-a-b-publication-proposal-r1.json",
                "ratified proposal hash changed",
            ),
            (
                "issue145-stage-a-b-publication-ratification-r1.json",
                "publication ratification hash changed",
            ),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                base, host_eval = self._copy_publication(Path(directory))
                with (host_eval / name).open("ab") as handle:
                    handle.write(b"\n")
                result = verify(base, host_eval, enforce_manifest_hash=False)
                self.assertEqual(result["status"], "invalid")
                self.assertIn(expected, result["errors"])

    def test_manifest_tampering_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base, host_eval = self._copy_publication(Path(directory))
            with (base / MANIFEST).open("ab") as handle:
                handle.write(b"\n")
            result = verify(base, host_eval)
            self.assertEqual(result["status"], "invalid")
            self.assertIn("publication manifest hash changed", result["errors"])

    @staticmethod
    def _copy_publication(root: Path) -> tuple[Path, Path]:
        base = root / "Summaries"
        host_eval = root / "HostEval"
        base.mkdir()
        host_eval.mkdir()
        manifest = json.loads((BASE / MANIFEST).read_text())
        names = {
            MANIFEST,
            *manifest["protectedExistingArtifacts"],
            *manifest["protectedHistoricalArtifacts"],
            *manifest["publishedArtifacts"],
        }
        for name in names:
            shutil.copy2(BASE / name, base / name)
        for name in (
            "issue145-stage-a-b-publication-proposal-r1.json",
            "issue145-stage-a-b-publication-ratification-r1.json",
        ):
            shutil.copy2(HOST_EVAL / name, host_eval / name)
        return base, host_eval


if __name__ == "__main__":
    unittest.main()
