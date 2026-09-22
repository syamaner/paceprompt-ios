"""Bounded, route-pinned GPT-5.6 Sol versus GPT-6 Sol workout-import run."""

from __future__ import annotations

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import random
import sys
from typing import Any, Callable

_REPOSITORY_IMPORT_ROOT = Path(__file__).resolve().parents[4]
if str(_REPOSITORY_IMPORT_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPOSITORY_IMPORT_ROOT))

from Evaluation.WorkoutImport.Acceptance.verify_v3 import verify as verify_acceptance

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import (
    cost_preflight,
    mock_payloads,
    model_messages,
    required_parameter_contracts,
    scored_strata,
)
from .openrouter import load_model_specs
from .runner import compare_catalogues, write_json
from .transport_strategy import SOL_COMPARISON_REGISTRY_ID, strategy_for
from .v3 import (
    HOST_EVAL_ROOT,
    MODEL_SCHEMA,
    REPOSITORY_ROOT,
    RUN_POLICY as V3_RUN_POLICY,
    V3LiveRun,
    aggregate as aggregate_v3,
    asset_paths,
    canonical_hash,
    host_source_tree_hash,
    load_cases,
    safe_run_dir,
    sha256_file,
    strict_json_load,
    user_message,
)


MODELS = HOST_EVAL_ROOT / "models-v1-sol-comparison.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v1-sol-comparison.json"
PROMPT = REPOSITORY_ROOT / "PacePrompt" / "Import" / "ImportResources" / "system-issue130-r2.md"
SCORER = REPOSITORY_ROOT / "Evaluation" / "WorkoutImport" / "Scoring" / "scorer.py"
TRANSPORT_SCHEMA = (
    HOST_EVAL_ROOT / "schemas" / "v2.3" / "workout-import-provider-transport-v2.3.schema.json"
)
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/sol-comparison-v1"
EXPECTED_MODELS = ("openai/gpt-5.6-sol", "openai/gpt-6-sol")
RUN_ID = "sol56-vs-sol6-20260922-01"


def policy() -> dict[str, Any]:
    return strict_json_load(RUN_POLICY)


def verify() -> dict[str, Any]:
    selected = policy()
    specs = load_model_specs(MODELS)
    errors: list[str] = []
    if tuple(spec.requested_model_id for spec in specs) != EXPECTED_MODELS:
        errors.append("the paired model set or order changed")
    if selected["execution"]["modelOrder"] != list(EXPECTED_MODELS):
        errors.append("run policy model order changed")
    if (
        selected["execution"]["requestedRepetitionsPerStratum"] != 1
        or selected["execution"]["scoredAttempts"] != 218
        or selected["execution"]["warmups"] != 2
        or selected["execution"]["totalProviderCalls"] != 220
    ):
        errors.append("one-pass comparison count changed")
    if any(spec.transport_registry_id != SOL_COMPARISON_REGISTRY_ID for spec in specs):
        errors.append("a model left the pinned comparison route registry")
    for spec in specs:
        if (
            spec.provider_endpoint != "openai"
            or spec.reasoning != {"enabled": False, "effort": "none", "exclude": False}
            or spec.response_contract != "nativeJsonSchema"
            or set(spec.required_parameters)
            != {"max_tokens", "response_format", "structured_outputs"}
        ):
            errors.append(f"{spec.requested_model_id} generation or route controls changed")
    if any(spec.max_output_tokens != selected["generation"]["maxOutputTokens"] for spec in specs):
        errors.append("model output ceiling differs from run policy")
    for spec in specs:
        try:
            strategy = strategy_for(spec)
            if sha256_file(strategy.schema_path) != selected["sealedInputs"]["transportSchemaSha256"]:
                errors.append(f"{spec.requested_model_id} transport schema changed")
        except ValueError as error:
            errors.append(str(error))
    for key, path in (
        ("productionPromptSha256", PROMPT),
        ("scorerSha256", SCORER),
        ("transportSchemaSha256", TRANSPORT_SCHEMA),
        ("v3HeldoutCasesSha256", asset_paths()["heldoutCases"]),
    ):
        if sha256_file(path) != selected["sealedInputs"][key]:
            errors.append(f"{key} differs from the sealed input")
    strata = scored_strata()
    acceptance = verify_acceptance(HOST_EVAL_ROOT.parent)
    if (
        acceptance["status"] != "valid"
        or acceptance.get("corpusHash")
        != selected["sealedInputs"]["issue130AcceptanceCorpusSha256"]
    ):
        errors.append("issue #130 acceptance corpus differs from its sealed revision")
    if [(name, len(cases)) for name, cases in strata] != [
        (item["id"], item["caseCount"]) for item in selected["dataset"]["scoredStrata"]
    ]:
        errors.append("case strata changed")
    if selected["execution"]["totalProviderCalls"] != (
        selected["execution"]["warmups"] + selected["execution"]["scoredAttempts"]
    ):
        errors.append("provider call count is inconsistent")
    if selected["spending"]["proposedHardLimitUSD"] != "26.00":
        errors.append("proposed hard spending limit changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "modelCount": len(specs),
        "caseCount": sum(len(cases) for _, cases in strata),
        "configurationHashes": {
            "models": sha256_file(MODELS),
            "runPolicy": sha256_file(RUN_POLICY),
        },
    }


