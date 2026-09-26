"""Separately authorised, serial issue #145 Together r4 matrix execution.

This module has no import-time network or credential access. A live call requires
the exact sealed gate phrase and cap. It never publishes or selects a production model.
"""

from __future__ import annotations

import argparse
import asyncio
from copy import deepcopy
from dataclasses import replace
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
import time
from typing import Any, Callable

import httpx2

from .catalogue import snapshot_catalogue
from .issue145 import (
    BASETEN_DUPLICATE_ALLOWLIST, RUN_POLICY, required_parameter_contracts,
    scored_strata,
)
from .issue145_11model_together_gate import (
    HARD_LIMIT_USD, PROPOSED_ROOT_RUN_ID, cases_by_id, checked_run_dir, model_specs,
    planned_calls, ratified_profile, verify_sealed_child_gate,
    verify_sealed_gate,
)
from .issue145_lineage import usd
from .issue145_retry import RetryPolicy
from .issue145_retry_execution import RetryingWireExecutor, evidence_tree_sha256
from .issue145_wire_adapter import OpenRouterOneSend, WireRouteBinding
from .openrouter import ModelSpec, redact
from .runner import (
    affected_paths_equal, authority_preserved, compare_catalogues,
    completed_content, git_head, parse_completed_output, write_json,
)
from .scorer_adapter import (
    ScorerFailure, normalized_document, provider_outcome, score_completed,
)
from .transport_strategy import strategy_for
from .v3 import (
    MODEL_SCHEMA, REPOSITORY_ROOT, RUNS_ROOT, RUN_POLICY as V3_RUN_POLICY,
    aggregate as aggregate_v3, canonical_hash,
    strict_json_load,
)


POLICY = RetryPolicy(3, frozenset({429, 502, 503, 504, 524, 529}),
                     (30, 120), 900, 900)


class CompletionPacer:
    """Keep the frozen two-second interval after each physical send finishes."""

    def __init__(self, sender: OpenRouterOneSend, *,
                 now: Callable[[], float] = time.monotonic,
                 sleep: Callable[[float], Any] = asyncio.sleep) -> None:
        self.sender = sender
        self.now = now
        self.sleep = sleep
        self.last_finished_at: float | None = None

    async def send_once(self, logical_id: str, wire_id: str, body: bytes) -> Any:
        if self.last_finished_at is not None:
            remaining = 2 - (self.now() - self.last_finished_at)
            if remaining > 0:
                await self.sleep(remaining)
        started = self.now()
        try:
            response = await asyncio.wait_for(
                self.sender.send_once(logical_id, wire_id, body), timeout=180,
            )
        finally:
            self.last_finished_at = self.now()
        elapsed = max(0, round((self.last_finished_at - started) * 1000))
        return replace(response, evidence={
            **response.evidence, "providerLatencyMilliseconds": elapsed,
        })


def _conservative_charges(gate: dict[str, Any], ledger: dict[str, Any]) -> tuple[str, str]:
    instance = usd(ledger["chargedUSD"])
    prior = usd(gate.get("priorChargedUSD", "0"))
    cumulative = prior + instance
    if cumulative > usd(HARD_LIMIT_USD):
        raise RuntimeError("lineage charge exceeds ratified cumulative cap")
    return format(instance, "f"), format(cumulative, "f")


def _diagnostic_stratum_report(
    attempts: list[dict[str, Any]], cases: list[dict[str, Any]],
    specs: tuple[ModelSpec, ...], policy: dict[str, Any],
) -> dict[str, Any]:
    report = aggregate_v3(attempts, cases, specs, policy)
    report["diagnosticOnly"] = True
    report["automaticWinner"] = None
    cost_available = all(
        item["observedScoredCostUSD"] is not None
        for item in report["models"].values()
    )
    report["costTieBreakAvailable"] = cost_available
    if not cost_available:
        report["tieBreakTrace"] = None
    return report


