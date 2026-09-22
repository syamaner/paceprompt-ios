"""Fail-closed two-route compatibility probe for the issue #145 full matrix.

Preparation and sealing are local, zero-spend operations. Live execution requires
another, exact-instance operator authorization and never scores held-out cases.
"""

from __future__ import annotations

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
from typing import Any, Callable

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import (
    MODELS, RUN_POLICY, _body_for_case, model_messages,
    required_parameter_contracts, verify as verify_issue145,
)
from .openrouter import load_model_specs
from .runner import compare_catalogues, write_json
from .transport_strategy import strategy_for
from .v3 import (
    HOST_EVAL_ROOT, MODEL_SCHEMA, REPOSITORY_ROOT, V3LiveRun,
    asset_paths, canonical_hash, host_source_tree_hash, load_cases,
    safe_run_dir, sha256_file, strict_json_load,
)

PROPOSAL = HOST_EVAL_ROOT / "issue145-full-matrix-route-probe-proposal-r1.json"
RATIFICATION = HOST_EVAL_ROOT / "issue145-full-matrix-route-probe-ratification-r1.json"
PROPOSAL_SHA256 = "2c4b2a6122a50fd5acc029f9282cd8bd3bb429072afe6b174ed446058715b500"
RATIFICATION_SHA256 = "b879cdd6eec28626d102719ceb02aae4d58e0ef3f729c0318dfba7a323183485"
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/issue145-route-probes-r1"
AUTHORIZATION_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_ROUTE_PROBES_"


def _profile() -> tuple[dict[str, Any], dict[str, Any], tuple[Any, ...]]:
    if sha256_file(PROPOSAL) != PROPOSAL_SHA256 or sha256_file(RATIFICATION) != RATIFICATION_SHA256:
        raise RuntimeError("route-probe proposal or ratification changed")
    proposal, ratification = strict_json_load(PROPOSAL), strict_json_load(RATIFICATION)
    if ratification != {
        "ratificationContractVersion": "paceprompt-issue145-full-matrix-route-probes-ratification/r1",
        "proposalSha256": PROPOSAL_SHA256,
        "ratifiedRunID": proposal["proposedRunID"],
        "parentPreparedRunID": "issue145-full-matrix-v5-20260922-prep01",
        "ratifiedSpendingLimitUSD": proposal["spending"]["recommendedHardLimit"],
        "authority": {
            "zeroSpendRunnerImplementation": True, "zeroSpendGateSealing": True,
            "credentialRead": False, "providerInference": False, "spend": False,
            "liveRun": False, "fullMatrixRun": False, "publication": False,
            "productionChange": False, "release": False, "issueClosure": False,
        },
        "authoritySource": "operator approved the immediately preceding request to ratify the exact two-call proposal and implement and seal its zero-spend gate; separate exact live-run authorization remains required",
    }:
        raise RuntimeError("route-probe ratification is inconsistent with the proposal")
    if verify_issue145()["status"] != "valid":
        raise RuntimeError("parent issue #145 evaluation assets changed")
    if (
        proposal["execution"] != {
            "totalProviderCalls": 2, "globalConcurrency": 1,
            "minimumInterCallDelaySeconds": 2, "maxOutputTokensPerCall": 8192,
            "automaticRetries": 0, "httpConnectRetries": 0,
            "connectTimeoutSeconds": 15, "attemptTimeoutSeconds": 180,
            "resumable": False, "fallbacks": False,
            "stopAfterAnyFailedCompatibilityCall": True, "scoredHeldoutCalls": 0,
        }
        or proposal["warmupCaseID"] != "WI-V3-D020"
        or proposal["spending"]["conservativeWorstCase"] != ratification["ratifiedSpendingLimitUSD"]
        or proposal["spending"]["hardLimitRatified"] is not False
    ):
        raise RuntimeError("route-probe execution or spending profile changed")
    by_id = {spec.requested_model_id: spec for spec in load_model_specs(MODELS)}
    calls = proposal["orderedCalls"]
    expected = ("mistralai/mistral-small-2603", "deepseek/deepseek-v4-flash-0731")
    if tuple(item["requestedModelID"] for item in calls) != expected:
        raise RuntimeError("route-probe model order changed")
    specs = tuple(by_id[model_id] for model_id in expected)
    for item, spec in zip(calls, specs):
        if (item["canonicalRevision"], item["providerEndpoint"]) != (
            spec.canonical_revision, spec.provider_endpoint
        ) or spec.max_output_tokens != 8192:
            raise RuntimeError("route-probe model route or output ceiling changed")
    return proposal, ratification, specs


def _parent_evidence(
    proposal: dict[str, Any], ratification: dict[str, Any], specs: tuple[Any, ...]
) -> tuple[Path, list[dict[str, Any]], dict[str, dict[str, Any]]]:
    parent_dir = safe_run_dir(ratification["parentPreparedRunID"], create=False)
    gate_path = parent_dir / "operator-gate.json"
    if sha256_file(gate_path) != proposal["preparedZeroSpendGateSha256"]:
        raise RuntimeError("prepared full-matrix parent gate changed")
    parent = strict_json_load(gate_path)
    if (
        parent.get("status") != "awaitingReplacementRouteCompatibilityProofAndSpendingRatification"
        or parent.get("providerCalls") != 0
        or parent.get("credentialRead") is not False
        or parent.get("spendUSD") != "0.00"
        or parent.get("authorizationPhrase") is not None
        or parent.get("catalogueSnapshotSha256") != proposal["publicCatalogueSelectedSha256"]
    ):
        raise RuntimeError("parent full-matrix gate crossed the zero-spend boundary")
    catalogue_path = parent_dir / "catalogue" / "selected.json"
    if sha256_file(catalogue_path) != proposal["publicCatalogueSelectedSha256"]:
        raise RuntimeError("parent catalogue snapshot changed")
    catalogue = strict_json_load(catalogue_path)
    selected_by_id = {item["requestedModelID"]: item for item in catalogue["selected"]}
    selected, templates = [], {}
    for item, spec in zip(proposal["orderedCalls"], specs):
        model_id = spec.requested_model_id
        payload_path = parent_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        if (
            sha256_file(payload_path) != item["mockPayloadSha256"]
            or parent["mockPayloadHashes"].get(model_id) != item["mockPayloadSha256"]
        ):
            raise RuntimeError(f"parent mock request changed for {model_id}")
        body = strict_json_load(payload_path)["body"]
        endpoint = selected_by_id[model_id]
        if (
            endpoint["canonicalRevision"] != item["canonicalRevision"]
            or endpoint["providerEndpoint"] != item["providerEndpoint"]
            or endpoint["inputPricePerToken"] != item["inputPricePerTokenUSD"]
            or endpoint["outputPricePerToken"] != item["outputPricePerTokenUSD"]
        ):
            raise RuntimeError(f"parent catalogue route or price changed for {model_id}")
        selected.append(endpoint)
        templates[model_id] = body
    warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                  if case["id"] == proposal["warmupCaseID"])
    _validate_outbound_messages(specs, templates, warmup)
    total = Decimal("0")
    for item, spec in zip(proposal["orderedCalls"], specs):
        body = _body_for_case(templates[spec.requested_model_id], warmup)
        size = len(json.dumps(body, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")).encode("utf-8"))
        cost = conservative_call_cost(
            input_utf8_bytes=size, input_price=item["inputPricePerTokenUSD"],
            output_price=item["outputPricePerTokenUSD"], output_tokens=8192,
        )
        if size != item["completeRequestUTF8Bytes"] or format(cost, "f") != item["conservativeCallUSD"]:
            raise RuntimeError("route-probe request size or cost changed")
        total += cost
    if format(total, "f") != proposal["spending"]["conservativeWorstCase"]:
        raise RuntimeError("route-probe total worst-case cost changed")
    return parent_dir, selected, templates


def _validate_outbound_messages(
    specs: tuple[Any, ...], templates: dict[str, dict[str, Any]], warmup: dict[str, Any]
) -> None:
    for spec in specs:
        actual = [
            {"role": message.role, "content": message.content}
            for message in model_messages(warmup, strategy_for(spec))
        ]
        expected = _body_for_case(templates[spec.requested_model_id], warmup)["messages"]
        if actual != expected:
            raise RuntimeError(
                f"live route-probe messages differ from sealed mock for {spec.requested_model_id}"
            )


def verify() -> dict[str, Any]:
    proposal, ratification, specs = _profile()
    _parent_evidence(proposal, ratification, specs)
    return {
        "status": "valid", "proposalSha256": PROPOSAL_SHA256,
        "ratificationSha256": RATIFICATION_SHA256,
        "runID": ratification["ratifiedRunID"],
        "parentGateSha256": proposal["preparedZeroSpendGateSha256"],
        "callCount": 2, "scoredCalls": 0,
        "ratifiedLimitUSD": ratification["ratifiedSpendingLimitUSD"],
        "liveAuthorized": False,
    }


def _prepared_gate() -> dict[str, Any]:
    proposal, ratification, specs = _profile()
    _, selected, _ = _parent_evidence(proposal, ratification, specs)
    return {
        "gateContractVersion": GATE_CONTRACT,
        "runID": ratification["ratifiedRunID"],
        "status": "awaitingZeroSpendSealing",
        "proposalSha256": PROPOSAL_SHA256,
        "ratificationSha256": RATIFICATION_SHA256,
        "parentRunID": ratification["parentPreparedRunID"],
        "parentGateSha256": proposal["preparedZeroSpendGateSha256"],
        "hostSourceTreeSha256": host_source_tree_hash(),
        "orderedCalls": proposal["orderedCalls"],
        "selectedEndpoints": selected,
        "conservativeWorstCaseUSD": proposal["spending"]["conservativeWorstCase"],
        "providerCalls": 0, "credentialRead": False, "spendUSD": "0.00",
        "ratifiedSpendingLimitUSD": None, "authorizationPhrase": None,
        "requiredBeforeLive": ["separate-exact-run-authorization", "fresh-public-catalogue-route-and-price-preflight"],
    }


def prepare_gate(run_id: str) -> dict[str, Any]:
    expected = _prepared_gate()
    if run_id != expected["runID"]:
        raise RuntimeError("probe run ID is not the ratified exact instance")
    run_dir = safe_run_dir(run_id, create=True)
    write_json(run_dir / "operator-gate.json", expected)
    return expected


def _sealed_gate(prepared: dict[str, Any]) -> dict[str, Any]:
    sealed = deepcopy(prepared)
    sealed["status"] = "awaitingFinalLiveRunAuthorization"
    sealed["ratifiedSpendingLimitUSD"] = prepared["conservativeWorstCaseUSD"]
    sealed["authorizationPhrase"] = AUTHORIZATION_PREFIX + canonical_hash(sealed)[:16].upper()
    return sealed


def _validate_gate(run_id: str, status: str) -> tuple[Path, dict[str, Any]]:
    run_dir = safe_run_dir(run_id, create=False)
    if run_dir.name != run_id:
        raise RuntimeError("probe gate directory differs from run ID")
    gate = strict_json_load(run_dir / "operator-gate.json")
    expected = _prepared_gate()
    if run_id != expected["runID"]:
        raise RuntimeError("probe run ID is not the ratified exact instance")
    comparison = expected if status == "awaitingZeroSpendSealing" else _sealed_gate(expected)
    if gate != comparison or gate.get("status") != status:
        raise RuntimeError("probe gate differs from the exact ratified source and evidence")
    return run_dir, gate


def seal_gate(run_id: str) -> dict[str, Any]:
    run_dir, prepared = _validate_gate(run_id, "awaitingZeroSpendSealing")
    sealed = _sealed_gate(prepared)
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


class RouteProbeRun(V3LiveRun):
    def __init__(self, *, payload_templates: dict[str, dict[str, Any]], **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self.payload_templates = payload_templates

    def worst_case(self, case: dict[str, Any], spec: Any) -> Decimal:
        body = _body_for_case(self.payload_templates[spec.requested_model_id], case)
        size = len(json.dumps(body, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")).encode("utf-8"))
        selected = self.selected[spec.requested_model_id]
        return conservative_call_cost(
            input_utf8_bytes=size, input_price=selected["inputPricePerToken"],
            output_price=selected["outputPricePerToken"], output_tokens=8192,
        )

    async def execute(self) -> dict[str, Any]:
        self.setup()
        await self.save_state("runningCompatibilityProbes")
        results = []
        try:
            for spec in self.specs.values():
                if results and not results[-1].get("compatibilityPassed"):
                    break
                results.append(await self.call(
                    attempt_id=f"warmup-{spec.requested_model_id.replace('/', '--')}",
                    kind="warmup", case=self.warmup, spec=spec, repetition=0,
                ))
        except (asyncio.CancelledError, KeyboardInterrupt):
            await self.save_state("cancelledNonResumable")
            raise
        report = {
            "reportContractVersion": "paceprompt-host-eval-report/issue145-route-probes-r1",
            "runID": self.run_dir.name,
            "orderedModels": list(self.specs),
            "attempts": [
                {"modelID": item["modelID"], "hostClassification": item["hostClassification"],
                 "schemaValid": item["schemaValid"], "compatibilityPassed": item["compatibilityPassed"]}
                for item in results
            ],
            "providerCalls": len(results), "scoredHeldoutCalls": 0,
            "stoppedAfterFailure": bool(results and not results[-1].get("compatibilityPassed")),
            "automaticWinner": None,
            "providerDecision": "requiresSeparateHumanEvidenceAcceptance",
        }
        write_json(self.run_dir / "diagnostic-report.json", report)
        audit = self._evidence_integrity()
        write_json(self.run_dir / "evidence-integrity-audit.json", audit)
        await self.save_state("completeAwaitingHumanEvidenceAcceptance" if audit["passed"]
                              else "completeEvidenceIntegrityFailed")
        return report


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str,
    fetch: Callable[[str], bytes] | None = None,
) -> dict[str, Any]:
    run_dir, gate = _validate_gate(run_id, "awaitingFinalLiveRunAuthorization")
    if (
        authorization != gate["authorizationPhrase"]
        or spending_limit_usd != gate["ratifiedSpendingLimitUSD"]
    ):
        raise RuntimeError("exact route-probe live authorization or spending limit is missing")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable route-probe instance already entered live execution")
    proposal, ratification, specs = _profile()
    _, _, templates = _parent_evidence(proposal, ratification, specs)
    live = snapshot_catalogue(
        run_dir / "live-catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
        **({"fetch": fetch} if fetch else {}),
    )
    compare_catalogues(gate["selectedEndpoints"], live["selected"])
    for before, now in zip(gate["selectedEndpoints"], live["selected"]):
        for key in ("inputPricePerToken", "outputPricePerToken"):
            price = Decimal(now[key])
            if not price.is_finite() or price < 0:
                raise RuntimeError("route-probe live catalogue price is not finite and non-negative")
            if price > Decimal(before[key]):
                raise RuntimeError("route-probe live catalogue price increased")
    warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                  if case["id"] == proposal["warmupCaseID"])
    estimated = sum((conservative_call_cost(
        input_utf8_bytes=len(json.dumps(
            _body_for_case(templates[spec.requested_model_id], warmup),
            ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        ).encode("utf-8")),
        input_price=endpoint["inputPricePerToken"],
        output_price=endpoint["outputPricePerToken"], output_tokens=8192,
    ) for spec, endpoint in zip(specs, live["selected"])), Decimal("0"))
    if estimated > Decimal(spending_limit_usd):
        raise RuntimeError("route-probe live preflight exceeds the ratified hard limit")
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local environment")
    write_json(run_dir / "operator-ratification.json", {
        "runID": run_id, "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "authorizationPhrase": authorization, "spendingLimitUSD": spending_limit_usd,
        "providerCallLimit": 2, "credentialAvailable": True, "credentialPersisted": False,
        "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
        "liveCostPreflightUSD": format(estimated, "f"),
    })
    policy = strict_json_load(RUN_POLICY)
    runner = RouteProbeRun(
        run_dir=run_dir, gate=dict(gate, selectedEndpoints=live["selected"]), api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA), transport_schema=strategy_for(specs[0]).schema(),
        cases=[], development_cases=load_cases(asset_paths()["developmentCases"]),
        queue=[], specs=specs, messages_for_case=model_messages,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=strategy_for(specs[0]).schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id="paceprompt-host-eval-run-policy/issue145-route-probes-r1",
        spending_limit_usd=spending_limit_usd,
        transport_strategy_for_spec=strategy_for,
        warmup_case_id=proposal["warmupCaseID"], require_returned_identity=True,
        host_latency_profile=True, output_limit_is_invalid=True,
        prompt_template_version="workout-import-prompt/issue130-r2",
        payload_templates=templates,
    )
    try:
        return await runner.execute()
    finally:
        runner.api_key = ""
        api_key = ""
