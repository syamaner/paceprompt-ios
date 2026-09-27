"""Zero-spend proposal for MiniMax M3 on Together; no live authority.

The ratified r3 profile and failed-but-unstarted CoreWeave root remain sealed.
Only MiniMax's exact provider route changes; all eleven model IDs, scored
questions, expected answers, queue positions and generation controls persist.
"""

from __future__ import annotations

import argparse
import asyncio
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Callable

from .catalogue import MODELS_URL, endpoint_url, snapshot_catalogue
from .issue145 import (
    BASETEN_DUPLICATE_ALLOWLIST, mock_payloads, required_parameter_contracts,
)
from .issue145_11model_gate import (
    HARD_LIMIT_USD, PROFILE_SHA256, planned_calls, ratified_profile,
)
from .issue145_full_matrix_r3 import materialized_models
from .issue145_retry_execution import evidence_tree_sha256
from .openrouter import ModelSpec
from .runner import write_json
from .transport_strategy import ISSUE145_R4_REGISTRY_ID, strategy_for
from .v3 import (
    canonical_hash, host_source_tree_hash, safe_run_dir,
    sha256_file, strict_json_load,
)


PROPOSAL_RUN_ID = "issue145-11model-together-profile-r4-20260925-01"
PROPOSED_ROOT_RUN_ID = "issue145-11model-together-matrix-20260925-01"
MINIMAX_ID = "minimax/minimax-m3"
OLD_ROUTE = "coreweave/fp4"
NEW_ROUTE = "together"
PROPOSAL_VERSION = "paceprompt-host-eval-profile/issue145-11model-together-r4"


def materialized_models_r4(base: dict[str, Any] | None = None) -> dict[str, Any]:
    if base is None:
        base, _ = ratified_profile()
    document = deepcopy(materialized_models())
    document["modelSetVersion"] = "paceprompt-host-eval-models/issue145-11model-together-r4"
    document["models"] = [item for item in document["models"]
                          if item["requestedModelID"] in base["candidateModelIDs"]]
    if [item["requestedModelID"] for item in document["models"]] != base["candidateModelIDs"]:
        raise RuntimeError("r4 model order differs from ratified r3")
    mini = next(item for item in document["models"]
                if item["requestedModelID"] == MINIMAX_ID)
    if mini["providerEndpoint"] != OLD_ROUTE or mini["quantization"] != "fp4":
        raise RuntimeError("r3 MiniMax route changed")
    mini["providerEndpoint"] = NEW_ROUTE
    mini["quantization"] = None
    mini["transportRegistry"] = ISSUE145_R4_REGISTRY_ID
    mini.pop("zdr", None)
    specs = tuple(ModelSpec.from_json(item) for item in document["models"])
    for spec in specs:
        strategy_for(spec)
    return document


def profile_material_r4() -> tuple[dict[str, Any], dict[str, Any]]:
    base, queue = ratified_profile()
    document = materialized_models_r4(base)
    profile = deepcopy(base)
    profile.pop("profileSha256")
    profile["profileVersion"] = PROPOSAL_VERSION
    profile["status"] = "proposed-awaiting-separate-ratification-and-live-authority"
    profile["parentRatifiedProfileSha256"] = PROFILE_SHA256
    profile["proposalRunID"] = PROPOSAL_RUN_ID
    profile["proposedRootRunID"] = PROPOSED_ROOT_RUN_ID
    profile["hostSourceTreeSha256"] = host_source_tree_hash()
    profile.pop("supersededLocalDraftEvidenceSha256", None)
    profile.pop("threeSendConservativeUSDFromSavedCatalogue", None)
    profile["routeCompatibilityProof"] = None
    profile["liveAuthorized"] = False
    mini = next(item for item in profile["candidateRoutes"]
                if item["requestedModelID"] == MINIMAX_ID)
    if mini["providerEndpoint"] != OLD_ROUTE or mini["quantization"] != "fp4":
        raise RuntimeError("r3 profile MiniMax route changed")
    mini["providerEndpoint"] = NEW_ROUTE
    mini["quantization"] = None
    expected_routes = [
        {key: item[key] for key in (
            "requestedModelID", "canonicalRevision", "providerEndpoint",
            "quantization", "responseContract", "maxOutputTokens",
        )}
        for item in document["models"]
    ]
    if profile["candidateRoutes"] != expected_routes:
        raise RuntimeError("r4 route change is not MiniMax-only")
    profile["profileSha256"] = canonical_hash(profile)
    return profile, queue


async def prepare_proposal(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None,
) -> dict[str, Any]:
    """Use only public catalogue and mocked payloads; never read a key."""
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("r4 proposal run ID changed")
    profile, queue = await asyncio.to_thread(profile_material_r4)
    directory = safe_run_dir(run_id, create=True)
    if any(directory.iterdir()):
        raise RuntimeError("r4 proposal directory must be fresh")
    models_path = directory / "models-11-together.json"
    document = materialized_models_r4(profile)
    write_json(models_path, document)
    specs = tuple(ModelSpec.from_json(item) for item in document["models"])
    selected = snapshot_catalogue(
        directory / "catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        **({"fetch": fetch} if fetch else {}),
    )
    if any(type(item.get("status")) is not int or item["status"] != 0
           for item in selected["selected"]):
        raise RuntimeError("an r4 route is unavailable")
    _, templates = await mock_payloads(directory, selected, models_path=models_path)
    calls, _ = planned_calls(
        profile, queue, templates, selected["selected"], specs_override=specs,
    )
    three_send = sum((Decimal(item["oneSendWorstCaseUSD"]) * 3
                      for item in calls), Decimal("0"))
    if three_send > Decimal(HARD_LIMIT_USD):
        raise RuntimeError("r4 worst-case plan exceeds proposed USD 300 cap")
    write_json(directory / "planned-queue.json", queue)
    write_json(directory / "planned-calls.json", calls)
    proposal = {
        "proposalVersion": PROPOSAL_VERSION,
        "status": "awaitingExactProfileAndCapRatification",
        "proposalRunID": run_id,
        "proposedRootRunID": PROPOSED_ROOT_RUN_ID,
        "profile": profile,
        "profileSha256": profile["profileSha256"],
        "parentRatifiedProfileSha256": PROFILE_SHA256,
        "queueSha256": queue["queueSha256"],
        "modelsSha256": sha256_file(models_path),
        "catalogueSelectedSha256": sha256_file(directory / "catalogue" / "selected.json"),
        "plannedCallsSha256": sha256_file(directory / "planned-calls.json"),
        "mockSummarySha256": sha256_file(directory / "mock-summary.json"),
        "logicalPositions": len(calls),
        "maximumPhysicalSends": len(calls) * 3,
        "threeSendConservativeUSD": format(three_send, "f"),
        "recommendedCumulativeHardLimitUSD": HARD_LIMIT_USD,
        "credentialRead": False,
        "providerCalls": 0,
        "spendUSD": "0.00",
        "liveAuthorized": False,
    }
    proposal["proposalSha256"] = canonical_hash(proposal)
    write_json(directory / "proposal.json", proposal)
    return proposal


