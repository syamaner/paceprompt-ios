"""Separately authorised, non-resumable r3 replacement-route warm-ups only."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
import time
from typing import Any, Callable

import httpx2

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import _body_for_case, required_parameter_contracts
from .issue145_full_matrix_r3 import RATIFICATION as MATRIX_RATIFICATION
from .issue145_r3_route_probe_profile import (
    ORDERED_MODELS, RATIFICATION, verify_probe_ratification,
)
from .issue145_retry import RetryPolicy
from .issue145_retry_execution import RetryingWireExecutor, evidence_tree_sha256
from .issue145_wire_adapter import OpenRouterOneSend, WireRouteBinding
from .openrouter import ModelSpec, redact
from .runner import authority_preserved, compare_catalogues, write_json
from .scorer_adapter import parse_model_output
from .transport_strategy import strategy_for
from .v3 import (
    MODEL_SCHEMA, RUNS_ROOT, asset_paths, canonical_hash, host_source_tree_hash,
    load_cases, safe_run_dir, strict_json_load,
)


RUN_ID = "issue145-r3-route-probes-20260924-01"
GATE_VERSION = "paceprompt-host-eval-operator-gate/issue145-r3-route-probes-r1"
AUTH_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_R3_ROUTE_PROBES_"
POLICY = RetryPolicy(3, frozenset({429, 502, 503, 504, 524, 529}), (30, 120), 900, 900)


def _parent() -> tuple[dict[str, Any], dict[str, Any], list[ModelSpec], dict[str, Any]]:
    checked = verify_probe_ratification()
    if checked["status"] != "valid":
        raise RuntimeError(f"r3 probe ratification invalid: {checked['errors']}")
    ratification = strict_json_load(RATIFICATION)
    parent_dir = safe_run_dir(ratification["preparedRunID"], create=False)
    proposal = strict_json_load(parent_dir / "r3-route-probe-proposal.json")
    matrix_ratification = strict_json_load(MATRIX_RATIFICATION)
    matrix_dir = safe_run_dir(matrix_ratification["preparedRunID"], create=False)
    models = strict_json_load(matrix_dir / "models-r3-materialized.json")
    catalogue = strict_json_load(matrix_dir / "catalogue" / "selected.json")
    by_model = {item["requestedModelID"]: ModelSpec.from_json(item) for item in models["models"]}
    specs = [by_model[model_id] for model_id in ORDERED_MODELS]
    selected = {item["requestedModelID"]: item for item in catalogue["selected"]}
    return ratification, proposal, specs, selected


def _request_bytes(proposal: dict[str, Any]) -> dict[str, bytes]:
    parent_id = strict_json_load(MATRIX_RATIFICATION)["preparedRunID"]
    matrix_dir = safe_run_dir(parent_id, create=False)
    warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                  if case["id"] == "WI-V3-D020")
    result: dict[str, bytes] = {}
    for call in proposal["orderedCalls"]:
        model_id = call["requestedModelID"]
        template = strict_json_load(
            matrix_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        )["body"]
        body = _body_for_case(template, warmup)
        if body.get("provider", {}).get("allow_fallbacks") is not False:
            raise RuntimeError("probe fallback control changed")
        if body["provider"].get("data_collection") != "deny":
            raise RuntimeError("probe data-collection control changed")
        if model_id == ORDERED_MODELS[0] and "zdr" in body["provider"]:
            raise RuntimeError("r3 Mistral probe unexpectedly requires ZDR")
        encoded = json.dumps(body, ensure_ascii=False, sort_keys=True,
                             separators=(",", ":")).encode("utf-8")
        if len(encoded) != call["requestUTF8Bytes"]:
            raise RuntimeError("probe request size changed")
        result[call["logicalID"]] = encoded
    return result


def _prepared_gate() -> dict[str, Any]:
    ratification, proposal, specs, selected = _parent()
    requests = _request_bytes(proposal)
    calls = proposal["orderedCalls"]
    if (tuple(call["requestedModelID"] for call in calls) != ORDERED_MODELS
            or len(calls) != 2 or proposal["scoredHeldoutCalls"] != 0):
        raise RuntimeError("probe queue changed")
    return {
        "gateVersion": GATE_VERSION, "runID": RUN_ID,
        "status": "awaitingZeroSpendSealing",
        "hostSourceTreeSha256": host_source_tree_hash(),
        "ratificationSha256": verify_probe_ratification()["ratificationSha256"],
        "proposalSha256": ratification["proposalSha256"],
        "parentPreparedEvidenceTreeSha256": ratification["supportingPreparedEvidenceTreeSha256"],
        "orderedCalls": calls,
        "requestSha256": {key: hashlib.sha256(value).hexdigest()
                          for key, value in requests.items()},
        "selectedEndpoints": [selected[model_id] for model_id in ORDERED_MODELS],
        "hardLimitUSD": ratification["probeHardLimitUSD"],
        "maximumPhysicalSends": 6, "scoredHeldoutCalls": 0,
        "authorizationPhrase": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "routeCompatibilityProof": None,
    }


def _sealed_gate(prepared: dict[str, Any]) -> dict[str, Any]:
    sealed = dict(prepared)
    sealed["status"] = "awaitingFinalLiveRunAuthorization"
    sealed["authorizationPhrase"] = AUTH_PREFIX + canonical_hash(sealed)[:16].upper()
    return sealed


def prepare_gate(run_id: str) -> dict[str, Any]:
    if run_id != RUN_ID:
        raise RuntimeError("r3 probe run ID differs from the proposed exact instance")
    gate = _prepared_gate()
    run_dir = safe_run_dir(run_id, create=True)
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _validate_gate(run_id: str, *, sealed: bool) -> tuple[Any, dict[str, Any]]:
    if run_id != RUN_ID:
        raise RuntimeError("r3 probe run ID changed")
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    expected = _prepared_gate()
    if sealed:
        expected = _sealed_gate(expected)
    if gate != expected:
        raise RuntimeError("r3 probe gate differs from the ratified exact source")
    return run_dir, gate


def seal_gate(run_id: str) -> dict[str, Any]:
    run_dir, prepared = _validate_gate(run_id, sealed=False)
    sealed = _sealed_gate(prepared)
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def _inspect_success(
    run_dir: Any, position: dict[str, Any], spec: ModelSpec, request_body: bytes
) -> dict[str, Any]:
    last = position["wires"][-1]
    evidence = strict_json_load(run_dir / "wire-evidence" / f"{last['wireID']}.json")
    body = evidence.get("body")
    try:
        choice = body["choices"][0]
        if choice.get("finish_reason") != "stop":
            raise ValueError("response did not finish normally")
        content = choice["message"]["content"]
        if not isinstance(content, str):
            raise ValueError("content is not a string")
        strategy = strategy_for(spec)
        transport_schema = strategy.schema()
        if not authority_preserved(
            {"requests": [{"body": json.loads(request_body)}],
             "responses": [{"body": body}]},
            completion=content, spec=spec, transport_schema=transport_schema,
        ):
            raise ValueError("native JSON-schema response authority was not preserved")
        observed = parse_model_output(content, strict_json_load(MODEL_SCHEMA),
                                      transport_schema, strategy.normalize_output)
        if observed.get("structure") != "valid":
            raise ValueError("response failed provider and host schema")
    except (KeyError, IndexError, TypeError, ValueError) as error:
        return {"compatibilityPassed": False, "reason": str(error)}
    return {"compatibilityPassed": True, "reason": "native and host schema valid"}


def _complete_probe_results(
    ordered_calls: list[dict[str, Any]], attempted: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Keep every scheduled warm-up visible even when an earlier one stops the run."""
    if [item["logicalID"] for item in attempted] != [
        item["logicalID"] for item in ordered_calls[:len(attempted)]
    ]:
        raise ValueError("probe results are not a prefix of the frozen queue")
    results = list(attempted)
    for call in ordered_calls[len(attempted):]:
        results.append({
            "logicalID": call["logicalID"], "modelID": call["requestedModelID"],
            "state": "notStarted", "compatibilityPassed": False,
            "reason": "earlier route warm-up failed",
        })
    return results


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str,
    fetch: Callable[[str], bytes] | None = None,
    api_key_lookup: Callable[[], str | None] | None = None,
) -> dict[str, Any]:
    run_dir, gate = _validate_gate(run_id, sealed=True)
    if authorization != gate["authorizationPhrase"] or spending_limit_usd != gate["hardLimitUSD"]:
        raise RuntimeError("exact r3 probe live authorization and hard limit are required")
    if any((run_dir / name).exists() for name in ("live-state.json", "wire-ledger.json")):
        raise RuntimeError("r3 probe instance has already entered live execution")
    _, proposal, specs, _ = _parent()
    live = snapshot_catalogue(
        run_dir / "live-catalogue", tuple(specs),
        required_parameters=required_parameter_contracts(tuple(specs)),
        **({"fetch": fetch} if fetch else {}),
    )
    compare_catalogues(gate["selectedEndpoints"], live["selected"])
    requests = _request_bytes(proposal)
    selected = {item["requestedModelID"]: item for item in live["selected"]}
    for call in gate["orderedCalls"]:
        endpoint = selected[call["requestedModelID"]]
        before = gate["selectedEndpoints"][ORDERED_MODELS.index(call["requestedModelID"])]
        for field in ("inputPricePerToken", "outputPricePerToken"):
            value = Decimal(endpoint[field])
            if not value.is_finite() or value < 0 or value > Decimal(before[field]):
                raise RuntimeError("r3 probe live price is invalid or increased")
        cost = conservative_call_cost(
            input_utf8_bytes=len(requests[call["logicalID"]]),
            input_price=endpoint["inputPricePerToken"],
            output_price=endpoint["outputPricePerToken"], output_tokens=specs[
                ORDERED_MODELS.index(call["requestedModelID"])
            ].max_output_tokens,
        )
        if cost > Decimal(call["oneSendWorstCaseUSD"]):
            raise RuntimeError("r3 probe worst-case send price increased")
    key = (api_key_lookup or (lambda: os.environ.get("OPENROUTER_API_KEY")))()
    if not key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the process environment")
    bindings = {}
    for call in gate["orderedCalls"]:
        endpoint = selected[call["requestedModelID"]]
        bindings[call["logicalID"]] = WireRouteBinding(
            request_sha256=gate["requestSha256"][call["logicalID"]],
            requested_model_id=call["requestedModelID"],
            canonical_revision=call["canonicalRevision"],
            provider_endpoint=call["providerEndpoint"],
            reported_provider_name=endpoint["reportedProviderName"],
        )
    sender = OpenRouterOneSend(
        bindings=bindings, api_key=key,
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
        profile_sha256=gate["proposalSha256"],
        planned_position_ids=tuple(call["logicalID"] for call in gate["orderedCalls"]),
        hard_limit_usd=spending_limit_usd, policy=POLICY,
        send_once=paced_send,
        redact_evidence=lambda value: redact(value, (key,)),
        sleep=asyncio.sleep, now=lambda: datetime.now(timezone.utc),
    )
    results = []
    try:
        for call, spec in zip(gate["orderedCalls"], specs):
            position = await executor.run_position(
                logical_id=call["logicalID"],
                request_body=requests[call["logicalID"]],
                worst_case_usd=call["oneSendWorstCaseUSD"],
            )
            checked = (_inspect_success(run_dir, position, spec,
                                        requests[call["logicalID"]])
                       if position["state"] == "terminalComplete"
                       else {"compatibilityPassed": False, "reason": position["state"]})
            results.append({"logicalID": call["logicalID"], "modelID": call["requestedModelID"],
                            "state": position["state"], **checked})
            if not checked["compatibilityPassed"]:
                break
    finally:
        sender.api_key = ""
        key = ""
    report = {
        "reportVersion": "paceprompt-host-eval-report/issue145-r3-route-probes-r1",
        "runID": run_id, "results": _complete_probe_results(gate["orderedCalls"], results),
        "scoredHeldoutCalls": 0, "providerDecision": "requiresSeparateHumanEvidenceAcceptance",
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
        "runID": run_id, "evidenceTreeSha256BeforeAudit": evidence_tree_sha256(run_dir),
        "status": "requiresSeparateExactEvidenceReview",
    })
    return report
