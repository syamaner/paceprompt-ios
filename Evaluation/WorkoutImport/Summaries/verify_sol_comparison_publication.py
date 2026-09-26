"""Verify the bounded GPT-5.6 Sol versus GPT-6 Sol aggregate publication."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


BASE = Path(__file__).resolve().parent
MANIFEST = "issue145-sol56-vs-sol6-publication-manifest.json"
DATA = "issue145-sol56-vs-sol6-2026-09-22-data.json"
AUDIT = "issue145-sol56-vs-sol6-2026-09-22-evidence-integrity.json"
REPORT = "issue145-sol56-vs-sol6-2026-09-22.md"
EXPECTED_MANIFEST_SHA256 = "02b5c4e236a6192d15597b3eba3bd85b3738fc2fb1db0403a80cdc38fa5b0717"
SENSITIVE = (b"OPENROUTER_API_KEY", b"Bearer ", b"sk-or-", b"AUTHORIZE_PACEPROMPT")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} is not a JSON object")
    return value


def verify(base: Path = BASE, *, enforce_manifest_hash: bool = True) -> dict[str, Any]:
    errors: list[str] = []
    manifest_path = base / MANIFEST
    if enforce_manifest_hash and _sha256(manifest_path) != EXPECTED_MANIFEST_SHA256:
        errors.append("publication manifest hash changed")
    manifest = _json(manifest_path)
    if (
        manifest.get("manifestContractVersion")
        != "paceprompt-workout-import-publication/sol56-vs-sol6-r1"
        or manifest.get("runID") != "sol56-vs-sol6-20260922-01"
        or manifest.get("status") != "publishedAggregateEvidence"
    ):
        errors.append("publication identity changed")
    if manifest.get("ratifiedPreparedGateSha256") != (
        "af29772865b901d272e71c281b49543d05bc15f08216c3b6e63cd091e0548f01"
    ):
        errors.append("ratified prepared gate changed")
    if manifest.get("queueSha256") != (
        "d3627835682b17517637caf5a792b45dbbf6e3e45f6d524c72ceb05caa94d51e"
    ):
        errors.append("comparison queue changed")

    protected = manifest.get("protectedHistoricalArtifacts", {})
    for name, expected in protected.items():
        if _sha256(base / name) != expected:
            errors.append(f"protected artifact changed: {name}")
    published = manifest.get("proposedAggregateArtifacts", {})
    if set(published) != {DATA, AUDIT, REPORT}:
        errors.append("publication artifact set changed")
    for name, expected in published.items():
        path = base / name
        if _sha256(path) != expected:
            errors.append(f"aggregate artifact changed: {name}")
        if any(marker in path.read_bytes() for marker in SENSITIVE):
            errors.append(f"sensitive marker in aggregate artifact: {name}")

    audit = _json(base / AUDIT)
    if (
        audit.get("passed") is not True or audit.get("errors") != []
        or audit.get("providerDecision") != "requiresHumanRatification"
    ):
        errors.append("mechanical evidence audit is not passing")
    report = _json(base / DATA)
    if (
        report.get("reportContractVersion") != "paceprompt-host-eval-report/sol-comparison-v1"
        or report.get("runID") != manifest.get("runID")
        or report.get("automaticWinner") is not None
        or set(report.get("strata", {}))
        != {"v3-heldout-regression", "issue130-acceptance-r2"}
    ):
        errors.append("aggregate comparison identity changed")
    else:
        for stratum, expected in (("v3-heldout-regression", 79), ("issue130-acceptance-r2", 30)):
            data = report["strata"][stratum]
            models = data.get("models", {})
            if set(models) != {"openai/gpt-5.6-sol", "openai/gpt-6-sol"}:
                errors.append(f"model set changed: {stratum}")
                continue
            for model in models.values():
                if (
                    model.get("scheduledAttempts") != expected
                    or model.get("preservedAttempts") != expected
                    or model.get("schemaValidResponses") != expected
                    or model.get("decisionEligible") is not False
                ):
                    errors.append(f"denominator, schema or gate changed: {stratum}")
            if data.get("automaticWinner") is not None or data.get("eligibleModels") != []:
                errors.append(f"automatic winner appeared: {stratum}")
    boundary = manifest.get("decisionBoundary", {})
    if (
        boundary.get("automaticWinner") is not None
        or boundary.get("evidenceAcceptedByOperator") is not True
        or boundary.get("humanChoiceForSeparateReviewedChange") != "openai/gpt-6-sol"
        or boundary.get("onePassAndUnchangedGateFailuresDisclosed") is not True
        or boundary.get("productionChanged") is not False
        or boundary.get("rawRunPublished") is not False
        or boundary.get("issueClosureAuthorized") is not False
    ):
        errors.append("human decision boundary changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "manifestSha256": _sha256(manifest_path),
        "aggregateArtifactCount": len(published),
        "protectedArtifactCount": len(protected),
    }


if __name__ == "__main__":
    result = verify()
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0 if result["status"] == "valid" else 1)
