"""Fail-closed verifier for the versioned issue #145 Stage A publication."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


BASE = Path(__file__).resolve().parent
MANIFEST = "issue145-stage-a-publication-manifest.json"
EXPECTED_MANIFEST_SHA256 = (
    "ac9350f3a2876a387548d44931922f197f937f23692ed1e1111b5594786e514b"
)
EXPECTED_IDENTITY = {
    "manifestContractVersion": "paceprompt-workout-import-publication/issue145-stage-a-r1",
    "runID": "issue145-top4-stage-a-v5-20260920-01",
    "proposalSha256": "9ac554267bb052220f628a8ae97124b135afb6a94d188416df03a1ad92e7bd1f",
    "queueSha256": "1d99300cffea87bd01eb081131e877032e169601c7db7b0ed2b5ff04ded52f3d",
    "hostSourceTreeSha256": "99ed167b4116c131719ce39380d3c34fe0f69174a75a93b67e510cca8d538560",
    "liveStateSha256": "1ce813c83c6461fd4614681c3393933eba17bfacc7ee324a84371cabb4d995b1",
    "operatorRatificationSha256": "73fdd28d56e8b9914512f19cc7d1dc5946b90d90e13c1bcf4f1eab670a1cc130",
    "liveCatalogueSelectionSha256": "c58585b82693b44007cc3d6a439b5b1df4b955f41f7d7abd73a7c8db49b00949",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return value


def verify(base: Path = BASE) -> dict[str, Any]:
    errors: list[str] = []
    manifest_path = base / MANIFEST
    if _sha256(manifest_path) != EXPECTED_MANIFEST_SHA256:
        errors.append("publication manifest hash changed")
    manifest = _json(manifest_path)
    identity = {
        "manifestContractVersion": manifest.get("manifestContractVersion"),
        "runID": manifest.get("runID"),
        **manifest.get("profile", {}),
        **manifest.get("ignoredRunProvenance", {}),
    }
    if identity != EXPECTED_IDENTITY:
        errors.append("run, profile, queue, source or ignored provenance identity changed")

    published = manifest.get("publishedArtifacts")
    if not isinstance(published, dict) or set(published) != {
        "issue145-stage-a-2026-09-20.md",
        "issue145-stage-a-data.json",
        "issue145-stage-a-evidence-integrity.json",
    }:
        errors.append("published artifact set changed")
    else:
        for name, expected_hash in published.items():
            if _sha256(base / name) != expected_hash:
                errors.append(f"published artifact hash changed: {name}")

    aggregate = _json(base / "issue145-stage-a-data.json")
    if (
        aggregate.get("reportContractVersion")
        != "paceprompt-host-eval-report/issue145-v5-stage-a"
        or aggregate.get("stage") != "A"
        or aggregate.get("automaticContinuation") is not False
        or aggregate.get("automaticWinner") is not None
        or aggregate.get("providerDecision")
        != "requiresSeparateHumanRatification"
    ):
        errors.append("published aggregate decision boundary changed")

    audit = _json(base / "issue145-stage-a-evidence-integrity.json")
    if (
        audit.get("auditContractVersion")
        != "paceprompt-host-eval-evidence-integrity/issue145-v5-stage-a"
        or audit.get("passed") is not True
        or audit.get("errors") != []
        or audit.get("providerDecision") != "requiresHumanRatification"
    ):
        errors.append("published evidence audit changed")

    correction = manifest.get("preservedOperatorRecordCorrection", {})
    if correction != {
        "field": "liveCostPreflight",
        "recordedHardLimitUSD": None,
        "recordedAdmitted": False,
        "estimatedUSD": "24.65417240",
        "ratifiedHardLimitUSD": "24.65417240",
        "effectiveAdmission": True,
        "reason": "The live gate compared the current estimate with the exact ratified limit before credential access; the ignored record preserved the generic estimator shape.",
    }:
        errors.append("preserved operator-record correction changed")

    report = (base / "issue145-stage-a-2026-09-20.md").read_text(encoding="utf-8")
    for key, value in EXPECTED_IDENTITY.items():
        if key == "manifestContractVersion":
            continue
        if value not in report:
            errors.append(f"human report omits bound identity: {value}")

    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "manifestSha256": _sha256(manifest_path),
        "publishedArtifactCount": len(published) if isinstance(published, dict) else 0,
    }


if __name__ == "__main__":
    result = verify()
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0 if result["status"] == "valid" else 1)
