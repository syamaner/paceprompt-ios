"""Fail-closed verifier for the issue #145 Stage A+B publication."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


BASE = Path(__file__).resolve().parent
HOST_EVAL = BASE.parent / "HostEval"
MANIFEST = "issue145-stage-a-b-publication-manifest.json"
EXPECTED_MANIFEST_SHA256 = (
    "b89651c63c80904644d64e552e8b80073a726934aafcc9e55bf3c609df739f1a"
)
EXPECTED_MODELS = [
    "openai/gpt-5.6-sol",
    "qwen/qwen3.8-27b",
    "openai/gpt-5.6-luna",
]
EXPECTED_EXACT_ATTEMPTS = {
    "openai/gpt-5.6-luna": 271,
    "openai/gpt-5.6-sol": 311,
    "qwen/qwen3.8-27b": 290,
}
SENSITIVE_MARKERS = (
    b"OPENROUTER_API_KEY",
    b"Bearer ",
    b"sk-or-",
    b"AUTHORIZE_PACEPROMPT",
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return value


def verify(
    base: Path = BASE, host_eval: Path = HOST_EVAL, *, enforce_manifest_hash: bool = True
) -> dict[str, Any]:
    errors: list[str] = []
    manifest_path = base / MANIFEST
    if enforce_manifest_hash and _sha256(manifest_path) != EXPECTED_MANIFEST_SHA256:
        errors.append("publication manifest hash changed")
    manifest = _json(manifest_path)

    if (
        manifest.get("manifestContractVersion")
        != "paceprompt-workout-import-publication/issue145-stage-a-b-r1"
        or manifest.get("status") != "publishedAggregateEvidence"
    ):
        errors.append("publication identity changed")

    proposal_ref = manifest.get("proposal", {})
    ratification_ref = manifest.get("ratification", {})
    proposal_path = host_eval / "issue145-stage-a-b-publication-proposal-r1.json"
    ratification_path = (
        host_eval / "issue145-stage-a-b-publication-ratification-r1.json"
    )
    if proposal_ref.get("sha256") != _sha256(proposal_path):
        errors.append("ratified proposal hash changed")
    if ratification_ref.get("sha256") != _sha256(ratification_path):
        errors.append("publication ratification hash changed")

    proposal = _json(proposal_path)
    ratification = _json(ratification_path)
    if proposal.get("status") != "awaitingOperatorRatification":
        errors.append("ratified proposal status was rewritten")
    expected_ratification_authority = {
        "boundedPublicationImplementation": True,
        "exactHeadReview": True,
        "rawRunEvidencePublication": False,
        "modelSelection": False,
        "scorerOrGateRelaxation": False,
        "productionChange": False,
        "merge": False,
        "issueClosure": False,
    }
    if (
        ratification.get("ratifiedProposalSha256")
        != "bbef325cd88faac72424b647b692a1217989f4f09c2db80bc1345bb7db1ad3c4"
        or ratification.get("authority") != expected_ratification_authority
    ):
        errors.append("publication authority changed")

    protected = {}
    for key in ("protectedExistingArtifacts", "protectedHistoricalArtifacts"):
        values = manifest.get(key)
        if not isinstance(values, dict):
            errors.append(f"{key} is missing")
            continue
        protected.update(values)
    for name, expected_hash in protected.items():
        if _sha256(base / name) != expected_hash:
            errors.append(f"protected publication changed: {name}")

    published = manifest.get("publishedArtifacts")
    if not isinstance(published, dict) or set(published) != {
        "issue145-stage-a-b-comparison-data.json",
        "issue145-stage-b-and-comparison-2026-09-22.md",
        "issue145-stage-b-data.json",
        "issue145-stage-b-evidence-integrity.json",
    }:
        errors.append("published artifact set changed")
        published = {}
    for name, expected_hash in published.items():
        path = base / name
        if _sha256(path) != expected_hash:
            errors.append(f"published artifact hash changed: {name}")
        payload = path.read_bytes()
        for marker in SENSITIVE_MARKERS:
            if marker in payload:
                errors.append(f"published artifact contains sensitive marker: {name}")

    if proposal.get("proposedPublishedArtifacts") != published:
        errors.append("published bytes differ from the ratified proposal")

    stage_b = _json(base / "issue145-stage-b-data.json")
    if (
        stage_b.get("reportContractVersion")
        != "paceprompt-host-eval-report/issue145-v5-stage-b"
        or stage_b.get("stage") != "B"
        or stage_b.get("repetitionIndices") != [2, 3]
        or stage_b.get("automaticWinner") is not None
        or stage_b.get("combinedStageAAndBComparison") != "notPerformed"
    ):
        errors.append("Stage B aggregate boundary changed")

    stage_b_audit = _json(base / "issue145-stage-b-evidence-integrity.json")
    if (
        stage_b_audit.get("passed") is not True
        or stage_b_audit.get("errors") != []
        or stage_b_audit.get("providerDecision") != "requiresHumanRatification"
    ):
        errors.append("Stage B evidence audit changed")

    comparison = _json(base / "issue145-stage-a-b-comparison-data.json")
    if (
        comparison.get("comparisonContractVersion")
        != "paceprompt-host-eval-comparison/issue145-v5-stage-a-b-r1"
        or comparison.get("status") != "proposedForHumanRatification"
        or comparison.get("sourceRuns")
        != [
            "issue145-top4-stage-a-v5-20260920-01",
            "issue145-top3-stage-b-v5-20260921-01",
        ]
        or comparison.get("retainedModels") != EXPECTED_MODELS
        or comparison.get("repetitionIndices") != [1, 2, 3]
        or comparison.get("distinctCases") != 109
        or comparison.get("scoredAttempts") != 981
        or comparison.get("strictExactAttemptsByModel") != EXPECTED_EXACT_ATTEMPTS
        or comparison.get("automaticWinner") is not None
        or comparison.get("providerDecision")
        != "requiresSeparateHumanModelSelection"
        or comparison.get("productionChange") is not False
    ):
        errors.append("combined comparison identity or decision boundary changed")

    gate = comparison.get("gateInterpretation", {})
    if (
        gate.get("issue130AcceptanceCapabilityBoundary")
        != "structurally-inapplicable-but-false"
        or gate.get("relaxationApplied") is not False
    ):
        errors.append("capability-gate interpretation changed")
    strata = comparison.get("strata", {})
    if set(strata) != {"v3-heldout-regression", "issue130-acceptance-r2"}:
        errors.append("comparison stratum set changed")
    else:
        for stratum_id, report in strata.items():
            if report.get("eligibleModels") != [] or report.get("automaticWinner") is not None:
                errors.append(f"{stratum_id} unexpectedly selects an eligible model")

    boundary = manifest.get("decisionBoundary", {})
    if boundary != {
        "automaticWinner": None,
        "modelSelected": False,
        "scorerOrGateRelaxed": False,
        "productionChanged": False,
        "mergeAuthorized": False,
        "issueClosureAuthorized": False,
    }:
        errors.append("publication decision boundary changed")

    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "manifestSha256": _sha256(manifest_path),
        "publishedArtifactCount": len(published),
        "protectedArtifactCount": len(protected),
    }


if __name__ == "__main__":
    result = verify()
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0 if result["status"] == "valid" else 1)
