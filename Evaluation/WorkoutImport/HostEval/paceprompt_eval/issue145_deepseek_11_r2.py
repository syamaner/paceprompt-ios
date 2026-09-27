"""Additive, zero-spend DeepSeek probe and eleven-candidate r2 proposals.

These documents are not live gates. In particular, neither a saved catalogue
price nor the operator's lineage ceiling authorises a credential read or send.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from .issue145_post_probe_11 import (
    ACCEPTED_GATE_SHA256, ACCEPTED_RUN_ID, PROPOSAL_RUN_ID as PARENT_RUN_ID,
    _filtered_queue,
)
from .issue145_retry_execution import evidence_tree_sha256
from .runner import write_json
from .v3 import (
    canonical_hash, host_source_tree_hash, safe_run_dir, sha256_file,
    strict_json_load,
)


PARENT_PROPOSAL_SHA256 = "73630d711660c326302c9f860133f36308ca668dff738053ed245b07418ae763"
PARENT_EVIDENCE_SHA256 = "72b2108f74090a33441834f391aeb6a9e3dc49dc24c57945e9a3296c76cac3f6"
DEEPSEEK_MODEL = "deepseek/deepseek-v4-flash-0731"
DEEPSEEK_RUN_ID = "issue145-deepseek-probe-proposal-20260924-03"
MATRIX_RUN_ID = "issue145-11model-proposal-r2-20260924-03"
LINEAGE_CEILING_USD = "300.00"


def _parent() -> tuple[dict[str, Any], dict[str, Any]]:
    run_dir = safe_run_dir(PARENT_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PARENT_EVIDENCE_SHA256:
        raise RuntimeError("sealed eleven-candidate r1 proposal evidence changed")
    proposal = strict_json_load(run_dir / "proposal.json")
    queue = strict_json_load(run_dir / "planned-queue.json")
    if (proposal.get("proposalSha256") != PARENT_PROPOSAL_SHA256
            or canonical_hash({k: v for k, v in proposal.items()
                               if k != "proposalSha256"}) != PARENT_PROPOSAL_SHA256
            or proposal.get("queueSha256") != queue.get("queueSha256")
            or queue != _filtered_queue()
            or proposal.get("deepseekRouteCompatibilityProof") is not None):
        raise RuntimeError("sealed eleven-candidate r1 proposal changed")
    return proposal, queue


def _historical_deepseek_call() -> dict[str, Any]:
    gate_path = safe_run_dir(ACCEPTED_RUN_ID, create=False) / "operator-gate.json"
    if sha256_file(gate_path) != ACCEPTED_GATE_SHA256:
        raise RuntimeError("accepted probe gate bytes changed")
    calls = strict_json_load(gate_path)["orderedCalls"]
    if (len(calls) != 2 or calls[1]["requestedModelID"] != DEEPSEEK_MODEL
            or calls[1]["providerEndpoint"] != "deepinfra/fp8"
            or calls[1]["warmupCaseID"] != "WI-V3-D020"
            or calls[1]["maximumPhysicalSends"] != 3):
        raise RuntimeError("accepted DeepSeek warm-up contract changed")
    price = Decimal(calls[1]["oneSendWorstCaseUSD"])
    if not price.is_finite() or price <= 0:
        raise RuntimeError("accepted DeepSeek price is invalid")
    return calls[1]


def deepseek_material() -> dict[str, Any]:
    parent, _ = _parent()
    route = next(item for item in parent["candidateRoutes"]
                 if item["requestedModelID"] == DEEPSEEK_MODEL)
    if route["providerEndpoint"] != "deepinfra/fp8":
        raise RuntimeError("DeepSeek route changed")
    call = _historical_deepseek_call()
    # Historical catalogue-derived bound, not a fresh public price.
    one_send = Decimal(call["oneSendWorstCaseUSD"])
    return {
        "proposalVersion": "paceprompt-host-eval-proposal/issue145-deepseek-only-r1",
        "status": "awaiting-fresh-catalogue-exact-cap-and-live-authorization",
        "runID": DEEPSEEK_RUN_ID,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "parentProposalSha256": PARENT_PROPOSAL_SHA256,
        "parentEvidenceTreeSha256": PARENT_EVIDENCE_SHA256,
        "acceptedProbeGateSha256": ACCEPTED_GATE_SHA256,
        "requestedModelID": DEEPSEEK_MODEL,
        "route": route,
        "warmupCaseID": "WI-V3-D020",
        "logicalPositions": 1,
        "scoredHeldoutCalls": 0,
        "maximumPhysicalSends": 3,
        "historicalOneSendWorstCaseUSD": format(one_send, "f"),
        "historicalThreeSendWorstCaseUSD": format(one_send * 3, "f"),
        "freshPublicCatalogueRequiredBeforeLive": True,
        "recommendedHardLimitUSD": format(one_send * 3, "f"),
        "ratifiedHardLimitUSD": None,
        "routeCompatibilityProof": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def matrix_material() -> tuple[dict[str, Any], dict[str, Any]]:
    parent, queue = _parent()
    deepseek = deepseek_material()
    if (parent["scoredLogicalPositions"] != 3597
            or parent["warmupLogicalPositions"] != 11
            or parent["maximumPhysicalSends"] != 10824
            or Decimal(parent["threeSendConservativeUSDFromSavedCatalogue"])
               >= Decimal(LINEAGE_CEILING_USD)):
        raise RuntimeError("eleven-candidate queue or cost ceiling changed")
    return ({
        "proposalVersion": "paceprompt-host-eval-proposal/issue145-post-probe-11-r2",
        "status": "awaiting-deepseek-proof-fresh-catalogue-exact-profile-and-live-authorization",
        "runID": MATRIX_RUN_ID,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "parentProposalSha256": PARENT_PROPOSAL_SHA256,
        "parentEvidenceTreeSha256": PARENT_EVIDENCE_SHA256,
        "candidateModelIDs": parent["candidateModelIDs"],
        "candidateRoutes": parent["candidateRoutes"],
        "excludedCandidate": parent["excludedCandidate"],
        "queueSha256": queue["queueSha256"],
        "scoredLogicalPositions": 3597,
        "warmupLogicalPositions": 11,
        "maximumPhysicalSends": 10824,
        "stratumScoredPositions": parent["stratumScoredPositions"],
        "threeSendConservativeUSDFromSavedCatalogue": parent[
            "threeSendConservativeUSDFromSavedCatalogue"],
        "operatorApprovedCumulativeCeilingUSD": LINEAGE_CEILING_USD,
        "ratifiedHardLimitUSD": None,
        "freshPublicCatalogueRequiredBeforeLive": True,
        "deepseekProbeProposalSha256": canonical_hash(deepseek),
        "deepseekRouteCompatibilityProof": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }, queue)


def prepare_proposals() -> dict[str, Any]:
    deepseek = deepseek_material()
    matrix, queue = matrix_material()
    for run_id in (DEEPSEEK_RUN_ID, MATRIX_RUN_ID):
        run_dir = safe_run_dir(run_id, create=True)
        if any(run_dir.iterdir()):
            raise RuntimeError(f"proposal directory is not fresh: {run_id}")
    deepseek["proposalSha256"] = canonical_hash(deepseek)
    matrix["proposalSha256"] = canonical_hash(matrix)
    write_json(safe_run_dir(DEEPSEEK_RUN_ID, create=False) / "proposal.json", deepseek)
    matrix_dir = safe_run_dir(MATRIX_RUN_ID, create=False)
    write_json(matrix_dir / "planned-queue.json", queue)
    write_json(matrix_dir / "proposal.json", matrix)
    return verify_prepared_proposals()


def verify_prepared_proposals() -> dict[str, Any]:
    deepseek = deepseek_material()
    matrix, queue = matrix_material()
    deepseek["proposalSha256"] = canonical_hash(deepseek)
    matrix["proposalSha256"] = canonical_hash(matrix)
    deepseek_dir = safe_run_dir(DEEPSEEK_RUN_ID, create=False)
    matrix_dir = safe_run_dir(MATRIX_RUN_ID, create=False)
    if (strict_json_load(deepseek_dir / "proposal.json") != deepseek
            or strict_json_load(matrix_dir / "proposal.json") != matrix
            or strict_json_load(matrix_dir / "planned-queue.json") != queue):
        raise RuntimeError("prepared proposals differ from source-bound material")
    return {
        "status": "valid", "deepseekProposalSha256": deepseek["proposalSha256"],
        "deepseekEvidenceTreeSha256": evidence_tree_sha256(deepseek_dir),
        "matrixProposalSha256": matrix["proposalSha256"],
        "matrixEvidenceTreeSha256": evidence_tree_sha256(matrix_dir),
        "queueSha256": queue["queueSha256"],
        "hostSourceTreeSha256": host_source_tree_hash(),
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }
