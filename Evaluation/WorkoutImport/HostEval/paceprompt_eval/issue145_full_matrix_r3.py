"""Zero-spend, unratified issue #145 r3 full-matrix proposal preparation.

The sealed v5 queue, corpora, prompt, scorer and model profiles remain intact.
This module materialises only the operator-proposed Mistral route and retry
overlay, then records public-catalogue and mocked-payload evidence. It cannot
read credentials or invoke a model.
"""

from __future__ import annotations

import asyncio
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import tempfile
from typing import Any, Callable

from .catalogue import MODELS_URL, endpoint_url, snapshot_catalogue
from .issue145 import (
    BASETEN_DUPLICATE_ALLOWLIST, MODELS, RUN_POLICY, cost_preflight,
    mock_payloads, queue_document, required_parameter_contracts,
    verify as verify_v5,
)
from .issue145_retry_profile_r3 import verify as verify_retry_r3
from .issue145_retry_execution import evidence_tree_sha256
from .openrouter import ModelSpec
from .runner import write_json
from .transport_strategy import (
    ISSUE145_R3_REGISTRY_ID, ISSUE145_R3_ROUTE_STRATEGIES,
    ISSUE145_V5_ROUTE_STRATEGIES, ProviderRoute, TransportStrategyID,
    strategy_for,
)
from .v3 import HOST_EVAL_ROOT, canonical_hash, safe_run_dir, sha256_file, strict_json_load


MODEL_OVERLAY = HOST_EVAL_ROOT / "models-issue145-r3-overlay-r1.json"
POLICY_OVERLAY = HOST_EVAL_ROOT / "run-policy-issue145-r3-overlay-r1.json"
RATIFICATION = HOST_EVAL_ROOT / "issue145-r3-profile-ratification-r1.json"
MODEL_OVERLAY_SHA256 = "45fa8038dcf7cba83cc604f07a28225e59b806b377459097fa6c1723bec7ebc9"
POLICY_OVERLAY_SHA256 = "7efd24464bfcc3ca7b9a120a9212a5b8a328cd2200637b94928aaa56db0bef5e"
RATIFICATION_SHA256 = "5af41dc20be7610f763b521baecb0fe2988d9ea0ee89768a6446d4f69e325336"
MISTRAL_ID = "mistralai/mistral-small-2603"
MISTRAL_V5_ROUTE = ProviderRoute(MISTRAL_ID, MISTRAL_ID, "mistral/zdr")
MISTRAL_R3_ROUTE = ProviderRoute(MISTRAL_ID, MISTRAL_ID, "mistral")


def materialized_models() -> dict[str, Any]:
    """Derive the proposed model document from sealed v5 without editing it."""
    overlay = strict_json_load(MODEL_OVERLAY)
    document = deepcopy(strict_json_load(MODELS))
    document["modelSetVersion"] = overlay["materializedModelSetVersion"]
    for model in document["models"]:
        model["transportRegistry"] = ISSUE145_R3_REGISTRY_ID
        if model["requestedModelID"] == MISTRAL_ID:
            model["providerEndpoint"] = overlay["changedFields"]["providerEndpoint"]
            model.pop("zdr", None)
    return document


def verify() -> dict[str, Any]:
    errors: list[str] = []
    if verify_v5()["status"] != "valid":
        errors.append("sealed v5 profile failed verification")
    if verify_retry_r3()["status"] != "valid":
        errors.append("unratified r3 route/retry proposal changed")
    if sha256_file(MODEL_OVERLAY) != MODEL_OVERLAY_SHA256:
        errors.append("r3 model overlay bytes changed")
    if sha256_file(POLICY_OVERLAY) != POLICY_OVERLAY_SHA256:
        errors.append("r3 policy overlay bytes changed")
    models = strict_json_load(MODEL_OVERLAY)
    policy = strict_json_load(POLICY_OVERLAY)
    if models.get("baseModelsSha256") != sha256_file(MODELS):
        errors.append("r3 model overlay changed its v5 base")
    if policy.get("baseRunPolicySha256") != sha256_file(RUN_POLICY):
        errors.append("r3 policy overlay changed its v5 base")
    if policy.get("queueSha256") != queue_document()["queueSha256"]:
        errors.append("r3 queue changed")
    if policy.get("finiteLineageHardLimitUSD") is not None:
        errors.append("unratified r3 overlay must not authorise spend")
    expected_routes = dict(ISSUE145_V5_ROUTE_STRATEGIES)
    expected_routes.pop(MISTRAL_V5_ROUTE)
    expected_routes[MISTRAL_R3_ROUTE] = TransportStrategyID.NESTED_V2_3
    if dict(ISSUE145_R3_ROUTE_STRATEGIES) != expected_routes:
        errors.append("r3 transport registry changed beyond the Mistral route")
    document = materialized_models()
    if len(document["models"]) != 12:
        errors.append("r3 materialized model count changed")
    for item in document["models"]:
        try:
            strategy_for(ModelSpec.from_json(item))
        except (KeyError, ValueError) as error:
            errors.append(f"r3 route strategy invalid: {error}")
    authority = {"credentialRead": False, "providerInference": False,
                 "spend": False, "liveRun": False}
    if models.get("authority") != authority or policy.get("authority") != authority:
        errors.append("r3 overlay authority expanded")
    return {
        "status": "valid" if not errors else "invalid", "errors": errors,
        "modelOverlaySha256": sha256_file(MODEL_OVERLAY),
        "policyOverlaySha256": sha256_file(POLICY_OVERLAY),
        "materializedModelsSha256": canonical_hash(document),
        "queueSha256": queue_document()["queueSha256"],
        "liveAuthorized": False,
    }


def _proposal_material(
    run_id: str, run_dir: Path, snapshot: dict[str, Any],
    mock_hashes: dict[str, str], one_send: Decimal,
) -> dict[str, Any]:
    queue = queue_document()
    return {
        "profileVersion": "paceprompt-host-eval-profile/issue145-r3-proposal-r1",
        "status": "awaiting-route-proof-profile-cap-and-live-ratification",
        "runID": run_id,
        "modelOverlaySha256": sha256_file(MODEL_OVERLAY),
        "policyOverlaySha256": sha256_file(POLICY_OVERLAY),
        "materializedModelsSha256": sha256_file(run_dir / "models-r3-materialized.json"),
        "queueSha256": queue["queueSha256"],
        "queueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "catalogueSelectedSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "catalogueModelsSha256": snapshot["modelsSha256"],
        "mockPayloadHashes": mock_hashes,
        "scoredLogicalPositions": 3924,
        "warmupLogicalPositions": 12,
        "maximumPhysicalSends": 11808,
        "oneSendConservativeUSD": format(one_send, "f"),
        "threeSendConservativeUSD": format(one_send * 3, "f"),
        "recommendedHardLimitUSD": None,
        "ratifiedHardLimitUSD": None,
        "routeCompatibilityProof": None,
        "credentialRead": False,
        "providerCalls": 0,
        "spendUSD": "0.00",
        "liveAuthorized": False,
    }


async def prepare_proposal(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None
) -> dict[str, Any]:
    """Write ignored public-catalogue and mock evidence; never touch a key."""
    # The sealed lineage verifier runs its own mock coroutine synchronously.
    # Keep it outside this preparation coroutine's event loop.
    checked = await asyncio.to_thread(verify)
    if checked["status"] != "valid":
        raise RuntimeError(f"r3 profile verification failed: {checked['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    models_path = run_dir / "models-r3-materialized.json"
    write_json(models_path, materialized_models())
    specs = tuple(ModelSpec.from_json(item) for item in materialized_models()["models"])
    snapshot = snapshot_catalogue(
        run_dir / "catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        **({"fetch": fetch} if fetch else {}),
    )
    if any(item["status"] != 0 for item in snapshot["selected"]):
        raise RuntimeError("a proposed r3 endpoint is unavailable")
    for item in snapshot["selected"]:
        for field in ("inputPricePerToken", "outputPricePerToken"):
            price = Decimal(item[field])
            if not price.is_finite() or price < 0:
                raise RuntimeError("a proposed r3 endpoint price is invalid")
    mocks, templates = await mock_payloads(run_dir, snapshot, models_path=models_path)
    preflight = cost_preflight(snapshot, templates, models_path=models_path)
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    one_send = Decimal(preflight["estimatedUSD"])
    profile = _proposal_material(run_id, run_dir, snapshot, mocks["payloadHashes"], one_send)
    profile["profileSha256"] = canonical_hash(profile)
    write_json(run_dir / "r3-proposal.json", profile)
    return profile


def verify_prepared_proposal(run_id: str) -> dict[str, Any]:
    """Audit an ignored zero-spend proposal; no network or credential access."""
    errors: list[str] = []
    if verify()["status"] != "valid":
        errors.append("versioned r3 overlay verification failed")
    run_dir = safe_run_dir(run_id, create=False)
    if not run_dir.is_dir() or run_dir.name != run_id:
        return {"status": "invalid", "errors": ["prepared run directory is absent or aliased"]}
    try:
        model_path = run_dir / "models-r3-materialized.json"
        if strict_json_load(model_path) != materialized_models():
            errors.append("materialized r3 model document changed")
        queue = strict_json_load(run_dir / "planned-queue.json")
        if queue != queue_document():
            errors.append("frozen logical queue changed")
        specs = tuple(ModelSpec.from_json(item) for item in materialized_models()["models"])
        raw_catalogue = run_dir / "catalogue"
        raw_by_url = {MODELS_URL: raw_catalogue / "models.json"}
        raw_by_url.update({
            endpoint_url(spec.canonical_revision):
                raw_catalogue / f"{spec.requested_model_id.replace('/', '--')}.json"
            for spec in specs
        })

        def saved_raw_fetch(url: str) -> bytes:
            return raw_by_url[url].read_bytes()

        # The selected prices, parameter support and provider identities must
        # come from the saved raw public responses, not from self-reported
        # values in the mutable selected/profile files. Likewise, recreate
        # complete request bodies from sealed models, prompt, schema and cases.
        with tempfile.TemporaryDirectory(prefix="paceprompt-r3-audit-") as temporary:
            reconstructed_dir = Path(temporary)
            snapshot = snapshot_catalogue(
                reconstructed_dir / "catalogue", specs,
                fetch=saved_raw_fetch,
                required_parameters=required_parameter_contracts(specs),
                allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
            )
            if strict_json_load(raw_catalogue / "selected.json") != snapshot:
                errors.append("selected catalogue differs from saved raw responses")
            if any(item["status"] != 0 for item in snapshot["selected"]):
                errors.append("a reconstructed r3 endpoint is unavailable")
            for endpoint in snapshot["selected"]:
                for field in ("inputPricePerToken", "outputPricePerToken"):
                    price = Decimal(endpoint[field])
                    if not price.is_finite() or price < 0:
                        errors.append("a reconstructed r3 endpoint price is invalid")
            regenerated, templates = asyncio.run(mock_payloads(
                reconstructed_dir, snapshot, models_path=model_path
            ))
            mocks = strict_json_load(run_dir / "mock-summary.json")
            mock_hashes = mocks["payloadHashes"]
            if ({key: value for key, value in mocks.items() if key != "payloadHashes"}
                    != {key: value for key, value in regenerated.items()
                        if key != "payloadHashes"}
                    or set(mock_hashes) != {spec.requested_model_id for spec in specs}):
                errors.append("mock summary differs from regenerated requests")
            for spec in specs:
                name = f"{spec.requested_model_id.replace('/', '--')}.json"
                saved_path = run_dir / "mock-payloads" / name
                if sha256_file(saved_path) != mock_hashes[spec.requested_model_id]:
                    errors.append(f"mock payload hash changed: {spec.requested_model_id}")
                saved = strict_json_load(saved_path)
                fresh = strict_json_load(reconstructed_dir / "mock-payloads" / name)
                # The SDK generates a fresh x-irid trace header on each
                # capture. It is not part of the model request contract.
                saved.get("headers", {}).pop("x-irid", None)
                fresh.get("headers", {}).pop("x-irid", None)
                if saved != fresh:
                    errors.append(f"mock payload differs from sealed inputs: {spec.requested_model_id}")
        preflight = cost_preflight(snapshot, templates, models_path=model_path)
        profile = strict_json_load(run_dir / "r3-proposal.json")
        expected = _proposal_material(
            run_id, run_dir, snapshot, mock_hashes, Decimal(preflight["estimatedUSD"])
        )
        expected["profileSha256"] = canonical_hash(expected)
        if profile != expected:
            errors.append("prepared profile differs from its verified inputs")
        tree_hash = evidence_tree_sha256(run_dir)
    except (KeyError, OSError, TypeError, ValueError) as error:
        errors.append(f"prepared proposal unreadable or malformed: {error}")
        tree_hash = None
        profile = None
    return {
        "status": "valid" if not errors else "invalid", "errors": errors,
        "profileSha256": profile.get("profileSha256") if isinstance(profile, dict) else None,
        "evidenceTreeSha256": tree_hash,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def verify_ratification(*, require_prepared_evidence: bool = False) -> dict[str, Any]:
    """Bind the operator's exact profile and cap without granting live access."""
    errors: list[str] = []
    if sha256_file(RATIFICATION) != RATIFICATION_SHA256:
        errors.append("profile/cap ratification bytes changed")
    ratification = strict_json_load(RATIFICATION)
    checked = verify()
    if checked["status"] != "valid" or ratification.get("queueSha256") != checked["queueSha256"]:
        errors.append("ratification does not bind the versioned r3 queue")
    limit = Decimal(ratification["finiteCumulativeLineageHardLimitUSD"])
    bound = Decimal(ratification["supportingThreeSendConservativeUSD"])
    if (not limit.is_finite() or limit <= 0
            or not bound.is_finite() or bound <= 0 or limit < bound):
        errors.append("ratified cumulative cap is invalid or below the conservative bound")
    if require_prepared_evidence:
        prepared = verify_prepared_proposal(ratification["preparedRunID"])
        if (prepared["status"] != "valid"
                or ratification["profileSha256"] != prepared["profileSha256"]
                or ratification["supportingPreparedEvidenceTreeSha256"]
                != prepared["evidenceTreeSha256"]):
            errors.append("ratification does not bind the audited prepared profile")
        else:
            profile = strict_json_load(
                safe_run_dir(ratification["preparedRunID"], create=False) / "r3-proposal.json"
            )
            if profile["threeSendConservativeUSD"] != ratification[
                "supportingThreeSendConservativeUSD"
            ]:
                errors.append("ratification conservative bound changed")
    authority = {"credentialRead": False, "providerInference": False,
                 "spend": False, "liveRun": False}
    if (ratification.get("operatorRatifiedFields")
            != ["profileSha256", "finiteCumulativeLineageHardLimitUSD"]
            or ratification.get("authority") != authority
            or ratification.get("routeCompatibilityProof") is not None
            or ratification.get("liveGate") is not None
            or ratification.get("initialLiveAuthorization") is not None):
        errors.append("ratification authority or scope expanded")
    return {
        "status": "valid" if not errors else "invalid", "errors": errors,
        "ratificationSha256": sha256_file(RATIFICATION),
        "profileSha256": ratification["profileSha256"],
        "finiteCumulativeLineageHardLimitUSD": format(limit, "f"),
        "preparedEvidenceRequired": require_prepared_evidence,
        "liveAuthorized": False,
    }
