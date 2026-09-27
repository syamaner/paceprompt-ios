"""Offline verification of the proposed issue #145 full-matrix lineage revision."""

from __future__ import annotations

import asyncio
from pathlib import Path
import tempfile
from typing import Any

from . import issue145
from .v3 import HOST_EVAL_ROOT, safe_run_dir, sha256_file, strict_json_load


PROPOSAL = HOST_EVAL_ROOT / "issue145-full-matrix-lineage-proposal-r1.json"
STANDING_CONTRACT = HOST_EVAL_ROOT / "issue145-standing-restart-and-repair-r1.md"
SELECTED_MANIFEST = HOST_EVAL_ROOT / "issue145-public-catalogue-selected-r1.json"
COST_MANIFEST = HOST_EVAL_ROOT / "issue145-public-cost-preflight-r1.json"
PROPOSAL_SHA256 = "0fdef98aed0fcedae57d5aa09a6e050385743934cc25136d03b777af5e5f7906"


def verify() -> dict[str, Any]:
    """Check the additive proposal without consulting a key or provider."""
    errors: list[str] = []
    base = issue145.verify()
    if base["status"] != "valid":
        errors.append("sealed v5 base verification failed")
    proposal = strict_json_load(PROPOSAL)
    if sha256_file(PROPOSAL) != PROPOSAL_SHA256:
        errors.append("versioned proposal bytes changed")
    if set(proposal) != {
        "proposalVersion", "status", "purpose", "baseProfile", "proposedDelta",
        "unchangedV5Execution", "publicCataloguePreparation",
        "unresolvedBeforeLive", "authority",
    } or proposal.get("purpose") != "versioned manual-continuation profile for the issue145 full matrix":
        errors.append("proposal has an unknown or conflicting top-level field")
    policy = strict_json_load(issue145.RUN_POLICY)
    source = proposal.get("baseProfile", {})
    expected_source = {
        "runPolicyV5Sha256": sha256_file(issue145.RUN_POLICY),
        "modelsV5Sha256": sha256_file(issue145.MODELS),
        "candidateReviewSha256": sha256_file(issue145.CANDIDATE_REVIEW),
        "candidateRatificationSha256": sha256_file(issue145.RATIFICATION),
        "queueSha256": issue145.queue_document()["queueSha256"],
        "standingRestartContractSha256": sha256_file(STANDING_CONTRACT),
    }
    if source != expected_source:
        errors.append("proposal does not bind the exact sealed v5 and standing contract")
    if proposal.get("proposalVersion") != "paceprompt-host-eval-proposal/issue145-full-matrix-lineage-r1" or proposal.get("status") != "proposed-not-ratified":
        errors.append("proposal revision or status changed")
    if policy["execution"]["resumable"] is not False:
        errors.append("sealed v5 must remain non-resumable")
    if proposal.get("proposedDelta") != {
        "onlyChangedV5ExecutionField": "resumable",
        "resumable": True,
        "restartMode": "manual-verified-descendants-only",
        "lineageDepthLimit": None,
        "automaticRetryOrFallback": False,
        "startedPositionReplay": False,
        "terminalScoredResultReplacement": False,
        "cumulativeHardLimitAcrossDescendants": True,
        "unknownCallCost": "charge-conservative-reserved-worst-case",
        "parentEvidence": "verify-complete-immutable-ancestry-before-child-admission",
        "sourceRepairs": "only-separately-reviewed-compatible-HostEval-changes",
    }:
        errors.append("proposal changes the approved manual-continuation semantics")
    execution = policy["execution"]
    expected_execution = {
        "models": len(policy["execution"]["modelOrder"]),
        "scoredStrata": len(policy["dataset"]["scoredStrata"]),
        "distinctCases": policy["dataset"]["totalDistinctScoredCases"],
        "requestedRepetitionsPerStratum": execution["requestedRepetitionsPerStratum"],
        "scoredAttempts": execution["scoredAttempts"],
        "warmups": execution["warmups"],
        "totalProviderCalls": execution["totalProviderCalls"],
        "globalConcurrency": execution["globalConcurrency"],
        "minimumInterCallDelaySeconds": execution["minimumInterCallDelaySeconds"],
        "automaticRetries": execution["automaticRetries"],
        "httpConnectRetries": execution["httpConnectRetries"],
        "maxOutputTokens": policy["generation"]["maxOutputTokens"],
    }
    if proposal.get("unchangedV5Execution") != expected_execution:
        errors.append("proposal execution controls differ from sealed v5")
    if proposal.get("unresolvedBeforeLive") != {
        "replacementRouteCompatibilityProof": None,
        "rootRunID": None,
        "finiteLineageHardLimitUSD": None,
        "exactVersionedProfileRatification": None,
        "initialLiveAuthorization": None,
        "reviewedAndBoundRunnerSourceSha256": None,
    }:
        errors.append("proposal incorrectly resolves a live-run prerequisite")
    if proposal.get("authority") != {
        "credentialRead": False,
        "providerInference": False,
        "spend": False,
        "liveRun": False,
        "publishResults": False,
        "productionChange": False,
    }:
        errors.append("proposal grants live or production authority")

    prepared = proposal.get("publicCataloguePreparation", {})
    if prepared != {
        "runID": "issue145-full-matrix-v5-20260923-prep03",
        "catalogueURL": "https://openrouter.ai/api/v1/models",
        "localSnapshotRecordedAtUTC": "2026-09-23T07:04:31Z",
        "modelsResponseSha256": "ec0f7b08f25342d0da06317fbde112c3ccacb01c88eea57e076ab579628d2c04",
        "selectedSha256": "5f6cb4a54fb5aef0a16c4fe0eb8e3321449a5be08df42097c10c5edcf360a0bc",
        "costManifestSha256": "1b3b6fe731d8f063761ecf55e3a6340347aa212501cfd15295045b3d83b688b7",
        "conservativeWorstCaseUSD": "98.742225560",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
    }:
        errors.append("public-catalogue preparation record changed")
    selected = strict_json_load(SELECTED_MANIFEST)
    cost_manifest = strict_json_load(COST_MANIFEST)
    if (
        sha256_file(SELECTED_MANIFEST) != prepared.get("selectedSha256")
        or selected.get("modelsURL") != prepared.get("catalogueURL")
        or selected.get("modelsSha256") != prepared.get("modelsResponseSha256")
        or sha256_file(COST_MANIFEST) != prepared.get("costManifestSha256")
    ):
        errors.append("committed public-catalogue manifest differs from proposal")
    with tempfile.TemporaryDirectory(prefix="paceprompt-issue145-public-cost-") as directory:
        mocks, templates = asyncio.run(
            issue145.mock_payloads(Path(directory), selected)
        )
        recomputed = issue145.cost_preflight(selected, templates)
    if (
        mocks.get("providerCalls") != 0
        or mocks.get("credentialRead") is not False
        or recomputed != cost_manifest
        or recomputed.get("estimatedUSD") != prepared.get("conservativeWorstCaseUSD")
    ):
        errors.append("committed public-catalogue cost cannot be reproduced offline")
    prepared_run_id = prepared.get("runID")
    local_preparation = "notPresentInCheckout"
    if isinstance(prepared_run_id, str):
        try:
            run_dir = safe_run_dir(prepared_run_id, create=False)
        except (FileNotFoundError, ValueError):
            run_dir = None
        if run_dir is not None and (run_dir / "operator-gate.json").is_file():
            gate = strict_json_load(run_dir / "operator-gate.json")
            local_selected = run_dir / "catalogue" / "selected.json"
            if (
                gate.get("providerCalls") != 0
                or gate.get("credentialRead") is not False
                or gate.get("authorizationPhrase") is not None
                or gate.get("catalogueSnapshotSha256") != prepared.get("selectedSha256")
                or sha256_file(local_selected) != prepared.get("selectedSha256")
                or gate.get("costPreflight") != cost_manifest
                or gate.get("costPreflight", {}).get("admitted") is not False
                or gate.get("queueSha256") != expected_source["queueSha256"]
            ):
                errors.append("local public-catalogue preparation differs from proposal")
            else:
                local_preparation = "exactLocalZeroSpendEvidence"
    else:
        errors.append("proposal lacks a prepared public-catalogue run ID")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "proposalSha256": sha256_file(PROPOSAL),
        "localPreparation": local_preparation,
        "liveAuthorized": False,
    }
