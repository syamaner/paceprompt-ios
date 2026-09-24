"""Source-bound, zero-spend profile for one DeepSeek route warm-up.

This module reads only sealed local evidence and a public-catalogue snapshot.
It has no credential lookup, live gate sealing or provider send entrypoint.
"""

from __future__ import annotations

from dataclasses import asdict
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
from tempfile import TemporaryDirectory
from typing import Any

from .catalogue import MODELS_URL, conservative_call_cost, endpoint_url, snapshot_catalogue
from .issue145 import EXAMPLES, PRODUCTION_PROMPT, required_parameter_contracts
from .issue145_deepseek_11_r2 import DEEPSEEK_MODEL, DEEPSEEK_RUN_ID, _historical_deepseek_call
from .issue145_post_probe_11 import ACCEPTED_GATE_SHA256, ACCEPTED_RUN_ID
from .issue145_r3_route_probe_run import _parent as old_probe_parent
from .issue145_r3_route_probe_run import _request_bytes as old_probe_request_bytes
from .issue145_retry_execution import evidence_tree_sha256
from .runner import write_json
from .v3 import (
    MODEL_SCHEMA, canonical_hash, host_source_tree_hash,
    safe_run_dir, sha256_file, strict_json_load,
)


PARENT_PROPOSAL_SHA256 = "0b5c2485361861c34f1ba2057dfb909db2fda58785d2ac7be2ebb73aa0d6c4f9"
PARENT_EVIDENCE_SHA256 = "f0479fd2362b9df89e5ea517cd2b18d60868b1aa53d68fcef7710ac379cb80b9"
CATALOGUE_RUN_ID = "issue145-deepseek-catalogue-20260924-01"
CATALOGUE_EVIDENCE_SHA256 = "e34dd89c37c34c59e4edfc453cef61eccfc8d0cdcb878776d3a5c964eb6c725c"
PROFILE_RUN_ID = "issue145-deepseek-probe-profile-20260924-06"
PROPOSED_LIVE_RUN_ID = "issue145-deepseek-route-probe-20260924-01"
LOGICAL_ID = "warmup-deepseek--deepseek-v4-flash-0731"
PROMPT_SHA256 = "5e27496875f6fd20d737d8c190fc938bfdc2b2cd3658e48f606dccf64bbdf007"
EXAMPLES_SHA256 = "0313c531454bae3545ec97118be33232f53b0b62613a2339d8a96dbe21a680fd"
_SHA = re.compile(r"[0-9a-f]{64}\Z")


def _accepted_parent() -> dict[str, Any]:
    run_dir = safe_run_dir(DEEPSEEK_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PARENT_EVIDENCE_SHA256:
        raise RuntimeError("accepted DeepSeek-only proposal evidence changed")
    proposal = strict_json_load(run_dir / "proposal.json")
    if (proposal.get("proposalSha256") != PARENT_PROPOSAL_SHA256
            or canonical_hash({key: value for key, value in proposal.items()
                               if key != "proposalSha256"}) != PARENT_PROPOSAL_SHA256
            or proposal.get("requestedModelID") != DEEPSEEK_MODEL
            or proposal.get("route", {}).get("providerEndpoint") != "deepinfra/fp8"
            or proposal.get("ratifiedHardLimitUSD") is not None
            or proposal.get("liveAuthorized") is not False):
        raise RuntimeError("accepted DeepSeek-only proposal changed")
    return proposal


def _fresh_catalogue(spec: Any) -> dict[str, Any]:
    run_dir = safe_run_dir(CATALOGUE_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != CATALOGUE_EVIDENCE_SHA256:
        raise RuntimeError("fresh public catalogue evidence changed")
    source = run_dir / "catalogue"
    raw_models = (source / "models.json").read_bytes()
    raw_endpoint = (source / f"{DEEPSEEK_MODEL.replace('/', '--')}.json").read_bytes()
    selected = strict_json_load(source / "selected.json")

    def replay(url: str) -> bytes:
        if url == MODELS_URL:
            return raw_models
        if url == endpoint_url(spec.canonical_revision):
            return raw_endpoint
        raise RuntimeError("unexpected public catalogue URL")

    with TemporaryDirectory() as directory:
        rebuilt = snapshot_catalogue(
            Path(directory) / "replayed", (spec,), fetch=replay,
            required_parameters=required_parameter_contracts((spec,)),
        )
    if rebuilt != selected or len(selected["selected"]) != 1:
        raise RuntimeError("fresh catalogue selection does not replay")
    endpoint = selected["selected"][0]
    if (endpoint["requestedModelID"] != DEEPSEEK_MODEL
            or endpoint["providerEndpoint"] != "deepinfra/fp8"
            or endpoint["canonicalRevision"] != spec.canonical_revision
            or endpoint["reportedQuantization"] != "fp8"
            or type(endpoint.get("status")) is not int
            or endpoint["status"] != 0):
        raise RuntimeError("fresh DeepSeek route differs from the pinned route")
    return selected


def _accepted_request_identity() -> tuple[str, int]:
    gate_path = safe_run_dir(ACCEPTED_RUN_ID, create=False) / "operator-gate.json"
    if sha256_file(gate_path) != ACCEPTED_GATE_SHA256:
        raise RuntimeError("accepted probe gate bytes changed")
    gate = strict_json_load(gate_path)
    call = next(item for item in gate["orderedCalls"]
                if item["logicalID"] == LOGICAL_ID)
    return gate["requestSha256"][LOGICAL_ID], call["requestUTF8Bytes"]


def profile_material(*, preparation_source_sha256: str) -> dict[str, Any]:
    if not _SHA.fullmatch(preparation_source_sha256):
        raise ValueError("an exact preparation source SHA-256 is required")
    if (sha256_file(PRODUCTION_PROMPT) != PROMPT_SHA256
            or sha256_file(EXAMPLES) != EXAMPLES_SHA256):
        raise RuntimeError("production prompt or examples changed")
    parent = _accepted_parent()
    _, old_proposal, specs, _ = old_probe_parent()
    spec = next(item for item in specs if item.requested_model_id == DEEPSEEK_MODEL)
    request = old_probe_request_bytes(old_proposal)[LOGICAL_ID]
    accepted_hash, accepted_length = _accepted_request_identity()
    if (hashlib.sha256(request).hexdigest() != accepted_hash
            or len(request) != accepted_length):
        raise RuntimeError("DeepSeek warm-up request differs from accepted gate")
    body = json.loads(request)
    if (body.get("model") != DEEPSEEK_MODEL
            or body.get("provider", {}).get("order") != ["deepinfra/fp8"]
            or body["provider"].get("only") != ["deepinfra/fp8"]
            or body["provider"].get("allow_fallbacks") is not False
            or body["provider"].get("require_parameters") is not True
            or body["provider"].get("data_collection") != "deny"
            or body["provider"].get("quantizations") != ["fp8"]
            or body["provider"].get("zdr") is not True
            or body.get("max_tokens") != spec.max_output_tokens
            or body.get("response_format", {}).get("type") != "json_schema"):
        raise RuntimeError("DeepSeek warm-up request controls changed")
    selected = _fresh_catalogue(spec)
    endpoint = selected["selected"][0]
    one_send = conservative_call_cost(
        input_utf8_bytes=len(request),
        input_price=endpoint["inputPricePerToken"],
        output_price=endpoint["outputPricePerToken"],
        output_tokens=spec.max_output_tokens,
    )
    historical = Decimal(_historical_deepseek_call()["oneSendWorstCaseUSD"])
    if (not one_send.is_finite() or one_send <= 0
            or one_send > historical
            or one_send * 3 != Decimal(parent["recommendedHardLimitUSD"])):
        raise RuntimeError("fresh DeepSeek cost exceeds the accepted proposal")
    model_spec = asdict(spec)
    model_spec["required_parameters"] = list(spec.required_parameters)
    return {
        "profileVersion": "paceprompt-host-eval-profile/issue145-deepseek-probe-r1",
        "status": "awaiting-exact-profile-and-cap-ratification",
        "proposalRunID": PROFILE_RUN_ID,
        "proposedLiveRunID": PROPOSED_LIVE_RUN_ID,
        "preparationSourceTreeSha256": preparation_source_sha256,
        "parentProposalSha256": PARENT_PROPOSAL_SHA256,
        "parentEvidenceTreeSha256": PARENT_EVIDENCE_SHA256,
        "freshCatalogueRunID": CATALOGUE_RUN_ID,
        "freshCatalogueEvidenceTreeSha256": CATALOGUE_EVIDENCE_SHA256,
        "freshCatalogueModelsSha256": selected["modelsSha256"],
        "selectedEndpoint": endpoint,
        "modelSpec": model_spec,
        "productionPromptSha256": PROMPT_SHA256,
        "productionExamplesSha256": EXAMPLES_SHA256,
        "modelSchemaSha256": sha256_file(MODEL_SCHEMA),
        "logicalID": LOGICAL_ID,
        "warmupCaseID": "WI-V3-D020",
        "requestSha256": hashlib.sha256(request).hexdigest(),
        "requestUTF8Bytes": len(request),
        "scoredHeldoutCalls": 0,
        "maximumLogicalPositions": 1,
        "maximumPhysicalSends": 3,
        "retryPolicy": {
            "maximumSendsPerPosition": 3,
            "completeHTTPStatusCodes": [429, 502, 503, 504, 524, 529],
            "fallbackBackoffSeconds": [30, 120],
            "honourRetryAfterAsMinimum": True,
            "maximumSingleWaitSeconds": 900,
            "maximumCumulativeWaitSeconds": 900,
            "noRetryWithoutCompleteHTTPResponse": True,
        },
        "transport": {
            "connectTimeoutSeconds": 15, "readTimeoutSeconds": 180,
            "writeTimeoutSeconds": 15, "poolTimeoutSeconds": 15,
            "perSendCeilingSeconds": 180, "hiddenSDKRetries": 0,
            "allowFallbacks": False, "followRedirects": False,
            "minimumInterSendDelaySeconds": 2,
        },
        "responseAcceptance": {
            "completeHTTPResponseRequiredForRetry": True,
            "returnedModelAndProviderIdentityRequired": True,
            "exactlyOneChoice": True,
            "finishReason": "stop",
            "toolCallsAllowed": False,
            "nativeAndHostSchemaRequired": True,
            "scoredCase": False,
        },
        "oneSendConservativeUSD": format(one_send, "f"),
        "threeSendConservativeUSD": format(one_send * 3, "f"),
        "recommendedHardLimitUSD": format(one_send * 3, "f"),
        "ratifiedHardLimitUSD": None,
        "routeCompatibilityProof": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def prepare_profile() -> dict[str, Any]:
    profile = profile_material(preparation_source_sha256=host_source_tree_hash())
    run_dir = safe_run_dir(PROFILE_RUN_ID, create=True)
    profile["profileSha256"] = canonical_hash(profile)
    write_json(run_dir / "profile.json", profile)
    return verify_prepared_profile()


def verify_prepared_profile() -> dict[str, Any]:
    run_dir = safe_run_dir(PROFILE_RUN_ID, create=False)
    actual = strict_json_load(run_dir / "profile.json")
    if actual["preparationSourceTreeSha256"] != host_source_tree_hash():
        raise RuntimeError("prepared DeepSeek profile source tree changed")
    expected = profile_material(
        preparation_source_sha256=actual["preparationSourceTreeSha256"]
    )
    expected["profileSha256"] = canonical_hash(expected)
    if actual != expected:
        raise RuntimeError("prepared DeepSeek profile changed")
    return {
        "status": "valid", "profileSha256": expected["profileSha256"],
        "profileEvidenceTreeSha256": evidence_tree_sha256(run_dir),
        "preparationSourceTreeSha256": expected["preparationSourceTreeSha256"],
        "recommendedHardLimitUSD": expected["recommendedHardLimitUSD"],
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }
