"""Exact-run DeepSeek warm-up gate; no credential or provider work at import.

The operator ratified the profile and cap, not live execution. Gate preparation
and sealing are local. Only run_live, with the separately supplied exact phrase
and USD limit, can reach a fresh public catalogue and then a credential lookup.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import time
from typing import Any, Callable

import httpx2

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import required_parameter_contracts
from .issue145_deepseek_probe_profile import (
    LOGICAL_ID, PROFILE_RUN_ID, PROPOSED_LIVE_RUN_ID,
    old_probe_parent, old_probe_request_bytes, profile_material,
)
from .issue145_retry import RetryPolicy
from .issue145_retry_execution import RetryingWireExecutor, evidence_tree_sha256
from .issue145_wire_adapter import OpenRouterOneSend, WireRouteBinding
from .openrouter import ModelSpec, redact
from .runner import authority_preserved, compare_catalogues, write_json
from .scorer_adapter import parse_model_output
from .transport_strategy import strategy_for
from .v3 import (
    HOST_EVAL_ROOT, MODEL_SCHEMA, RUNS_ROOT, canonical_hash,
    host_source_tree_hash, safe_run_dir, sha256_file, strict_json_load,
)


RATIFICATION = HOST_EVAL_ROOT / "issue145-deepseek-probe-ratification-r1.json"
RATIFICATION_SHA256 = "e1573be09fafe65deb7997db3385e6911a7e830373fe3ce6b511a43ebfab2744"
PROFILE_MODULE_SHA256 = "37bdf7fdabeb97294aae9ef991237276024a082d7cec08d34385a5ef64c8b4fa"
PROFILE_SHA256 = "b148d5b0cb6cac0445382a3dd3a6bc17bb283096d6b3ea043652ac6d5467cd29"
PROFILE_EVIDENCE_SHA256 = "66e300de3070d30c188d0a3b40e93c961983d3b4832a2ac01ea49e8c21cf7893"
PROFILE_SOURCE_SHA256 = "2ec6fc2a48f77a2b63fa606365c7ee8c37f9f7ad106e13718d29e937bc854cc9"
HARD_LIMIT_USD = "0.00917478"
RUN_ID = PROPOSED_LIVE_RUN_ID
AUTH_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_DEEPSEEK_PROBE_"
GATE_VERSION = "paceprompt-host-eval-operator-gate/issue145-deepseek-probe-r1"
POLICY = RetryPolicy(3, frozenset({429, 502, 503, 504, 524, 529}), (30, 120), 900, 900)


def _expected_ratification() -> dict[str, Any]:
    return {
        "ratificationVersion": "paceprompt-host-eval-ratification/issue145-deepseek-probe-r1",
        "status": "profile-and-cap-ratified-live-run-not-authorized",
        "source": "operator replied 'I ratify it. Go on' on 2026-09-24 to the immediately preceding exact -06 profile and USD 0.00917478 limit handoff",
        "operatorRatifiedFields": ["profileSha256", "hardLimitUSD"],
        "preparedRunID": PROFILE_RUN_ID,
        "profileSha256": PROFILE_SHA256,
        "profileEvidenceTreeSha256": PROFILE_EVIDENCE_SHA256,
        "preparationSourceTreeSha256": PROFILE_SOURCE_SHA256,
        "proposedLiveRunID": RUN_ID,
        "hardLimitUSD": HARD_LIMIT_USD, "currency": "USD",
        "scope": "one unscored DeepSeek WI-V3-D020 development warm-up on deepinfra/fp8 only",
        "maximumLogicalPositions": 1, "maximumPhysicalSends": 3,
        "scoredHeldoutCalls": 0, "routeCompatibilityProof": None,
        "liveGate": None, "initialLiveAuthorization": None,
        "authority": {"credentialRead": False, "providerInference": False,
                      "spend": False, "liveRun": False},
    }


def _ratified() -> tuple[dict[str, Any], bytes, ModelSpec]:
    """Rebuild the old ratified profile without treating new gate source as old source."""
    if sha256_file(RATIFICATION) != RATIFICATION_SHA256:
        raise RuntimeError("DeepSeek profile/cap ratification bytes changed")
    if strict_json_load(RATIFICATION) != _expected_ratification():
        raise RuntimeError("DeepSeek profile/cap ratification scope changed")
    profile_module = HOST_EVAL_ROOT / "paceprompt_eval" / "issue145_deepseek_probe_profile.py"
    if sha256_file(profile_module) != PROFILE_MODULE_SHA256:
        raise RuntimeError("ratified DeepSeek profile implementation changed")
    run_dir = safe_run_dir(PROFILE_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PROFILE_EVIDENCE_SHA256:
        raise RuntimeError("ratified DeepSeek profile evidence changed")
    actual = strict_json_load(run_dir / "profile.json")
    expected = profile_material(preparation_source_sha256=PROFILE_SOURCE_SHA256)
    expected["profileSha256"] = canonical_hash(expected)
    if (actual != expected or actual["profileSha256"] != PROFILE_SHA256
            or actual["proposedLiveRunID"] != RUN_ID
            or actual["recommendedHardLimitUSD"] != HARD_LIMIT_USD
            or actual["maximumLogicalPositions"] != 1
            or actual["maximumPhysicalSends"] != 3
            or actual["scoredHeldoutCalls"] != 0
            or actual["liveAuthorized"] is not False):
        raise RuntimeError("ratified DeepSeek profile changed")
    _, old_proposal, specs, _ = old_probe_parent()
    spec = next(item for item in specs if item.requested_model_id == actual["modelSpec"]["requested_model_id"])
    request = old_probe_request_bytes(old_proposal)[LOGICAL_ID]
    if (hashlib.sha256(request).hexdigest() != actual["requestSha256"]
            or len(request) != actual["requestUTF8Bytes"]):
        raise RuntimeError("ratified DeepSeek request bytes changed")
    return actual, request, spec


def verify_ratification() -> dict[str, Any]:
    profile, _, _ = _ratified()
    return {
        "status": "valid", "ratificationSha256": RATIFICATION_SHA256,
        "profileSha256": profile["profileSha256"], "hardLimitUSD": HARD_LIMIT_USD,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def _prepared_gate() -> dict[str, Any]:
    profile, request, _ = _ratified()
    return {
        "gateVersion": GATE_VERSION, "runID": RUN_ID,
        "status": "awaitingZeroSpendSealing",
        "hostSourceTreeSha256": host_source_tree_hash(),
        "ratificationSha256": RATIFICATION_SHA256,
        "profileSha256": PROFILE_SHA256,
        "profileEvidenceTreeSha256": PROFILE_EVIDENCE_SHA256,
        "profilePreparationSourceTreeSha256": PROFILE_SOURCE_SHA256,
        "logicalID": LOGICAL_ID, "warmupCaseID": profile["warmupCaseID"],
        "requestSha256": hashlib.sha256(request).hexdigest(),
        "requestUTF8Bytes": len(request),
        "modelSpec": profile["modelSpec"],
        "selectedEndpoint": profile["selectedEndpoint"],
        "retryPolicy": profile["retryPolicy"],
        "transport": profile["transport"],
        "responseAcceptance": profile["responseAcceptance"],
        "oneSendConservativeUSD": profile["oneSendConservativeUSD"],
        "hardLimitUSD": HARD_LIMIT_USD,
        "maximumLogicalPositions": 1, "maximumPhysicalSends": 3,
        "scoredHeldoutCalls": 0,
        "authorizationPhrase": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "routeCompatibilityProof": None,
    }


def _sealed_gate(prepared: dict[str, Any]) -> dict[str, Any]:
    sealed = dict(prepared)
    sealed["status"] = "awaitingFinalLiveRunAuthorization"
    sealed["authorizationPhrase"] = AUTH_PREFIX + canonical_hash(prepared)[:16].upper()
    return sealed


def prepare_gate(run_id: str) -> dict[str, Any]:
    if run_id != RUN_ID:
        raise RuntimeError("DeepSeek run ID differs from ratified profile")
    prepared = _prepared_gate()
    run_dir = safe_run_dir(run_id, create=True)
    if any(run_dir.iterdir()):
        raise RuntimeError("DeepSeek gate directory is not fresh")
    write_json(run_dir / "operator-gate.json", prepared)
    return prepared


def _validate_gate(run_id: str, *, sealed: bool) -> tuple[Path, dict[str, Any]]:
    if run_id != RUN_ID:
        raise RuntimeError("DeepSeek run ID differs from ratified profile")
    run_dir = safe_run_dir(run_id, create=False)
    if run_dir.is_symlink() or not run_dir.is_dir():
        raise RuntimeError("DeepSeek gate directory is missing or symlinked")
    path = run_dir / "operator-gate.json"
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("DeepSeek gate file is missing or symlinked")
    actual = strict_json_load(path)
    expected = _prepared_gate()
    if sealed:
        expected = _sealed_gate(expected)
    if actual != expected:
        raise RuntimeError("DeepSeek gate differs from the ratified exact source")
    return run_dir, actual


def seal_gate(run_id: str) -> dict[str, Any]:
    run_dir, prepared = _validate_gate(run_id, sealed=False)
    if {path.name for path in run_dir.iterdir()} != {"operator-gate.json"}:
        raise RuntimeError("DeepSeek gate has unexpected evidence before sealing")
    sealed = _sealed_gate(prepared)
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def verify_sealed_gate(run_id: str) -> dict[str, Any]:
    _, gate = _validate_gate(run_id, sealed=True)
    return {
        "status": "valid", "runID": run_id,
        "gateSha256": canonical_hash(gate),
        "authorizationPhrase": gate["authorizationPhrase"],
        "profileSha256": gate["profileSha256"],
        "hardLimitUSD": gate["hardLimitUSD"],
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def _inspect_success(run_dir: Path, position: dict[str, Any], spec: ModelSpec,
                     request: bytes) -> dict[str, Any]:
    last = position["wires"][-1]
    evidence = strict_json_load(run_dir / "wire-evidence" / f"{last['wireID']}.json")
    body = evidence.get("body")
    try:
        if not isinstance(body, dict) or not isinstance(body.get("choices"), list) or len(body["choices"]) != 1:
            raise ValueError("response must have exactly one choice")
        choice = body["choices"][0]
        if choice.get("finish_reason") != "stop":
            raise ValueError("response did not finish normally")
        message = choice["message"]
        if "tool_calls" in message or "function_call" in message:
            raise ValueError("tool calls are not permitted")
        content = message["content"]
        if not isinstance(content, str):
            raise ValueError("content is not a string")
        strategy = strategy_for(spec)
        transport_schema = strategy.schema()
        if not authority_preserved(
            {"requests": [{"body": json.loads(request)}],
             "responses": [{"body": body}]},
            completion=content, spec=spec, transport_schema=transport_schema,
        ):
            raise ValueError("native JSON-schema response authority was not preserved")
        parsed = parse_model_output(content, strict_json_load(MODEL_SCHEMA),
                                    transport_schema, strategy.normalize_output)
        if parsed.get("structure") != "valid":
            raise ValueError("response failed provider and host schema")
    except (AttributeError, KeyError, IndexError, TypeError, ValueError) as error:
        return {"compatibilityPassed": False, "reason": str(error)}
    return {"compatibilityPassed": True, "reason": "native and host schema valid"}


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str,
    api_key_lookup: Callable[[], str | None] | None = None,
) -> dict[str, Any]:
    # The parent verifier rebuilds historical mock evidence using asyncio.run().
    # Keep that synchronous audit outside this live coroutine's event loop.
    run_dir, gate = await asyncio.to_thread(_validate_gate, run_id, sealed=True)
    if authorization != gate["authorizationPhrase"] or spending_limit_usd != gate["hardLimitUSD"]:
        raise RuntimeError("exact DeepSeek live authorization and hard limit are required")
    if any((run_dir / name).exists() for name in ("live-state.json", "wire-ledger.json", "live-catalogue")):
        raise RuntimeError("DeepSeek run instance has already entered live preflight or execution")
    profile, request, spec = await asyncio.to_thread(_ratified)
    live = snapshot_catalogue(
        run_dir / "live-catalogue", (spec,),
        required_parameters=required_parameter_contracts((spec,)),
    )
    compare_catalogues([gate["selectedEndpoint"]], live["selected"])
    if len(live["selected"]) != 1 or type(live["selected"][0].get("status")) is not int or live["selected"][0]["status"] != 0:
        raise RuntimeError("DeepSeek route is not available in the live catalogue")
    endpoint = live["selected"][0]
    for field in ("inputPricePerToken", "outputPricePerToken"):
        value = Decimal(endpoint[field])
        if not value.is_finite() or value < 0 or value > Decimal(gate["selectedEndpoint"][field]):
            raise RuntimeError("DeepSeek live price is invalid or increased")
    one_send = conservative_call_cost(
        input_utf8_bytes=len(request), input_price=endpoint["inputPricePerToken"],
        output_price=endpoint["outputPricePerToken"], output_tokens=spec.max_output_tokens,
    )
    if one_send > Decimal(gate["oneSendConservativeUSD"]) or one_send * 3 > Decimal(spending_limit_usd):
        raise RuntimeError("DeepSeek live cost exceeds the ratified hard limit")
    key = (api_key_lookup or (lambda: os.environ.get("OPENROUTER_API_KEY")))()
    if not isinstance(key, str) or not key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the process environment")
    binding = WireRouteBinding(
        request_sha256=gate["requestSha256"],
        requested_model_id=spec.requested_model_id,
        canonical_revision=spec.canonical_revision,
        provider_endpoint=spec.provider_endpoint,
        reported_provider_name=endpoint["reportedProviderName"],
    )
    sender = OpenRouterOneSend(
        bindings={LOGICAL_ID: binding}, api_key=key,
        timeout=httpx2.Timeout(connect=15, read=180, write=15, pool=15),
    )
    last_send_at: float | None = None

    async def paced_send(logical_id: str, wire_id: str, body: bytes) -> Any:
        nonlocal last_send_at
        now = time.monotonic()
        if last_send_at is not None and now - last_send_at < 2:
            await asyncio.sleep(2 - (now - last_send_at))
        last_send_at = time.monotonic()
        return await asyncio.wait_for(sender.send_once(logical_id, wire_id, body), timeout=180)

    write_json(run_dir / "live-state.json", {
        "runID": run_id, "status": "authorisedBeforeFirstSend",
        "authorisedAt": datetime.now(timezone.utc).isoformat(),
        "authorizationPhrase": authorization, "hardLimitUSD": spending_limit_usd,
        "liveCatalogueSha256": canonical_hash(live),
        "credentialPersisted": False,
    })
    executor = RetryingWireExecutor(
        run_dir=run_dir, evidence_root=RUNS_ROOT,
        profile_sha256=PROFILE_SHA256,
        planned_position_ids=(LOGICAL_ID,),
        hard_limit_usd=spending_limit_usd, policy=POLICY,
        send_once=paced_send,
        redact_evidence=lambda value: redact(value, (key,)),
        sleep=asyncio.sleep, now=lambda: datetime.now(timezone.utc),
    )
    try:
        position = await executor.run_position(
            logical_id=LOGICAL_ID, request_body=request,
            worst_case_usd=gate["oneSendConservativeUSD"],
        )
        checked = (_inspect_success(run_dir, position, spec, request)
                   if position["state"] == "terminalComplete"
                   else {"compatibilityPassed": False, "reason": position["state"]})
    finally:
        sender.api_key = ""
        key = ""
    report = {
        "reportVersion": "paceprompt-host-eval-report/issue145-deepseek-probe-r1",
        "runID": run_id,
        "result": {"logicalID": LOGICAL_ID, "modelID": spec.requested_model_id,
                   "state": position["state"], **checked},
        "scoredHeldoutCalls": 0,
        "providerDecision": "requiresSeparateHumanEvidenceAcceptance",
        "chargedWorstCaseUSD": executor.ledger["chargedUSD"],
    }
    write_json(run_dir / "diagnostic-report.json", report)
    write_json(run_dir / "live-state.json", {
        "runID": run_id, "status": "completeAwaitingHumanEvidenceAcceptance",
        "authorizationPhrase": authorization, "hardLimitUSD": spending_limit_usd,
        "liveCatalogueSha256": canonical_hash(live),
        "credentialPersisted": False,
        "completedAt": datetime.now(timezone.utc).isoformat(),
    })
    write_json(run_dir / "evidence-integrity-audit.json", {
        "runID": run_id,
        "evidenceTreeSha256BeforeAudit": evidence_tree_sha256(run_dir),
        "status": "requiresSeparateExactEvidenceReview",
    })
    return report