def queue_document() -> dict[str, Any]:
    selected = policy()
    entries: list[dict[str, Any]] = []
    for stratum_id, cases in scored_strata():
        for repetition in range(1, selected["execution"]["requestedRepetitionsPerStratum"] + 1):
            shuffled = list(cases)
            random.Random(selected["execution"]["orderSeedBase"] + repetition).shuffle(shuffled)
            for case_index, case in enumerate(shuffled):
                ordered = EXPECTED_MODELS if (case_index + repetition) % 2 else EXPECTED_MODELS[::-1]
                for position, model_id in enumerate(ordered, start=1):
                    entries.append({
                        "attemptID": f"{stratum_id}-r{repetition:02d}-{case['id']}-{model_id.replace('/', '--')}",
                        "stratumID": stratum_id,
                        "repetitionIndex": repetition,
                        "caseID": case["id"],
                        "modelID": model_id,
                        "modelPosition": position,
                    })
    if len(entries) != selected["execution"]["scoredAttempts"]:
        raise ValueError("planned scored count differs from policy")
    if len({entry["attemptID"] for entry in entries}) != len(entries):
        raise ValueError("planned attempt IDs are not unique")
    material = {
        "queueContractVersion": "paceprompt-host-eval-queue/sol-comparison-v1",
        "modelsSha256": sha256_file(MODELS),
        "runPolicySha256": sha256_file(RUN_POLICY),
        "entries": entries,
    }
    return dict(material, queueSha256=canonical_hash(material))


