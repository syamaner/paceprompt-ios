"""Additive, zero-spend eleven-model profile after the accepted DeepSeek probe.

This is a proposal, not a live gate. It binds the immutable earlier proposal
and terminal route evidence while leaving the cap and live authority unset.
"""

from __future__ import annotations

from collections import Counter
from decimal import Decimal
from typing import Any

from .issue145_deepseek_11_r2 import MATRIX_RUN_ID as PARENT_RUN_ID
from .issue145_deepseek_probe_gate import _inspect_success, _ratified
from .issue145_retry_execution import evidence_tree_sha256, verify_wire_ledger
from .runner import write_json
from .v3 import (
    RUNS_ROOT, canonical_hash, host_source_tree_hash, safe_run_dir,
    sha256_file, strict_json_load,
)


PARENT_PROPOSAL_SHA256 = "f1f51e8d37c5d6859f23bb233c7c389e1497ed2db42445a6c5f75918b95aa439"
PARENT_EVIDENCE_SHA256 = "316123933703743c4a85f147517ed5c01fab1718c503712b30933f05131c2a9c"
PROBE_RUN_ID = "issue145-deepseek-route-probe-20260924-01"
PROBE_EVIDENCE_SHA256 = "36ea9800fe11c853551cfdf962e9750a6c5ab0026e15b336f26f9d7d13a38681"
PROBE_PREAUDIT_SHA256 = "7828ed9fa049751cd89e1a873706fcdee07021f8471371bebd3b47330c39c8df"
PROBE_GATE_SHA256 = "ab200a0b81430f57df840c497f4e2d70f83ed6124a0a793c3fe5291402ad1fa6"
PROPOSAL_RUN_ID = "issue145-11model-profile-r3-20260925-02"
PROPOSED_ROOT_RUN_ID = "issue145-11model-matrix-20260925-01"
SUPERSEDED_DRAFT_EVIDENCE_SHA256 = "790a60cfa348499ce0c67f7a44df76770055658c2b5b40ae62fe7fb35a0d53c2"
EXPECTED_QUEUE_SHA256 = "1c0d4ce6c43c40919afc8ac7d420403bc18f67773bcf355b9c93439f0a76ea05"
RECOMMENDED_CAP_USD = "300.00"
LOGICAL_ID = "warmup-deepseek--deepseek-v4-flash-0731"


