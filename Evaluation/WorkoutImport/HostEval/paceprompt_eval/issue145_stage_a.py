"""Issue #145 zero-spend preparation for the four-model Stage A profile."""

from __future__ import annotations

import asyncio
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import random
from typing import Any, Callable

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import (
    MODELS as TWELVE_MODEL_CONFIG,
    REVIEW_SHA256,
    cost_preflight,
    model_messages,
    mock_payloads,
    required_parameter_contracts,
    scored_strata,
    verify as verify_twelve_model_profile,
)
from .openrouter import load_model_specs
from .runner import compare_catalogues, write_json
from .transport_strategy import ISSUE145_V5_REGISTRY_ID, strategy_for
from .v3 import (
    HOST_EVAL_ROOT,
    MODEL_SCHEMA,
    REPOSITORY_ROOT,
    V3LiveRun,
    aggregate as aggregate_v3,
    asset_paths as v3_asset_paths,
    canonical_hash,
    host_source_tree_hash,
    load_cases,
    RUN_POLICY as V3_RUN_POLICY,
    safe_run_dir,
    sha256_file,
    strict_json_load,
)


MODELS = HOST_EVAL_ROOT / "models-v5-issue145-stage-a.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v5-issue145-stage-a.json"
REVIEW = HOST_EVAL_ROOT / "issue145-stage-a-review-r1.json"
PROPOSAL = HOST_EVAL_ROOT / "issue145-stage-a-proposal-r1.json"
RATIFICATION = HOST_EVAL_ROOT / "issue145-stage-a-ratification-r1.json"
CONSOLIDATED = REPOSITORY_ROOT / "Evaluation" / "WorkoutImport" / "Summaries" / "consolidated-evaluation-data.json"
QUEUE_CONTRACT = "paceprompt-host-eval-queue/issue145-v5-stage-a"
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/issue145-v5-stage-a"
MODELS_SHA256 = "f83a7ef3d59bc575ce50d1a57abd343e0b533bef30ec858bf46a715056caf95e"
RUN_POLICY_SHA256 = "4c2d010c7a32eef1ac05ab31ad5978c572e7b3c4539f52c509ec95e0e32bfcad"
REVIEW_SHA256_STAGE_A = "29fbe1056a8c25267c14005a84a24e24f0787b3adc72ba5e0b1539acceba0974"
PROPOSAL_SHA256 = "9ac554267bb052220f628a8ae97124b135afb6a94d188416df03a1ad92e7bd1f"
RATIFICATION_SHA256 = "637f47732cc3ae9305d2299359df95f03d618ffa45cd27bd09bb4a6ecbe5f4cd"
CONSOLIDATED_SHA256 = "a5648e4dbb0dd22643c775938a400ae8ab3d056592931d80568b535da3c9ce58"
EXPECTED_RANKING = (
    ("openai/gpt-5.6-sol", "99.3817"),
    ("google/gemini-3.7-flash", "98.1422"),
    ("qwen/qwen3.8-27b", "91.9060"),
    ("openai/gpt-5.6-luna", "91.3305"),
)
AUTHORIZATION_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_STAGE_A_"


def _policy() -> dict[str, Any]:
    return strict_json_load(RUN_POLICY)


def _admit_live_cost_preflight(
    preflight: dict[str, Any], spending_limit_usd: str
) -> dict[str, Any]:
    """Bind a successful current-price check to its exact ratified limit."""
    admitted = deepcopy(preflight)
    if Decimal(admitted["estimatedUSD"]) > Decimal(spending_limit_usd):
        raise RuntimeError("current Stage A prices exceed the ratified limit")
    admitted["hardLimitUSD"] = spending_limit_usd
    admitted["admitted"] = True
    admitted["status"] = "admittedUnderExactRatifiedHardLimit"
    return admitted


def _display_percent(value: Any) -> str:
    if isinstance(value, dict):
        return value["displayPercent"]
    return f"{float(value):.4f}"


def _sealed_ranking() -> tuple[tuple[str, str], ...]:
    summary = strict_json_load(CONSOLIDATED)
    candidates: dict[str, dict[str, Any]] = {}
    candidates.update(summary["v3"]["models"])
    candidates.update(summary["v4"]["models"])
    ranked = sorted(
        (
            (model_id, _display_percent(report["metrics"]["weightedComposite"]))
            for model_id, report in candidates.items()
            if model_id in {spec.requested_model_id for spec in load_model_specs(TWELVE_MODEL_CONFIG)}
        ),
        key=lambda item: (-float(item[1]), item[0]),
    )
    return tuple(ranked[:4])


def queue_document() -> dict[str, Any]:
    policy = _policy()
    specs = load_model_specs(MODELS)
    if [spec.requested_model_id for spec in specs] != policy["execution"]["modelOrder"]:
        raise ValueError("issue #145 Stage A model order differs from policy")
    if policy["execution"]["requestedRepetitionsPerStratum"] != 1:
        raise ValueError("issue #145 Stage A is fixed at one repetition")
    entries: list[dict[str, Any]] = []
    seed = policy["execution"]["orderSeedBase"] + 1
    for stratum_id, cases in scored_strata():
        shuffled = list(cases)
        random.Random(seed).shuffle(shuffled)
        for case_index, case in enumerate(shuffled):
            rotation = case_index % len(specs)
            ordered = specs[rotation:] + specs[:rotation]
            for position, spec in enumerate(ordered, start=1):
                entries.append(
                    {
                        "attemptID": (
                            f"{stratum_id}-r01-{case['id']}-"
                            f"{spec.requested_model_id.replace('/', '--')}"
                        ),
                        "stratumID": stratum_id,
                        "repetitionIndex": 1,
                        "caseID": case["id"],
                        "modelID": spec.requested_model_id,
                        "modelPosition": position,
                    }
                )
    material = {
        "runPolicyVersion": policy["runPolicyVersion"],
        "parentCandidateReviewSha256": REVIEW_SHA256,
        "stageAReviewSha256": REVIEW_SHA256_STAGE_A,
        "strata": [
            {
                "id": stratum_id,
                "caseCount": len(cases),
                "caseIDsSha256": canonical_hash([case["id"] for case in cases]),
            }
            for stratum_id, cases in scored_strata()
        ],
        "repetitionsPerStratum": 1,
        "entries": entries,
    }
    return {
        "queueContractVersion": QUEUE_CONTRACT,
        **material,
        "queueSha256": canonical_hash(material),
    }


def verify() -> dict[str, Any]:
    errors: list[str] = []
    parent = verify_twelve_model_profile()
    if parent["status"] != "valid":
        errors.append("preserved twelve-model profile verification failed")
    for path, expected, label in (
        (MODELS, MODELS_SHA256, "models"),
        (RUN_POLICY, RUN_POLICY_SHA256, "run policy"),
        (REVIEW, REVIEW_SHA256_STAGE_A, "review"),
        (PROPOSAL, PROPOSAL_SHA256, "proposal"),
        (RATIFICATION, RATIFICATION_SHA256, "ratification"),
        (CONSOLIDATED, CONSOLIDATED_SHA256, "selection source"),
    ):
        if sha256_file(path) != expected:
            errors.append(f"Stage A {label} hash changed")

    specs = load_model_specs(MODELS)
    parent_by_id = {
        spec.requested_model_id: spec for spec in load_model_specs(TWELVE_MODEL_CONFIG)
    }
    if _sealed_ranking() != EXPECTED_RANKING:
        errors.append("sealed top-four ranking changed")
    if tuple(spec.requested_model_id for spec in specs) != tuple(
        model_id for model_id, _ in EXPECTED_RANKING
    ):
        errors.append("Stage A model order differs from the sealed top four")
    for spec in specs:
        parent_spec = parent_by_id.get(spec.requested_model_id)
        if parent_spec is None:
            errors.append(f"Stage A added non-ratified model {spec.requested_model_id}")
            continue
        comparable = (
            spec.canonical_revision,
            spec.provider_endpoint,
            spec.quantization,
            spec.temperature,
            spec.top_p,
            spec.reasoning,
            spec.max_output_tokens,
            spec.response_contract,
            strategy_for(spec).identifier,
        )
        parent_comparable = (
            parent_spec.canonical_revision,
            parent_spec.provider_endpoint,
            parent_spec.quantization,
            parent_spec.temperature,
            parent_spec.top_p,
            parent_spec.reasoning,
            parent_spec.max_output_tokens,
            parent_spec.response_contract,
            strategy_for(parent_spec).identifier,
        )
        if comparable != parent_comparable:
            errors.append(f"Stage A changed prior profile for {spec.requested_model_id}")
        if spec.transport_registry_id != ISSUE145_V5_REGISTRY_ID:
            errors.append(f"Stage A changed transport registry for {spec.requested_model_id}")

    policy = _policy()
    proposal = strict_json_load(PROPOSAL)
    ratification = strict_json_load(RATIFICATION)
    if policy["generation"]["maxOutputTokens"] != 8192:
        errors.append("Stage A lowered the output ceiling without token evidence")
    if policy["routing"]["replacementRoutes"]:
        errors.append("Stage A must not retain unused replacement routes")
    if policy["stageB"]["automaticContinuation"]:
        errors.append("Stage B must require separate operator ratification")
    if policy["spending"]["hardLimit"] is not None:
        errors.append("Stage A must not preselect a spending limit")

    queue = queue_document() if len(specs) == 4 else None
    if queue is not None:
        model_counts = Counter(item["modelID"] for item in queue["entries"])
        stratum_counts = Counter(item["stratumID"] for item in queue["entries"])
        if len(queue["entries"]) != 436 or set(model_counts.values()) != {109}:
            errors.append("Stage A queue must contain 436 attempts and 109 per model")
        if stratum_counts != {"v3-heldout-regression": 316, "issue130-acceptance-r2": 120}:
            errors.append("Stage A stratum counts changed")
        if proposal["profile"]["queueSha256"] != queue["queueSha256"]:
            errors.append("Stage A proposal does not bind the deterministic queue")
    if proposal["profile"]["modelsSha256"] != MODELS_SHA256:
        errors.append("Stage A proposal does not bind the model configuration")
    if proposal["profile"]["runPolicySha256"] != RUN_POLICY_SHA256:
        errors.append("Stage A proposal does not bind the run policy")
    if proposal["spending"]["hardLimitRatified"]:
        errors.append("Stage A proposal must remain unratified")
    if ratification.get("ratifiedProposalSha256") != PROPOSAL_SHA256:
        errors.append("Stage A ratification does not bind the exact proposal")
    if ratification.get("ratifiedRunID") != proposal.get("proposedRunID"):
        errors.append("Stage A ratification changed the proposed run ID")
    if ratification.get("ratifiedSpendingLimitUSD") != proposal["spending"][
        "recommendedHardLimit"
    ]:
        errors.append("Stage A ratification changed the proposed spending limit")
    if ratification.get("authority") != {
        "zeroSpendGatePreparation": True,
        "gateSealing": True,
        "credentialRead": False,
        "providerInference": False,
        "evaluationSpend": False,
        "liveRun": False,
        "publication": False,
        "productionChange": False,
    }:
        errors.append("Stage A ratification authority boundary changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "models": len(specs),
        "scoredAttempts": len(queue["entries"]) if queue else None,
        "warmups": len(specs),
        "totalProviderCalls": len(queue["entries"]) + len(specs) if queue else None,
        "queueSha256": queue["queueSha256"] if queue else None,
        "configurationHashes": {
            "models": sha256_file(MODELS),
            "runPolicy": sha256_file(RUN_POLICY),
            "review": sha256_file(REVIEW),
            "proposal": sha256_file(PROPOSAL),
            "ratification": sha256_file(RATIFICATION),
            "selectionSource": sha256_file(CONSOLIDATED),
        },
    }


async def prepare_gate(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None
) -> dict[str, Any]:
    verification = verify()
    if verification["status"] != "valid":
        raise RuntimeError(f"issue #145 Stage A verification failed: {verification['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(MODELS)
    snapshot = snapshot_catalogue(
        run_dir / "catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
        **({"fetch": fetch} if fetch else {}),
    )
    write_json(
        run_dir / "catalogue-evidence.json",
        {
            "evidenceType": "readOnlyPublicOpenRouterCatalogueRefresh",
            "providerCalls": 0,
            "credentialRead": False,
            "spendUSD": "0.00",
            "selectedSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        },
    )
    mocks, templates = await mock_payloads(
        run_dir,
        snapshot,
        models_path=MODELS,
        policy_path=RUN_POLICY,
    )
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    preflight = cost_preflight(
        snapshot,
        templates,
        models_path=MODELS,
        policy_path=RUN_POLICY,
    )
    gate = {
        "gateContractVersion": GATE_CONTRACT,
        "runID": run_id,
        "status": "awaitingExactProfileAndSpendingLimitRatification",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "authorizationPhrase": None,
        "ratifiedSpendingLimitUSD": None,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "configurationHashes": verification["configurationHashes"],
        "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "selectedEndpoints": snapshot["selected"],
        "mockPayloadHashes": mocks["payloadHashes"],
        "costPreflight": preflight,
        "profileRatification": strict_json_load(RATIFICATION),
        "stageB": _policy()["stageB"],
        "requiredBeforeLive": [
            "human-ratifies-the-exact-stage-a-profile-hash",
            "human-ratifies-an-exact-hard-spending-limit",
            "a-new-run-instance-binds-the-catalogue-queue-and-spend-cap",
            "local-OPENROUTER_API_KEY-is-available-without-persistence",
            "human-explicitly-authorizes-provider-calls-for-that-run-instance",
        ],
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _payload_templates(run_dir: Path, gate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for model_id, expected_hash in gate["mockPayloadHashes"].items():
        path = run_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        if sha256_file(path) != expected_hash:
            raise RuntimeError(f"sealed mock payload changed for {model_id}")
        templates[model_id] = strict_json_load(path)["body"]
    return templates


def _validate_gate_integrity(
    run_dir: Path, gate: dict[str, Any], *, expected_status: str
) -> dict[str, dict[str, Any]]:
    if gate.get("gateContractVersion") != GATE_CONTRACT:
        raise RuntimeError("gate contract is not issue #145 Stage A")
    if gate.get("status") != expected_status:
        raise RuntimeError(f"gate is not {expected_status}")
    verification = verify()
    if (
        verification["status"] != "valid"
        or verification["configurationHashes"] != gate.get("configurationHashes")
    ):
        raise RuntimeError("Stage A assets differ from the prepared gate")
    if gate.get("hostSourceTreeSha256") != host_source_tree_hash():
        raise RuntimeError("HostEval source changed after gate preparation")
    queue = queue_document()
    queue_path = run_dir / "planned-queue.json"
    if strict_json_load(queue_path) != queue:
        raise RuntimeError("planned queue differs from the canonical Stage A queue")
    if (
        gate.get("queueSha256") != queue["queueSha256"]
        or gate.get("plannedQueueFileSha256") != sha256_file(queue_path)
    ):
        raise RuntimeError("Stage A queue hashes changed")
    catalogue_path = run_dir / "catalogue" / "selected.json"
    catalogue = strict_json_load(catalogue_path)
    if (
        gate.get("catalogueSnapshotSha256") != sha256_file(catalogue_path)
        or gate.get("selectedEndpoints") != catalogue.get("selected")
    ):
        raise RuntimeError("Stage A catalogue evidence changed")
    if gate.get("profileRatification") != strict_json_load(RATIFICATION):
        raise RuntimeError("Stage A ratification differs from the gate")
    if (
        gate.get("providerCalls") != 0
        or gate.get("credentialRead") is not False
        or gate.get("spendUSD") != "0.00"
    ):
        raise RuntimeError("Stage A gate crossed the zero-spend boundary")
    templates = _payload_templates(run_dir, gate)
    current = cost_preflight(
        {"selected": gate["selectedEndpoints"]},
        templates,
        models_path=MODELS,
        policy_path=RUN_POLICY,
    )
    if expected_status == "awaitingExactProfileAndSpendingLimitRatification":
        if (
            gate.get("authorizationPhrase") is not None
            or gate.get("ratifiedSpendingLimitUSD") is not None
            or gate.get("costPreflight") != current
        ):
            raise RuntimeError("prepared Stage A spending gate changed")
        return templates
    limit_text = gate.get("ratifiedSpendingLimitUSD")
    try:
        limit = Decimal(limit_text)
    except (InvalidOperation, TypeError, ValueError):
        raise RuntimeError("sealed Stage A spending limit is invalid") from None
    expected = dict(current)
    expected.update(
        {
            "hardLimitUSD": limit_text,
            "admitted": True,
            "status": "admittedBySeparatelyRatifiedLimit",
        }
    )
    if (
        limit != Decimal(strict_json_load(RATIFICATION)["ratifiedSpendingLimitUSD"])
        or limit < Decimal(current["estimatedUSD"])
        or gate.get("costPreflight") != expected
    ):
        raise RuntimeError("sealed Stage A spending gate changed")
    return templates


def seal_gate(run_id: str) -> dict[str, Any]:
    ratification = strict_json_load(RATIFICATION)
    if run_id != ratification["ratifiedRunID"]:
        raise RuntimeError("Stage A run ID is not the ratified run instance")
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    _validate_gate_integrity(
        run_dir,
        gate,
        expected_status="awaitingExactProfileAndSpendingLimitRatification",
    )
    limit_text = ratification["ratifiedSpendingLimitUSD"]
    if Decimal(limit_text) < Decimal(gate["costPreflight"]["estimatedUSD"]):
        raise RuntimeError("ratified limit is below the prepared Stage A worst case")
    sealed = deepcopy(gate)
    sealed["status"] = "awaitingFinalLiveRunAuthorization"
    sealed["ratifiedSpendingLimitUSD"] = limit_text
    sealed["costPreflight"].update(
        {
            "hardLimitUSD": limit_text,
            "admitted": True,
            "status": "admittedBySeparatelyRatifiedLimit",
        }
    )
    material = deepcopy(sealed)
    material["authorizationPhrase"] = None
    sealed["authorizationPhrase"] = (
        AUTHORIZATION_PREFIX + canonical_hash(material)[:16].upper()
    )
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def _body_for_case(template: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    from .v3 import user_message

    body = deepcopy(template)
    messages = body.get("messages", [])
    if not messages or messages[-1].get("role") != "user":
        raise RuntimeError("sealed Stage A payload lacks its final user message")
    messages[-1]["content"] = user_message(case)
    return body


def _prices_do_not_increase(
    prepared: list[dict[str, Any]], current: list[dict[str, Any]]
) -> None:
    prior = {item["requestedModelID"]: item for item in prepared}
    for endpoint in current:
        before = prior[endpoint["requestedModelID"]]
        for key in ("inputPricePerToken", "outputPricePerToken"):
            if Decimal(endpoint[key]) > Decimal(before[key]):
                raise RuntimeError(
                    f"live Stage A catalogue {key} increased for "
                    f"{endpoint['requestedModelID']}"
                )


def _stage_a_aggregate(
    attempts: list[dict[str, Any]],
    specs: tuple[Any, ...],
    run_dir: Path,
) -> dict[str, Any]:
    diagnostic_policy = deepcopy(strict_json_load(V3_RUN_POLICY))
    diagnostic_policy["execution"]["requestedRepetitions"] = 1
    diagnostic_policy["categoryFloors"]["majorityCorrectAttempts"] = 1
    diagnostic_policy["categoryFloors"]["majorityRepetitions"] = 1
    strata_reports: dict[str, Any] = {}
    for stratum_id, cases in scored_strata():
        ids = {case["id"] for case in cases}
        selected_attempts = [
            item
            for item in attempts
            if item.get("kind") == "scored" and item.get("caseID") in ids
        ]
        report = aggregate_v3(selected_attempts, cases, specs, diagnostic_policy)
        report["stageADiagnosticOnly"] = True
        report["eligibleModels"] = []
        report["automaticWinner"] = None
        for model in report["models"].values():
            model["decisionEligible"] = False
            model["ineligibilityReasons"] = sorted(
                set(model["ineligibilityReasons"] + ["singleRepetitionStageAOnly"])
            )
        strata_reports[stratum_id] = report

    token_evidence: dict[str, list[int]] = {spec.requested_model_id: [] for spec in specs}
    for attempt in attempts:
        if attempt.get("kind") not in {"warmup", "scored"}:
            continue
        path = run_dir / "framework-logs" / f"{attempt['attemptID']}.json"
        if not path.is_file():
            continue
        usage = strict_json_load(path).get("usage") or {}
        value = usage.get("output_tokens")
        if isinstance(value, int) and value >= 0:
            token_evidence[attempt["modelID"]].append(value)
    token_report = {
        model_id: {
            "reportedAttempts": len(values),
            "maximumOutputTokens": max(values) if values else None,
            "values": values,
        }
        for model_id, values in token_evidence.items()
    }
    scored = [item for item in attempts if item.get("kind") == "scored"]
    readiness: dict[str, Any] = {}
    for spec in specs:
        model_items = [item for item in scored if item.get("modelID") == spec.requested_model_id]
        complete = [
            item for item in model_items if item.get("hostClassification") == "modelQuality"
        ]
        warmup = next(
            (
                item
                for item in attempts
                if item.get("kind") == "warmup"
                and item.get("modelID") == spec.requested_model_id
            ),
            None,
        )
        readiness[spec.requested_model_id] = {
            "warmupPassed": bool(warmup and warmup.get("compatibilityPassed")),
            "completionCoverage": {
                "completed": len(complete),
                "scheduled": 109,
            },
            "completionCoverageAtLeast095": len(complete) * 100 >= 109 * 95,
            "rateLimitPaused": any(
                item.get("reasonCategory") in {"rateLimited", "rateLimitPause"}
                for item in model_items
            ),
            "outputLimitFailure": any(
                item.get("providerFinishReason") in {"length", "max_tokens"}
                for item in model_items
            ),
        }
    return {
        "reportContractVersion": "paceprompt-host-eval-report/issue145-v5-stage-a",
        "stage": "A",
        "strata": strata_reports,
        "stageBReadiness": readiness,
        "reportedOutputTokenEvidence": token_report,
        "automaticContinuation": False,
        "automaticWinner": None,
        "providerDecision": "requiresSeparateHumanRatification",
    }


class StageALiveRun(V3LiveRun):
    def __init__(
        self, *, payload_templates: dict[str, dict[str, Any]], **kwargs: Any
    ) -> None:
        super().__init__(**kwargs)
        self.payload_templates = payload_templates

    def worst_case(self, case: dict[str, Any], spec: Any) -> Decimal:
        body = _body_for_case(self.payload_templates[spec.requested_model_id], case)
        body_bytes = len(
            json.dumps(
                body,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        )
        selected = self.selected[spec.requested_model_id]
        return conservative_call_cost(
            input_utf8_bytes=body_bytes,
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
                    kind="warmup",
                    case=self.warmup,
                    spec=spec,
                    repetition=0,
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
                        attempt_id=item["attemptID"],
                        kind="scored",
                        case=self.cases[item["caseID"]],
                        spec=self.specs[model_id],
                        repetition=item["repetitionIndex"],
                    )
                except Exception as error:
                    from .task import SpendingLimitReached

                    if not isinstance(error, SpendingLimitReached):
                        raise
                    self._not_started(item, "spendingLimitReached")
                    for remaining in self.queue[index + 1 :]:
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
                await asyncio.wait_for(
                    self.save_state("cancelledNonResumable"),
                    timeout=self.cancel_flush_seconds,
                )
            except TimeoutError:
                pass
            raise
        report = _stage_a_aggregate(
            self.attempts,
            tuple(self.specs.values()),
            self.run_dir,
        )
        write_json(self.run_dir / "aggregate-report.json", report)
        audit = self._evidence_integrity()
        audit["auditContractVersion"] = (
            "paceprompt-host-eval-evidence-integrity/issue145-v5-stage-a"
        )
        write_json(self.run_dir / "evidence-integrity-audit.json", audit)
        await self.save_state(
            "completeEvidenceMechanicallyAccepted"
            if audit["passed"]
            else "completeEvidenceIntegrityFailed"
        )
        return report


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    templates = _validate_gate_integrity(
        run_dir,
        gate,
        expected_status="awaitingFinalLiveRunAuthorization",
    )
    if (
        authorization != gate.get("authorizationPhrase")
        or spending_limit_usd != gate.get("ratifiedSpendingLimitUSD")
    ):
        raise RuntimeError("exact Stage A authorization or spending limit is missing")
    material = deepcopy(gate)
    material["authorizationPhrase"] = None
    if authorization != AUTHORIZATION_PREFIX + canonical_hash(material)[:16].upper():
        raise RuntimeError("Stage A gate changed after authorization was sealed")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable Stage A run already entered live execution")
    specs = load_model_specs(MODELS)
    live = snapshot_catalogue(
        run_dir / "live-catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
    )
    compare_catalogues(gate["selectedEndpoints"], live["selected"])
    _prices_do_not_increase(gate["selectedEndpoints"], live["selected"])
    live_preflight = _admit_live_cost_preflight(
        cost_preflight(
            live,
            templates,
            models_path=MODELS,
            policy_path=RUN_POLICY,
        ),
        spending_limit_usd,
    )
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 440,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
        },
    )
    paths = v3_asset_paths()
    cases = [case for _, stratum_cases in scored_strata() for case in stratum_cases]
    runner = StageALiveRun(
        run_dir=run_dir,
        gate=dict(gate, selectedEndpoints=live["selected"]),
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
        execution_policy=_policy()["execution"],
        run_configuration_id=_policy()["runPolicyVersion"],
        spending_limit_usd=spending_limit_usd,
        transport_strategy_for_spec=strategy_for,
        warmup_case_id=_policy()["dataset"]["warmupCaseID"],
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