async def prepare_gate(run_id: str = RUN_ID, *, fetch: Callable[[str], bytes] | None = None) -> dict[str, Any]:
    check = verify()
    if check["status"] != "valid":
        raise RuntimeError(f"comparison profile invalid: {check['errors']}")
    if run_id != RUN_ID:
        raise RuntimeError("run ID differs from the versioned proposal")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(MODELS)
    catalogue = snapshot_catalogue(
        run_dir / "catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
        **({"fetch": fetch} if fetch else {}),
    )
    mocks, templates = await mock_payloads(
        run_dir, catalogue, models_path=MODELS, policy_path=RUN_POLICY
    )
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    preflight = cost_preflight(catalogue, templates, models_path=MODELS, policy_path=RUN_POLICY)
    gate = {
        "gateContractVersion": GATE_CONTRACT,
        "runID": run_id,
        "status": "awaitingProfileAndSpendingLimitRatification",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "configurationHashes": check["configurationHashes"],
        "hostSourceTreeSha256": host_source_tree_hash(),
        "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "selectedEndpoints": catalogue["selected"],
        "mockPayloadHashes": mocks["payloadHashes"],
        "costPreflight": preflight,
        "ratifiedSpendingLimitUSD": None,
        "authorizationPhrase": None,
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _templates(run_dir: Path, gate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for model_id, expected_hash in gate["mockPayloadHashes"].items():
        path = run_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        if sha256_file(path) != expected_hash:
            raise RuntimeError(f"mock payload changed for {model_id}")
        templates[model_id] = strict_json_load(path)["body"]
    return templates


def validate_gate(run_dir: Path, gate: dict[str, Any], *, status: str) -> dict[str, dict[str, Any]]:
    if gate.get("gateContractVersion") != GATE_CONTRACT or gate.get("runID") != RUN_ID or run_dir.name != RUN_ID:
        raise RuntimeError("gate does not bind this exact comparison run")
    if gate.get("status") != status:
        raise RuntimeError(f"gate is not {status}")
    check = verify()
    if check["status"] != "valid" or check["configurationHashes"] != gate.get("configurationHashes"):
        raise RuntimeError("comparison inputs differ from the prepared gate")
    if gate.get("hostSourceTreeSha256") != host_source_tree_hash():
        raise RuntimeError("host evaluation source changed after gate preparation")
    queue_path = run_dir / "planned-queue.json"
    queue = queue_document()
    if strict_json_load(queue_path) != queue or sha256_file(queue_path) != gate.get("plannedQueueFileSha256"):
        raise RuntimeError("prepared queue changed")
    if gate.get("queueSha256") != queue["queueSha256"]:
        raise RuntimeError("prepared queue hash changed")
    catalogue_path = run_dir / "catalogue" / "selected.json"
    catalogue = strict_json_load(catalogue_path)
    if sha256_file(catalogue_path) != gate.get("catalogueSnapshotSha256") or catalogue["selected"] != gate.get("selectedEndpoints"):
        raise RuntimeError("prepared catalogue changed")
    if gate.get("providerCalls") != 0 or gate.get("credentialRead") is not False or gate.get("spendUSD") != "0.00":
        raise RuntimeError("prepared gate crossed the zero-spend boundary")
    templates = _templates(run_dir, gate)
    current = cost_preflight(catalogue, templates, models_path=MODELS, policy_path=RUN_POLICY)
    if status == "awaitingProfileAndSpendingLimitRatification":
        if gate.get("costPreflight") != current or gate.get("ratifiedSpendingLimitUSD") is not None or gate.get("authorizationPhrase") is not None:
            raise RuntimeError("unratified gate changed")
    else:
        limit = gate.get("ratifiedSpendingLimitUSD")
        if not isinstance(limit, str) or Decimal(limit) < Decimal(current["estimatedUSD"]):
            raise RuntimeError("sealed spending limit is invalid")
        expected = dict(current, hardLimitUSD=limit, admitted=True, status="admittedByOperator")
        if gate.get("costPreflight") != expected:
            raise RuntimeError("sealed spending preflight changed")
        material = dict(gate, authorizationPhrase=None)
        if gate.get("authorizationPhrase") != "AUTHORIZE_PACEPROMPT_SOL_COMPARE_" + canonical_hash(material)[:16].upper():
            raise RuntimeError("sealed authorization phrase changed")
    return templates


def seal_gate(run_id: str, spending_limit_usd: str) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    validate_gate(run_dir, gate, status="awaitingProfileAndSpendingLimitRatification")
    if spending_limit_usd != policy()["spending"]["proposedHardLimitUSD"]:
        raise RuntimeError("spending limit differs from the ratified profile")
    if Decimal(spending_limit_usd) < Decimal(gate["costPreflight"]["estimatedUSD"]):
        raise RuntimeError("spending limit is below the conservative preflight")
    sealed = deepcopy(gate)
    sealed["status"] = "awaitingExactLiveAuthorization"
    sealed["ratifiedSpendingLimitUSD"] = spending_limit_usd
    sealed["costPreflight"].update(hardLimitUSD=spending_limit_usd, admitted=True, status="admittedByOperator")
    material = dict(sealed, authorizationPhrase=None)
    sealed["authorizationPhrase"] = "AUTHORIZE_PACEPROMPT_SOL_COMPARE_" + canonical_hash(material)[:16].upper()
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def _diagnostic_aggregate(attempts: list[dict[str, Any]], specs: tuple[Any, ...]) -> dict[str, Any]:
    scoring_policy = deepcopy(strict_json_load(V3_RUN_POLICY))
    repetitions = policy()["execution"]["requestedRepetitionsPerStratum"]
    scoring_policy["execution"]["requestedRepetitions"] = repetitions
    scoring_policy["categoryFloors"]["majorityCorrectAttempts"] = repetitions
    scoring_policy["categoryFloors"]["majorityRepetitions"] = repetitions
    strata: dict[str, Any] = {}
    for stratum_id, cases in scored_strata():
        ids = {case["id"] for case in cases}
        scoped = [item for item in attempts if item.get("kind") == "scored" and item.get("caseID") in ids]
        result = aggregate_v3(scoped, cases, specs, scoring_policy)
        result["automaticWinner"] = None
        result["eligibleModels"] = []
        result["comparisonDiagnosticOnly"] = True
        for model in result["models"].values():
            model["decisionEligible"] = False
            model["ineligibilityReasons"] = sorted(
                set(model["ineligibilityReasons"] + ["oneRepetitionDiagnosticOnly"])
            )
        strata[stratum_id] = result
    return {
        "reportContractVersion": "paceprompt-host-eval-report/sol-comparison-v1",
        "runID": RUN_ID,
        "strata": strata,
        "automaticWinner": None,
        "decision": "requiresHumanEvidenceReview",
    }


class SolComparisonLiveRun(V3LiveRun):
    def __init__(self, *, payload_templates: dict[str, dict[str, Any]], **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self.payload_templates = payload_templates

    def worst_case(self, case: dict[str, Any], spec: Any) -> Decimal:
        body = deepcopy(self.payload_templates[spec.requested_model_id])
        body["messages"][-1]["content"] = user_message(case)
        size = len(json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
        selected = self.selected[spec.requested_model_id]
        return conservative_call_cost(
            input_utf8_bytes=size,
            input_price=selected["inputPricePerToken"],
            output_price=selected["outputPricePerToken"],
            output_tokens=spec.max_output_tokens,
        )

    async def execute(self) -> dict[str, Any]:
        self.setup()
        admitted: set[str] = set()
        paused: set[str] = set()
        try:
            await self.save_state("runningWarmups")
            for spec in self.specs.values():
                result = await self.call(
                    attempt_id=f"warmup-{spec.requested_model_id.replace('/', '--')}",
                    kind="warmup", case=self.warmup, spec=spec, repetition=0,
                )
                if result.get("reasonCategory") == "rateLimited":
                    paused.add(spec.requested_model_id)
                elif result.get("compatibilityPassed"):
                    admitted.add(spec.requested_model_id)
            await self.save_state("runningScoredMatrix")
            for index, item in enumerate(self.queue):
                model_id = item["modelID"]
                if model_id in paused:
                    self._not_started(item, "rateLimitPause")
                    continue
                if model_id not in admitted:
                    self._not_started(item, "prerequisiteMismatch")
                    continue
                try:
                    result = await self.call(
                        attempt_id=item["attemptID"], kind="scored",
                        case=self.cases[item["caseID"]], spec=self.specs[model_id],
                        repetition=item["repetitionIndex"],
                    )
                except Exception as error:
                    from .task import SpendingLimitReached
                    if not isinstance(error, SpendingLimitReached):
                        raise
                    self._not_started(item, "spendingLimitReached")
                    for remaining in self.queue[index + 1:]:
                        self._not_started(remaining, "spendingLimitReached")
                    break
                if result.get("reasonCategory") == "rateLimited":
                    paused.add(model_id)
        except Exception as error:
            from .task import SpendingLimitReached
            if not isinstance(error, SpendingLimitReached):
                raise
            terminal = {item["attemptID"] for item in self.attempts}
            for item in self.queue:
                if item["attemptID"] not in terminal:
                    self._not_started(item, "spendingLimitReached")
            await self.save_state("runtimeSpendingLimitReached")
        except (asyncio.CancelledError, KeyboardInterrupt):
            terminal = {item["attemptID"] for item in self.attempts}
            for item in self.queue:
                if item["attemptID"] not in terminal:
                    self._not_started(item, "operatorCancelled")
            try:
                await asyncio.wait_for(self.save_state("cancelledNonResumable"), timeout=self.cancel_flush_seconds)
            except TimeoutError:
                pass
            raise
        report = _diagnostic_aggregate(self.attempts, tuple(self.specs.values()))
        write_json(self.run_dir / "aggregate-report.json", report)
        audit = self._evidence_integrity()
        audit["auditContractVersion"] = "paceprompt-host-eval-evidence-integrity/sol-comparison-v1"
        write_json(self.run_dir / "evidence-integrity-audit.json", audit)
        await self.save_state("completeEvidenceMechanicallyAccepted" if audit["passed"] else "completeEvidenceIntegrityFailed")
        return report


async def run_live(*, run_id: str, authorization: str, spending_limit_usd: str) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    templates = validate_gate(run_dir, gate, status="awaitingExactLiveAuthorization")
    if authorization != gate["authorizationPhrase"] or spending_limit_usd != gate["ratifiedSpendingLimitUSD"]:
        raise RuntimeError("exact comparison authorization or spending limit is missing")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable comparison already entered live execution")
    specs = load_model_specs(MODELS)
    live_catalogue = snapshot_catalogue(
        run_dir / "live-catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
    )
    compare_catalogues(gate["selectedEndpoints"], live_catalogue["selected"])
    for before, now in zip(gate["selectedEndpoints"], live_catalogue["selected"], strict=True):
        for price in ("inputPricePerToken", "outputPricePerToken"):
            if Decimal(now[price]) > Decimal(before[price]):
                raise RuntimeError("live catalogue price increased after preparation")
    live_cost = cost_preflight(live_catalogue, templates, models_path=MODELS, policy_path=RUN_POLICY)
    if Decimal(live_cost["estimatedUSD"]) > Decimal(spending_limit_usd):
        raise RuntimeError("current catalogue exceeds the ratified hard spending limit")
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local environment")
    write_json(run_dir / "operator-ratification.json", {
        "runID": run_id,
        "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "authorizationPhrase": authorization,
        "spendingLimitUSD": spending_limit_usd,
        "providerCallLimit": policy()["execution"]["totalProviderCalls"],
        "credentialAvailable": True,
        "credentialPersisted": False,
        "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
        "liveCostPreflight": dict(live_cost, hardLimitUSD=spending_limit_usd, admitted=True),
    })
    selected = policy()
    paths = asset_paths()
    cases = [case for _, stratum_cases in scored_strata() for case in stratum_cases]
    runner = SolComparisonLiveRun(
        run_dir=run_dir,
        gate=dict(gate, selectedEndpoints=live_catalogue["selected"]),
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=strategy_for(specs[0]).schema(),
        cases=cases,
        development_cases=load_cases(paths["developmentCases"]),
        queue=queue_document()["entries"],
        specs=specs,
        messages_for_case=model_messages,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=strategy_for(specs[0]).schema_file_bytes(),
        execution_policy=selected["execution"],
        run_configuration_id=selected["runPolicyVersion"],
        spending_limit_usd=spending_limit_usd,
        transport_strategy_for_spec=strategy_for,
        warmup_case_id=selected["dataset"]["warmupCaseID"],
        require_returned_identity=True,
        host_latency_profile=True,
        output_limit_is_invalid=True,
        prompt_template_version="workout-import-prompt/issue130-r2",
        payload_templates=templates,
    )
    try:
        return await runner.execute()
    finally:
        runner.api_key = ""
        api_key = ""
