from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
import unittest

from verify_issue145_stage_a_publication import BASE, MANIFEST, verify


class Issue145StageAPublicationTests(unittest.TestCase):
    def test_committed_publication_is_valid(self) -> None:
        result = verify()
        self.assertEqual(result["status"], "valid", result["errors"])
        self.assertEqual(result["publishedArtifactCount"], 3)

    def test_every_published_artifact_is_hash_bound(self) -> None:
        names = (
            "issue145-stage-a-2026-09-20.md",
            "issue145-stage-a-data.json",
            "issue145-stage-a-evidence-integrity.json",
        )
        for name in names:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                target = Path(directory)
                for source_name in (*names, MANIFEST):
                    shutil.copy2(BASE / source_name, target / source_name)
                with (target / name).open("ab") as handle:
                    handle.write(b"\n")
                result = verify(target)
                self.assertEqual(result["status"], "invalid")
                self.assertIn(f"published artifact hash changed: {name}", result["errors"])

    def test_manifest_tampering_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            for name in (
                "issue145-stage-a-2026-09-20.md",
                "issue145-stage-a-data.json",
                "issue145-stage-a-evidence-integrity.json",
                MANIFEST,
            ):
                shutil.copy2(BASE / name, target / name)
            with (target / MANIFEST).open("ab") as handle:
                handle.write(b"\n")
            result = verify(target)
            self.assertEqual(result["status"], "invalid")
            self.assertIn("publication manifest hash changed", result["errors"])


if __name__ == "__main__":
    unittest.main()