def _parent() -> tuple[dict[str, Any], dict[str, Any]]:
    run_dir = safe_run_dir(PARENT_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PARENT_EVIDENCE_SHA256:
        raise RuntimeError("sealed eleven-model proposal evidence changed")
    proposal = strict_json_load(run_dir / "proposal.json")
    queue = strict_json_load(run_dir / "planned-queue.json")
    if (proposal.get("proposalSha256") != PARENT_PROPOSAL_SHA256
            or canonical_hash({k: v for k, v in proposal.items()
                               if k != "proposalSha256"}) != PARENT_PROPOSAL_SHA256
            or queue.get("queueSha256") != EXPECTED_QUEUE_SHA256
            or proposal.get("queueSha256") != EXPECTED_QUEUE_SHA256
            or proposal.get("deepseekRouteCompatibilityProof") is not None
            or proposal.get("ratifiedHardLimitUSD") is not None
            or proposal.get("liveAuthorized") is not False):
        raise RuntimeError("sealed eleven-model proposal changed")
    counts = Counter(item["modelID"] for item in queue["entries"])
    if (len(queue["entries"]) != 3597 or len(counts) != 11
            or set(counts.values()) != {327}
            or set(counts) != set(proposal["candidateModelIDs"])):
        raise RuntimeError("sealed eleven-model queue changed")
    return proposal, queue


def _probe_outcome_valid(
    *, audit: dict[str, Any], report: dict[str, Any],
    state: dict[str, Any], ledger: dict[str, Any],
    checked: dict[str, Any], result: dict[str, Any], model_id: str,
) -> bool:
    positions = ledger.get("positions")
    if not isinstance(positions, list) or len(positions) != 1:
        return False
    wires = positions[0].get("wires")
    return (
        checked.get("status") == "valid"
        and audit == {"runID": PROBE_RUN_ID,
                      "evidenceTreeSha256BeforeAudit": PROBE_PREAUDIT_SHA256,
                      "status": "requiresSeparateExactEvidenceReview"}
        and report.get("result") == {"logicalID": LOGICAL_ID,
                                      "modelID": model_id,
                                      "state": "terminalComplete", **result}
        and result == {"compatibilityPassed": True,
                       "reason": "native and host schema valid"}
        and report.get("scoredHeldoutCalls") == 0
        and report.get("chargedWorstCaseUSD") == "0.00305826"
        and state.get("status") == "completeAwaitingHumanEvidenceAcceptance"
        and ledger.get("chargedUSD") == "0.00305826"
        and isinstance(wires, list) and len(wires) == 1
        and wires[0].get("statusCode") == 200
        and wires[0].get("state") == "completeHTTPResponse"
        and wires[0].get("retryDecision", {}).get("retry") is False
    )


def _accepted_probe() -> dict[str, Any]:
    run_dir = safe_run_dir(PROBE_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PROBE_EVIDENCE_SHA256:
        raise RuntimeError("accepted DeepSeek probe evidence changed")
    gate_path = run_dir / "operator-gate.json"
    if sha256_file(gate_path) != PROBE_GATE_SHA256:
        raise RuntimeError("accepted DeepSeek probe gate changed")
    gate = strict_json_load(gate_path)
    audit = strict_json_load(run_dir / "evidence-integrity-audit.json")
    report = strict_json_load(run_dir / "diagnostic-report.json")
    state = strict_json_load(run_dir / "live-state.json")
    ledger = strict_json_load(run_dir / "wire-ledger.json")
    checked = verify_wire_ledger(
        run_dir, evidence_root=RUNS_ROOT,
        profile_sha256=gate["profileSha256"],
        planned_position_ids=(LOGICAL_ID,),
        hard_limit_usd=gate["hardLimitUSD"],
        sealed_evidence_tree_sha256=PROBE_EVIDENCE_SHA256,
    )
    _, request, spec = _ratified()
    positions = ledger.get("positions")
    if not isinstance(positions, list) or len(positions) != 1:
        raise RuntimeError("accepted DeepSeek probe position count changed")
    result = _inspect_success(run_dir, positions[0], spec, request)
    if not _probe_outcome_valid(
        audit=audit, report=report, state=state, ledger=ledger,
        checked=checked, result=result, model_id=spec.requested_model_id,
    ):
        raise RuntimeError("accepted DeepSeek probe outcome changed")
    return {
        "runID": PROBE_RUN_ID,
        "evidenceTreeSha256": PROBE_EVIDENCE_SHA256,
        "gateSha256": PROBE_GATE_SHA256,
        "route": "deepinfra/fp8",
        "compatibility": "native-and-host-schema-valid",
        "physicalSends": 1,
        "scoredHeldoutCalls": 0,
        "conservativeChargedUSD": "0.00305826",
        "humanEvidenceAcceptance": "issue145-comment-5828778749",
    }


def profile_material() -> tuple[dict[str, Any], dict[str, Any]]:
    parent, queue = _parent()
    accepted = _accepted_probe()
    bound = Decimal(parent["threeSendConservativeUSDFromSavedCatalogue"])
    if (not bound.is_finite() or bound <= 0
            or bound >= Decimal(RECOMMENDED_CAP_USD)):
        raise RuntimeError("saved-catalogue conservative bound exceeds proposed cap")
    profile = {
        "profileVersion": "paceprompt-host-eval-profile/issue145-post-deepseek-11-r3",
        "status": "proposed-awaiting-fresh-catalogue-ratification-and-reviewed-live-runner",
        "proposalRunID": PROPOSAL_RUN_ID,
        "proposedRootRunID": PROPOSED_ROOT_RUN_ID,
        "supersededLocalDraftEvidenceSha256": SUPERSEDED_DRAFT_EVIDENCE_SHA256,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "parentProposalSha256": PARENT_PROPOSAL_SHA256,
        "parentEvidenceTreeSha256": PARENT_EVIDENCE_SHA256,
        "acceptedDeepseekProbe": accepted,
        "candidateModelIDs": parent["candidateModelIDs"],
        "candidateRoutes": parent["candidateRoutes"],
        "excludedCandidate": parent["excludedCandidate"],
        "queueSha256": EXPECTED_QUEUE_SHA256,
        "scoredLogicalPositions": 3597,
        "warmupLogicalPositions": 11,
        "maximumPhysicalSends": 10824,
        "stratumScoredPositions": parent["stratumScoredPositions"],
        "threeSendConservativeUSDFromSavedCatalogue": format(bound, "f"),
        "recommendedCumulativeHardLimitUSD": RECOMMENDED_CAP_USD,
        "ratifiedCumulativeHardLimitUSD": None,
        "freshPublicCatalogueRequiredBeforeCredentialRead": True,
        "reviewedLiveRunnerSha256": None,
        "initialLiveAuthorization": None,
        "credentialRead": False,
        "providerCalls": 0,
        "spendUSD": "0.00",
        "liveAuthorized": False,
    }
    return profile, queue


def prepare_profile(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("proposal run ID changed")
    profile, queue = profile_material()
    run_dir = safe_run_dir(run_id, create=True)
    if any(run_dir.iterdir()):
        raise RuntimeError("additive profile directory is not fresh")
    profile["profileSha256"] = canonical_hash(profile)
    write_json(run_dir / "planned-queue.json", queue)
    write_json(run_dir / "profile.json", profile)
    return verify_prepared_profile(run_id)


def verify_prepared_profile(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("proposal run ID changed")
    expected, queue = profile_material()
    expected["profileSha256"] = canonical_hash(expected)
    run_dir = safe_run_dir(run_id, create=False)
    errors = []
    if (strict_json_load(run_dir / "profile.json") != expected
            or strict_json_load(run_dir / "planned-queue.json") != queue):
        errors.append("prepared profile or queue changed")
    return {
        "status": "valid" if not errors else "invalid", "errors": errors,
        "profileSha256": expected["profileSha256"],
        "queueSha256": queue["queueSha256"],
        "evidenceTreeSha256": evidence_tree_sha256(run_dir),
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }
