"""Issue #17 open-weight evaluation over the immutable v3 prompt and corpus."""

from __future__ import annotations

import asyncio
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal
from fractions import Fraction
import json
import os
from pathlib import Path
import random
from typing import Any, Callable

from .catalogue import conservative_call_cost, snapshot_catalogue
from .openrouter import (
    FORCED_TOOL_ARGUMENTS,
    NATIVE_JSON_SCHEMA,
    ModelSpec,
    assert_payload_controls,
    capture_wire_payload,
    load_model_specs,
)
from .runner import compare_catalogues, write_json
from .transport_strategy import (
    TransportStrategyID,
    V4_OPEN_WEIGHT_REGISTRY_ID,
    strategy_for,
)
from .v3 import (
    HOST_EVAL_ROOT,
    MODEL_SCHEMA,
    REPOSITORY_ROOT,
    V3LiveRun,
    aggregate as aggregate_v3,
    asset_paths as v3_asset_paths,
    canonical_hash,
    load_cases,
    model_messages_for_strategy,
    safe_run_dir,
    sha256_file,
    verify as verify_v3,
)


MODELS = HOST_EVAL_ROOT / "models-v4-open-weight.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v4-open-weight.json"
AUTHORIZATION_PREFIX = "AUTHORIZE_PACEPROMPT_OPEN_WEIGHT_EVAL_V4_"
GATE_CONTRACT = "paceprompt-host-eval-open-weight-operator-gate/v4"
REPORT_CONTRACT = "paceprompt-host-eval-open-weight-report/v4"
AUDIT_CONTRACT = "paceprompt-host-eval-open-weight-evidence-integrity/v4"
BASETEN_MODEL_ID = "nvidia/nemotron-3-ultra-550b-a55b"


EXPECTED_ROUTES = (
    ("qwen/qwen3.8-27b", "qwen/qwen3.8-27b-20260814", "parasail/fp8", "fp8", NATIVE_JSON_SCHEMA),
    ("mistralai/mistral-small-2603", "mistralai/mistral-small-2603", "venice/fp8", "fp8", NATIVE_JSON_SCHEMA),
    ("nvidia/nemotron-3.5-lightning", "nvidia/nemotron-3.5-lightning-20260807", "deepinfra/bf16", "bf16", NATIVE_JSON_SCHEMA),
    ("deepseek/deepseek-v4-flash-0731", "deepseek/deepseek-v4-flash-20260731", "open-inference/fp8", "fp8", NATIVE_JSON_SCHEMA),
    ("z-ai/glm-5.3-flash", "z-ai/glm-5.3-flash-20260826", "deepinfra/fp4", "fp4", NATIVE_JSON_SCHEMA),
    ("minimax/minimax-m3", "minimax/minimax-m3-20260531", "coreweave/fp4", "fp4", NATIVE_JSON_SCHEMA),
    (BASETEN_MODEL_ID, "nvidia/nemotron-3-ultra-550b-a55b-20260604", "baseten/fp4", "fp4", FORCED_TOOL_ARGUMENTS),
    ("qwen/qwen-2.5-7b-instruct", "qwen/qwen-2.5-7b-instruct", "phala", None, NATIVE_JSON_SCHEMA),
    ("mistralai/mistral-small-3.2-24b-instruct", "mistralai/mistral-small-3.2-24b-instruct-2506", "deepinfra/fp8", "fp8", NATIVE_JSON_SCHEMA),
)

EXPECTED_NATIVE_CONTRACT = {
    "schemaCarrier": "response_format.json_schema",
    "requiredParameters": ["max_tokens", "response_format", "structured_outputs"],
}
EXPECTED_FORCED_TOOL_CONTRACT = {
    "schemaCarrier": "tools[0].function.parameters",
    "resultCarrier": "choices[0].message.tool_calls[0].function.arguments",
    "requiredParameters": ["max_tokens", "tools", "tool_choice"],
    "exactToolName": "submit_workout_import_result",
    "toolDefinitionStrict": "omitted",
}


def queue_document(*, repetitions: int | None = None) -> dict[str, Any]:
    policy = _policy()
    repeat_count = (
        policy["execution"]["requestedRepetitions"]
        if repetitions is None
        else repetitions
    )
    if repeat_count != 3:
        raise ValueError("open-weight v4 repetitions are indivisible and fixed at three")
    cases = load_cases(v3_asset_paths()["heldoutCases"])
    specs = load_model_specs(MODELS)
    configured_order = policy["execution"]["modelOrder"]
    if [spec.requested_model_id for spec in specs] != configured_order:
        raise ValueError("open-weight model order differs from run policy")
    entries: list[dict[str, Any]] = []
    seed_base = policy["execution"]["orderSeedBase"]
    for repetition in range(1, repeat_count + 1):
        shuffled = list(cases)
        random.Random(seed_base + repetition).shuffle(shuffled)
        for case_index, case in enumerate(shuffled):
            rotation = (case_index + repetition - 1) % len(specs)
            ordered = specs[rotation:] + specs[:rotation]
            for position, spec in enumerate(ordered, start=1):
                entries.append(
                    {
                        "attemptID": (
                            f"r{repetition:02d}-{case['id']}-"
                            f"{spec.requested_model_id.replace('/', '--')}"
                        ),
                        "repetitionIndex": repetition,
                        "caseID": case["id"],
                        "modelID": spec.requested_model_id,
                        "modelPosition": position,
                    }
                )
    frozen = verify_v3()
    corpus_hashes = {
        name: frozen["artifactHashes"][name]
        for name in (
            "prompt",
            "developmentCases",
            "developmentManifest",
            "heldoutCases",
            "heldoutManifest",
            "semanticReview",
        )
    }
    material = {
        "runPolicyVersion": policy["runPolicyVersion"],
        "repetitions": repeat_count,
        "corpusHashes": corpus_hashes,
        "entries": entries,
    }
    return {
        "queueContractVersion": "paceprompt-host-eval-open-weight-queue/v4",
        **material,
        "queueSha256": canonical_hash(material),
    }


def _policy() -> dict[str, Any]:
    from .v3 import strict_json_load

    return strict_json_load(RUN_POLICY)


def required_parameter_contracts(
    specs: tuple[ModelSpec, ...] | None = None,
) -> dict[str, set[str]]:
    return {
        spec.requested_model_id: set(spec.required_parameters)
        for spec in (specs or load_model_specs(MODELS))
    }


def verify() -> dict[str, Any]:
    frozen = verify_v3()
    errors = list(frozen["errors"])
    policy = _policy()
    models_document = json.loads(MODELS.read_text(encoding="utf-8"))
    specs = load_model_specs(MODELS)
    actual_routes = tuple(
        (
            spec.requested_model_id,
            spec.canonical_revision,
            spec.provider_endpoint,
            spec.quantization,
            spec.response_contract,
        )
        for spec in specs
    )
    if models_document.get("modelSetVersion") != "paceprompt-host-eval-open-weight-models/v4":
        errors.append("open-weight model-set version changed")
    if actual_routes != EXPECTED_ROUTES:
        errors.append("open-weight model, revision, endpoint, quantisation or contract changed")
    if policy.get("runPolicyVersion") != "paceprompt-host-eval-open-weight-run-policy/v4":
        errors.append("open-weight run-policy version changed")
    if policy.get("extendsFrozenReference") != "paceprompt-host-eval-run-policy/v3":
        errors.append("open-weight policy no longer extends frozen v3")
    if policy.get("artifacts", {}).get("modelsV4Sha256") != sha256_file(MODELS):
        errors.append("open-weight model hash differs from run policy")
    frozen_policy_names = {
        "promptSha256": "prompt",
        "developmentCasesSha256": "developmentCases",
        "developmentManifestSha256": "developmentManifest",
        "heldoutCasesSha256": "heldoutCases",
        "heldoutManifestSha256": "heldoutManifest",
        "semanticReviewSha256": "semanticReview",
        "modelOutputSchemaSha256": "modelSchema",
        "providerTransportSchemaSha256": "nestedV23Schema",
        "v1ScorerSha256": "v1Scorer",
    }
    for policy_name, frozen_name in frozen_policy_names.items():
        if policy.get("artifacts", {}).get(policy_name) != frozen["artifactHashes"].get(
            frozen_name
        ):
            errors.append(f"open-weight policy {policy_name} differs from frozen v3")
    response_contracts = policy.get("generation", {}).get("responseContracts", {})
    if response_contracts != {
        NATIVE_JSON_SCHEMA: EXPECTED_NATIVE_CONTRACT,
        FORCED_TOOL_ARGUMENTS: EXPECTED_FORCED_TOOL_CONTRACT,
    }:
        errors.append("open-weight response contracts changed")
    expected_contract_parameters = {
        name: tuple(record.get("requiredParameters", ()))
        for name, record in response_contracts.items()
        if isinstance(record, dict)
    }
    for spec, record in zip(specs, models_document.get("models", []), strict=True):
        if (
            spec.role != "openWeightCandidate"
            or spec.temperature is not None
            or spec.top_p is not None
            or spec.reasoning is not None
            or spec.max_output_tokens != 8192
            or spec.zdr is not True
        ):
            errors.append(f"{spec.requested_model_id} generation or privacy controls changed")
        if tuple(spec.required_parameters) != expected_contract_parameters.get(
            spec.response_contract
        ):
            errors.append(f"{spec.requested_model_id} parameter contract changed")
        if spec.response_contract == FORCED_TOOL_ARGUMENTS:
            expected_tool = response_contracts.get(FORCED_TOOL_ARGUMENTS, {}).get(
                "exactToolName"
            )
            if spec.forced_tool_name != expected_tool:
                errors.append(f"{spec.requested_model_id} forced tool changed")
        try:
            strategy = strategy_for(spec)
        except ValueError as error:
            errors.append(str(error))
            continue
        if strategy.identifier is not TransportStrategyID.NESTED_V2_3:
            errors.append(f"{spec.requested_model_id} does not use nestedV23")
        if spec.transport_registry_id != V4_OPEN_WEIGHT_REGISTRY_ID:
            errors.append(f"{spec.requested_model_id} uses the wrong strategy registry")
        if sha256_file(strategy.schema_path) != record.get("transportSchemaSha256"):
            errors.append(f"{spec.requested_model_id} transport schema hash changed")
    if [spec.requested_model_id for spec in specs] != policy.get("execution", {}).get(
        "modelOrder"
    ):
        errors.append("open-weight execution model order changed")
    if policy.get("execution", {}).get("requestedRepetitions") != 3:
        errors.append("open-weight repetitions changed")
    expected_execution = {
        "requestedRepetitions": 3,
        "budgetFallbackRepetitions": None,
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "orderSeedBase": 15003405,
        "modelOrder": [route[0] for route in EXPECTED_ROUTES],
        "orderRule": "shuffle-cases-per-repetition-then-rotate-models-in-place",
        "warmupsPerModel": 1,
        "warmupGate": "perModelResponseContractTransportAndFullV2SchemaValidity",
        "warmupOracleAgreement": "diagnosticOnly",
        "cache": False,
        "cachePrompt": False,
        "automaticRetries": 0,
        "httpConnectRetries": 0,
        "connectTimeoutSeconds": 15,
        "attemptTimeoutSeconds": 180,
        "overallRunTimeoutSeconds": None,
        "cancelFlushSeconds": 15,
        "resumable": False,
        "rateLimitDisposition": "pauseModelSkipRemainingInPlace",
        "rateLimitNotStartedReason": "rateLimitPause",
    }
    if policy.get("execution") != expected_execution:
        errors.append("open-weight execution contract changed")
    if policy.get("routing") != {
        "allowFallbacks": False,
        "requireParameters": True,
        "dataCollection": "deny",
        "zdr": True,
        "returnedIdentityMustMatchCanonicalRoute": True,
        "duplicateEndpointTagPolicy": {
            "default": "reject",
            BASETEN_MODEL_ID: "allow-only-if-materially-equivalent",
        },
    }:
        errors.append("open-weight routing contract changed")
    if policy.get("spending") != {
        "currency": "USD",
        "hardLimit": "25.00",
        "preflightMethod": (
            "serialized-complete-request-utf8-byte-upper-bound-plus-"
            "4096-framing-tokens-and-8192-output-tokens-per-call"
        ),
        "runtimeReservationCompletionTokensPerAttempt": 8192,
        "preflightOverLimitBehaviour": "noCallsAndReratify",
        "runtimeLimitBehaviour": "notStartedSpendingLimitReached",
        "warmupsExcludedFromObservedCostTieBreak": True,
    }:
        errors.append("open-weight spending contract changed")
    queue = queue_document() if frozen["status"] == "valid" else None
    if queue is not None:
        counts = Counter(item["modelID"] for item in queue["entries"])
        if len(queue["entries"]) != 2133 or set(counts.values()) != {237}:
            errors.append("open-weight queue must contain 2,133 attempts and 237 per model")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "developmentCases": frozen.get("developmentCases"),
        "heldoutCases": frozen.get("heldoutCases"),
        "fewShotCases": frozen.get("fewShotCases"),
        "models": len(specs),
        "warmups": len(specs),
        "scoredAttempts": len(queue["entries"]) if queue else None,
        "totalProviderCalls": len(queue["entries"]) + len(specs) if queue else None,
        "queueSha256": queue["queueSha256"] if queue else None,
        "frozenV3ArtifactHashes": frozen.get("artifactHashes"),
        "configurationHashes": {
            "models": sha256_file(MODELS),
            "runPolicy": sha256_file(RUN_POLICY),
            "hostEvalSourceTree": frozen.get("artifactHashes", {}).get(
                "hostEvalSourceTree"
            ),
        },
    }