def _completion(
    run_dir: Path, position: dict[str, Any], spec: ModelSpec,
    request: bytes,
) -> tuple[dict[str, Any], bool]:
    wire_id = position["wires"][-1]["wireID"]
    body = strict_json_load(run_dir / "wire-evidence" / f"{wire_id}.json").get("body")
    if not isinstance(body, dict):
        raise ValueError("successful wire has no response object")
    exchange = {"requests": [{"body": json.loads(request)}],
                "responses": [{"body": body}]}
    strategy = strategy_for(spec)
    content = completed_content(exchange, None, spec)
    preserved = authority_preserved(exchange, content, spec, strategy.schema())
    return ({"content": content, "finishReason": body.get("choices", [{}])[0].get("finish_reason"),
             "body": body, "exchange": exchange}, preserved)


def _warmup_passed(
    run_dir: Path, position: dict[str, Any], spec: ModelSpec, request: bytes,
) -> bool:
    if position["state"] != "terminalComplete":
        return False
    try:
        completed, preserved = _completion(run_dir, position, spec, request)
        strategy = strategy_for(spec)
        observed = parse_completed_output(
            completed["content"], strict_json_load(MODEL_SCHEMA),
            strategy.schema(), strategy.normalize_output,
            finish_reason=completed["finishReason"], output_limit_is_invalid=True,
        )
        return preserved and completed["finishReason"] == "stop" and observed["structure"] == "valid"
    except (KeyError, IndexError, TypeError, ValueError):
        return False


def _failure_reason(position: dict[str, Any]) -> str:
    if position["state"] == "terminalPossiblySent":
        return "incompleteResponse"
    if position["state"] == "terminalBudgetStop":
        return "invocationFailure"
    wire = position["wires"][-1]
    if wire["state"] == "returnedRouteMismatch":
        return "routingMismatch"
    status = wire.get("statusCode")
    if status in {401, 403}:
        return "authenticationFailure"
    if status == 429:
        return "rateLimited"
    if isinstance(status, int) and status >= 400:
        return "httpFailure"
    return "invocationFailure"


def _score_one(
    run_dir: Path, call: dict[str, Any], position: dict[str, Any],
    request: bytes, spec: ModelSpec, app_commit: str,
) -> dict[str, Any]:
    case = cases_by_id()[call["caseID"]]
    result = {key: call[key] for key in (
        "attemptID", "kind", "caseID", "modelID", "stratumID", "repetitionIndex",
    )}
    result["status"] = position["state"]
    result["terminal"] = True
    reported = [wire.get("reportedCostUSD") for wire in position["wires"]]
    result["reportedCostUSD"] = (
        format(sum((usd(value) for value in reported), Decimal("0")), "f")
        if reported and all(isinstance(value, str) for value in reported)
        else None
    )
    if position["state"] == "terminalComplete":
        try:
            last_wire = position["wires"][-1]["wireID"]
            evidence = strict_json_load(run_dir / "wire-evidence" / f"{last_wire}.json")
            latency = evidence.get("providerLatencyMilliseconds")
            result["providerLatencyMilliseconds"] = (
                latency if type(latency) is int and latency >= 0 else None
            )
            completed, preserved = _completion(run_dir, position, spec, request)
            strategy = strategy_for(spec)
            observed = parse_completed_output(
                completed["content"], strict_json_load(MODEL_SCHEMA),
                strategy.schema(), strategy.normalize_output,
                finish_reason=completed["finishReason"], output_limit_is_invalid=True,
            )
            result["authorityPreserved"] = preserved
            result["schemaValid"] = observed["structure"] == "valid"
            result["hostClassification"] = "modelQuality"
            if result["schemaValid"]:
                expected = case["expected"]["modelOutput"]["outcome"]
                actual = observed["outcome"]
                result["authorityPreserved"] = preserved and actual["type"] not in {
                    "providerUnavailable", "providerFailure",
                }
                result.update({
                    "expectedOutcomeType": expected["type"],
                    "actualOutcomeType": actual["type"],
                    "outcomeExact": expected["type"] == actual["type"],
                    "expectedReasonCategory": expected.get("reasonCategory"),
                    "actualReasonCategory": actual.get("reasonCategory"),
                    "reasonExact": expected.get("reasonCategory") == actual.get("reasonCategory"),
                    "pathsExact": affected_paths_equal(expected, actual),
                })
        except (KeyError, IndexError, TypeError, ValueError):
            observed = provider_outcome("providerFailure", "responseDecodingFailure")
            result["hostClassification"] = "infrastructure"
            result["schemaValid"] = None
            result["reasonCategory"] = "responseDecodingFailure"
    else:
        reason = _failure_reason(position)
        observed = provider_outcome("providerFailure", reason)
        result["hostClassification"] = "infrastructure"
        result["schemaValid"] = None
        result["reasonCategory"] = reason
    document = normalized_document(
        case=case, observed=observed, run_id=run_dir.name,
        result_id=call["attemptID"], repetition_index=call["repetitionIndex"],
        app_commit=app_commit, model_id=spec.requested_model_id,
        model_revision=spec.canonical_revision, provider_id=spec.provider_endpoint,
        run_configuration_id=strict_json_load(RUN_POLICY)["runPolicyVersion"],
        prompt_template_version="workout-import-prompt/issue130-r2",
    )
    projection = run_dir / "projections" / call["attemptID"]
    try:
        report = score_completed(projection_root=projection, case=case, document=document)
        case_result = report["caseResults"][0]
        result["scorerOverall"] = case_result["overall"]
        result["pipelineClassification"] = case_result["pipelineClassification"]
        if result.get("schemaValid"):
            rules = case_result["rules"]
            result["proposalFidelity"] = (
                rules["statedValueFidelity"]["status"] == "passed"
                and rules["stepOrderFidelity"]["status"] == "passed"
            )
            result["mappingValidatorAgreement"] = (
                rules["localValidatorOutcome"]["status"] == "passed"
            )
    except ScorerFailure as error:
        report = error.report
        result["hostClassification"] = "scorerFailure"
        result["scorerOverall"] = "scorerFailure"
        result["pipelineClassification"] = "scorerFailure"
    write_json(run_dir / "normalized-results" / f"{call['attemptID']}.json", document)
    write_json(run_dir / "scorer-reports" / f"{call['attemptID']}.json", report)
    return result


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str,
    api_key_lookup: Callable[[], str | None] | None = None,
    source_repair_seals: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """Execute one exact root or manually prepared descendant once."""
    # Historical profile verification invokes a synchronous mock coroutine.
    verifier = verify_sealed_gate if run_id == PROPOSED_ROOT_RUN_ID else verify_sealed_child_gate
    checked = await asyncio.to_thread(
        verifier, run_id, repair_seals=source_repair_seals,
    )
    if (authorization != checked["authorizationPhrase"]
            or spending_limit_usd != HARD_LIMIT_USD):
        raise RuntimeError("exact reviewed eleven-model live authorization and cap required")
    run_dir = checked_run_dir(run_id, create=False)
    if any((run_dir / item).exists() for item in (
        "live-state.json", "wire-ledger.json", "live-catalogue",
    )):
        raise RuntimeError("root instance has already entered live preflight")
    profile, queue = await asyncio.to_thread(ratified_profile)
    specs = model_specs(profile)
    gate = strict_json_load(run_dir / "operator-gate.json")
    selected = strict_json_load(run_dir / "catalogue" / "selected.json")
    with TemporaryDirectory(prefix="paceprompt-live-catalogue-") as temporary:
        catalogue_dir = Path(temporary) / "catalogue"
        live = snapshot_catalogue(
            catalogue_dir, specs,
            required_parameters=required_parameter_contracts(specs),
            allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        )
        compare_catalogues(selected["selected"], live["selected"])
        old_prices = {item["requestedModelID"]: item for item in selected["selected"]}
        new_prices = {item["requestedModelID"]: item for item in live["selected"]}
        for spec in specs:
            current = new_prices[spec.requested_model_id]
            if type(current.get("status")) is not int or current["status"] != 0:
                raise RuntimeError("a ratified endpoint is unavailable")
            for field in ("inputPricePerToken", "outputPricePerToken"):
                value = Decimal(current[field])
                if (not value.is_finite() or value < 0
                        or value > Decimal(old_prices[spec.requested_model_id][field])):
                    raise RuntimeError("public price is invalid or increased")
        # This is the first credential access in the entire gate/run path.
        key = (api_key_lookup or (lambda: os.environ.get("OPENROUTER_API_KEY")))()
        if not isinstance(key, str) or not key:
            raise RuntimeError("OPENROUTER_API_KEY is absent from the process environment")
        # A rejected public-only preflight or absent key leaves the root reusable.
        shutil.copytree(catalogue_dir, run_dir / "live-catalogue")
    calls = strict_json_load(run_dir / "planned-calls.json")
    templates = {spec.requested_model_id: strict_json_load(
        run_dir / "mock-payloads" / f"{spec.requested_model_id.replace('/', '--')}.json"
    )["body"] for spec in specs}
    rebuilt, requests = planned_calls(profile, queue, templates, selected["selected"])
    rebuilt_by_id = {item["attemptID"]: item for item in rebuilt}
    if (calls != [rebuilt_by_id[item["attemptID"]] for item in calls]
            or len(calls) != gate["maximumLogicalPositions"]):
        raise RuntimeError("planned request mapping changed")
    spec_by_model = {spec.requested_model_id: spec for spec in specs}
    bindings = {item["attemptID"]: WireRouteBinding(
        request_sha256=item["requestSha256"],
        requested_model_id=item["modelID"],
        canonical_revision=spec_by_model[item["modelID"]].canonical_revision,
        provider_endpoint=spec_by_model[item["modelID"]].provider_endpoint,
        reported_provider_name=new_prices[item["modelID"]]["reportedProviderName"],
    ) for item in calls}
    sender = OpenRouterOneSend(
        bindings=bindings, api_key=key,
        timeout=httpx2.Timeout(connect=15, read=180, write=15, pool=15),
    )
    pacer = CompletionPacer(sender)

    write_json(run_dir / "live-state.json", {
        "runID": run_id, "status": "authorisedBeforeFirstSend",
        "authorizationPhrase": authorization, "hardLimitUSD": spending_limit_usd,
        "sourceRepairSeals": source_repair_seals or gate.get("sourceRepairSeals", []),
        "liveCatalogueSha256": canonical_hash(live),
        "credentialPersisted": False,
    })
    executor = RetryingWireExecutor(
        run_dir=run_dir, evidence_root=RUNS_ROOT,
        profile_sha256=profile["profileSha256"],
        planned_position_ids=tuple(item["attemptID"] for item in calls),
        hard_limit_usd=gate.get("instanceHardLimitUSD", spending_limit_usd), policy=POLICY,
        send_once=pacer.send_once, redact_evidence=lambda value: redact(value, (key,)),
        sleep=asyncio.sleep, now=lambda: datetime.now(timezone.utc),
    )
    (run_dir / "normalized-results").mkdir()
    (run_dir / "scorer-reports").mkdir()
    (run_dir / "projections").mkdir()
    (run_dir / "position-results").mkdir()
    admitted: set[str] = set()
    paused: set[str] = set()
    remaining_reason = "operatorCancelled"
    ancestor_results: dict[str, dict[str, Any]] = {}
    for seal in gate.get("ancestorSeals", []):
        ancestor = checked_run_dir(seal["runID"], create=False)
        ledger = strict_json_load(ancestor / "wire-ledger.json")
        old_calls = {item["attemptID"]: item for item in
                     strict_json_load(ancestor / "planned-calls.json")}
        for prior in ledger["positions"]:
            if (prior["state"] == "terminalFailure" and prior["wires"]
                    and prior["wires"][-1].get("statusCode") == 429):
                paused.add(old_calls[prior["logicalID"]]["modelID"])
            result_path = ancestor / "position-results" / f"{prior['logicalID']}.json"
            if result_path.exists():
                previous = strict_json_load(result_path)
                ancestor_results[prior["logicalID"]] = previous
                if previous.get("kind") == "warmup" and previous.get("compatibilityPassed") is True:
                    admitted.add(previous["modelID"])
                if (previous.get("reasonCategory") == "rateLimited"
                        and previous.get("modelID") is not None):
                    paused.add(previous["modelID"])
            elif prior["state"] == "terminalComplete" and prior["logicalID"].startswith("warmup-"):
                # A crash after the durable wire but before the result projection
                # must not silently turn a passing warm-up into a new send.
                old_call = old_calls[prior["logicalID"]]
                model_id = old_call["modelID"]
                if _warmup_passed(ancestor, prior, spec_by_model[model_id],
                                  requests[prior["logicalID"]]):
                    admitted.add(model_id)
            elif not result_path.exists() and (prior["state"] != "inProgress" or prior["wires"]):
                old_call = old_calls[prior["logicalID"]]
                if old_call["kind"] == "scored":
                    ancestor_results[prior["logicalID"]] = {
                        **{key: old_call[key] for key in (
                            "attemptID", "kind", "caseID", "modelID",
                            "stratumID", "repetitionIndex",
                        )},
                        "status": (
                            "notStarted" if prior["state"] == "terminalSkipped"
                            else "terminalUnprojected"
                        ),
                        "hostClassification": "infrastructure",
                        "terminal": True,
                        "reasonCategory": (
                            prior.get("reasonCategory", "priorTerminalResultMissing")
                        ),
                    }
    app_commit = git_head(REPOSITORY_ROOT)
    try:
        for call in calls:
            model_id = call["modelID"]
            if call["kind"] == "scored" and model_id not in admitted:
                position = executor.skip_position(
                    logical_id=call["attemptID"], reason="prerequisiteMismatch",
                )
            elif model_id in paused:
                position = executor.skip_position(
                    logical_id=call["attemptID"], reason="rateLimited",
                )
            else:
                position = await executor.run_position(
                    logical_id=call["attemptID"],
                    request_body=requests[call["attemptID"]],
                    worst_case_usd=call["oneSendWorstCaseUSD"],
                )
            if call["kind"] == "warmup":
                passed = _warmup_passed(
                    run_dir, position, spec_by_model[model_id], requests[call["attemptID"]],
                )
                if passed:
                    admitted.add(model_id)
                result = {"attemptID": call["attemptID"], "kind": "warmup",
                          "modelID": model_id, "status": position["state"],
                          "compatibilityPassed": passed}
            elif position["state"] == "terminalSkipped":
                result = {"attemptID": call["attemptID"], "kind": "scored",
                          "caseID": call["caseID"], "stratumID": call["stratumID"],
                          "repetitionIndex": call["repetitionIndex"],
                          "modelID": model_id, "status": "notStarted",
                          "terminal": True,
                          "reasonCategory": (
                              "rateLimitPause" if position["reasonCategory"] == "rateLimited"
                              else position["reasonCategory"]
                          )}
            else:
                result = _score_one(
                    run_dir, call, position, requests[call["attemptID"]],
                    spec_by_model[model_id], app_commit,
                )
            write_json(run_dir / "position-results" / f"{call['attemptID']}.json", result)
            if position["state"] == "terminalFailure" and _failure_reason(position) == "rateLimited":
                paused.add(model_id)
            if (position["state"] == "terminalFailure"
                    and _failure_reason(position) == "authenticationFailure"):
                remaining_reason = "authorizationMissing"
                break
            if position["state"] == "terminalBudgetStop":
                remaining_reason = "spendingLimitReached"
                break
    finally:
        sender.api_key = ""
        key = ""
    saved = dict(ancestor_results)
    saved.update({path.stem: strict_json_load(path) for path in
                  (run_dir / "position-results").glob("*.json")})
    scored_results = []
    for call in rebuilt:
        if call["kind"] != "scored":
            continue
        result = saved.get(call["attemptID"])
        if result is None:
            result = {key: call[key] for key in (
                "attemptID", "kind", "caseID", "modelID", "stratumID",
                "repetitionIndex",
            )}
            result.update(status="notStarted", terminal=True,
                          reasonCategory=remaining_reason)
        scored_results.append(result)
    policy = deepcopy(strict_json_load(V3_RUN_POLICY))
    stratum_reports: dict[str, Any] = {}
    for stratum_id, cases in scored_strata():
        report = _diagnostic_stratum_report(
            [item for item in scored_results if item["stratumID"] == stratum_id],
            cases, specs, policy,
        )
        stratum_reports[stratum_id] = report
    aggregate_report = {
        "reportContractVersion": "paceprompt-host-eval-report/issue145-11model-together-r4-r1",
        "fixedScoredDenominator": 3597,
        "strata": stratum_reports,
        "automaticWinner": None,
        "providerDecision": "requiresSeparateHumanEvidenceAcceptance",
    }
    write_json(run_dir / "aggregate-report.json", aggregate_report)
    write_json(run_dir / "stratum-reports.json", stratum_reports)
    instance_charge, cumulative_charge = _conservative_charges(gate, executor.ledger)
    report = {
        "reportVersion": "paceprompt-host-eval-report/issue145-11model-together-r4-r1",
        "runID": run_id, "profileSha256": profile["profileSha256"],
        "queueSha256": queue["queueSha256"],
        "fixedScoredDenominator": 3597,
        "positionResults": len(saved),
        "instanceChargedConservativeUSD": instance_charge,
        "cumulativeChargedConservativeUSD": cumulative_charge,
        "status": "requiresSeparateEvidenceAuditAndHumanDecision",
        "productionSelection": None,
    }
    write_json(run_dir / "diagnostic-report.json", report)
    write_json(run_dir / "live-state.json", {
        "runID": run_id, "status": "completeAwaitingHumanEvidenceAcceptance",
        "authorizationPhrase": authorization, "hardLimitUSD": spending_limit_usd,
        "sourceRepairSeals": source_repair_seals or gate.get("sourceRepairSeals", []),
        "liveCatalogueSha256": canonical_hash(live),
        "credentialPersisted": False,
    })
    write_json(run_dir / "evidence-integrity-audit.json", {
        "runID": run_id,
        "evidenceTreeSha256BeforeAudit": evidence_tree_sha256(run_dir),
        "status": "requiresSeparateExactEvidenceReview",
    })
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Exact-authorisation issue #145 Together r4 matrix runner")
    parser.add_argument("--live", action="store_true", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--authorization", required=True)
    parser.add_argument("--spending-limit-usd", required=True)
    parser.add_argument("--source-repair-seal", action="append", default=[])
    args = parser.parse_args()
    repairs = []
    for item in args.source_repair_seal:
        parts = item.rsplit(":", 1)
        if len(parts) != 2:
            parser.error("source repair seal must have path and SHA-256")
        repairs.append({"path": parts[0], "sha256": parts[1]})
    report = asyncio.run(run_live(
        run_id=args.run_id, authorization=args.authorization,
        spending_limit_usd=args.spending_limit_usd,
        source_repair_seals=repairs or None,
    ))
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