def verify_proposal(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSAL_RUN_ID:
        raise RuntimeError("r4 proposal run ID changed")
    directory = safe_run_dir(run_id, create=False)
    proposal = strict_json_load(directory / "proposal.json")
    profile, queue = profile_material_r4()
    if (proposal.get("profile") != profile
            or proposal.get("proposalVersion") != PROPOSAL_VERSION
            or proposal.get("status") != "awaitingExactProfileAndCapRatification"
            or proposal.get("proposalRunID") != PROPOSAL_RUN_ID
            or proposal.get("proposedRootRunID") != PROPOSED_ROOT_RUN_ID
            or proposal.get("parentRatifiedProfileSha256") != PROFILE_SHA256
            or proposal.get("queueSha256") != queue["queueSha256"]
            or proposal.get("profileSha256") != profile["profileSha256"]
            or proposal.get("proposalSha256") != canonical_hash({
                key: value for key, value in proposal.items()
                if key != "proposalSha256"
            })
            or strict_json_load(directory / "planned-queue.json") != queue
            or strict_json_load(directory / "models-11-together.json")
               != materialized_models_r4(profile)):
        raise RuntimeError("r4 proposed profile or queue changed")
    selected = strict_json_load(directory / "catalogue" / "selected.json")
    if (len(selected["selected"]) != 11
            or any(type(item.get("status")) is not int or item["status"] != 0
                   for item in selected["selected"])):
        raise RuntimeError("r4 saved public routes are unavailable")
    specs = tuple(ModelSpec.from_json(item) for item in
                  strict_json_load(directory / "models-11-together.json")["models"])
    # Rebuild derived evidence from the saved public response bytes. A selected
    # route/price summary is not an independent authority for itself.
    raw_catalogue = directory / "catalogue"
    raw_by_url = {MODELS_URL: raw_catalogue / "models.json"}
    for spec in specs:
        revision = spec.canonical_revision
        if revision is None:
            raise RuntimeError("r4 route has no pinned canonical revision")
        raw_by_url[endpoint_url(revision)] = (
            raw_catalogue / f"{spec.requested_model_id.replace('/', '--')}.json"
        )

    def saved_fetch(url: str) -> bytes:
        if url not in raw_by_url:
            raise RuntimeError("r4 raw catalogue URL is not pinned")
        return raw_by_url[url].read_bytes()

    with TemporaryDirectory(prefix="paceprompt-r4-replay-") as temporary:
        replay_dir = Path(temporary)
        replay_selected = snapshot_catalogue(
            replay_dir / "catalogue", specs, fetch=saved_fetch,
            required_parameters=required_parameter_contracts(specs),
            allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        )
        if replay_selected != selected:
            raise RuntimeError("r4 selected routes diverge from raw catalogue")
        _, replay_templates = asyncio.run(mock_payloads(
            replay_dir, replay_selected,
            models_path=directory / "models-11-together.json",
        ))
        replay_summary = strict_json_load(replay_dir / "mock-summary.json")
        saved_summary = strict_json_load(directory / "mock-summary.json")
        # Inspect assigns a random x-irid per capture, so its full-file hash
        # cannot be reproduced. Check saved hashes below; replay all stable
        # request fields and the summary contract independently.
        if ({key: value for key, value in replay_summary.items()
             if key != "payloadHashes"}
                != {key: value for key, value in saved_summary.items()
                    if key != "payloadHashes"}):
            raise RuntimeError("r4 mock summary diverges from replay")
        for spec in specs:
            name = f"{spec.requested_model_id.replace('/', '--')}.json"
            replay_payload = strict_json_load(replay_dir / "mock-payloads" / name)
            saved_payload = strict_json_load(directory / "mock-payloads" / name)
            for payload in (replay_payload, saved_payload):
                payload["headers"].pop("x-irid", None)
            if replay_payload != saved_payload:
                raise RuntimeError("r4 mocked payload diverges from replay")
    mock_summary = strict_json_load(directory / "mock-summary.json")
    if (mock_summary.get("credentialRead") is not False
            or mock_summary.get("providerCalls") != 0
            or mock_summary.get("spendUSD") != "0.00"):
        raise RuntimeError("r4 mock summary claims live activity")
    for spec in specs:
        name = f"{spec.requested_model_id.replace('/', '--')}.json"
        if (mock_summary["payloadHashes"].get(spec.requested_model_id)
                != sha256_file(directory / "mock-payloads" / name)):
            raise RuntimeError("r4 mocked outbound payload changed")
    calls, _ = planned_calls(
        profile, queue, replay_templates, replay_selected["selected"],
        specs_override=specs,
    )
    three_send = sum(
        (Decimal(item["oneSendWorstCaseUSD"]) * 3 for item in calls),
        Decimal("0"),
    )
    if not three_send.is_finite() or three_send <= 0 or three_send > Decimal(HARD_LIMIT_USD):
        raise RuntimeError("r4 replayed worst-case plan exceeds proposed cap")
    if (proposal["modelsSha256"] != sha256_file(directory / "models-11-together.json")
            or proposal["catalogueSelectedSha256"]
               != sha256_file(directory / "catalogue" / "selected.json")
            or proposal["plannedCallsSha256"]
               != sha256_file(directory / "planned-calls.json")
            or proposal["mockSummarySha256"]
               != sha256_file(directory / "mock-summary.json")
            or strict_json_load(directory / "planned-calls.json") != calls
            or proposal["logicalPositions"] != 3608
            or proposal["maximumPhysicalSends"] != 10824
            or proposal["recommendedCumulativeHardLimitUSD"] != HARD_LIMIT_USD
            or proposal["threeSendConservativeUSD"] != format(three_send, "f")
            or proposal["credentialRead"] is not False
            or proposal["providerCalls"] != 0
            or proposal["spendUSD"] != "0.00"
            or proposal["liveAuthorized"] is not False):
        raise RuntimeError("r4 proposal evidence changed")
    return {
        "status": "valid", "profileSha256": profile["profileSha256"],
        "proposalSha256": proposal["proposalSha256"],
        "queueSha256": queue["queueSha256"],
        "evidenceTreeSha256": evidence_tree_sha256(directory),
        "threeSendConservativeUSD": proposal["threeSendConservativeUSD"],
        "recommendedCumulativeHardLimitUSD": HARD_LIMIT_USD,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Zero-spend issue #145 Together proposal")
    parser.add_argument("action", choices=("prepare", "verify"))
    parser.add_argument("--run-id", default=PROPOSAL_RUN_ID)
    args = parser.parse_args()
    result = (asyncio.run(prepare_proposal(args.run_id)) if args.action == "prepare"
              else verify_proposal(args.run_id))
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
