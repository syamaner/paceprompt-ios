"""Offline verification, deterministic matrix construction and gated execution."""

from __future__ import annotations

import argparse
import asyncio
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys
from typing import Any, Iterable
from decimal import Decimal

from inspect_ai.model import ChatMessage, ChatMessageAssistant, ChatMessageSystem, ChatMessageUser
from jsonschema import Draft202012Validator

from . import HARNESS_VERSION
from .openrouter import (
    ModelSpec,
    assert_payload_controls,
    capture_wire_payload,
    load_model_specs,
)
from .catalogue import conservative_call_cost, choose_repetitions, snapshot_catalogue
from .scorer_adapter import provider_transport_output
from .transport_strategy import (
    ProviderTransportStrategy,
    TransportStrategyID,
    STRATEGIES,
    strategy_for,
)


HOST_EVAL_ROOT = Path(__file__).resolve().parents[1]
WORKOUT_IMPORT_ROOT = HOST_EVAL_ROOT.parent
REPOSITORY_ROOT = WORKOUT_IMPORT_ROOT.parents[1]
RUNS_ROOT = WORKOUT_IMPORT_ROOT / ".runs" / "host-eval"
DEVELOPMENT_CASES = HOST_EVAL_ROOT / "datasets" / "development" / "cases.json"
HELDOUT_CASES = HOST_EVAL_ROOT / "datasets" / "heldout" / "cases.json"
MODEL_SCHEMA = HOST_EVAL_ROOT / "schemas" / "v2" / "workout-import-model-output-v2.schema.json"
TRANSPORT_SCHEMA = HOST_EVAL_ROOT / "schemas" / "v2.3" / "workout-import-provider-transport-v2.3.schema.json"
SYSTEM_PROMPT = HOST_EVAL_ROOT / "prompts" / "v2" / "system.md"
MODELS = HOST_EVAL_ROOT / "models-v2.3.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v2.3.json"
STRATEGY_MODELS = HOST_EVAL_ROOT / "models-v2.7.json"
STRATEGY_RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v2.7.json"
DIAGNOSTIC_MODELS_V2_4 = HOST_EVAL_ROOT / "models-v2.4-gemini-diagnostic.json"
DIAGNOSTIC_RUN_POLICY_V2_4 = HOST_EVAL_ROOT / "run-policy-v2.4-gemini-diagnostic.json"
DIAGNOSTIC_MODELS = HOST_EVAL_ROOT / "models-v2.5-gemini-diagnostic.json"
DIAGNOSTIC_RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v2.5-gemini-diagnostic.json"
CURL_PROBE_POLICY = HOST_EVAL_ROOT / "curl-probe-policy-v2.6.json"
STRATEGY_DIAGNOSTIC_MODELS = (
    HOST_EVAL_ROOT / "models-v2.7-gemini-strategy-diagnostic.json"
)
STRATEGY_DIAGNOSTIC_RUN_POLICY = (
    HOST_EVAL_ROOT / "run-policy-v2.7-gemini-strategy-diagnostic.json"
)
SHALLOW_STEP_TRANSPORT_SCHEMA = (
    HOST_EVAL_ROOT
    / "schemas"
    / "v2.7"
    / "workout-import-provider-transport-shallow-step-v2.7.schema.json"
)
FLAT_STRATEGY_MODELS = HOST_EVAL_ROOT / "models-v2.8.json"
FLAT_STRATEGY_RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v2.8.json"
FLAT_STRATEGY_DIAGNOSTIC_MODELS = (
    HOST_EVAL_ROOT / "models-v2.8-gemini-strategy-diagnostic.json"
)
FLAT_STRATEGY_DIAGNOSTIC_RUN_POLICY = (
    HOST_EVAL_ROOT / "run-policy-v2.8-gemini-strategy-diagnostic.json"
)
FLAT_ENVELOPE_TRANSPORT_SCHEMA = (
    HOST_EVAL_ROOT
    / "schemas"
    / "v2.8"
    / "workout-import-provider-transport-flat-envelope-v2.8.schema.json"
)
SEMANTIC_JSON_STRATEGY_MODELS = HOST_EVAL_ROOT / "models-v2.9.json"
SEMANTIC_JSON_STRATEGY_RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v2.9.json"
SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS = (
    HOST_EVAL_ROOT / "models-v2.9-gemini-strategy-diagnostic.json"
)
SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_RUN_POLICY = (
    HOST_EVAL_ROOT / "run-policy-v2.9-gemini-strategy-diagnostic.json"
)
SEMANTIC_JSON_TRANSPORT_SCHEMA = (
    HOST_EVAL_ROOT
    / "schemas"
    / "v2.9"
    / "workout-import-provider-transport-semantic-json-v2.9.schema.json"
)
SEMANTIC_REVIEW = HOST_EVAL_ROOT / "datasets" / "semantic-nonduplication-v2.json"
V1_CASES = WORKOUT_IMPORT_ROOT / "Corpus" / "v1" / "cases.json"

ALLOWED_REASON_CATEGORIES = {
    "missingRequiredField",
    "ambiguousRequiredField",
    "contradictoryRequest",
    "outOfDomain",
    "unsupportedActivity",
    "unsupportedTarget",
    "unsupportedUnit",
    "unsupportedOperation",
    "knownCapabilityUnsupported",
    "excessiveComplexity",
    "promptInjection",
    "unsafeRequest",
    "medicalRequest",
}
PATH_ORDER = [
    "activity",
    "steps",
    "steps.repetitions",
    "steps.kind",
    "steps.duration",
    "steps.duration.value",
    "steps.duration.unit",
    "steps.targetSpeed",
    "steps.targetSpeed.value",
    "steps.targetSpeed.unit",
    "steps.targetInclination",
    "steps.targetInclination.value",
    "steps.targetInclination.unit",
    "capabilities.speed",
    "capabilities.inclination",
]
PATH_RANK = {value: index for index, value in enumerate(PATH_ORDER)}


class SpendingLimitReached(RuntimeError):
    pass


class SpendGuard:
    """Reserve worst-case per-call spend before any request can start."""

    def __init__(self, limit: str) -> None:
        self.limit = Decimal(limit)
        self.reserved = Decimal("0")
        self.actual = Decimal("0")
        self._reservations: dict[str, Decimal] = {}

    def reserve(self, attempt_id: str, worst_case: Decimal) -> None:
        if worst_case < 0 or attempt_id in self._reservations:
            raise ValueError("invalid spend reservation")
        if self.actual + self.reserved + worst_case > self.limit:
            raise SpendingLimitReached(attempt_id)
        self._reservations[attempt_id] = worst_case
        self.reserved += worst_case

    def settle(self, attempt_id: str, actual: Decimal) -> None:
        reserved = self._reservations.pop(attempt_id)
        if actual < 0 or actual > reserved:
            raise ValueError("reported cost exceeds the reserved worst case")
        self.reserved -= reserved
        self.actual += actual
        if self.actual + self.reserved > self.limit:
            raise SpendingLimitReached(attempt_id)


def strict_json_load(path: Path) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate key {key!r} in {path}")
            result[key] = value
        return result

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_hash(value: Any) -> str:
    material = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def normalize_prompt(value: str) -> str:
    return " ".join(value.casefold().split())


def skeleton_prompt(value: str) -> str:
    text = normalize_prompt(value)
    text = re.sub(
        r"\b(?:kilometres? per hour|km/?h|miles? per hour|mph|seconds?|secs?|minutes?|mins?|percent|%)\b",
        " <unit> ",
        text,
    )
    text = re.sub(r"(?<![a-z])[-+]?\d+(?:\.\d+)?", " <number> ", text)
    text = re.sub(r"[^a-z<>]+", " ", text)
    return " ".join(text.split())


def artifact_hashes() -> dict[str, str]:
    paths = {
        "prompt": SYSTEM_PROMPT,
        "modelSchema": MODEL_SCHEMA,
        "providerTransportSchema": TRANSPORT_SCHEMA,
        "developmentCases": DEVELOPMENT_CASES,
        "developmentManifest": DEVELOPMENT_CASES.with_name("manifest.json"),
        "heldoutCases": HELDOUT_CASES,
        "heldoutManifest": HELDOUT_CASES.with_name("manifest.json"),
        "semanticReview": SEMANTIC_REVIEW,
        "models": MODELS,
        "runPolicy": RUN_POLICY,
        "strategyModels": STRATEGY_MODELS,
        "strategyRunPolicy": STRATEGY_RUN_POLICY,
        "diagnosticModelsV2_4": DIAGNOSTIC_MODELS_V2_4,
        "diagnosticRunPolicyV2_4": DIAGNOSTIC_RUN_POLICY_V2_4,
        "diagnosticModels": DIAGNOSTIC_MODELS,
        "diagnosticRunPolicy": DIAGNOSTIC_RUN_POLICY,
        "curlProbePolicy": CURL_PROBE_POLICY,
        "strategyDiagnosticModels": STRATEGY_DIAGNOSTIC_MODELS,
        "strategyDiagnosticRunPolicy": STRATEGY_DIAGNOSTIC_RUN_POLICY,
        "shallowStepTransportSchema": SHALLOW_STEP_TRANSPORT_SCHEMA,
        "flatStrategyModels": FLAT_STRATEGY_MODELS,
        "flatStrategyRunPolicy": FLAT_STRATEGY_RUN_POLICY,
        "flatStrategyDiagnosticModels": FLAT_STRATEGY_DIAGNOSTIC_MODELS,
        "flatStrategyDiagnosticRunPolicy": FLAT_STRATEGY_DIAGNOSTIC_RUN_POLICY,
        "flatEnvelopeTransportSchema": FLAT_ENVELOPE_TRANSPORT_SCHEMA,
        "semanticJsonStrategyModels": SEMANTIC_JSON_STRATEGY_MODELS,
        "semanticJsonStrategyRunPolicy": SEMANTIC_JSON_STRATEGY_RUN_POLICY,
        "semanticJsonStrategyDiagnosticModels": SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS,
        "semanticJsonStrategyDiagnosticRunPolicy": SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_RUN_POLICY,
        "semanticJsonTransportSchema": SEMANTIC_JSON_TRANSPORT_SCHEMA,
        "v1Scorer": WORKOUT_IMPORT_ROOT / "Scoring" / "scorer.py",
        "v1ProposalSchema": WORKOUT_IMPORT_ROOT / "Contracts" / "workout-proposal-v1.schema.json",
        "v1ResultSchema": WORKOUT_IMPORT_ROOT / "Contracts" / "workout-import-result-v1.schema.json",
    }
    hashes = {name: sha256_file(path) for name, path in paths.items()}
    excluded_parts = {".venv", "__pycache__", ".pytest_cache", ".ruff_cache"}
    source_files = sorted(
        path for path in HOST_EVAL_ROOT.rglob("*")
        if path.is_file()
        and path.name != ".env"
        and not any(part in excluded_parts for part in path.relative_to(HOST_EVAL_ROOT).parts)
    )
    source_manifest = {
        str(path.relative_to(HOST_EVAL_ROOT)): sha256_file(path) for path in source_files
    }
    hashes["hostEvalSourceTree"] = canonical_hash(source_manifest)
    return hashes


def load_cases(path: Path) -> list[dict[str, Any]]:
    value = strict_json_load(path)
    if not isinstance(value, list):
        raise ValueError(f"{path} must contain an array")
    return value


def user_message(case: dict[str, Any]) -> str:
    capabilities = json.dumps(case["capabilities"], sort_keys=True, separators=(",", ":"))
    return f"Locale: {case['locale']}\nCapabilities: {capabilities}\nWorkout request:\n{case['prompt']}"


def model_messages_for_strategy(
    case: dict[str, Any], strategy: ProviderTransportStrategy
) -> list[ChatMessage]:
    development = load_cases(DEVELOPMENT_CASES)
    examples = [item for item in development if item["fewShot"]]
    messages: list[ChatMessage] = [ChatMessageSystem(content=SYSTEM_PROMPT.read_text(encoding="utf-8"))]
    for example in examples:
        messages.append(ChatMessageUser(content=user_message(example)))
        messages.append(
            ChatMessageAssistant(
                content=json.dumps(
                    strategy.project_output(example["expected"]["modelOutput"]),
                    # Every few-shot output uses the selected strategy's exact
                    # provider shape. Its paired normalizer reconstructs the
                    # semantic document before host validation and scoring.
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
            )
        )
    messages.append(ChatMessageUser(content=user_message(case)))
    return messages


def model_messages(case: dict[str, Any]) -> list[ChatMessage]:
    """Retain the immutable nested-v2.3 prompt projection for prior run paths."""

    return model_messages_for_strategy(case, STRATEGIES[TransportStrategyID.NESTED_V2_3])


def message_text(messages: Iterable[ChatMessage]) -> str:
    return "\n".join(str(message.content) for message in messages)


def _deterministic_queue(repetitions: int, model_path: Path) -> list[dict[str, Any]]:
    cases = load_cases(HELDOUT_CASES)
    models = load_model_specs(model_path)
    queue: list[dict[str, Any]] = []
    for repetition in range(1, repetitions + 1):
        shuffled = list(cases)
        random.Random(15003405 + repetition).shuffle(shuffled)
        for case_index, case in enumerate(shuffled):
            rotation = (case_index + repetition - 1) % len(models)
            ordered_models = models[rotation:] + models[:rotation]
            for model_position, model in enumerate(ordered_models):
                queue.append(
                    {
                        "attemptID": f"r{repetition:02d}-{case['id']}-{model.requested_model_id.replace('/', '--')}",
                        "repetitionIndex": repetition,
                        "caseID": case["id"],
                        "modelID": model.requested_model_id,
                        "modelPosition": model_position + 1,
                    }
                )
    return queue


def deterministic_queue(repetitions: int) -> list[dict[str, Any]]:
    """Retain the frozen v2.3 queue entry point."""

    return _deterministic_queue(repetitions, MODELS)


def deterministic_strategy_queue(repetitions: int) -> list[dict[str, Any]]:
    return _deterministic_queue(repetitions, STRATEGY_MODELS)


def deterministic_flat_strategy_queue(repetitions: int) -> list[dict[str, Any]]:
    return _deterministic_queue(repetitions, FLAT_STRATEGY_MODELS)


def deterministic_semantic_json_strategy_queue(
    repetitions: int,
) -> list[dict[str, Any]]:
    return _deterministic_queue(repetitions, SEMANTIC_JSON_STRATEGY_MODELS)


def _verify_v2() -> dict[str, Any]:
    development = load_cases(DEVELOPMENT_CASES)
    heldout = load_cases(HELDOUT_CASES)
    v1 = load_cases(V1_CASES)
    schema = strict_json_load(MODEL_SCHEMA)
    validator = Draft202012Validator(schema)
    transport_schema = strict_json_load(TRANSPORT_SCHEMA)
    transport_validator = Draft202012Validator(transport_schema)
    shallow_step_schema = strict_json_load(SHALLOW_STEP_TRANSPORT_SCHEMA)
    shallow_step_validator = Draft202012Validator(shallow_step_schema)
    flat_envelope_schema = strict_json_load(FLAT_ENVELOPE_TRANSPORT_SCHEMA)
    flat_envelope_validator = Draft202012Validator(flat_envelope_schema)
    semantic_json_schema = strict_json_load(SEMANTIC_JSON_TRANSPORT_SCHEMA)
    semantic_json_validator = Draft202012Validator(semantic_json_schema)
    errors: list[str] = []

    for name, path, cases, expected_count, locales in (
        ("development", DEVELOPMENT_CASES, development, 17, {"en-GB": 9, "en-US": 8}),
        ("heldout", HELDOUT_CASES, heldout, 34, {"en-GB": 17, "en-US": 17}),
    ):
        manifest = strict_json_load(path.with_name("manifest.json"))
        if manifest["casesSha256"] != sha256_file(path):
            errors.append(f"{name} cases hash differs from manifest")
        if len(cases) != expected_count or manifest["caseCount"] != expected_count:
            errors.append(f"{name} case count is not {expected_count}")
        if Counter(case["locale"] for case in cases) != Counter(locales):
            errors.append(f"{name} locale allocation changed")

    if sum(case["category"] == "proposal" for case in development) != 4:
        errors.append("development must contain four proposal cases")
    if sum(case["category"] == "proposal" for case in heldout) != 8:
        errors.append("heldout must contain eight proposal cases")
    dev_reasons = Counter(case["category"] for case in development if case["category"] != "proposal")
    held_reasons = Counter(case["category"] for case in heldout if case["category"] != "proposal")
    if dev_reasons != Counter({category: 1 for category in ALLOWED_REASON_CATEGORIES}):
        errors.append("development reason-category stratification changed")
    if held_reasons != Counter({category: 2 for category in ALLOWED_REASON_CATEGORIES}):
        errors.append("heldout reason-category stratification changed")
    examples = [case for case in development if case["fewShot"]]
    if len(examples) != 8:
        errors.append("exactly eight development cases must be few-shot examples")
    if any(case["fewShot"] for case in heldout):
        errors.append("heldout case marked as few-shot")

    all_v2 = development + heldout
    ids = [case["id"] for case in all_v2]
    aliases = [case["scorerAlias"] for case in all_v2]
    if len(ids) != len(set(ids)) or len(aliases) != len(set(aliases)):
        errors.append("case IDs and scorer aliases must be globally unique")
    if any(re.fullmatch(r"WI-V1-1\d\d", alias) is None for alias in aliases):
        errors.append("every v2 case must have a stable WI-V1-1xx scorer alias")
    for case in all_v2:
        output = case["expected"]["modelOutput"]
        for validation_error in validator.iter_errors(output):
            location = ".".join(str(part) for part in validation_error.absolute_path) or "$"
            errors.append(f"{case['id']} expected model output invalid at {location}: {validation_error.message}")
        for validation_error in transport_validator.iter_errors(provider_transport_output(output)):
            location = ".".join(str(part) for part in validation_error.absolute_path) or "$"
            errors.append(
                f"{case['id']} expected model output invalid for provider transport at "
                f"{location}: {validation_error.message}"
            )
        shallow_strategy = STRATEGIES[TransportStrategyID.SHALLOW_STEP_V2_7]
        for validation_error in shallow_step_validator.iter_errors(
            shallow_strategy.project_output(output)
        ):
            location = ".".join(
                str(part) for part in validation_error.absolute_path
            ) or "$"
            errors.append(
                f"{case['id']} expected model output invalid for shallow-step transport at "
                f"{location}: {validation_error.message}"
            )
        flat_strategy = STRATEGIES[TransportStrategyID.FLAT_ENVELOPE_V2_8]
        for validation_error in flat_envelope_validator.iter_errors(
            flat_strategy.project_output(output)
        ):
            location = ".".join(
                str(part) for part in validation_error.absolute_path
            ) or "$"
            errors.append(
                f"{case['id']} expected model output invalid for flat-envelope transport at "
                f"{location}: {validation_error.message}"
            )
        semantic_json_strategy = STRATEGIES[TransportStrategyID.SEMANTIC_JSON_V2_9]
        for validation_error in semantic_json_validator.iter_errors(
            semantic_json_strategy.project_output(output)
        ):
            location = ".".join(
                str(part) for part in validation_error.absolute_path
            ) or "$"
            errors.append(
                f"{case['id']} expected model output invalid for semantic-json transport at "
                f"{location}: {validation_error.message}"
            )
        outcome = output["outcome"]
        if outcome["type"] != "proposal":
            paths = outcome["affectedPaths"]
            if paths != sorted(set(paths), key=PATH_RANK.__getitem__):
                errors.append(f"{case['id']} affectedPaths are not ordered and deduplicated")

    groups = {"v1": v1, "development": development, "heldout": heldout}
    normalized: dict[str, set[str]] = {
        name: {hashlib.sha256(normalize_prompt(case["prompt"]).encode()).hexdigest() for case in cases}
        for name, cases in groups.items()
    }
    skeletons: dict[str, set[str]] = {
        name: {hashlib.sha256(skeleton_prompt(case["prompt"]).encode()).hexdigest() for case in cases}
        for name, cases in groups.items()
    }
    for left, right in (("v1", "development"), ("v1", "heldout"), ("development", "heldout")):
        if normalized[left] & normalized[right]:
            errors.append(f"normalized prompt hash collision between {left} and {right}")
        if skeletons[left] & skeletons[right]:
            errors.append(f"prompt skeleton collision between {left} and {right}")
    dev_families = {case["scenarioFamily"] for case in development}
    held_families = {case["scenarioFamily"] for case in heldout}
    if dev_families & held_families:
        errors.append("development and heldout scenario families overlap")

    review = strict_json_load(SEMANTIC_REVIEW)
    if set(review["reviewedCaseIDs"]) != set(ids) or review["reviewStatus"] not in {
        "implementation-reviewed-pending-operator-ratification",
        "ratified-before-model-results",
    }:
        errors.append("semantic nonduplication review does not cover every v2 case")

    heldout_ids = set(case["id"] for case in heldout)
    for case in heldout:
        for strategy in STRATEGIES.values():
            visible = message_text(model_messages_for_strategy(case, strategy))
            if any(case_id in visible for case_id in heldout_ids):
                errors.append(
                    f"{case['id']}/{strategy.identifier.value} model-visible prompt "
                    "leaked a heldout case ID"
                )
            for forbidden in (
                "scenarioFamily",
                "scorerAlias",
                "unsupportedCapabilityHandling",
                "localValidatorOutcome",
                "localValidatorIssueCodes",
            ):
                if forbidden in visible:
                    errors.append(
                        f"{case['id']}/{strategy.identifier.value} model-visible prompt "
                        f"leaked {forbidden}"
                    )

    models = load_model_specs(MODELS)
    if len(models) != 5 or len({model.requested_model_id for model in models}) != 5:
        errors.append("model catalogue must contain the ratified five-model v2.3 set")
    paused = set(strict_json_load(MODELS).get("pausedAfterRateLimits", []))
    expected_paused = {
        "deepseek/deepseek-v4-flash-0731",
        "z-ai/glm-5.3-flash",
        "nvidia/nemotron-3-ultra-253b-a22b",
    }
    if paused != expected_paused or paused & {model.requested_model_id for model in models}:
        errors.append("the ratified 429 model pause set changed")
    for model in models:
        if not model.provider_endpoint:
            errors.append(f"{model.requested_model_id} has no provider endpoint")

    def schema_keywords(value: Any) -> set[str]:
        if isinstance(value, dict):
            return set(value) | set().union(*(schema_keywords(item) for item in value.values()), set())
        if isinstance(value, list):
            return set().union(*(schema_keywords(item) for item in value), set())
        return set()

    forbidden_transport_keywords = {
        "oneOf", "anyOf", "allOf", "const", "uniqueItems",
        "exclusiveMinimum", "exclusiveMaximum",
    }
    present = forbidden_transport_keywords & schema_keywords(transport_schema)
    if present:
        errors.append(f"provider transport contains unsupported keywords: {sorted(present)}")

    def has_multi_type(value: Any) -> bool:
        if isinstance(value, dict):
            return isinstance(value.get("type"), list) or any(
                has_multi_type(item) for item in value.values()
            )
        if isinstance(value, list):
            return any(has_multi_type(item) for item in value)
        return False

    if has_multi_type(transport_schema):
        errors.append("provider transport contains a multi-type declaration")

    queue5 = deterministic_queue(5)
    queue1 = deterministic_queue(1)
    strategy_queue5 = deterministic_strategy_queue(5)
    strategy_queue1 = deterministic_strategy_queue(1)
    flat_strategy_queue5 = deterministic_flat_strategy_queue(5)
    flat_strategy_queue1 = deterministic_flat_strategy_queue(1)
    semantic_json_strategy_queue5 = deterministic_semantic_json_strategy_queue(5)
    semantic_json_strategy_queue1 = deterministic_semantic_json_strategy_queue(1)
    if len(queue5) != 850 or len(queue1) != 170:
        errors.append("deterministic queue size changed")
    if len(strategy_queue5) != 850 or len(strategy_queue1) != 170:
        errors.append("v2.7 deterministic queue size changed")
    if strategy_queue5 != queue5 or strategy_queue1 != queue1:
        errors.append("v2.7 deterministic queue order changed")
    if flat_strategy_queue5 != queue5 or flat_strategy_queue1 != queue1:
        errors.append("v2.8 deterministic queue order changed")
    if (
        semantic_json_strategy_queue5 != queue5
        or semantic_json_strategy_queue1 != queue1
    ):
        errors.append("v2.9 deterministic queue order changed")

    policy = strict_json_load(RUN_POLICY)
    execution = policy.get("execution", {})
    if execution.get("globalConcurrency") != 1:
        errors.append("v2.3 global concurrency must be one")
    if execution.get("minimumInterCallDelaySeconds") != 2:
        errors.append("v2.3 inter-call delay must be two seconds")

    baseline_gemini = {
        model.requested_model_id: model
        for model in models
        if model.requested_model_id.startswith("google/gemini-")
    }
    expected_diagnostic_ids = {
        "google/gemini-3.5-flash-lite",
        "google/gemini-3.7-flash",
    }
    expected_diagnostic_execution = {
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "automaticRetries": 0,
        "httpConnectRetries": 0,
        "connectTimeoutSeconds": 15,
        "attemptTimeoutSeconds": 180,
        "cancelFlushSeconds": 15,
        "cache": False,
        "cachePrompt": False,
        "resumable": False,
    }
    expected_unchanged_inputs = {
        "prompt": "workout-import-prompt/v2",
        "providerTransportSchema": "workout-import-provider-transport/v2.3",
        "hostSemanticSchema": "workout-import-model-output/v2",
    }
    expected_diagnostic_scope = {
        "developmentCaseID": "WI-V2-D006",
        "warmupsPerModel": 1,
        "heldoutCalls": 0,
    }
    expected_diagnostic_spending = {
        "currency": "USD",
        "hardLimit": "2.00",
        "enforcement": "worstCaseBeforeEveryCallPlusEndpointPriceCap",
    }
    for version, model_path, policy_path, enabled, purpose in (
        (
            "v2.4",
            DIAGNOSTIC_MODELS_V2_4,
            DIAGNOSTIC_RUN_POLICY_V2_4,
            False,
            "isolate-reasoning-settings",
        ),
        (
            "v2.5",
            DIAGNOSTIC_MODELS,
            DIAGNOSTIC_RUN_POLICY,
            True,
            "test-required-reasoning-without-effort-or-exclusion",
        ),
    ):
        diagnostic_models = load_model_specs(model_path)
        if (
            len(diagnostic_models) != 2
            or {model.requested_model_id for model in diagnostic_models}
            != expected_diagnostic_ids
        ):
            errors.append(f"{version} diagnostic must contain exactly the two ratified Gemini models")
        for model in diagnostic_models:
            baseline = baseline_gemini.get(model.requested_model_id)
            if baseline is None or (
                model.canonical_revision,
                model.provider_endpoint,
                model.quantization,
                model.temperature,
                model.top_p,
            ) != (
                baseline.canonical_revision,
                baseline.provider_endpoint,
                baseline.quantization,
                baseline.temperature,
                baseline.top_p,
            ):
                errors.append(
                    f"{model.requested_model_id} {version} diagnostic changed a non-reasoning model control"
                )
            if model.reasoning != {"enabled": enabled, "effort": None, "exclude": False}:
                errors.append(f"{model.requested_model_id} {version} reasoning controls changed")
            if model.temperature != 0 or model.top_p != 1:
                errors.append(f"{model.requested_model_id} {version} sampling controls changed")
        diagnostic_policy = strict_json_load(policy_path)
        if diagnostic_policy.get("purpose") != purpose:
            errors.append(f"{version} diagnostic purpose changed")
        if diagnostic_policy.get("scope") != expected_diagnostic_scope:
            errors.append(f"{version} diagnostic scope changed")
        if diagnostic_policy.get("changedVariable") != {
            "reasoningEnabled": enabled,
            "reasoningEffort": None,
            "reasoningExcluded": False,
        }:
            errors.append(f"{version} diagnostic changed-variable declaration changed")
        if diagnostic_policy.get("unchangedInputs") != expected_unchanged_inputs:
            errors.append(f"{version} diagnostic unchanged-input declaration changed")
        if diagnostic_policy.get("execution") != expected_diagnostic_execution:
            errors.append(f"{version} diagnostic execution policy changed")
        if diagnostic_policy.get("spending") != expected_diagnostic_spending:
            errors.append(f"{version} diagnostic spending policy changed")

    curl_policy = strict_json_load(CURL_PROBE_POLICY)
    if curl_policy.get("runPolicyVersion") != "paceprompt-host-eval-curl-probe/v2.6":
        errors.append("v2.6 curl-probe policy version changed")
    if curl_policy.get("scope") != {
        "models": ["google/gemini-3.5-flash-lite", "google/gemini-3.7-flash"],
        "stagesPerModel": 5,
        "maximumCalls": 10,
        "heldoutCalls": 0,
        "developmentCaseID": "WI-V2-D006",
    }:
        errors.append("v2.6 curl-probe scope changed")
    if curl_policy.get("reasoning") != {
        "google/gemini-3.5-flash-lite": {"effort": "minimal"},
        "google/gemini-3.7-flash": {"effort": "medium"},
    }:
        errors.append("v2.6 curl-probe reasoning controls changed")
    if curl_policy.get("stages") != [
        {"id": "01-minimal-unstructured", "messages": "minimalSynthetic", "schema": "none"},
        {"id": "02-minimal-trivial-schema", "messages": "minimalSynthetic", "schema": "trivialStrict"},
        {"id": "03-minimal-full-schema", "messages": "minimalSynthetic", "schema": "providerTransportV2.3"},
        {"id": "04-full-prompt-trivial-schema", "messages": "promptV2EightFewShotPlusD006", "schema": "trivialStrict"},
        {"id": "05-full-prompt-full-schema", "messages": "promptV2EightFewShotPlusD006", "schema": "providerTransportV2.3"},
    ]:
        errors.append("v2.6 curl-probe stage order changed")
    if curl_policy.get("execution") != {
        "transport": "curl",
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "automaticRetries": 0,
        "connectTimeoutSeconds": 15,
        "attemptTimeoutSeconds": 180,
        "cancelFlushSeconds": 15,
        "cache": False,
        "resumable": False,
    }:
        errors.append("v2.6 curl-probe execution policy changed")
    if curl_policy.get("spending") != expected_diagnostic_spending:
        errors.append("v2.6 curl-probe spending policy changed")

    expected_strategy_assignments = {
        "openai/gpt-5.6-sol": "nestedV23",
        "anthropic/claude-sonnet-5": "nestedV23",
        "openai/gpt-5.6-luna": "nestedV23",
        "google/gemini-3.5-flash-lite": "shallowStepV27",
        "google/gemini-3.7-flash": "shallowStepV27",
    }
    strategy_assignments: dict[str, str] = {}
    for model in models:
        try:
            strategy_assignments[model.requested_model_id] = strategy_for(model).identifier.value
        except ValueError as error:
            errors.append(str(error))
    if strategy_assignments != expected_strategy_assignments:
        errors.append("v2.7 exact-route strategy assignments changed")

    strategy_full_models = load_model_specs(STRATEGY_MODELS)
    if [model.requested_model_id for model in strategy_full_models] != [
        model.requested_model_id for model in models
    ]:
        errors.append("v2.7 full model order or subset changed")
    baseline_by_id = {model.requested_model_id: model for model in models}
    expected_full_reasoning = {
        "openai/gpt-5.6-sol": {"enabled": False, "effort": "none", "exclude": False},
        "anthropic/claude-sonnet-5": {"enabled": False, "effort": None, "exclude": False},
        "openai/gpt-5.6-luna": {"enabled": False, "effort": "none", "exclude": False},
        "google/gemini-3.5-flash-lite": {"enabled": True, "effort": "minimal", "exclude": False},
        "google/gemini-3.7-flash": {"enabled": True, "effort": "medium", "exclude": False},
    }
    for model in strategy_full_models:
        baseline = baseline_by_id.get(model.requested_model_id)
        if baseline is None or (
            model.canonical_revision,
            model.provider_endpoint,
            model.quantization,
            model.role,
            model.temperature,
            model.top_p,
        ) != (
            baseline.canonical_revision,
            baseline.provider_endpoint,
            baseline.quantization,
            baseline.role,
            baseline.temperature,
            baseline.top_p,
        ):
            errors.append(f"{model.requested_model_id} v2.7 full route changed")
        if model.reasoning != expected_full_reasoning.get(model.requested_model_id):
            errors.append(f"{model.requested_model_id} v2.7 full reasoning changed")
        try:
            if strategy_for(model).identifier.value != expected_strategy_assignments.get(
                model.requested_model_id
            ):
                errors.append(f"{model.requested_model_id} v2.7 strategy changed")
        except ValueError as error:
            errors.append(str(error))
    full_paused = set(strict_json_load(STRATEGY_MODELS).get("pausedAfterRateLimits", []))
    if full_paused != expected_paused:
        errors.append("v2.7 paused 429 set changed")

    strategy_run_policy = strict_json_load(STRATEGY_RUN_POLICY)
    baseline_run_policy = strict_json_load(RUN_POLICY)
    for key in (
        "framework",
        "endpoint",
        "routing",
        "execution",
        "spending",
        "hardGates",
        "compositeWeights",
        "decision",
    ):
        if strategy_run_policy.get(key) != baseline_run_policy.get(key):
            errors.append(f"v2.7 full run policy changed frozen {key}")
    if strategy_run_policy.get("runPolicyVersion") != "paceprompt-host-eval-run-policy/v2.7":
        errors.append("v2.7 full run policy version changed")
    if strategy_run_policy.get("supersedesForNewRuns") != "paceprompt-host-eval-run-policy/v2.3":
        errors.append("v2.7 full run supersession changed")
    if strategy_run_policy.get("generation") != {
        "completionCount": 1,
        "maxOutputTokens": 8192,
        "seed": None,
        "stopSequences": None,
        "strictStructuredOutput": True,
        "providerTransportStrategies": {
            "nestedV23": "workout-import-provider-transport/v2.3",
            "shallowStepV27": "workout-import-provider-transport-shallow-step/v2.7",
        },
        "routeStrategyRegistry": "closedExactRouteRegistry",
        "unknownRouteBehaviour": "failClosed",
        "hostSemanticSchema": "workout-import-model-output/v2",
    }:
        errors.append("v2.7 full generation policy changed")

    strategy_models = load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)
    if (
        len(strategy_models) != 2
        or {model.requested_model_id for model in strategy_models}
        != expected_diagnostic_ids
    ):
        errors.append("v2.7 strategy diagnostic must contain exactly the two Gemini models")
    expected_reasoning = {
        "google/gemini-3.5-flash-lite": {
            "enabled": True,
            "effort": "minimal",
            "exclude": False,
        },
        "google/gemini-3.7-flash": {
            "enabled": True,
            "effort": "medium",
            "exclude": False,
        },
    }
    for model in strategy_models:
        baseline = baseline_gemini.get(model.requested_model_id)
        if baseline is None or (
            model.canonical_revision,
            model.provider_endpoint,
            model.quantization,
            model.temperature,
            model.top_p,
        ) != (
            baseline.canonical_revision,
            baseline.provider_endpoint,
            baseline.quantization,
            baseline.temperature,
            baseline.top_p,
        ):
            errors.append(
                f"{model.requested_model_id} v2.7 diagnostic changed a pinned route or sampling control"
            )
        if model.reasoning != expected_reasoning.get(model.requested_model_id):
            errors.append(f"{model.requested_model_id} v2.7 reasoning controls changed")
        try:
            strategy = strategy_for(model)
            if strategy.identifier is not TransportStrategyID.SHALLOW_STEP_V2_7:
                errors.append(f"{model.requested_model_id} is not assigned shallowStepV27")
        except ValueError as error:
            errors.append(str(error))

    expected_strategy_policy = {
        "registry": "closedExactRouteRegistry",
        "unknownRouteBehaviour": "failClosed",
        "google/gemini-3.5-flash-lite": "shallowStepV27",
        "google/gemini-3.7-flash": "shallowStepV27",
    }
    strategy_policy = strict_json_load(STRATEGY_DIAGNOSTIC_RUN_POLICY)
    if strategy_policy.get("runPolicyVersion") != (
        "paceprompt-host-eval-gemini-transport-strategy/v2.7"
    ):
        errors.append("v2.7 strategy diagnostic policy version changed")
    if strategy_policy.get("purpose") != (
        "verify-shared-shallow-step-strategy-through-inspect-before-heldout-evaluation"
    ):
        errors.append("v2.7 strategy diagnostic purpose changed")
    if strategy_policy.get("scope") != {
        "developmentCaseID": "WI-V2-D006",
        "warmupsPerModel": 1,
        "maximumCalls": 2,
        "heldoutCalls": 0,
    }:
        errors.append("v2.7 strategy diagnostic scope changed")
    if strategy_policy.get("strategy") != expected_strategy_policy:
        errors.append("v2.7 route strategy policy changed")
    if strategy_policy.get("reasoning") != expected_reasoning:
        errors.append("v2.7 strategy diagnostic reasoning policy changed")
    if strategy_policy.get("execution") != expected_diagnostic_execution:
        errors.append("v2.7 strategy diagnostic execution policy changed")
    if strategy_policy.get("spending") != expected_diagnostic_spending:
        errors.append("v2.7 strategy diagnostic spending policy changed")

    expected_flat_assignments = expected_strategy_assignments | {
        "google/gemini-3.5-flash-lite": "flatEnvelopeV28",
        "google/gemini-3.7-flash": "flatEnvelopeV28",
    }
    flat_models = load_model_specs(FLAT_STRATEGY_MODELS)
    if [model.requested_model_id for model in flat_models] != [
        model.requested_model_id for model in strategy_full_models
    ]:
        errors.append("v2.8 full model order or subset changed")
    v27_by_id = {model.requested_model_id: model for model in strategy_full_models}
    flat_assignments: dict[str, str] = {}
    for model in flat_models:
        baseline = v27_by_id.get(model.requested_model_id)
        if baseline is None or (
            model.canonical_revision,
            model.provider_endpoint,
            model.quantization,
            model.role,
            model.temperature,
            model.top_p,
            model.reasoning,
        ) != (
            baseline.canonical_revision,
            baseline.provider_endpoint,
            baseline.quantization,
            baseline.role,
            baseline.temperature,
            baseline.top_p,
            baseline.reasoning,
        ):
            errors.append(f"{model.requested_model_id} v2.8 changed a non-strategy model control")
        if model.transport_registry_id != "strategyRegistryV28":
            errors.append(f"{model.requested_model_id} v2.8 registry changed")
        try:
            flat_assignments[model.requested_model_id] = strategy_for(model).identifier.value
        except ValueError as error:
            errors.append(str(error))
    if flat_assignments != expected_flat_assignments:
        errors.append("v2.8 exact-route strategy assignments changed")
    if set(strict_json_load(FLAT_STRATEGY_MODELS).get("pausedAfterRateLimits", [])) != expected_paused:
        errors.append("v2.8 paused 429 set changed")

    flat_run_policy = strict_json_load(FLAT_STRATEGY_RUN_POLICY)
    for key in (
        "framework",
        "endpoint",
        "routing",
        "execution",
        "spending",
        "hardGates",
        "compositeWeights",
        "decision",
    ):
        if flat_run_policy.get(key) != strategy_run_policy.get(key):
            errors.append(f"v2.8 full run policy changed frozen {key}")
    if flat_run_policy.get("runPolicyVersion") != "paceprompt-host-eval-run-policy/v2.8":
        errors.append("v2.8 full run policy version changed")
    if flat_run_policy.get("supersedesForNewRuns") != "paceprompt-host-eval-run-policy/v2.7":
        errors.append("v2.8 full run supersession changed")
    if flat_run_policy.get("generation") != {
        "completionCount": 1,
        "maxOutputTokens": 8192,
        "seed": None,
        "stopSequences": None,
        "strictStructuredOutput": True,
        "providerTransportStrategies": {
            "nestedV23": "workout-import-provider-transport/v2.3",
            "flatEnvelopeV28": "workout-import-provider-transport-flat-envelope/v2.8",
        },
        "routeStrategyRegistry": "strategyRegistryV28",
        "unknownRouteBehaviour": "failClosed",
        "hostSemanticSchema": "workout-import-model-output/v2",
    }:
        errors.append("v2.8 full generation policy changed")

    flat_diagnostic_models = load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS)
    if (
        len(flat_diagnostic_models) != 2
        or {model.requested_model_id for model in flat_diagnostic_models}
        != expected_diagnostic_ids
    ):
        errors.append("v2.8 diagnostic must contain exactly the two Gemini models")
    for model in flat_diagnostic_models:
        baseline = next(
            (item for item in flat_models if item.requested_model_id == model.requested_model_id),
            None,
        )
        if baseline is None or model != ModelSpec(
            requested_model_id=baseline.requested_model_id,
            canonical_revision=baseline.canonical_revision,
            provider_endpoint=baseline.provider_endpoint,
            quantization=baseline.quantization,
            role="compatibilityDiagnostic",
            temperature=baseline.temperature,
            top_p=baseline.top_p,
            reasoning=baseline.reasoning,
            transport_strategy_id=baseline.transport_strategy_id,
            transport_registry_id=baseline.transport_registry_id,
        ):
            errors.append(f"{model.requested_model_id} v2.8 diagnostic model controls changed")
        try:
            if strategy_for(model).identifier is not TransportStrategyID.FLAT_ENVELOPE_V2_8:
                errors.append(f"{model.requested_model_id} is not assigned flatEnvelopeV28")
        except ValueError as error:
            errors.append(str(error))

    flat_diagnostic_policy = strict_json_load(FLAT_STRATEGY_DIAGNOSTIC_RUN_POLICY)
    if flat_diagnostic_policy.get("runPolicyVersion") != (
        "paceprompt-host-eval-gemini-flat-envelope/v2.8"
    ):
        errors.append("v2.8 diagnostic policy version changed")
    if flat_diagnostic_policy.get("purpose") != (
        "verify-flat-envelope-strategy-through-inspect-before-heldout-evaluation"
    ):
        errors.append("v2.8 diagnostic purpose changed")
    if flat_diagnostic_policy.get("scope") != {
        "developmentCaseID": "WI-V2-D006",
        "warmupsPerModel": 1,
        "maximumCalls": 2,
        "heldoutCalls": 0,
    }:
        errors.append("v2.8 diagnostic scope changed")
    if flat_diagnostic_policy.get("strategy") != {
        "registry": "strategyRegistryV28",
        "selection": "closedExactRouteRegistry",
        "unknownRouteBehaviour": "failClosed",
        "google/gemini-3.5-flash-lite": "flatEnvelopeV28",
        "google/gemini-3.7-flash": "flatEnvelopeV28",
    }:
        errors.append("v2.8 diagnostic strategy policy changed")
    if flat_diagnostic_policy.get("reasoning") != expected_reasoning:
        errors.append("v2.8 diagnostic reasoning policy changed")
    if flat_diagnostic_policy.get("execution") != expected_diagnostic_execution:
        errors.append("v2.8 diagnostic execution policy changed")
    if flat_diagnostic_policy.get("spending") != expected_diagnostic_spending:
        errors.append("v2.8 diagnostic spending policy changed")

    expected_semantic_json_assignments = expected_strategy_assignments | {
        "google/gemini-3.5-flash-lite": "semanticJsonV29",
        "google/gemini-3.7-flash": "semanticJsonV29",
    }
    semantic_json_models = load_model_specs(SEMANTIC_JSON_STRATEGY_MODELS)
    if [model.requested_model_id for model in semantic_json_models] != [
        model.requested_model_id for model in flat_models
    ]:
        errors.append("v2.9 full model order or subset changed")
    flat_by_id = {model.requested_model_id: model for model in flat_models}
    semantic_json_assignments: dict[str, str] = {}
    for model in semantic_json_models:
        baseline = flat_by_id.get(model.requested_model_id)
        if baseline is None or (
            model.canonical_revision,
            model.provider_endpoint,
            model.quantization,
            model.role,
            model.temperature,
            model.top_p,
            model.reasoning,
        ) != (
            baseline.canonical_revision,
            baseline.provider_endpoint,
            baseline.quantization,
            baseline.role,
            baseline.temperature,
            baseline.top_p,
            baseline.reasoning,
        ):
            errors.append(f"{model.requested_model_id} v2.9 changed a non-strategy model control")
        if model.transport_registry_id != "strategyRegistryV29":
            errors.append(f"{model.requested_model_id} v2.9 registry changed")
        try:
            semantic_json_assignments[model.requested_model_id] = (
                strategy_for(model).identifier.value
            )
        except ValueError as error:
            errors.append(str(error))
    if semantic_json_assignments != expected_semantic_json_assignments:
        errors.append("v2.9 exact-route strategy assignments changed")
    if set(
        strict_json_load(SEMANTIC_JSON_STRATEGY_MODELS).get(
            "pausedAfterRateLimits", []
        )
    ) != expected_paused:
        errors.append("v2.9 paused 429 set changed")

    semantic_json_run_policy = strict_json_load(SEMANTIC_JSON_STRATEGY_RUN_POLICY)
    for key in (
        "framework",
        "endpoint",
        "routing",
        "execution",
        "spending",
        "hardGates",
        "compositeWeights",
        "decision",
    ):
        if semantic_json_run_policy.get(key) != flat_run_policy.get(key):
            errors.append(f"v2.9 full run policy changed frozen {key}")
    if semantic_json_run_policy.get("runPolicyVersion") != (
        "paceprompt-host-eval-run-policy/v2.9"
    ):
        errors.append("v2.9 full run policy version changed")
    if semantic_json_run_policy.get("supersedesForNewRuns") != (
        "paceprompt-host-eval-run-policy/v2.8"
    ):
        errors.append("v2.9 full run supersession changed")
    if semantic_json_run_policy.get("generation") != {
        "completionCount": 1,
        "maxOutputTokens": 8192,
        "seed": None,
        "stopSequences": None,
        "strictStructuredOutput": True,
        "providerTransportStrategies": {
            "nestedV23": "workout-import-provider-transport/v2.3",
            "semanticJsonV29": "workout-import-provider-transport-semantic-json/v2.9",
        },
        "routeStrategyRegistry": "strategyRegistryV29",
        "schemaProfiles": {
            "nestedV23": "portableStrictV23",
            "semanticJsonV29": "googleGeminiMinimalV29",
        },
        "unknownRouteBehaviour": "failClosed",
        "hostSemanticSchema": "workout-import-model-output/v2",
    }:
        errors.append("v2.9 full generation policy changed")

    semantic_json_diagnostic_models = load_model_specs(
        SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS
    )
    if (
        len(semantic_json_diagnostic_models) != 2
        or {model.requested_model_id for model in semantic_json_diagnostic_models}
        != expected_diagnostic_ids
    ):
        errors.append("v2.9 diagnostic must contain exactly the two Gemini models")
    for model in semantic_json_diagnostic_models:
        baseline = next(
            (
                item
                for item in semantic_json_models
                if item.requested_model_id == model.requested_model_id
            ),
            None,
        )
        if baseline is None or model != ModelSpec(
            requested_model_id=baseline.requested_model_id,
            canonical_revision=baseline.canonical_revision,
            provider_endpoint=baseline.provider_endpoint,
            quantization=baseline.quantization,
            role="compatibilityDiagnostic",
            temperature=baseline.temperature,
            top_p=baseline.top_p,
            reasoning=baseline.reasoning,
            transport_strategy_id=baseline.transport_strategy_id,
            transport_registry_id=baseline.transport_registry_id,
        ):
            errors.append(f"{model.requested_model_id} v2.9 diagnostic model controls changed")
        try:
            strategy = strategy_for(model)
            if strategy.identifier is not TransportStrategyID.SEMANTIC_JSON_V2_9:
                errors.append(f"{model.requested_model_id} is not assigned semanticJsonV29")
            if strategy.schema_profile.identifier.value != "googleGeminiMinimalV29":
                errors.append(f"{model.requested_model_id} has the wrong schema profile")
        except ValueError as error:
            errors.append(str(error))

    semantic_json_diagnostic_policy = strict_json_load(
        SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_RUN_POLICY
    )
    if semantic_json_diagnostic_policy.get("runPolicyVersion") != (
        "paceprompt-host-eval-gemini-semantic-json/v2.9"
    ):
        errors.append("v2.9 diagnostic policy version changed")
    if semantic_json_diagnostic_policy.get("purpose") != (
        "verify-profile-validated-semantic-json-strategy-through-inspect-before-heldout-evaluation"
    ):
        errors.append("v2.9 diagnostic purpose changed")
    if semantic_json_diagnostic_policy.get("scope") != {
        "developmentCaseID": "WI-V2-D006",
        "warmupsPerModel": 1,
        "maximumCalls": 2,
        "heldoutCalls": 0,
    }:
        errors.append("v2.9 diagnostic scope changed")
    if semantic_json_diagnostic_policy.get("strategy") != {
        "registry": "strategyRegistryV29",
        "selection": "closedExactRouteRegistry",
        "unknownRouteBehaviour": "failClosed",
        "google/gemini-3.5-flash-lite": "semanticJsonV29",
        "google/gemini-3.7-flash": "semanticJsonV29",
    }:
        errors.append("v2.9 diagnostic strategy policy changed")
    if semantic_json_diagnostic_policy.get("schemaProfiles") != {
        "selection": "ownedByTransportStrategy",
        "validation": "offlineBeforePayloadConstruction",
        "google/gemini-3.5-flash-lite": "googleGeminiMinimalV29",
        "google/gemini-3.7-flash": "googleGeminiMinimalV29",
    }:
        errors.append("v2.9 diagnostic schema-profile policy changed")
    if semantic_json_diagnostic_policy.get("reasoning") != expected_reasoning:
        errors.append("v2.9 diagnostic reasoning policy changed")
    if semantic_json_diagnostic_policy.get("execution") != expected_diagnostic_execution:
        errors.append("v2.9 diagnostic execution policy changed")
    if semantic_json_diagnostic_policy.get("spending") != expected_diagnostic_spending:
        errors.append("v2.9 diagnostic spending policy changed")

    for name, candidate in (
        ("nestedV23", transport_schema),
        ("shallowStepV27", shallow_step_schema),
        ("flatEnvelopeV28", flat_envelope_schema),
        ("semanticJsonV29", semantic_json_schema),
    ):
        try:
            Draft202012Validator.check_schema(candidate)
        except Exception as error:
            errors.append(f"{name} is not a valid Draft 2020-12 schema: {error}")
        present = forbidden_transport_keywords & schema_keywords(candidate)
        if present:
            errors.append(f"{name} contains unsupported keywords: {sorted(present)}")
        if has_multi_type(candidate):
            errors.append(f"{name} contains a multi-type declaration")

    for strategy in STRATEGIES.values():
        for profile_error in strategy.schema_profile.validate(strategy.schema()):
            errors.append(
                f"{strategy.identifier.value}/{strategy.schema_profile.identifier.value}: "
                f"{profile_error}"
            )

    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "developmentCases": len(development),
        "heldoutCases": len(heldout),
        "fewShotCases": len(examples),
        "models": len(models),
        "fiveRepetitionAttempts": len(queue5),
        "oneRepetitionAttempts": len(queue1),
        "strategyFiveRepetitionAttempts": len(strategy_queue5),
        "strategyOneRepetitionAttempts": len(strategy_queue1),
        "flatStrategyFiveRepetitionAttempts": len(flat_strategy_queue5),
        "flatStrategyOneRepetitionAttempts": len(flat_strategy_queue1),
        "semanticJsonStrategyFiveRepetitionAttempts": len(
            semantic_json_strategy_queue5
        ),
        "semanticJsonStrategyOneRepetitionAttempts": len(
            semantic_json_strategy_queue1
        ),
        "queueHashes": {"five": canonical_hash(queue5), "one": canonical_hash(queue1)},
        "strategyQueueHashes": {
            "five": canonical_hash(strategy_queue5),
            "one": canonical_hash(strategy_queue1),
        },
        "flatStrategyQueueHashes": {
            "five": canonical_hash(flat_strategy_queue5),
            "one": canonical_hash(flat_strategy_queue1),
        },
        "semanticJsonStrategyQueueHashes": {
            "five": canonical_hash(semantic_json_strategy_queue5),
            "one": canonical_hash(semantic_json_strategy_queue1),
        },
        "artifactHashes": artifact_hashes(),
        "strategyAssignments": strategy_assignments,
        "flatStrategyAssignments": flat_assignments,
        "semanticJsonStrategyAssignments": semantic_json_assignments,
        "strategySchemaProfiles": {
            identifier.value: strategy.schema_profile.identifier.value
            for identifier, strategy in STRATEGIES.items()
        },
        "strategySchemaHashes": {
            identifier.value: sha256_file(strategy.schema_path)
            for identifier, strategy in STRATEGIES.items()
        },
    }


def verify() -> dict[str, Any]:
    """Verify immutable v2 evidence and, once integrated, the sealed v3 slice."""

    report = _verify_v2()
    v3_prompt = HOST_EVAL_ROOT / "prompts" / "v3" / "system.md"
    if v3_prompt.exists():
        from .v3 import verify as verify_v3

        v3_report = verify_v3()
        report["v3"] = v3_report
        report["errors"].extend(f"v3: {error}" for error in v3_report["errors"])
        report["status"] = "valid" if not report["errors"] else "invalid"
    return report


def safe_run_dir(run_id: str, *, create: bool) -> Path:
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}", run_id) is None:
        raise ValueError("run ID contains unsupported characters")
    root = RUNS_ROOT.resolve()
    candidate = (RUNS_ROOT / run_id).resolve()
    if candidate.parent != root:
        raise ValueError("run directory escaped the ignored evidence root")
    if create:
        candidate.mkdir(parents=True, exist_ok=False)
    return candidate


def max_price_per_million(selected: dict[str, Any]) -> dict[str, float]:
    scale = Decimal("1000000")
    return {
        "prompt": float(Decimal(selected["inputPricePerToken"]) * scale),
        "completion": float(Decimal(selected["outputPricePerToken"]) * scale),
    }


async def _write_mock_payloads(
    run_dir: Path,
    report: dict[str, Any],
    selected_endpoints: list[dict[str, Any]] | None = None,
    *,
    specs: tuple[ModelSpec, ...] | None = None,
    case: dict[str, Any] | None = None,
) -> dict[str, Any]:
    run_id = run_dir.name
    (run_dir / "mock-payloads").mkdir()
    schema = strict_json_load(TRANSPORT_SCHEMA)
    active_case = case or load_cases(HELDOUT_CASES)[0]
    active_specs = specs or load_model_specs(MODELS)
    selected = {
        item["requestedModelID"]: item for item in (selected_endpoints or [])
    }
    payload_hashes: dict[str, str] = {}
    for spec in active_specs:
        price = max_price_per_million(selected[spec.requested_model_id]) if selected else None
        payload = await capture_wire_payload(
            spec, schema, model_messages(active_case), max_price_per_million=price
        )
        assert_payload_controls(payload, spec, schema, price)
        name = spec.requested_model_id.replace("/", "--") + ".json"
        path = run_dir / "mock-payloads" / name
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        payload_hashes[spec.requested_model_id] = sha256_file(path)
    evidence = {
        "evidenceType": "offlineMockOnly",
        "runID": run_id,
        "providerCalls": 0,
        "spendUSD": "0.00",
        "payloadHashes": payload_hashes,
        "verification": report,
    }
    (run_dir / "mock-summary.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return evidence


async def mock_payloads(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    return await _write_mock_payloads(run_dir, report)


async def _write_strategy_mock_payloads(
    run_dir: Path,
    report: dict[str, Any],
    selected_endpoints: list[dict[str, Any]],
    *,
    specs: tuple[ModelSpec, ...] | None = None,
) -> dict[str, Any]:
    mock_dir = run_dir / "mock-payloads"
    mock_dir.mkdir()
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    active_specs = specs or load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)
    selected = {item["requestedModelID"]: item for item in selected_endpoints}
    payload_hashes: dict[str, str] = {}
    assignments: list[dict[str, str]] = []
    for spec in active_specs:
        strategy = strategy_for(spec)
        schema = strategy.schema()
        price = max_price_per_million(selected[spec.requested_model_id])
        payload = await capture_wire_payload(
            spec,
            schema,
            model_messages_for_strategy(warmup, strategy),
            max_price_per_million=price,
            schema_name=strategy.schema_name,
            mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
        )
        assert_payload_controls(
            payload,
            spec,
            schema,
            price,
            schema_name=strategy.schema_name,
        )
        name = spec.requested_model_id.replace("/", "--") + ".json"
        path = mock_dir / name
        path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        payload_hashes[spec.requested_model_id] = sha256_file(path)
        assignments.append(
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": spec.canonical_revision or "",
                "providerEndpoint": spec.provider_endpoint,
                "transportStrategy": strategy.identifier.value,
                "schemaProfile": strategy.schema_profile.identifier.value,
                "schemaName": strategy.schema_name,
                "schemaSha256": sha256_file(strategy.schema_path),
            }
        )
    evidence = {
        "evidenceType": "offlineStrategyMockOnly",
        "runID": run_dir.name,
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "payloadHashes": payload_hashes,
        "strategyAssignments": assignments,
        "verification": report,
    }
    (run_dir / "mock-summary.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return evidence


def _strategy_assignments(specs: tuple[ModelSpec, ...]) -> list[dict[str, str]]:
    return [
        {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision or "",
            "providerEndpoint": spec.provider_endpoint,
            "transportStrategy": strategy_for(spec).identifier.value,
            "schemaProfile": strategy_for(spec).schema_profile.identifier.value,
            "schemaName": strategy_for(spec).schema_name,
            "schemaSha256": sha256_file(strategy_for(spec).schema_path),
        }
        for spec in specs
    ]


def _cost_preflight(snapshot: dict[str, Any]) -> dict[str, Any]:
    cases = load_cases(HELDOUT_CASES)
    warmup = next(case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006")
    schema_bytes = len(TRANSPORT_SCHEMA.read_bytes())
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_model_one: dict[str, Decimal] = {}
    for spec in load_model_specs(MODELS):
        price = prices[spec.requested_model_id]

        def cost(case: dict[str, Any]) -> Decimal:
            input_bytes = len(message_text(model_messages(case)).encode("utf-8")) + schema_bytes
            return conservative_call_cost(
                input_utf8_bytes=input_bytes,
                input_price=price["inputPricePerToken"],
                output_price=price["outputPricePerToken"],
            )

        per_model_one[spec.requested_model_id] = cost(warmup) + sum(cost(case) for case in cases)
    one = sum(per_model_one.values(), Decimal("0"))
    # Warm-ups occur once. Five repetitions multiply only the 34 scored cases.
    warmups = Decimal("0")
    scored_one = Decimal("0")
    for spec in load_model_specs(MODELS):
        price = prices[spec.requested_model_id]
        warmup_bytes = len(message_text(model_messages(warmup)).encode("utf-8")) + schema_bytes
        warmup_cost = conservative_call_cost(
            input_utf8_bytes=warmup_bytes,
            input_price=price["inputPricePerToken"],
            output_price=price["outputPricePerToken"],
        )
        warmups += warmup_cost
        scored_one += per_model_one[spec.requested_model_id] - warmup_cost
    five = warmups + Decimal(5) * scored_one
    repetitions = choose_repetitions(
        five_repetition_worst_case=five, one_repetition_worst_case=one
    )
    return {
        "method": "utf8-byte-token-upper-bound-plus-4096-framing-tokens-and-8192-output-tokens-per-call",
        "hardLimitUSD": "20.00",
        "fiveRepetitionWorstCaseUSD": format(five, "f"),
        "oneRepetitionWorstCaseUSD": format(one, "f"),
        "selectedRepetitions": repetitions,
        "admitted": repetitions in {1, 5},
        "perModelOneRepetitionWorstCaseUSD": {
            key: format(value, "f") for key, value in per_model_one.items()
        },
    }


def _diagnostic_cost_preflight(snapshot: dict[str, Any]) -> dict[str, Any]:
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    schema_bytes = len(TRANSPORT_SCHEMA.read_bytes())
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_model: dict[str, Decimal] = {}
    for spec in load_model_specs(DIAGNOSTIC_MODELS):
        price = prices[spec.requested_model_id]
        input_bytes = len(message_text(model_messages(warmup)).encode("utf-8")) + schema_bytes
        per_model[spec.requested_model_id] = conservative_call_cost(
            input_utf8_bytes=input_bytes,
            input_price=price["inputPricePerToken"],
            output_price=price["outputPricePerToken"],
        )
    total = sum(per_model.values(), Decimal("0"))
    return {
        "method": "utf8-byte-token-upper-bound-plus-4096-framing-tokens-and-8192-output-tokens-per-call",
        "hardLimitUSD": "2.00",
        "callCount": 2,
        "heldoutCalls": 0,
        "worstCaseUSD": format(total, "f"),
        "admitted": total <= Decimal("2.00"),
        "perModelWorstCaseUSD": {
            key: format(value, "f") for key, value in per_model.items()
        },
    }


def _strategy_diagnostic_cost_preflight(
    snapshot: dict[str, Any],
    model_path: Path = STRATEGY_DIAGNOSTIC_MODELS,
) -> dict[str, Any]:
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_model: dict[str, Decimal] = {}
    for spec in load_model_specs(model_path):
        strategy = strategy_for(spec)
        price = prices[spec.requested_model_id]
        input_bytes = (
            len(message_text(model_messages_for_strategy(warmup, strategy)).encode("utf-8"))
            + strategy.schema_file_bytes()
        )
        per_model[spec.requested_model_id] = conservative_call_cost(
            input_utf8_bytes=input_bytes,
            input_price=price["inputPricePerToken"],
            output_price=price["outputPricePerToken"],
        )
    total = sum(per_model.values(), Decimal("0"))
    return {
        "method": "strategy-specific-prompt-plus-schema-utf8-byte-upper-bound-plus-4096-framing-tokens-and-8192-output-tokens-per-call",
        "hardLimitUSD": "2.00",
        "callCount": 2,
        "heldoutCalls": 0,
        "worstCaseUSD": format(total, "f"),
        "admitted": total <= Decimal("2.00"),
        "perModelWorstCaseUSD": {
            key: format(value, "f") for key, value in per_model.items()
        },
    }


def _strategy_cost_preflight(
    snapshot: dict[str, Any], model_path: Path = STRATEGY_MODELS
) -> dict[str, Any]:
    cases = load_cases(HELDOUT_CASES)
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_model_warmup: dict[str, Decimal] = {}
    per_model_scored: dict[str, Decimal] = {}
    for spec in load_model_specs(model_path):
        strategy = strategy_for(spec)
        price = prices[spec.requested_model_id]

        def cost(case: dict[str, Any]) -> Decimal:
            input_bytes = (
                len(
                    message_text(model_messages_for_strategy(case, strategy)).encode(
                        "utf-8"
                    )
                )
                + strategy.schema_file_bytes()
            )
            return conservative_call_cost(
                input_utf8_bytes=input_bytes,
                input_price=price["inputPricePerToken"],
                output_price=price["outputPricePerToken"],
            )

        per_model_warmup[spec.requested_model_id] = cost(warmup)
        per_model_scored[spec.requested_model_id] = sum(
            (cost(case) for case in cases), Decimal("0")
        )
    warmups = sum(per_model_warmup.values(), Decimal("0"))
    scored_one = sum(per_model_scored.values(), Decimal("0"))
    one = warmups + scored_one
    five = warmups + Decimal(5) * scored_one
    repetitions = choose_repetitions(
        five_repetition_worst_case=five, one_repetition_worst_case=one
    )
    return {
        "method": "per-route-strategy-prompt-plus-schema-utf8-byte-upper-bound-plus-4096-framing-tokens-and-8192-output-tokens-per-call",
        "hardLimitUSD": "20.00",
        "fiveRepetitionWorstCaseUSD": format(five, "f"),
        "oneRepetitionWorstCaseUSD": format(one, "f"),
        "selectedRepetitions": repetitions,
        "admitted": repetitions in {1, 5},
        "perModelOneRepetitionWorstCaseUSD": {
            model_id: format(
                per_model_warmup[model_id] + per_model_scored[model_id], "f"
            )
            for model_id in per_model_warmup
        },
    }


def curl_version() -> str:
    result = subprocess.run(
        ["curl", "--version"], check=True, capture_output=True, text=True
    )
    return result.stdout.splitlines()[0]


async def _write_curl_probe_payloads(
    run_dir: Path, selected_endpoints: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    payload_dir = run_dir / "curl-payloads"
    payload_dir.mkdir()
    schema = strict_json_load(TRANSPORT_SCHEMA)
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    policy = strict_json_load(CURL_PROBE_POLICY)
    selected = {item["requestedModelID"]: item for item in selected_endpoints}
    specs = load_model_specs(DIAGNOSTIC_MODELS)
    base_bodies: dict[str, dict[str, Any]] = {}
    for spec in specs:
        price = max_price_per_million(selected[spec.requested_model_id])
        captured = await capture_wire_payload(
            spec,
            schema,
            model_messages(warmup),
            max_price_per_million=price,
        )
        assert_payload_controls(captured, spec, schema, price)
        body = deepcopy(captured["body"])
        body["reasoning"] = deepcopy(policy["reasoning"][spec.requested_model_id])
        base_bodies[spec.requested_model_id] = body

    minimal_messages = [
        {
            "role": "user",
            "content": "Return a JSON object whose ok property is true.",
        }
    ]
    trivial_response_format = {
        "type": "json_schema",
        "json_schema": {
            "name": "paceprompt_curl_probe_trivial_v2_6",
            "description": "A minimal provider compatibility response.",
            "schema": {
                "type": "object",
                "properties": {"ok": {"type": "boolean"}},
                "required": ["ok"],
                "additionalProperties": False,
            },
            "strict": True,
        },
    }
    manifest: list[dict[str, Any]] = []
    for stage in policy["stages"]:
        for spec in specs:
            body = deepcopy(base_bodies[spec.requested_model_id])
            if stage["messages"] == "minimalSynthetic":
                body["messages"] = deepcopy(minimal_messages)
            if stage["schema"] == "none":
                body.pop("response_format", None)
            elif stage["schema"] == "trivialStrict":
                body["response_format"] = deepcopy(trivial_response_format)
            elif stage["schema"] != "providerTransportV2.3":
                raise RuntimeError(f"unsupported curl-probe schema stage {stage['schema']}")
            attempt_id = (
                f"{stage['id']}-{spec.requested_model_id.replace('/', '--')}"
            )
            relative_path = Path("curl-payloads") / f"{attempt_id}.json"
            payload_path = run_dir / relative_path
            payload_path.write_text(
                json.dumps(body, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
            manifest.append(
                {
                    "attemptID": attempt_id,
                    "modelID": spec.requested_model_id,
                    "stageID": stage["id"],
                    "messages": stage["messages"],
                    "schema": stage["schema"],
                    "payloadPath": str(relative_path),
                    "payloadSha256": sha256_file(payload_path),
                }
            )
    if len(manifest) != policy["scope"]["maximumCalls"]:
        raise RuntimeError("curl-probe manifest call count differs from policy")
    (run_dir / "curl-probe-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (run_dir / "curl-mock-summary.json").write_text(
        json.dumps(
            {
                "evidenceType": "offlineCurlPayloadsOnly",
                "runID": run_dir.name,
                "providerCalls": 0,
                "spendUSD": "0.00",
                "payloadCount": len(manifest),
                "manifestSha256": sha256_file(run_dir / "curl-probe-manifest.json"),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return manifest


def _curl_probe_cost_preflight(
    snapshot: dict[str, Any], run_dir: Path, manifest: list[dict[str, Any]]
) -> dict[str, Any]:
    prices = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_attempt: dict[str, Decimal] = {}
    for probe in manifest:
        selected = prices[probe["modelID"]]
        per_attempt[probe["attemptID"]] = conservative_call_cost(
            input_utf8_bytes=(run_dir / probe["payloadPath"]).stat().st_size,
            input_price=selected["inputPricePerToken"],
            output_price=selected["outputPricePerToken"],
        )
    total = sum(per_attempt.values(), Decimal("0"))
    return {
        "method": "serialized-payload-utf8-byte-upper-bound-plus-4096-framing-tokens-and-8192-output-tokens-per-call",
        "hardLimitUSD": "2.00",
        "callCount": len(manifest),
        "heldoutCalls": 0,
        "worstCaseUSD": format(total, "f"),
        "admitted": len(manifest) == 10 and total <= Decimal("2.00"),
        "perAttemptWorstCaseUSD": {
            key: format(value, "f") for key, value in per_attempt.items()
        },
    }


async def prepare_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    snapshot = snapshot_catalogue(run_dir / "catalogue", load_model_specs(MODELS))
    mocks = await _write_mock_payloads(run_dir, report, snapshot["selected"])
    preflight = _cost_preflight(snapshot)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-operator-gate/v2.3",
        "runID": run_id,
        "status": "awaitingHumanRatification" if preflight["admitted"] else "blockedBySpendingLimit",
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "artifactHashes": report["artifactHashes"],
        "queueHashes": report["queueHashes"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-bounded-spend",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_"
        + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_strategy_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(STRATEGY_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"], specs=specs
    )
    preflight = _strategy_cost_preflight(snapshot)
    policy = strict_json_load(STRATEGY_RUN_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-operator-gate/v2.7",
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "artifactHashes": report["artifactHashes"],
        "queueHashes": report["strategyQueueHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "runPolicy": policy,
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-successful-v2.7-compatibility-evidence",
            "human-ratifies-this-complete-five-model-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-bounded-spend",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_diagnostic_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(DIAGNOSTIC_MODELS)
    warmup = next(
        case for case in load_cases(DEVELOPMENT_CASES) if case["id"] == "WI-V2-D006"
    )
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    await _write_mock_payloads(
        run_dir,
        report,
        snapshot["selected"],
        specs=specs,
        case=warmup,
    )
    preflight = _diagnostic_cost_preflight(snapshot)
    policy = strict_json_load(DIAGNOSTIC_RUN_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-gemini-diagnostic-gate/v2.5",
        "runID": run_id,
        "status": "awaitingHumanRatification" if preflight["admitted"] else "blockedBySpendingLimit",
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        "scope": policy["scope"],
        "changedVariable": policy["changedVariable"],
        "unchangedInputs": policy["unchangedInputs"],
        "execution": policy["execution"],
        "artifactHashes": report["artifactHashes"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-two-call-diagnostic-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-two-provider-calls-and-two-dollar-cap",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_curl_probe_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(DIAGNOSTIC_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    manifest = await _write_curl_probe_payloads(run_dir, snapshot["selected"])
    preflight = _curl_probe_cost_preflight(snapshot, run_dir, manifest)
    policy = strict_json_load(CURL_PROBE_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-curl-probe-gate/v2.6",
        "runID": run_id,
        "status": "awaitingHumanRatification" if preflight["admitted"] else "blockedBySpendingLimit",
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        "scope": policy["scope"],
        "reasoning": policy["reasoning"],
        "stages": policy["stages"],
        "execution": policy["execution"],
        "artifactHashes": report["artifactHashes"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "curlVersion": curl_version(),
        "mockSummarySha256": sha256_file(run_dir / "curl-mock-summary.json"),
        "probeManifestSha256": sha256_file(run_dir / "curl-probe-manifest.json"),
        "probeManifest": manifest,
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-ten-call-curl-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-ten-provider-calls-and-two-dollar-cap",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_strategy_diagnostic_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"]
    )
    preflight = _strategy_diagnostic_cost_preflight(snapshot)
    policy = strict_json_load(STRATEGY_DIAGNOSTIC_RUN_POLICY)
    gate = {
        "gateContractVersion": (
            "paceprompt-host-eval-gemini-transport-strategy-gate/v2.7"
        ),
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        "scope": policy["scope"],
        "strategy": policy["strategy"],
        "changedVariable": policy["changedVariable"],
        "unchangedInputs": policy["unchangedInputs"],
        "reasoning": policy["reasoning"],
        "execution": policy["execution"],
        "artifactHashes": report["artifactHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-v2.7-two-call-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-two-provider-calls-and-two-dollar-cap",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_flat_strategy_diagnostic_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"], specs=specs
    )
    preflight = _strategy_diagnostic_cost_preflight(
        snapshot, FLAT_STRATEGY_DIAGNOSTIC_MODELS
    )
    policy = strict_json_load(FLAT_STRATEGY_DIAGNOSTIC_RUN_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-gemini-flat-envelope-gate/v2.8",
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        "scope": policy["scope"],
        "strategy": policy["strategy"],
        "changedVariable": policy["changedVariable"],
        "unchangedInputs": policy["unchangedInputs"],
        "reasoning": policy["reasoning"],
        "execution": policy["execution"],
        "artifactHashes": report["artifactHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-v2.8-two-call-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-two-provider-calls-and-two-dollar-cap",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_flat_strategy_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(FLAT_STRATEGY_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"], specs=specs
    )
    preflight = _strategy_cost_preflight(snapshot, FLAT_STRATEGY_MODELS)
    policy = strict_json_load(FLAT_STRATEGY_RUN_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-operator-gate/v2.8",
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "artifactHashes": report["artifactHashes"],
        "queueHashes": report["flatStrategyQueueHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "runPolicy": policy,
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-successful-v2.8-compatibility-evidence",
            "human-ratifies-this-complete-five-model-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-bounded-spend",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_semantic_json_strategy_diagnostic_gate(
    run_id: str,
) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"], specs=specs
    )
    preflight = _strategy_diagnostic_cost_preflight(
        snapshot, SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS
    )
    policy = strict_json_load(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_RUN_POLICY)
    gate = {
        "gateContractVersion": (
            "paceprompt-host-eval-gemini-semantic-json-gate/v2.9"
        ),
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        "scope": policy["scope"],
        "strategy": policy["strategy"],
        "schemaProfiles": policy["schemaProfiles"],
        "changedVariable": policy["changedVariable"],
        "unchangedInputs": policy["unchangedInputs"],
        "reasoning": policy["reasoning"],
        "execution": policy["execution"],
        "artifactHashes": report["artifactHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "human-ratifies-this-complete-v2.9-two-call-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-two-provider-calls-and-two-dollar-cap",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


async def prepare_semantic_json_strategy_gate(run_id: str) -> dict[str, Any]:
    report = verify()
    if report["status"] != "valid":
        raise RuntimeError(f"verification failed: {report['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(SEMANTIC_JSON_STRATEGY_MODELS)
    snapshot = snapshot_catalogue(run_dir / "catalogue", specs)
    mocks = await _write_strategy_mock_payloads(
        run_dir, report, snapshot["selected"], specs=specs
    )
    preflight = _strategy_cost_preflight(snapshot, SEMANTIC_JSON_STRATEGY_MODELS)
    policy = strict_json_load(SEMANTIC_JSON_STRATEGY_RUN_POLICY)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-operator-gate/v2.9",
        "runID": run_id,
        "status": (
            "awaitingHumanRatification"
            if preflight["admitted"]
            else "blockedBySpendingLimit"
        ),
        "credentialRead": False,
        "liveCallsMade": 0,
        "spendUSD": "0.00",
        "artifactHashes": report["artifactHashes"],
        "queueHashes": report["semanticJsonStrategyQueueHashes"],
        "strategyAssignments": mocks["strategyAssignments"],
        "runPolicy": policy,
        "catalogueSnapshotSha256": sha256_file(
            run_dir / "catalogue" / "selected.json"
        ),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "costPreflight": preflight,
        "selectedEndpoints": snapshot["selected"],
        "requiredBeforeLive": [
            "successful-v2.9-compatibility-evidence-is-accepted-by-default",
            "human-ratifies-this-complete-five-model-gate",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-bounded-spend",
        ],
    }
    gate["authorizationPhrase"] = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_" + canonical_hash(gate)[:16].upper()
    )
    (run_dir / "operator-gate.json").write_text(
        json.dumps(gate, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return gate


def authorization_phrase(run_id: str | None = None) -> str:
    if run_id is not None:
        gate = strict_json_load(safe_run_dir(run_id, create=False) / "operator-gate.json")
        return gate["authorizationPhrase"]
    digest = canonical_hash(artifact_hashes())[:16].upper()
    return f"AUTHORIZE_PACEPROMPT_HOST_EVAL_{digest}"


def validate_gate_authorization(gate: dict[str, Any], authorization: str) -> None:
    unsigned_gate = dict(gate)
    recorded_phrase = unsigned_gate.pop("authorizationPhrase", None)
    expected_phrase = (
        "AUTHORIZE_PACEPROMPT_HOST_EVAL_"
        + canonical_hash(unsigned_gate)[:16].upper()
    )
    if recorded_phrase != expected_phrase:
        raise RuntimeError("operator gate contents changed after its authorization phrase was sealed")
    if authorization != recorded_phrase:
        raise RuntimeError("exact run-specific operator authorization is missing")


def operator_gate(run_id: str | None = None) -> dict[str, Any]:
    if run_id is not None:
        return strict_json_load(safe_run_dir(run_id, create=False) / "operator-gate.json")
    report = verify()
    return {
        "status": "readyForHumanRatification" if report["status"] == "valid" else "blocked",
        "liveCallsMade": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "authorizationPhrase": authorization_phrase() if report["status"] == "valid" else None,
        "verification": report,
        "requiredBeforeLive": [
            "human-ratifies-exact-artifacts-and-hashes",
            "human-ratifies-current-model-endpoint-and-quantization-snapshot",
            "local-OPENROUTER_API_KEY-is-available",
            "human-explicitly-authorizes-provider-calls-and-bounded-spend",
        ],
    }


async def run_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "20.00" or gate["costPreflight"]["hardLimitUSD"] != "20.00":
        raise RuntimeError("the frozen spending limit must be exactly 20.00 USD")
    if gate["costPreflight"]["selectedRepetitions"] not in {1, 5}:
        raise RuntimeError("the ratified cost preflight admitted no calls")
    current_hashes = artifact_hashes()
    if current_hashes != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the operator gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable run ID has already entered live execution")

    specs = load_model_specs(MODELS)
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _cost_preflight(live_snapshot)
    repetitions = gate["costPreflight"]["selectedRepetitions"]
    selected_cost = Decimal(
        live_preflight["fiveRepetitionWorstCaseUSD"]
        if repetitions == 5
        else live_preflight["oneRepetitionWorstCaseUSD"]
    )
    if selected_cost > Decimal("20.00"):
        raise RuntimeError("current prices no longer fit the ratified spending limit")

    # This is deliberately the first credential access in the command, after every
    # non-secret gate and drift check has passed.
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "selectedRepetitions": repetitions,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
            "liveCostPreflight": live_preflight,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=strict_json_load(TRANSPORT_SCHEMA),
        cases=load_cases(HELDOUT_CASES),
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=deterministic_queue(repetitions),
        specs=specs,
        messages_for_case=model_messages,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
        execution_policy=strict_json_load(RUN_POLICY)["execution"],
        run_configuration_id=strict_json_load(RUN_POLICY)["runPolicyVersion"],
        spending_limit_usd="20.00",
    )
    try:
        return await runner.execute()
    finally:
        api_key = ""


async def run_strategy_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != "paceprompt-host-eval-operator-gate/v2.7":
        raise RuntimeError("operator gate is not the v2.7 full strategy gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "20.00" or gate["costPreflight"]["hardLimitUSD"] != "20.00":
        raise RuntimeError("the frozen strategy run limit must be exactly 20.00 USD")
    repetitions = gate["costPreflight"].get("selectedRepetitions")
    if repetitions not in {1, 5}:
        raise RuntimeError("the strategy cost preflight admitted no calls")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the strategy gate")
    policy = strict_json_load(STRATEGY_RUN_POLICY)
    if gate.get("runPolicy") != policy:
        raise RuntimeError("v2.7 run policy changed after the strategy gate")
    queue = deterministic_strategy_queue(repetitions)
    expected_queue_hash = gate["queueHashes"]["five" if repetitions == 5 else "one"]
    if canonical_hash(queue) != expected_queue_hash:
        raise RuntimeError("v2.7 deterministic queue changed after the strategy gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable strategy run already entered live execution")

    specs = load_model_specs(STRATEGY_MODELS)
    expected_assignments = [
        {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision or "",
            "providerEndpoint": spec.provider_endpoint,
            "transportStrategy": strategy_for(spec).identifier.value,
            "schemaName": strategy_for(spec).schema_name,
            "schemaSha256": sha256_file(strategy_for(spec).schema_path),
        }
        for spec in specs
    ]
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("strategy assignment registry changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_cost_preflight(live_snapshot)
    selected_cost = Decimal(
        live_preflight[
            "fiveRepetitionWorstCaseUSD"
            if repetitions == 5
            else "oneRepetitionWorstCaseUSD"
        ]
    )
    if selected_cost > Decimal("20.00"):
        raise RuntimeError("current prices no longer fit the strategy run limit")

    # Credential access remains last, after every reproducibility, route and spend
    # invariant for this exact run has been revalidated.
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "selectedRepetitions": repetitions,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
            "queueSha256": expected_queue_hash,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=load_cases(HELDOUT_CASES),
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=queue,
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="20.00",
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute()
    finally:
        api_key = ""


async def run_flat_strategy_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != "paceprompt-host-eval-operator-gate/v2.8":
        raise RuntimeError("operator gate is not the v2.8 full strategy gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "20.00" or gate["costPreflight"]["hardLimitUSD"] != "20.00":
        raise RuntimeError("the frozen flat-envelope run limit must be 20.00 USD")
    repetitions = gate["costPreflight"].get("selectedRepetitions")
    if repetitions not in {1, 5}:
        raise RuntimeError("the flat-envelope cost preflight admitted no calls")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the flat-envelope gate")
    policy = strict_json_load(FLAT_STRATEGY_RUN_POLICY)
    if gate.get("runPolicy") != policy:
        raise RuntimeError("v2.8 run policy changed after the flat-envelope gate")
    queue = deterministic_flat_strategy_queue(repetitions)
    expected_queue_hash = gate["queueHashes"]["five" if repetitions == 5 else "one"]
    if canonical_hash(queue) != expected_queue_hash:
        raise RuntimeError("v2.8 deterministic queue changed after the flat-envelope gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable flat-envelope run already entered live execution")

    specs = load_model_specs(FLAT_STRATEGY_MODELS)
    expected_assignments = _strategy_assignments(specs)
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("flat-envelope registry changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_cost_preflight(live_snapshot, FLAT_STRATEGY_MODELS)
    selected_cost = Decimal(
        live_preflight[
            "fiveRepetitionWorstCaseUSD"
            if repetitions == 5
            else "oneRepetitionWorstCaseUSD"
        ]
    )
    if selected_cost > Decimal("20.00"):
        raise RuntimeError("current prices no longer fit the flat-envelope run limit")

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "selectedRepetitions": repetitions,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
            "queueSha256": expected_queue_hash,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=load_cases(HELDOUT_CASES),
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=queue,
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="20.00",
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute()
    finally:
        api_key = ""


async def run_semantic_json_strategy_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != "paceprompt-host-eval-operator-gate/v2.9":
        raise RuntimeError("operator gate is not the v2.9 full strategy gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "20.00" or gate["costPreflight"]["hardLimitUSD"] != "20.00":
        raise RuntimeError("the frozen semantic-json run limit must be 20.00 USD")
    repetitions = gate["costPreflight"].get("selectedRepetitions")
    if repetitions not in {1, 5}:
        raise RuntimeError("the semantic-json cost preflight admitted no calls")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the semantic-json gate")
    policy = strict_json_load(SEMANTIC_JSON_STRATEGY_RUN_POLICY)
    if gate.get("runPolicy") != policy:
        raise RuntimeError("v2.9 run policy changed after the semantic-json gate")
    queue = deterministic_semantic_json_strategy_queue(repetitions)
    expected_queue_hash = gate["queueHashes"]["five" if repetitions == 5 else "one"]
    if canonical_hash(queue) != expected_queue_hash:
        raise RuntimeError("v2.9 deterministic queue changed after the semantic-json gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable semantic-json run already entered live execution")

    specs = load_model_specs(SEMANTIC_JSON_STRATEGY_MODELS)
    expected_assignments = _strategy_assignments(specs)
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("semantic-json registry or schema profile changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_cost_preflight(
        live_snapshot, SEMANTIC_JSON_STRATEGY_MODELS
    )
    selected_cost = Decimal(
        live_preflight[
            "fiveRepetitionWorstCaseUSD"
            if repetitions == 5
            else "oneRepetitionWorstCaseUSD"
        ]
    )
    if selected_cost > Decimal("20.00"):
        raise RuntimeError("current prices no longer fit the semantic-json run limit")

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "selectedRepetitions": repetitions,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
            "queueSha256": expected_queue_hash,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=load_cases(HELDOUT_CASES),
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=queue,
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="20.00",
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute()
    finally:
        api_key = ""


async def run_diagnostic_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != "paceprompt-host-eval-gemini-diagnostic-gate/v2.5":
        raise RuntimeError("operator gate is not the v2.5 Gemini diagnostic gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "2.00" or gate["costPreflight"]["hardLimitUSD"] != "2.00":
        raise RuntimeError("the frozen diagnostic spending limit must be exactly 2.00 USD")
    if gate["costPreflight"].get("callCount") != 2 or gate["scope"].get("heldoutCalls") != 0:
        raise RuntimeError("the ratified diagnostic scope must be exactly two warm-ups and no held-out calls")
    policy = strict_json_load(DIAGNOSTIC_RUN_POLICY)
    for key in ("purpose", "scope", "changedVariable", "unchangedInputs", "execution"):
        if gate.get(key) != policy.get(key):
            raise RuntimeError(f"diagnostic gate {key} differs from the versioned run policy")
    current_hashes = artifact_hashes()
    if current_hashes != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the diagnostic operator gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable diagnostic run ID has already entered live execution")

    specs = load_model_specs(DIAGNOSTIC_MODELS)
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _diagnostic_cost_preflight(live_snapshot)
    if not live_preflight["admitted"] or Decimal(live_preflight["worstCaseUSD"]) > Decimal("2.00"):
        raise RuntimeError("current prices no longer fit the ratified diagnostic spending limit")

    # This remains the first credential access, after all non-secret gate and
    # catalogue-drift checks have passed.
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 2,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
            "liveCostPreflight": live_preflight,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=strict_json_load(TRANSPORT_SCHEMA),
        cases=[],
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=[],
        specs=specs,
        messages_for_case=model_messages,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=len(TRANSPORT_SCHEMA.read_bytes()),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="2.00",
        diagnostic_report_contract_version="paceprompt-host-eval-gemini-diagnostic-report/v2.5",
        diagnostic_purpose=policy["purpose"],
    )
    try:
        return await runner.execute_warmups_only()
    finally:
        api_key = ""


async def run_strategy_diagnostic_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != (
        "paceprompt-host-eval-gemini-transport-strategy-gate/v2.7"
    ):
        raise RuntimeError("operator gate is not the v2.7 strategy diagnostic gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "2.00" or gate["costPreflight"]["hardLimitUSD"] != "2.00":
        raise RuntimeError("the frozen strategy diagnostic limit must be exactly 2.00 USD")
    if gate["costPreflight"].get("callCount") != 2 or gate["scope"].get("heldoutCalls") != 0:
        raise RuntimeError("the strategy diagnostic must be exactly two warm-ups and no held-out calls")
    policy = strict_json_load(STRATEGY_DIAGNOSTIC_RUN_POLICY)
    for key in (
        "purpose",
        "scope",
        "strategy",
        "changedVariable",
        "unchangedInputs",
        "reasoning",
        "execution",
    ):
        if gate.get(key) != policy.get(key):
            raise RuntimeError(f"strategy diagnostic gate {key} differs from policy")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the strategy gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable strategy run already entered live execution")

    specs = load_model_specs(STRATEGY_DIAGNOSTIC_MODELS)
    expected_assignments = [
        {
            "requestedModelID": spec.requested_model_id,
            "canonicalRevision": spec.canonical_revision or "",
            "providerEndpoint": spec.provider_endpoint,
            "transportStrategy": strategy_for(spec).identifier.value,
            "schemaName": strategy_for(spec).schema_name,
            "schemaSha256": sha256_file(strategy_for(spec).schema_path),
        }
        for spec in specs
    ]
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("strategy assignment registry changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_diagnostic_cost_preflight(live_snapshot)
    if not live_preflight["admitted"] or Decimal(live_preflight["worstCaseUSD"]) > Decimal("2.00"):
        raise RuntimeError("current prices no longer fit the strategy diagnostic limit")

    # This is the first credential access, after the complete immutable strategy,
    # payload, catalogue, endpoint and spend gate has been revalidated.
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 2,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=[],
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=[],
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="2.00",
        diagnostic_report_contract_version=(
            "paceprompt-host-eval-gemini-transport-strategy-report/v2.7"
        ),
        diagnostic_purpose=policy["purpose"],
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute_warmups_only()
    finally:
        api_key = ""


async def run_flat_strategy_diagnostic_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != (
        "paceprompt-host-eval-gemini-flat-envelope-gate/v2.8"
    ):
        raise RuntimeError("operator gate is not the v2.8 flat-envelope diagnostic gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "2.00" or gate["costPreflight"]["hardLimitUSD"] != "2.00":
        raise RuntimeError("the frozen flat-envelope diagnostic limit must be 2.00 USD")
    if gate["costPreflight"].get("callCount") != 2 or gate["scope"].get("heldoutCalls") != 0:
        raise RuntimeError("the flat-envelope diagnostic must be two warm-ups and no held-out calls")
    policy = strict_json_load(FLAT_STRATEGY_DIAGNOSTIC_RUN_POLICY)
    for key in (
        "purpose",
        "scope",
        "strategy",
        "changedVariable",
        "unchangedInputs",
        "reasoning",
        "execution",
    ):
        if gate.get(key) != policy.get(key):
            raise RuntimeError(f"flat-envelope diagnostic gate {key} differs from policy")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the flat-envelope gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable flat-envelope run already entered live execution")

    specs = load_model_specs(FLAT_STRATEGY_DIAGNOSTIC_MODELS)
    expected_assignments = _strategy_assignments(specs)
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("flat-envelope registry changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_diagnostic_cost_preflight(
        live_snapshot, FLAT_STRATEGY_DIAGNOSTIC_MODELS
    )
    if not live_preflight["admitted"] or Decimal(live_preflight["worstCaseUSD"]) > Decimal("2.00"):
        raise RuntimeError("current prices no longer fit the flat-envelope diagnostic limit")

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 2,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=[],
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=[],
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="2.00",
        diagnostic_report_contract_version=(
            "paceprompt-host-eval-gemini-flat-envelope-report/v2.8"
        ),
        diagnostic_purpose=policy["purpose"],
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute_warmups_only()
    finally:
        api_key = ""


async def run_semantic_json_strategy_diagnostic_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != (
        "paceprompt-host-eval-gemini-semantic-json-gate/v2.9"
    ):
        raise RuntimeError("operator gate is not the v2.9 semantic-json diagnostic gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "2.00" or gate["costPreflight"]["hardLimitUSD"] != "2.00":
        raise RuntimeError("the frozen semantic-json diagnostic limit must be 2.00 USD")
    if gate["costPreflight"].get("callCount") != 2 or gate["scope"].get("heldoutCalls") != 0:
        raise RuntimeError("the semantic-json diagnostic must be two warm-ups and no held-out calls")
    policy = strict_json_load(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_RUN_POLICY)
    for key in (
        "purpose",
        "scope",
        "strategy",
        "schemaProfiles",
        "changedVariable",
        "unchangedInputs",
        "reasoning",
        "execution",
    ):
        if gate.get(key) != policy.get(key):
            raise RuntimeError(f"semantic-json diagnostic gate {key} differs from policy")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the semantic-json gate")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable semantic-json run already entered live execution")

    specs = load_model_specs(SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS)
    expected_assignments = _strategy_assignments(specs)
    if gate.get("strategyAssignments") != expected_assignments:
        raise RuntimeError("semantic-json registry or schema profile changed after the operator gate")
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import LiveRun, compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _strategy_diagnostic_cost_preflight(
        live_snapshot, SEMANTIC_JSON_STRATEGY_DIAGNOSTIC_MODELS
    )
    if (
        not live_preflight["admitted"]
        or Decimal(live_preflight["worstCaseUSD"]) > Decimal("2.00")
    ):
        raise RuntimeError("current prices no longer fit the semantic-json diagnostic limit")

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 2,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(
                run_dir / "live-catalogue" / "selected.json"
            ),
            "liveCostPreflight": live_preflight,
            "strategyAssignments": expected_assignments,
        },
    )
    effective_gate = dict(gate)
    effective_gate["selectedEndpoints"] = live_snapshot["selected"]
    nested = STRATEGIES[TransportStrategyID.NESTED_V2_3]
    runner = LiveRun(
        run_dir=run_dir,
        gate=effective_gate,
        api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA),
        transport_schema=nested.schema(),
        cases=[],
        development_cases=load_cases(DEVELOPMENT_CASES),
        queue=[],
        specs=specs,
        messages_for_case=model_messages_for_strategy,
        repository_root=REPOSITORY_ROOT,
        schema_file_bytes=nested.schema_file_bytes(),
        execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"],
        spending_limit_usd="2.00",
        diagnostic_report_contract_version=(
            "paceprompt-host-eval-gemini-semantic-json-report/v2.9"
        ),
        diagnostic_purpose=policy["purpose"],
        transport_strategy_for_spec=strategy_for,
    )
    try:
        return await runner.execute_warmups_only()
    finally:
        api_key = ""


async def run_curl_probe_live(
    *, run_id: str, authorization: str, spending_limit_usd: str
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != "paceprompt-host-eval-curl-probe-gate/v2.6":
        raise RuntimeError("operator gate is not the v2.6 curl-probe gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("operator gate is not awaiting ratification")
    validate_gate_authorization(gate, authorization)
    if spending_limit_usd != "2.00" or gate["costPreflight"]["hardLimitUSD"] != "2.00":
        raise RuntimeError("the frozen curl-probe spending limit must be exactly 2.00 USD")
    policy = strict_json_load(CURL_PROBE_POLICY)
    for key in ("purpose", "scope", "reasoning", "stages", "execution"):
        if gate.get(key) != policy.get(key):
            raise RuntimeError(f"curl-probe gate {key} differs from the versioned run policy")
    if gate["costPreflight"].get("callCount") != 10 or gate["scope"].get("heldoutCalls") != 0:
        raise RuntimeError("the ratified curl-probe scope must be ten calls and no held-out calls")
    if artifact_hashes() != gate["artifactHashes"]:
        raise RuntimeError("versioned harness inputs changed after the curl-probe operator gate")
    if (run_dir / "curl-live-state.json").exists():
        raise RuntimeError("this non-resumable curl-probe run ID has already entered live execution")
    if curl_version() != gate["curlVersion"]:
        raise RuntimeError("curl version changed after the operator gate")
    manifest = strict_json_load(run_dir / "curl-probe-manifest.json")
    if manifest != gate["probeManifest"]:
        raise RuntimeError("curl-probe manifest changed after the operator gate")
    if sha256_file(run_dir / "curl-probe-manifest.json") != gate["probeManifestSha256"]:
        raise RuntimeError("curl-probe manifest hash changed after the operator gate")
    for probe in manifest:
        if sha256_file(run_dir / probe["payloadPath"]) != probe["payloadSha256"]:
            raise RuntimeError(f"curl payload changed for {probe['attemptID']}")

    specs = load_model_specs(DIAGNOSTIC_MODELS)
    live_snapshot = snapshot_catalogue(run_dir / "live-catalogue", specs)
    from .runner import compare_catalogues, write_json

    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = _curl_probe_cost_preflight(live_snapshot, run_dir, manifest)
    if not live_preflight["admitted"] or Decimal(live_preflight["worstCaseUSD"]) > Decimal("2.00"):
        raise RuntimeError("current prices no longer fit the ratified curl-probe spending limit")

    # The credential is first read only after the sealed payloads, executable,
    # catalogue, endpoint and cost controls have all been revalidated.
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local launch environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": 10,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
            "liveCostPreflight": live_preflight,
        },
    )
    from .curl_probe import CurlProbeRun

    runner = CurlProbeRun(
        run_dir=run_dir,
        gate=dict(gate, selectedEndpoints=live_snapshot["selected"]),
        api_key=api_key,
        execution_policy=policy["execution"],
        spending_limit_usd="2.00",
    )
    try:
        return await runner.execute()
    finally:
        api_key = ""


def print_json(value: Any) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("verify")
    subparsers.add_parser("enumerate")
    verify_v3_parser = subparsers.add_parser("verify-v3")
    verify_v3_parser.add_argument("--asset-root", type=Path, default=HOST_EVAL_ROOT)
    enumerate_v3_parser = subparsers.add_parser("enumerate-v3")
    enumerate_v3_parser.add_argument("--asset-root", type=Path, default=HOST_EVAL_ROOT)
    prepare_v3_parser = subparsers.add_parser("prepare-v3-gate")
    prepare_v3_parser.add_argument("--run-id", required=True)
    prepare_v3_parser.add_argument("--asset-root", type=Path, default=HOST_EVAL_ROOT)
    run_v3_parser = subparsers.add_parser("run-v3")
    run_v3_parser.add_argument("--run-id", required=True)
    run_v3_parser.add_argument("--live", action="store_true")
    run_v3_parser.add_argument("--authorization")
    run_v3_parser.add_argument("--spending-limit-usd")
    mock = subparsers.add_parser("mock-payloads")
    mock.add_argument("--run-id", required=True)
    prepare = subparsers.add_parser("prepare-gate")
    prepare.add_argument("--run-id", required=True)
    prepare_strategy_full = subparsers.add_parser("prepare-strategy-gate")
    prepare_strategy_full.add_argument("--run-id", required=True)
    prepare_diagnostic = subparsers.add_parser("prepare-diagnostic-gate")
    prepare_diagnostic.add_argument("--run-id", required=True)
    prepare_curl = subparsers.add_parser("prepare-curl-probe-gate")
    prepare_curl.add_argument("--run-id", required=True)
    prepare_strategy = subparsers.add_parser("prepare-strategy-diagnostic-gate")
    prepare_strategy.add_argument("--run-id", required=True)
    prepare_flat_full = subparsers.add_parser("prepare-flat-strategy-gate")
    prepare_flat_full.add_argument("--run-id", required=True)
    prepare_flat_diagnostic = subparsers.add_parser(
        "prepare-flat-strategy-diagnostic-gate"
    )
    prepare_flat_diagnostic.add_argument("--run-id", required=True)
    prepare_semantic_json_full = subparsers.add_parser(
        "prepare-semantic-json-strategy-gate"
    )
    prepare_semantic_json_full.add_argument("--run-id", required=True)
    prepare_semantic_json_diagnostic = subparsers.add_parser(
        "prepare-semantic-json-strategy-diagnostic-gate"
    )
    prepare_semantic_json_diagnostic.add_argument("--run-id", required=True)
    gate_parser = subparsers.add_parser("operator-gate")
    gate_parser.add_argument("--run-id")
    run = subparsers.add_parser("run")
    run.add_argument("--run-id", required=True)
    run.add_argument("--live", action="store_true")
    run.add_argument("--authorization")
    run.add_argument("--spending-limit-usd")
    strategy_run = subparsers.add_parser("run-strategy")
    strategy_run.add_argument("--run-id", required=True)
    strategy_run.add_argument("--live", action="store_true")
    strategy_run.add_argument("--authorization")
    strategy_run.add_argument("--spending-limit-usd")
    diagnostic = subparsers.add_parser("run-diagnostic")
    diagnostic.add_argument("--run-id", required=True)
    diagnostic.add_argument("--live", action="store_true")
    diagnostic.add_argument("--authorization")
    diagnostic.add_argument("--spending-limit-usd")
    curl_probe = subparsers.add_parser("run-curl-probe")
    curl_probe.add_argument("--run-id", required=True)
    curl_probe.add_argument("--live", action="store_true")
    curl_probe.add_argument("--authorization")
    curl_probe.add_argument("--spending-limit-usd")
    strategy_diagnostic = subparsers.add_parser("run-strategy-diagnostic")
    strategy_diagnostic.add_argument("--run-id", required=True)
    strategy_diagnostic.add_argument("--live", action="store_true")
    strategy_diagnostic.add_argument("--authorization")
    strategy_diagnostic.add_argument("--spending-limit-usd")
    flat_strategy_run = subparsers.add_parser("run-flat-strategy")
    flat_strategy_run.add_argument("--run-id", required=True)
    flat_strategy_run.add_argument("--live", action="store_true")
    flat_strategy_run.add_argument("--authorization")
    flat_strategy_run.add_argument("--spending-limit-usd")
    flat_strategy_diagnostic = subparsers.add_parser(
        "run-flat-strategy-diagnostic"
    )
    flat_strategy_diagnostic.add_argument("--run-id", required=True)
    flat_strategy_diagnostic.add_argument("--live", action="store_true")
    flat_strategy_diagnostic.add_argument("--authorization")
    flat_strategy_diagnostic.add_argument("--spending-limit-usd")
    semantic_json_strategy_run = subparsers.add_parser(
        "run-semantic-json-strategy"
    )
    semantic_json_strategy_run.add_argument("--run-id", required=True)
    semantic_json_strategy_run.add_argument("--live", action="store_true")
    semantic_json_strategy_run.add_argument("--authorization")
    semantic_json_strategy_run.add_argument("--spending-limit-usd")
    semantic_json_strategy_diagnostic = subparsers.add_parser(
        "run-semantic-json-strategy-diagnostic"
    )
    semantic_json_strategy_diagnostic.add_argument("--run-id", required=True)
    semantic_json_strategy_diagnostic.add_argument("--live", action="store_true")
    semantic_json_strategy_diagnostic.add_argument("--authorization")
    semantic_json_strategy_diagnostic.add_argument("--spending-limit-usd")
    args = parser.parse_args(argv)

    if args.command == "verify":
        report = verify()
        print_json(report)
        return 0 if report["status"] == "valid" else 1
    if args.command == "verify-v3":
        from .v3 import verify as verify_v3

        report = verify_v3(args.asset_root.resolve())
        print_json(report)
        return 0 if report["status"] == "valid" else 1
    if args.command == "enumerate-v3":
        from .v3 import queue_document

        print_json(queue_document(asset_root=args.asset_root.resolve()))
        return 0
    if args.command == "prepare-v3-gate":
        from .v3 import prepare_gate as prepare_v3_gate

        print_json(
            asyncio.run(
                prepare_v3_gate(args.run_id, asset_root=args.asset_root.resolve())
            )
        )
        return 0
    if args.command == "run-v3":
        if not args.live:
            raise SystemExit("live v3 execution requires --live")
        from .v3 import run_live as run_v3_live

        print_json(
            asyncio.run(
                run_v3_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "enumerate":
        report = verify()
        print_json(
            {
                "status": report["status"],
                "warmups": report["models"],
                "fiveRepetitionAttempts": report["fiveRepetitionAttempts"],
                "oneRepetitionAttempts": report["oneRepetitionAttempts"],
                "queueHashes": report["queueHashes"],
            }
        )
        return 0 if report["status"] == "valid" else 1
    if args.command == "mock-payloads":
        print_json(asyncio.run(mock_payloads(args.run_id)))
        return 0
    if args.command == "prepare-gate":
        print_json(asyncio.run(prepare_gate(args.run_id)))
        return 0
    if args.command == "prepare-strategy-gate":
        print_json(asyncio.run(prepare_strategy_gate(args.run_id)))
        return 0
    if args.command == "prepare-diagnostic-gate":
        print_json(asyncio.run(prepare_diagnostic_gate(args.run_id)))
        return 0
    if args.command == "prepare-curl-probe-gate":
        print_json(asyncio.run(prepare_curl_probe_gate(args.run_id)))
        return 0
    if args.command == "prepare-strategy-diagnostic-gate":
        print_json(asyncio.run(prepare_strategy_diagnostic_gate(args.run_id)))
        return 0
    if args.command == "prepare-flat-strategy-gate":
        print_json(asyncio.run(prepare_flat_strategy_gate(args.run_id)))
        return 0
    if args.command == "prepare-flat-strategy-diagnostic-gate":
        print_json(asyncio.run(prepare_flat_strategy_diagnostic_gate(args.run_id)))
        return 0
    if args.command == "prepare-semantic-json-strategy-gate":
        print_json(asyncio.run(prepare_semantic_json_strategy_gate(args.run_id)))
        return 0
    if args.command == "prepare-semantic-json-strategy-diagnostic-gate":
        print_json(
            asyncio.run(prepare_semantic_json_strategy_diagnostic_gate(args.run_id))
        )
        return 0
    if args.command == "operator-gate":
        report = operator_gate(args.run_id)
        print_json(report)
        return 0 if report["status"] in {"readyForHumanRatification", "awaitingHumanRatification"} else 1
    if args.command == "run":
        if not args.live:
            raise SystemExit("live execution requires --live")
        print_json(
            asyncio.run(
                run_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-strategy":
        if not args.live:
            raise SystemExit("live strategy execution requires --live")
        print_json(
            asyncio.run(
                run_strategy_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-diagnostic":
        if not args.live:
            raise SystemExit("live diagnostic execution requires --live")
        print_json(
            asyncio.run(
                run_diagnostic_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-curl-probe":
        if not args.live:
            raise SystemExit("live curl-probe execution requires --live")
        print_json(
            asyncio.run(
                run_curl_probe_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-strategy-diagnostic":
        if not args.live:
            raise SystemExit("live strategy diagnostic execution requires --live")
        print_json(
            asyncio.run(
                run_strategy_diagnostic_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-flat-strategy":
        if not args.live:
            raise SystemExit("live flat-strategy execution requires --live")
        print_json(
            asyncio.run(
                run_flat_strategy_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-flat-strategy-diagnostic":
        if not args.live:
            raise SystemExit("live flat-strategy diagnostic execution requires --live")
        print_json(
            asyncio.run(
                run_flat_strategy_diagnostic_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-semantic-json-strategy":
        if not args.live:
            raise SystemExit("live semantic-json strategy execution requires --live")
        print_json(
            asyncio.run(
                run_semantic_json_strategy_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    if args.command == "run-semantic-json-strategy-diagnostic":
        if not args.live:
            raise SystemExit(
                "live semantic-json strategy diagnostic execution requires --live"
            )
        print_json(
            asyncio.run(
                run_semantic_json_strategy_diagnostic_live(
                    run_id=args.run_id,
                    authorization=args.authorization or "",
                    spending_limit_usd=args.spending_limit_usd or "",
                )
            )
        )
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