def _max_price_per_million(selected: dict[str, Any]) -> dict[str, float]:
    scale = Decimal("1000000")
    return {
        "prompt": float(Decimal(selected["inputPricePerToken"]) * scale),
        "completion": float(Decimal(selected["outputPricePerToken"]) * scale),
    }


async def mock_payloads(
    run_dir: Path, snapshot: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    policy = _policy()
    paths = v3_asset_paths()
    development = load_cases(paths["developmentCases"])
    warmup = next(
        item
        for item in development
        if item["id"] == policy["dataset"]["warmupCaseID"]
    )
    selected = {item["requestedModelID"]: item for item in snapshot["selected"]}
    mock_dir = run_dir / "mock-payloads"
    mock_dir.mkdir()
    payload_hashes: dict[str, str] = {}
    payload_templates: dict[str, dict[str, Any]] = {}
    contracts: dict[str, str] = {}
    for spec in load_model_specs(MODELS):
        strategy = strategy_for(spec)
        price = _max_price_per_million(selected[spec.requested_model_id])
        payload = await capture_wire_payload(
            spec,
            strategy.schema(),
            model_messages_for_strategy(warmup, strategy),
            max_price_per_million=price,
            schema_name=strategy.schema_name,
            mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
        )
        assert_payload_controls(
            payload,
            spec,
            strategy.schema(),
            price,
            schema_name=strategy.schema_name,
        )
        body = payload["body"]
        serialized = json.dumps(body, ensure_ascii=False)
        if '"rationale"' in serialized or '"conventionTags"' in serialized:
            raise AssertionError("adjudication metadata leaked into mocked payload")
        path = mock_dir / f"{spec.requested_model_id.replace('/', '--')}.json"
        write_json(path, payload)
        payload_hashes[spec.requested_model_id] = sha256_file(path)
        payload_templates[spec.requested_model_id] = body
        contracts[spec.requested_model_id] = spec.response_contract
    evidence = {
        "evidenceType": "offlineOpenWeightV4RouteAwareMockOnly",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "payloadHashes": payload_hashes,
        "responseContracts": contracts,
    }
    write_json(run_dir / "mock-summary.json", evidence)
    return evidence, payload_templates


def _body_for_case(template: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    from .v3 import user_message

    body = deepcopy(template)
    messages = body.get("messages", [])
    if not messages or messages[-1].get("role") != "user":
        raise ValueError("mock payload does not end with the evaluated user message")
    messages[-1]["content"] = user_message(case)
    return body


def cost_preflight(
    snapshot: dict[str, Any], payload_templates: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    policy = _policy()
    paths = v3_asset_paths()
    development = load_cases(paths["developmentCases"])
    heldout = load_cases(paths["heldoutCases"])
    warmup = next(
        item
        for item in development
        if item["id"] == policy["dataset"]["warmupCaseID"]
    )
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    repetitions = policy["execution"]["requestedRepetitions"]
    per_model: dict[str, Decimal] = {}
    for spec in load_model_specs(MODELS):
        endpoint = prices[spec.requested_model_id]
        template = payload_templates[spec.requested_model_id]

        def estimate(case: dict[str, Any]) -> Decimal:
            body = _body_for_case(template, case)
            body_bytes = len(
                json.dumps(
                    body,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
            )
            return conservative_call_cost(
                input_utf8_bytes=body_bytes,
                input_price=endpoint["inputPricePerToken"],
                output_price=endpoint["outputPricePerToken"],
                output_tokens=spec.max_output_tokens,
            )

        per_model[spec.requested_model_id] = estimate(warmup) + repetitions * sum(
            (estimate(case) for case in heldout), Decimal("0")
        )
    total = sum(per_model.values(), Decimal("0"))
    hard_limit = Decimal(policy["spending"]["hardLimit"])
    calls = len(load_model_specs(MODELS)) + repetitions * len(heldout) * len(
        load_model_specs(MODELS)
    )
    return {
        "method": policy["spending"]["preflightMethod"],
        "hardLimitUSD": format(hard_limit, "f"),
        "repetitions": repetitions,
        "fallbackRepetitions": None,
        "callCount": calls,
        "estimatedUSD": format(total, "f"),
        "admitted": calls == 2142 and total <= hard_limit,
        "perModelEstimatedUSD": {
            key: format(value, "f") for key, value in per_model.items()
        },
    }


def _payload_templates(
    run_dir: Path, expected_hashes: dict[str, str] | None = None
) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for spec in load_model_specs(MODELS):
        path = run_dir / "mock-payloads" / (
            spec.requested_model_id.replace("/", "--") + ".json"
        )
        if expected_hashes is not None and sha256_file(path) != expected_hashes.get(
            spec.requested_model_id
        ):
            raise RuntimeError(f"mock payload changed for {spec.requested_model_id}")
        templates[spec.requested_model_id] = json.loads(
            path.read_text(encoding="utf-8")
        )["body"]
    return templates


async def prepare_gate(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None
) -> dict[str, Any]:
    verification = verify()
    if verification["status"] != "valid":
        raise RuntimeError(f"open-weight v4 verification failed: {verification['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(MODELS)
    snapshot = snapshot_catalogue(
        run_dir / "catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags={BASETEN_MODEL_ID},
        **({"fetch": fetch} if fetch else {}),
    )
    write_json(
        run_dir / "catalogue-evidence.json",
        {
            "evidenceType": "readOnlyOpenRouterCatalogueRefresh",
            "providerCalls": 0,
            "credentialRead": False,
            "spendUSD": "0.00",
            "selectedSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        },
    )
    mocks, templates = await mock_payloads(run_dir, snapshot)
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    preflight = cost_preflight(snapshot, templates)
    gate_material = {
        "gateContractVersion": GATE_CONTRACT,
        "reportContractVersion": REPORT_CONTRACT,
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedByCostPreflight"
        ),
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "frozenV3ArtifactHashes": verification["frozenV3ArtifactHashes"],
        "configurationHashes": verification["configurationHashes"],
        "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "queueCorpusHashes": queue["corpusHashes"],
        "selectedEndpoints": snapshot["selected"],
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockPayloadHashes": mocks["payloadHashes"],
        "responseContracts": mocks["responseContracts"],
        "costPreflight": preflight,
        "models": json.loads(MODELS.read_text(encoding="utf-8")),
        "runPolicy": _policy(),
        "requiredBeforeLive": [
            "human-ratifies-this-complete-2142-call-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-the-sealed-spend-cap",
        ],
    }
    phrase = (
        AUTHORIZATION_PREFIX + canonical_hash(gate_material)[:16].upper()
        if preflight["admitted"]
        else None
    )
    gate = dict(gate_material, authorizationPhrase=phrase)
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _fraction_from_record(record: dict[str, Any]) -> Fraction:
    return Fraction(record["numerator"], record["denominator"])


def aggregate(
    attempts: list[dict[str, Any]],
    cases: list[dict[str, Any]],
    specs: tuple[ModelSpec, ...],
) -> dict[str, Any]:
    policy = _policy()
    compatibility_policy = deepcopy(policy)
    compatibility_policy["decision"]["transportSimplicity"] = {"nestedV23": 1}
    report = aggregate_v3(attempts, cases, specs, compatibility_policy)
    report["reportContractVersion"] = REPORT_CONTRACT
    report["comparisonProfile"] = policy["reporting"][
        "comparisonProfileDisclosure"
    ]
    by_id = {spec.requested_model_id: spec for spec in specs}
    exact_composites: dict[str, Fraction] = {}
    for model_id, model_report in report["models"].items():
        spec = by_id[model_id]
        model_report["responseContract"] = spec.response_contract
        model_report["transportSimplicityRank"] = policy["decision"][
            "transportSimplicity"
        ][spec.response_contract]
        exact_composites[model_id] = _fraction_from_record(
            model_report["metrics"]["weightedComposite"]
        ) * 100
    eligible = report["eligibleModels"]
    tie_group: list[str] = []
    after_latency: list[str] = []
    after_cost: list[str] = []
    after_transport: list[str] = []
    if eligible:
        highest = max(exact_composites[model_id] for model_id in eligible)
        tie_group = [
            model_id
            for model_id in eligible
            if highest - exact_composites[model_id]
            <= policy["decision"]["topCompositeTiePoints"]
        ]
        latency = [
            model_id
            for model_id in tie_group
            if report["models"][model_id]["meetsFiveSecondP95"]
        ]
        after_latency = latency or list(tie_group)
        costed = [
            (Decimal(report["models"][model_id]["observedScoredCostUSD"]), model_id)
            for model_id in after_latency
            if report["models"][model_id]["observedScoredCostUSD"] is not None
        ]
        if costed:
            minimum_cost = min(value for value, _ in costed)
            after_cost = [model_id for value, model_id in costed if value == minimum_cost]
        else:
            after_cost = list(after_latency)
        minimum_transport = min(
            report["models"][model_id]["transportSimplicityRank"]
            for model_id in after_cost
        )
        after_transport = [
            model_id
            for model_id in after_cost
            if report["models"][model_id]["transportSimplicityRank"]
            == minimum_transport
        ]
    report["topAnchoredCompositeTieGroup"] = tie_group
    report["tieBreakTrace"] = {
        "afterBinaryLatencyThreshold": after_latency,
        "afterExactObservedCost": after_cost,
        "afterResponseContractSimplicity": after_transport,
        "remainingForHumanDecision": after_transport,
    }
    fixed = deepcopy(policy["fixedReference"])
    fixed_composite = Decimal(fixed["compositeDisplay"])
    report["fixedSolReference"] = fixed
    report["fixedReferenceComparison"] = {
        model_id: {
            "candidateEligible": report["models"][model_id]["decisionEligible"],
            "candidateCompositeDisplay": report["models"][model_id]["metrics"][
                "weightedComposite"
            ]["displayPercent"],
            "publishedCompositeWithinTwoPointsOfSol": (
                Decimal(report["models"][model_id]["metrics"]["weightedComposite"]["displayPercent"])
                >= fixed_composite - Decimal("2")
            ),
        }
        for model_id in report["models"]
    }
    report["currentHumanSelectedProvider"] = fixed["modelID"]
    report["automaticWinner"] = None
    report["providerDecision"] = "requiresHumanRatification"
    report["productionProviderChanged"] = False
    return report


class V4LiveRun(V3LiveRun):
    def __init__(self, *, payload_templates: dict[str, dict[str, Any]], **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self.payload_templates = payload_templates

    def worst_case(self, case: dict[str, Any], spec: ModelSpec) -> Decimal:
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
        report = aggregate(
            self.attempts, list(self.cases.values()), tuple(self.specs.values())
        )
        write_json(self.run_dir / "aggregate-report.json", report)
        audit = self._evidence_integrity()
        audit["auditContractVersion"] = AUDIT_CONTRACT
        write_json(self.run_dir / "evidence-integrity-audit.json", audit)
        await self.save_state(
            "completeEvidenceMechanicallyAccepted"
            if audit["passed"]
            else "completeEvidenceIntegrityFailed"
        )
        return report


def _prices_do_not_increase(
    gated: list[dict[str, Any]], current: list[dict[str, Any]]
) -> None:
    before = {item["requestedModelID"]: item for item in gated}
    for endpoint in current:
        prior = before[endpoint["requestedModelID"]]
        for key in ("inputPricePerToken", "outputPricePerToken"):
            if Decimal(endpoint[key]) > Decimal(prior[key]):
                raise RuntimeError(
                    f"live catalogue {key} increased for {endpoint['requestedModelID']}"
                )


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    from .v3 import strict_json_load

    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != GATE_CONTRACT or gate.get(
        "status"
    ) != "awaitingHumanRatification":
        raise RuntimeError("run is not an awaiting open-weight v4 operator gate")
    if authorization != gate.get("authorizationPhrase"):
        raise RuntimeError("exact run-specific open-weight authorization is missing")
    material = dict(gate)
    material.pop("authorizationPhrase", None)
    if authorization != AUTHORIZATION_PREFIX + canonical_hash(material)[:16].upper():
        raise RuntimeError("open-weight v4 gate changed after authorization was sealed")
    policy = _policy()
    hard_limit = policy["spending"]["hardLimit"]
    if spending_limit_usd != hard_limit or gate["costPreflight"]["hardLimitUSD"] != hard_limit:
        raise RuntimeError(f"open-weight v4 spending limit must be exactly {hard_limit} USD")
    verification = verify()
    if (
        verification["status"] != "valid"
        or verification["configurationHashes"] != gate["configurationHashes"]
        or verification["frozenV3ArtifactHashes"] != gate["frozenV3ArtifactHashes"]
    ):
        raise RuntimeError("open-weight v4 artifacts differ from the ratified gate")
    if sha256_file(run_dir / "planned-queue.json") != gate["plannedQueueFileSha256"]:
        raise RuntimeError("open-weight planned queue changed")
    queue = strict_json_load(run_dir / "planned-queue.json")
    if queue["queueSha256"] != gate["queueSha256"] or queue["corpusHashes"] != gate[
        "queueCorpusHashes"
    ]:
        raise RuntimeError("open-weight planned queue or corpus hashes changed")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable open-weight run already entered live execution")
    specs = load_model_specs(MODELS)
    live = snapshot_catalogue(
        run_dir / "live-catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags={BASETEN_MODEL_ID},
    )
    compare_catalogues(gate["selectedEndpoints"], live["selected"])
    _prices_do_not_increase(gate["selectedEndpoints"], live["selected"])
    templates = _payload_templates(run_dir, gate["mockPayloadHashes"])
    preflight = cost_preflight(live, templates)
    if not preflight["admitted"]:
        raise RuntimeError("current prices no longer fit the open-weight spending limit")
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local unshared environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 2142,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": preflight,
        },
    )
    paths = v3_asset_paths()
    runner = V4LiveRun(
        run_dir=run_dir,
        gate=dict(gate, selectedEndpoints=live["selected"]),
        api_key=api_key,
        schema=json.loads(MODEL_SCHEMA.read_text(encoding="utf-8")),
        transport_schema=strategy_for(specs[0]).schema(),
        cases=load_cases(paths["heldoutCases"]),
        development_cases=load_cases(paths["developmentCases"]),
        queue=queue["entries"],
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=strategy_for(specs[0]).schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd=hard_limit,
        transport_strategy_for_spec=strategy_for,
        warmup_case_id=policy["dataset"]["warmupCaseID"],
        require_returned_identity=True,
        host_latency_profile=True,
        output_limit_is_invalid=True,
        prompt_template_version="workout-import-prompt/v3",
        payload_templates=templates,
    )
    try:
        return await runner.execute()
    finally:
        runner.api_key = ""
        api_key = ""
