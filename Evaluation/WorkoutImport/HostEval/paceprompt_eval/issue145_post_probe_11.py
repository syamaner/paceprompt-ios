"""Zero-spend, additive eleven-candidate proposal after the accepted r3 probe.

This prepares a proposed queue and cost bound; it cannot read credentials,
run a warm-up, or authorise the existing twelve-model lineage to change.
"""

from __future__ import annotations

from collections import Counter
from decimal import Decimal
from typing import Any

from .issue145 import cost_preflight, queue_document
from .issue145_full_matrix_r3 import RATIFICATION, verify_ratification
from .issue145_retry_execution import evidence_tree_sha256, verify_wire_ledger
from .runner import write_json
from .v3 import (
    RUNS_ROOT, canonical_hash, host_source_tree_hash, safe_run_dir,
    sha256_file, strict_json_load,
)


EXCLUDED_MODEL = "mistralai/mistral-small-2603"
ACCEPTED_RUN_ID = "issue145-r3-route-probes-20260924-02"
ACCEPTED_EVIDENCE_SHA256 = "df6667cf586a6bc621aa7036961ad5bbd11a3a615fd6bcc741606862d44890cc"
ACCEPTED_GATE_SHA256 = "930ac708786ab8c0991ef8bd5191280e627246c24578078d859931106968c147"
PROPOSAL_RUN_ID = "issue145-11model-proposal-20260924-01"


def _accepted_probe() -> dict[str, Any]:
    run_dir = safe_run_dir(ACCEPTED_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != ACCEPTED_EVIDENCE_SHA256:
        raise RuntimeError("accepted r3 probe evidence changed")
    gate = strict_json_load(run_dir / "operator-gate.json")
    ledger = strict_json_load(run_dir / "wire-ledger.json")
    report = strict_json_load(run_dir / "diagnostic-report.json")
    state = strict_json_load(run_dir / "live-state.json")
    if sha256_file(run_dir / "operator-gate.json") != ACCEPTED_GATE_SHA256:
        raise RuntimeError("accepted r3 probe gate changed")
    checked = verify_wire_ledger(
        run_dir, evidence_root=RUNS_ROOT,
        profile_sha256=gate["proposalSha256"],
        planned_position_ids=tuple(call["logicalID"] for call in gate["orderedCalls"]),
        hard_limit_usd=gate["hardLimitUSD"],
        sealed_evidence_tree_sha256=ACCEPTED_EVIDENCE_SHA256,
    )
    expected_results = [
        {"logicalID": "warmup-mistralai--mistral-small-2603",
         "modelID": EXCLUDED_MODEL, "state": "terminalFailure",
         "compatibilityPassed": False, "reason": "terminalFailure"},
        {"logicalID": "warmup-deepseek--deepseek-v4-flash-0731",
         "modelID": "deepseek/deepseek-v4-flash-0731", "state": "notStarted",
         "compatibilityPassed": False, "reason": "earlier route warm-up failed"},
    ]
    wires = ledger["positions"][0]["wires"]
    upstream = [strict_json_load(
        run_dir / "wire-evidence" / f"{wire['wireID']}.json"
    ).get("body", {}).get("error", {}).get("metadata", {}).get("limit_source")
                for wire in wires]
    if (checked["status"] != "valid" or report.get("results") != expected_results
            or report.get("scoredHeldoutCalls") != 0
            or report.get("chargedWorstCaseUSD") != "0.02660040"
            or state.get("status") != "completeAwaitingHumanEvidenceAcceptance"
            or ledger.get("chargedUSD") != "0.02660040"
            or len(ledger["positions"]) != 1 or len(wires) != 3
            or [wire.get("statusCode") for wire in wires] != [429, 429, 429]
            or upstream != ["upstream_provider_shared_pool"] * 3
            or [wire.get("retryDecision", {}).get("waitSeconds") for wire in wires]
               != [30, 120, None]
            or any(wire.get("state") != "completeHTTPResponse" for wire in wires)):
        raise RuntimeError("accepted r3 probe outcome differs from terminal evidence")
    return {"runID": ACCEPTED_RUN_ID,
            "evidenceTreeSha256": ACCEPTED_EVIDENCE_SHA256,
            "sealedGateSha256": ACCEPTED_GATE_SHA256,
            "mistralRouteOutcome": "upstream-shared-pool-429-exhausted",
            "deepseekRouteOutcome": "notStarted",
            "scoredHeldoutCalls": 0,
            "conservativeChargedUSD": "0.02660040",
            "actualProviderBillingUSD": None}


def _filtered_queue() -> dict[str, Any]:
    original = queue_document()
    entries: list[dict[str, Any]] = []
    positions: dict[tuple[str, int, str], int] = {}
    for entry in original["entries"]:
        if entry["modelID"] == EXCLUDED_MODEL:
            continue
        key = (entry["stratumID"], entry["repetitionIndex"], entry["caseID"])
        position = positions.get(key, 0) + 1
        positions[key] = position
        entries.append(dict(entry, modelPosition=position))
    model_counts = Counter(item["modelID"] for item in entries)
    stratum_counts = Counter(item["stratumID"] for item in entries)
    if (len(entries) != 3597 or len(model_counts) != 11
            or set(model_counts.values()) != {327}
            or stratum_counts != {"v3-heldout-regression": 2607,
                                  "issue130-acceptance-r2": 990}
            or len(positions) != 327 or set(positions.values()) != {11}):
        raise RuntimeError("eleven-model queue mapping is invalid")
    material = {
        "queueContractVersion": "paceprompt-host-eval-queue/issue145-post-probe-11-r1",
        "parentQueueSha256": original["queueSha256"],
        "derivation": "filter-mistral-then-renumber-model-position-per-case-and-repetition",
        "entries": entries,
    }
    return dict(material, queueSha256=canonical_hash(material))


def proposal_material() -> tuple[dict[str, Any], dict[str, Any]]:
    ratified = verify_ratification(require_prepared_evidence=True)
    if ratified["status"] != "valid":
        raise RuntimeError("sealed twelve-model r3 parent is invalid")
    accepted = _accepted_probe()
    parent = strict_json_load(RATIFICATION)
    parent_dir = safe_run_dir(parent["preparedRunID"], create=False)
    models = strict_json_load(parent_dir / "models-r3-materialized.json")
    selected = strict_json_load(parent_dir / "catalogue" / "selected.json")
    templates = {
        model["requestedModelID"]: strict_json_load(
            parent_dir / "mock-payloads"
            / f"{model['requestedModelID'].replace('/', '--')}.json"
        )["body"] for model in models["models"]
    }
    cost = cost_preflight(
        selected, templates,
        models_path=parent_dir / "models-r3-materialized.json",
    )
    remaining = Decimal(cost["estimatedUSD"]) - Decimal(
        cost["perModelEstimatedUSD"][EXCLUDED_MODEL]
    )
    if (len(models["models"]) != 12
            or len(selected["selected"]) != 12
            or remaining != Decimal("95.838047360")):
        raise RuntimeError("saved twelve-model cost evidence changed")
    candidate_ids = [model["requestedModelID"] for model in models["models"]
                     if model["requestedModelID"] != EXCLUDED_MODEL]
    candidate_routes = [
        {key: model[key] for key in (
            "requestedModelID", "canonicalRevision", "providerEndpoint",
            "quantization", "responseContract", "maxOutputTokens",
        )}
        for model in models["models"] if model["requestedModelID"] != EXCLUDED_MODEL
    ]
    queue = _filtered_queue()
    proposal = {
        "proposalVersion": "paceprompt-host-eval-proposal/issue145-post-probe-11-r1",
        "status": "awaiting-exact-profile-cap-and-live-ratification",
        "runID": PROPOSAL_RUN_ID,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "parentTwelveModelProfileSha256": parent["profileSha256"],
        "parentQueueSha256": parent["queueSha256"],
        "acceptedProbe": accepted,
        "excludedCandidate": {"requestedModelID": EXCLUDED_MODEL,
                              "disposition": "route-unavailable-not-scored",
                              "reason": "upstream-shared-pool-429-exhausted"},
        "candidateModelIDs": candidate_ids,
        "candidateRoutes": candidate_routes,
        "queueSha256": queue["queueSha256"],
        "scoredLogicalPositions": 3597,
        "warmupLogicalPositions": 11,
        "maximumPhysicalSends": 10824,
        "stratumScoredPositions": {"v3-heldout-regression": 2607,
                                   "issue130-acceptance-r2": 990},
        "oneSendConservativeUSDFromSavedCatalogue": format(remaining, "f"),
        "threeSendConservativeUSDFromSavedCatalogue": format(remaining * 3, "f"),
        "freshPublicCatalogueRequiredBeforeLive": True,
        "deepseekRouteCompatibilityProof": None,
        "hardLimitUSD": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }
    return proposal, queue


def prepare_proposal(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("eleven-model proposal run ID changed")
    proposal, queue = proposal_material()
    run_dir = safe_run_dir(run_id, create=True)
    if any(run_dir.iterdir()):
        raise RuntimeError("eleven-model proposal directory is not fresh")
    proposal["proposalSha256"] = canonical_hash(proposal)
    write_json(run_dir / "planned-queue.json", queue)
    write_json(run_dir / "proposal.json", proposal)
    return proposal


def verify_prepared_proposal(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("eleven-model proposal run ID changed")
    expected, queue = proposal_material()
    expected["proposalSha256"] = canonical_hash(expected)
    run_dir = safe_run_dir(run_id, create=False)
    errors = []
    if (strict_json_load(run_dir / "proposal.json") != expected
            or strict_json_load(run_dir / "planned-queue.json") != queue):
        errors.append("eleven-model proposal or queue changed")
    return {"status": "valid" if not errors else "invalid", "errors": errors,
            "proposalSha256": expected["proposalSha256"],
            "queueSha256": queue["queueSha256"],
            "evidenceTreeSha256": evidence_tree_sha256(run_dir),
            "liveAuthorized": False}
