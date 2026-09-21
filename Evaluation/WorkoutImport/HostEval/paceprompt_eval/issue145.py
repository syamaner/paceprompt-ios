"""Issue #145 zero-spend preparation for the ratified two-stratum matrix."""

from __future__ import annotations

from collections import Counter
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import random
import re
import sys
from typing import Any, Callable

from inspect_ai.model import ChatMessage, ChatMessageAssistant, ChatMessageSystem, ChatMessageUser

_REPOSITORY_IMPORT_ROOT = Path(__file__).resolve().parents[4]
if str(_REPOSITORY_IMPORT_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPOSITORY_IMPORT_ROOT))

from Evaluation.WorkoutImport.Acceptance.verify_v3 import verify as verify_acceptance

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue130 import EXAMPLES, projected_cases
from .openrouter import (
    FORCED_TOOL_ARGUMENTS,
    NATIVE_JSON_SCHEMA,
    ModelSpec,
    assert_payload_controls,
    capture_wire_payload,
    load_model_specs,
)
from .runner import write_json
from .transport_strategy import ISSUE145_V5_REGISTRY_ID, TransportStrategyID, strategy_for
from .v3 import (
    HOST_EVAL_ROOT,
    REPOSITORY_ROOT,
    asset_paths as v3_asset_paths,
    canonical_hash,
    load_cases,
    safe_run_dir,
    sha256_file,
    strict_json_load,
    user_message,
    verify as verify_v3,
)
from .v4 import BASETEN_MODEL_ID, verify as verify_v4


MODELS = HOST_EVAL_ROOT / "models-v5-issue145.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v5-issue145.json"
CANDIDATE_REVIEW = HOST_EVAL_ROOT / "issue145-candidate-review-r1.json"
RATIFICATION = HOST_EVAL_ROOT / "issue145-candidate-review-r1-ratification.json"
PRODUCTION_PROMPT = (
    REPOSITORY_ROOT / "PacePrompt" / "Import" / "ImportResources" / "system-issue130-r2.md"
)
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/issue145-v5"
QUEUE_CONTRACT = "paceprompt-host-eval-queue/issue145-v5"
REVIEW_SHA256 = "e21347e3a5d71be45717a8083e76878e3b450c5f1a7c7c9e30e0fca7aa92778b"
RATIFICATION_SHA256 = "e90532026d08d0d9d3423a47220de652fee17d6e154b544b9516fa4e30b67384"
MODELS_SHA256 = "27cff2665a89ca038bd0f4a99ce66d7a0d6dc240b5e8001b019ce83048cf38fe"
BASETEN_DUPLICATE_ALLOWLIST = {BASETEN_MODEL_ID}

EXPECTED_ROUTES = (
    ("openai/gpt-5.6-sol", "openai/gpt-5.6-sol-20260709", "openai", None, TransportStrategyID.NESTED_V2_3),
    ("openai/gpt-5.6-luna", "openai/gpt-5.6-luna-20260709", "openai", None, TransportStrategyID.NESTED_V2_3),
    ("google/gemini-3.7-flash", "google/gemini-3.7-flash-20260813", "google-ai-studio", None, TransportStrategyID.SEMANTIC_JSON_V2_9),
    ("qwen/qwen3.8-27b", "qwen/qwen3.8-27b-20260814", "parasail/fp8", "fp8", TransportStrategyID.NESTED_V2_3),
    ("mistralai/mistral-small-2603", "mistralai/mistral-small-2603", "mistral/zdr", None, TransportStrategyID.NESTED_V2_3),
    ("nvidia/nemotron-3.5-lightning", "nvidia/nemotron-3.5-lightning-20260807", "deepinfra/bf16", "bf16", TransportStrategyID.NESTED_V2_3),
    ("deepseek/deepseek-v4-flash-0731", "deepseek/deepseek-v4-flash-20260731", "deepinfra/fp8", "fp8", TransportStrategyID.NESTED_V2_3),
    ("z-ai/glm-5.3-flash", "z-ai/glm-5.3-flash-20260826", "deepinfra/fp4", "fp4", TransportStrategyID.NESTED_V2_3),
    ("minimax/minimax-m3", "minimax/minimax-m3-20260531", "coreweave/fp4", "fp4", TransportStrategyID.NESTED_V2_3),
    (BASETEN_MODEL_ID, "nvidia/nemotron-3-ultra-550b-a55b-20260604", "baseten/fp4", "fp4", TransportStrategyID.NESTED_V2_3),
    ("qwen/qwen-2.5-7b-instruct", "qwen/qwen-2.5-7b-instruct", "phala", None, TransportStrategyID.NESTED_V2_3),
    ("mistralai/mistral-small-3.2-24b-instruct", "mistralai/mistral-small-3.2-24b-instruct-2506", "deepinfra/fp8", "fp8", TransportStrategyID.NESTED_V2_3),
)


def _policy() -> dict[str, Any]:
    return strict_json_load(RUN_POLICY)


def scored_strata() -> tuple[tuple[str, list[dict[str, Any]]], ...]:
    heldout = load_cases(v3_asset_paths()["heldoutCases"])
    acceptance = projected_cases()
    return (
        ("v3-heldout-regression", heldout),
        ("issue130-acceptance-r2", acceptance),
    )


def queue_document() -> dict[str, Any]:
    policy = _policy()
    specs = load_model_specs(MODELS)
    model_order = policy["execution"]["modelOrder"]
    if [spec.requested_model_id for spec in specs] != model_order:
        raise ValueError("issue #145 model order differs from run policy")
    repetitions = policy["execution"]["requestedRepetitionsPerStratum"]
    if repetitions != 3:
        raise ValueError("issue #145 repetitions are indivisible and fixed at three")
    entries: list[dict[str, Any]] = []
    seed_base = policy["execution"]["orderSeedBase"]
    for stratum_id, cases in scored_strata():
        for repetition in range(1, repetitions + 1):
            shuffled = list(cases)
            random.Random(seed_base + repetition).shuffle(shuffled)
            for case_index, case in enumerate(shuffled):
                rotation = (case_index + repetition - 1) % len(specs)
                ordered = specs[rotation:] + specs[:rotation]
                for position, spec in enumerate(ordered, start=1):
                    entries.append(
                        {
                            "attemptID": (
                                f"{stratum_id}-r{repetition:02d}-{case['id']}-"
                                f"{spec.requested_model_id.replace('/', '--')}"
                            ),
                            "stratumID": stratum_id,
                            "repetitionIndex": repetition,
                            "caseID": case["id"],
                            "modelID": spec.requested_model_id,
                            "modelPosition": position,
                        }
                    )
    material = {
        "runPolicyVersion": policy["runPolicyVersion"],
        "candidateReviewSha256": REVIEW_SHA256,
        "strata": [
            {
                "id": stratum_id,
                "caseCount": len(cases),
                "caseIDsSha256": canonical_hash([case["id"] for case in cases]),
            }
            for stratum_id, cases in scored_strata()
        ],
        "repetitionsPerStratum": repetitions,
        "entries": entries,
    }
    return {
        "queueContractVersion": QUEUE_CONTRACT,
        **material,
        "queueSha256": canonical_hash(material),
    }


def required_parameter_contracts(
    specs: tuple[ModelSpec, ...] | None = None,
) -> dict[str, set[str]]:
    return {
        spec.requested_model_id: set(spec.required_parameters)
        for spec in (specs or load_model_specs(MODELS))
    }


def _normalise(value: str) -> str:
    return " ".join(value.casefold().split())


def _skeleton(value: str) -> str:
    text = _normalise(value)
    text = re.sub(
        r"\b(?:kilometres? per hour|kmph|kph|km/?h|degrees?|miles? per hour|mph|seconds?|secs?|minutes?|mins?|percent|%)\b",
        " <unit> ",
        text,
    )
    text = re.sub(r"(?<![a-z])[-+]?\d+(?:\.\d+)?", " <number> ", text)
    return " ".join(re.sub(r"[^a-z<>]+", " ", text).split())


def _example_requests() -> list[str]:
    marker = "Workout request:\n"
    return [
        message["content"].split(marker, 1)[1]
        for message in strict_json_load(EXAMPLES)
        if message["role"] == "user" and marker in message["content"]
    ]


def verify() -> dict[str, Any]:
    errors: list[str] = []
    frozen_v3 = verify_v3()
    frozen_v4 = verify_v4()
    acceptance = verify_acceptance(HOST_EVAL_ROOT.parent)
    if frozen_v3["status"] != "valid":
        errors.append("sealed v3 verifier failed")
    if frozen_v4["status"] != "valid":
        errors.append("sealed v4 verifier failed")
    if acceptance["status"] != "valid" or acceptance.get("corpusHash") != "204c6814cb62523426ed8871d77159f39a4daf4dc495ece7fcc70627e6d22864":
        errors.append("issue #130 acceptance corpus r2 verification failed")

    policy = _policy()
    review = strict_json_load(CANDIDATE_REVIEW)
    ratification = strict_json_load(RATIFICATION)
    if sha256_file(CANDIDATE_REVIEW) != REVIEW_SHA256:
        errors.append("ratified candidate review hash changed")
    if sha256_file(RATIFICATION) != RATIFICATION_SHA256:
        errors.append("candidate review ratification hash changed")
    if sha256_file(MODELS) != MODELS_SHA256:
        errors.append("issue #145 model configuration hash changed")
    if ratification.get("ratifiedCandidateReviewSha256") != REVIEW_SHA256:
        errors.append("ratification does not bind the candidate review")
    authority = ratification.get("authority", {})
    if authority != {
        "zeroSpendGateImplementation": True,
        "publicCataloguePreparation": True,
        "credentialRead": False,
        "compatibilityProbe": False,
        "providerInference": False,
        "evaluationSpend": False,
        "liveRun": False,
        "productionChange": False,
    }:
        errors.append("issue #145 authority boundary changed")

    artifact_paths = {
        "productionPromptSha256": PRODUCTION_PROMPT,
        "productionExamplesSha256": EXAMPLES,
        "heldoutCasesSha256": v3_asset_paths()["heldoutCases"],
        "heldoutManifestSha256": v3_asset_paths()["heldoutManifest"],
        "acceptanceCasesSha256": HOST_EVAL_ROOT.parent / "Corpus" / "v3" / "cases.json",
        "acceptanceManifestSha256": HOST_EVAL_ROOT.parent / "Corpus" / "v3" / "manifest.json",
        "acceptanceSemanticReviewSha256": HOST_EVAL_ROOT.parent / "Corpus" / "v3" / "semantic-review.json",
        "modelOutputSchemaSha256": HOST_EVAL_ROOT / "schemas" / "v2" / "workout-import-model-output-v2.schema.json",
        "nestedTransportSchemaSha256": HOST_EVAL_ROOT / "schemas" / "v2.3" / "workout-import-provider-transport-v2.3.schema.json",
        "semanticJsonTransportSchemaSha256": HOST_EVAL_ROOT / "schemas" / "v2.9" / "workout-import-provider-transport-semantic-json-v2.9.schema.json",
        "scorerSha256": HOST_EVAL_ROOT.parent / "Scoring" / "scorer.py",
        "schemaValidationSha256": HOST_EVAL_ROOT.parent / "Scoring" / "schema_validation.py",
        "modelsV5Sha256": MODELS,
    }
    for field, path in artifact_paths.items():
        actual = sha256_file(path)
        if policy.get("artifacts", {}).get(field) != actual:
            errors.append(f"issue #145 policy {field} differs from exact artifact")
        if field != "modelsV5Sha256" and review.get("artifacts", {}).get(field) not in {None, actual}:
            errors.append(f"candidate review {field} differs from exact artifact")

    specs = load_model_specs(MODELS)
    actual_routes = tuple(
        (
            spec.requested_model_id,
            spec.canonical_revision,
            spec.provider_endpoint,
            spec.quantization,
            strategy_for(spec).identifier,
        )
        for spec in specs
    )
    if actual_routes != EXPECTED_ROUTES:
        errors.append("issue #145 model route or transport strategy changed")
    if any(spec.transport_registry_id != ISSUE145_V5_REGISTRY_ID for spec in specs):
        errors.append("issue #145 models must use the additive v5 route registry")
    if any(spec.max_output_tokens != 8192 for spec in specs):
        errors.append("issue #145 maximum output tokens changed")
    if specs and (
        specs[0].reasoning != {"enabled": False, "effort": "none", "exclude": False}
        or specs[1].reasoning != {"enabled": False, "effort": "none", "exclude": False}
        or specs[2].reasoning != {"enabled": True, "effort": "medium", "exclude": False}
        or specs[2].temperature != 0
        or specs[2].top_p != 1
        or any(spec.reasoning is not None for spec in specs[3:])
    ):
        errors.append("prior per-model generation profiles changed")
    if any(spec.response_contract != NATIVE_JSON_SCHEMA for spec in specs if spec.requested_model_id != BASETEN_MODEL_ID):
        errors.append("native response contracts changed")
    baseten = next((spec for spec in specs if spec.requested_model_id == BASETEN_MODEL_ID), None)
    if baseten is None or baseten.response_contract != FORCED_TOOL_ARGUMENTS:
        errors.append("BaseTen forced-tool response contract changed")

    strata = scored_strata()
    all_cases = [case for _, cases in strata for case in cases]
    ids = [case["id"] for case in all_cases]
    prompts = [_normalise(case["prompt"]) for case in all_cases]
    skeletons_by_stratum = {
        stratum_id: {_skeleton(case["prompt"]) for case in cases}
        for stratum_id, cases in strata
    }
    if len(all_cases) != 109 or len(ids) != len(set(ids)):
        errors.append("two strata must contain 109 distinct case IDs")
    if len(prompts) != len(set(prompts)):
        errors.append("two strata contain an exact normalized prompt collision")
    if skeletons_by_stratum["v3-heldout-regression"].intersection(
        skeletons_by_stratum["issue130-acceptance-r2"]
    ):
        errors.append("the held-out and acceptance strata contain a semantic skeleton collision")
    examples = {_normalise(value) for value in _example_requests()}
    if examples.intersection(prompts):
        errors.append("a scored case was copied into production examples")

    if policy.get("spending", {}).get("hardLimit") is not None:
        errors.append("zero-spend preparation must not preselect a spending limit")
    queue = queue_document() if len(specs) == 12 else None
    if queue is not None:
        counts = Counter(item["modelID"] for item in queue["entries"])
        strata_counts = Counter(item["stratumID"] for item in queue["entries"])
        if len(queue["entries"]) != 3924 or set(counts.values()) != {327}:
            errors.append("issue #145 queue must contain 3,924 attempts and 327 per model")
        if strata_counts != {"v3-heldout-regression": 2844, "issue130-acceptance-r2": 1080}:
            errors.append("issue #145 stratum attempt counts changed")
    execution = review.get("recommendedExecutionProfile", {})
    for field, expected in {
        "requestedRepetitionsPerStratum": 3,
        "scoredAttempts": 3924,
        "warmups": 12,
        "totalProviderCalls": 3936,
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "orderSeedBase": 15003405,
        "maxOutputTokens": 8192,
        "automaticWinner": False,
    }.items():
        if execution.get(field) != expected:
            errors.append(f"ratified execution field {field} changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "models": len(specs),
        "strata": {stratum_id: len(cases) for stratum_id, cases in strata},
        "distinctScoredCases": len(all_cases),
        "scoredAttempts": len(queue["entries"]) if queue else None,
        "warmups": len(specs),
        "totalProviderCalls": len(queue["entries"]) + len(specs) if queue else None,
        "queueSha256": queue["queueSha256"] if queue else None,
        "configurationHashes": {
            "candidateReview": sha256_file(CANDIDATE_REVIEW),
            "ratification": sha256_file(RATIFICATION),
            "models": sha256_file(MODELS),
            "runPolicy": sha256_file(RUN_POLICY),
        },
    }


def model_messages(case: dict[str, Any], strategy: Any) -> list[ChatMessage]:
    messages: list[ChatMessage] = [
        ChatMessageSystem(content=PRODUCTION_PROMPT.read_text(encoding="utf-8"))
    ]
    for message in strict_json_load(EXAMPLES):
        if message["role"] == "user":
            messages.append(ChatMessageUser(content=message["content"]))
        elif message["role"] == "assistant":
            semantic = json.loads(message["content"])
            messages.append(
                ChatMessageAssistant(
                    content=json.dumps(
                        strategy.project_output(semantic),
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                )
            )
        else:
            raise ValueError("production examples contain an unsupported role")
    messages.append(ChatMessageUser(content=user_message(case)))
    return messages


def _max_price_per_million(selected: dict[str, Any]) -> dict[str, float]:
    scale = Decimal("1000000")
    return {
        "prompt": float(Decimal(selected["inputPricePerToken"]) * scale),
        "completion": float(Decimal(selected["outputPricePerToken"]) * scale),
    }


async def mock_payloads(
    run_dir: Path,
    snapshot: dict[str, Any],
    *,
    models_path: Path = MODELS,
    policy_path: Path = RUN_POLICY,
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    policy = strict_json_load(policy_path)
    warmup = next(
        case
        for case in load_cases(v3_asset_paths()["developmentCases"])
        if case["id"] == policy["dataset"]["warmupCaseID"]
    )
    selected = {item["requestedModelID"]: item for item in snapshot["selected"]}
    mock_dir = run_dir / "mock-payloads"
    mock_dir.mkdir()
    payload_hashes: dict[str, str] = {}
    payload_templates: dict[str, dict[str, Any]] = {}
    contracts: dict[str, str] = {}
    for spec in load_model_specs(models_path):
        strategy = strategy_for(spec)
        price = _max_price_per_million(selected[spec.requested_model_id])
        payload = await capture_wire_payload(
            spec,
            strategy.schema(),
            model_messages(warmup, strategy),
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
        serialized = json.dumps(payload["body"], ensure_ascii=False)
        if '"rationale"' in serialized or '"conventionTags"' in serialized:
            raise AssertionError("adjudication metadata leaked into mocked payload")
        path = mock_dir / f"{spec.requested_model_id.replace('/', '--')}.json"
        write_json(path, payload)
        payload_hashes[spec.requested_model_id] = sha256_file(path)
        payload_templates[spec.requested_model_id] = payload["body"]
        contracts[spec.requested_model_id] = spec.response_contract
    evidence = {
        "evidenceType": "offlineIssue145V5RouteAwareMockOnly",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "payloadHashes": payload_hashes,
        "responseContracts": contracts,
    }
    write_json(run_dir / "mock-summary.json", evidence)
    return evidence, payload_templates


def _body_for_case(template: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    body = deepcopy(template)
    messages = body.get("messages", [])
    if not messages or messages[-1].get("role") != "user":
        raise ValueError("mock payload does not end with the evaluated user message")
    messages[-1]["content"] = user_message(case)
    return body


def cost_preflight(
    snapshot: dict[str, Any],
    payload_templates: dict[str, dict[str, Any]],
    *,
    models_path: Path = MODELS,
    policy_path: Path = RUN_POLICY,
) -> dict[str, Any]:
    policy = strict_json_load(policy_path)
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    specs = load_model_specs(models_path)
    warmup = next(
        case
        for case in load_cases(v3_asset_paths()["developmentCases"])
        if case["id"] == policy["dataset"]["warmupCaseID"]
    )
    all_cases = [case for _, cases in scored_strata() for case in cases]
    repetitions = policy["execution"]["requestedRepetitionsPerStratum"]
    per_model: dict[str, Decimal] = {}
    for spec in specs:
        endpoint = prices[spec.requested_model_id]
        template = payload_templates[spec.requested_model_id]

        def estimate(case: dict[str, Any]) -> Decimal:
            body_bytes = len(
                json.dumps(
                    _body_for_case(template, case),
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
            (estimate(case) for case in all_cases), Decimal("0")
        )
    total = sum(per_model.values(), Decimal("0"))
    return {
        "method": policy["spending"]["preflightMethod"],
        "hardLimitUSD": None,
        "callCount": len(specs) * (1 + repetitions * len(all_cases)),
        "estimatedUSD": format(total, "f"),
        "admitted": False,
        "status": "awaitingSeparateHardLimitRatification",
        "perModelEstimatedUSD": {
            key: format(value, "f") for key, value in per_model.items()
        },
    }


async def prepare_gate(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None
) -> dict[str, Any]:
    verification = verify()
    if verification["status"] != "valid":
        raise RuntimeError(f"issue #145 verification failed: {verification['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(MODELS)
    snapshot = snapshot_catalogue(
        run_dir / "catalogue",
        specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
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
    mocks, templates = await mock_payloads(run_dir, snapshot)
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    preflight = cost_preflight(snapshot, templates)
    gate = {
        "gateContractVersion": GATE_CONTRACT,
        "runID": run_id,
        "status": "awaitingReplacementRouteCompatibilityProofAndSpendingRatification",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "authorizationPhrase": None,
        "configurationHashes": verification["configurationHashes"],
        "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "selectedEndpoints": snapshot["selected"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "mockPayloadHashes": mocks["payloadHashes"],
        "responseContracts": mocks["responseContracts"],
        "costPreflight": preflight,
        "models": strict_json_load(MODELS),
        "runPolicy": _policy(),
        "requiredBeforeLive": [
            "separately-authorized-compatibility-probes-pass-for-both-replacement-routes",
            "human-ratifies-an-exact-hard-spending-limit",
            "a-new-run-instance-binds-the-probe-evidence-catalogue-queue-and-spend-cap",
            "local-OPENROUTER_API_KEY-is-available-without-persistence",
            "human-explicitly-authorizes-provider-calls-for-that-run-instance",
        ],
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate
