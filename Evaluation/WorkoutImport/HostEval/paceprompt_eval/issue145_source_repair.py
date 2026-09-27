"""Verify reviewed, additive HostEval source bridges for historical run gates.

Bridge records live outside the hashed HostEval tree so recording a repair does
not change the source identity it certifies. No bridge is implicit or created by
this module; a compatible repair needs a separately committed reviewed record.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess
from typing import Any

from .v3 import REPOSITORY_ROOT, canonical_hash, sha256_file, strict_json_load


BRIDGE_VERSION = "paceprompt-issue145-compatible-source-repair/r1"
BRIDGE_PREFIX = "Evaluation/WorkoutImport/SourceRepairBridges/"
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_GIT_SHA = re.compile(r"[0-9a-f]{40}\Z")
_EXCLUDED = {".venv", ".runs", "__pycache__", ".pytest_cache", ".ruff_cache"}


def _git(*arguments: str) -> bytes:
    return subprocess.run(
        ("git", *arguments), cwd=REPOSITORY_ROOT, check=True,
        capture_output=True,
    ).stdout


def _source_at_commit(commit: str) -> str:
    """Recompute the current HostEval source-hash contract from Git blobs."""
    if not _GIT_SHA.fullmatch(commit):
        raise RuntimeError("repair commit identity is malformed")
    prefix = "Evaluation/WorkoutImport/HostEval/"
    manifest: dict[str, str] = {}
    for entry in _git("ls-tree", "-r", "-z", commit, "--", prefix).split(b"\0"):
        if not entry:
            continue
        metadata, path_bytes = entry.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        if mode not in {"100644", "100755"} or kind != "blob":
            raise RuntimeError("repair source tree contains an unsupported object")
        path = path_bytes.decode()
        relative = Path(path.removeprefix(prefix))
        if relative.name == ".env" or any(part in _EXCLUDED for part in relative.parts):
            continue
        manifest[str(relative)] = hashlib.sha256(_git("cat-file", "blob", object_id)).hexdigest()
    return canonical_hash(manifest)


def _validated_record(seal: dict[str, str]) -> dict[str, Any]:
    if set(seal) != {"path", "sha256"}:
        raise RuntimeError("source repair seal needs exact path and SHA-256")
    path_text, expected_hash = seal["path"], seal["sha256"]
    if (not isinstance(path_text, str) or not path_text.startswith(BRIDGE_PREFIX)
            or not path_text.endswith(".json") or ".." in Path(path_text).parts
            or not isinstance(expected_hash, str) or not _SHA256.fullmatch(expected_hash)):
        raise RuntimeError("source repair seal path or digest is invalid")
    path = REPOSITORY_ROOT / path_text
    if (path.is_symlink() or path.parent.is_symlink()
            or not path.is_file() or sha256_file(path) != expected_hash):
        raise RuntimeError("source repair record changed or is symlinked")
    if (_git("ls-files", "--error-unmatch", "--", path_text).strip()
            != path_text.encode()
            or _git("diff", "HEAD", "--", path_text)
            or _git("diff", "--cached", "--", path_text)):
        raise RuntimeError("source repair record must be committed and clean")
    record = strict_json_load(path)
    if set(record) != {
        "bridgeVersion", "oldSourceTreeSha256", "newSourceTreeSha256",
        "oldHead", "newHead", "completeDiffSha256", "reviewEvidence",
        "focusedValidationEvidence", "frozenInputsPreserved",
    } or record["bridgeVersion"] != BRIDGE_VERSION:
        raise RuntimeError("source repair record schema changed")
    old, new = record["oldHead"], record["newHead"]
    if (not isinstance(old, str) or not _GIT_SHA.fullmatch(old)
            or not isinstance(new, str) or not _GIT_SHA.fullmatch(new)
            or record["frozenInputsPreserved"] is not True
            or not isinstance(record["reviewEvidence"], str)
            or not record["reviewEvidence"].strip()
            or not isinstance(record["focusedValidationEvidence"], str)
            or not record["focusedValidationEvidence"].strip()):
        raise RuntimeError("source repair lacks reviewed compatible evidence")
    current_head = _git("rev-parse", "HEAD").decode().strip()
    _git("merge-base", "--is-ancestor", old, new)
    _git("merge-base", "--is-ancestor", new, current_head)
    changed = _git("diff", "--name-only", old, new).decode().splitlines()
    allowed = (
        "Evaluation/WorkoutImport/HostEval/paceprompt_eval/",
        "Evaluation/WorkoutImport/HostEval/tests/",
    )
    if not changed or any(
        path not in {"DEVELOPMENT_NOTES.md",
                     "Evaluation/WorkoutImport/HostEval/README.md"}
        and not path.startswith(allowed) for path in changed
    ):
        raise RuntimeError("repair diff reaches outside compatible HostEval scope")
    diff = _git("diff", "--binary", "--no-ext-diff", old, new)
    if (record["oldSourceTreeSha256"] != _source_at_commit(old)
            or record["newSourceTreeSha256"] != _source_at_commit(new)
            or record["completeDiffSha256"] != hashlib.sha256(diff).hexdigest()):
        raise RuntimeError("source repair commit, diff or source identity changed")
    return record


def verify_source_chain(
    sealed_source_sha256: str, current_source_sha256: str,
    seals: list[dict[str, str]],
) -> None:
    """Require a complete, finite reviewed bridge chain when source changed."""
    if (not isinstance(sealed_source_sha256, str)
            or not _SHA256.fullmatch(sealed_source_sha256)
            or not isinstance(current_source_sha256, str)
            or not _SHA256.fullmatch(current_source_sha256)
            or not isinstance(seals, list)
            or any(not isinstance(seal, dict) for seal in seals)):
        raise RuntimeError("source repair chain identity is invalid")
    if not seals and sealed_source_sha256 == current_source_sha256:
        return
    records = [_validated_record(seal) for seal in seals]
    if not records:
        raise RuntimeError("historical source needs an exact reviewed repair bridge")
    if len({seal["path"] for seal in seals}) != len(seals):
        raise RuntimeError("source repair bridge repeats")
    for left, right in zip(records, records[1:]):
        if left["newSourceTreeSha256"] != right["oldSourceTreeSha256"]:
            raise RuntimeError("source repair chain has a gap")
    if records[-1]["newSourceTreeSha256"] != current_source_sha256:
        raise RuntimeError("source repair chain does not end at current source")
    if sealed_source_sha256 == current_source_sha256:
        return
    start = next((index for index, record in enumerate(records)
                  if record["oldSourceTreeSha256"] == sealed_source_sha256), None)
    if start is None:
        raise RuntimeError("repair chain does not start at sealed source")
    cursor = sealed_source_sha256
    for record in records[start:]:
        if record["oldSourceTreeSha256"] != cursor:
            raise RuntimeError("source repair chain has a gap")
        cursor = record["newSourceTreeSha256"]
    if cursor != current_source_sha256:
        raise RuntimeError("source repair chain does not reach current source")
