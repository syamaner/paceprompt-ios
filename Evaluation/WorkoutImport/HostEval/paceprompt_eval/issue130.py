"""Issue #130 same-model prompt-arm evaluation and zero-spend operator gate."""

from __future__ import annotations

import asyncio
from collections import Counter, defaultdict
from copy import deepcopy
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import random
import sys
from typing import Any, Callable

from inspect_ai.model import ChatMessage, ChatMessageAssistant, ChatMessageSystem, ChatMessageUser
from jsonschema import Draft202012Validator

_REPOSITORY_IMPORT_ROOT = Path(__file__).resolve().parents[4]
if str(_REPOSITORY_IMPORT_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPOSITORY_IMPORT_ROOT))

from Evaluation.WorkoutImport.Acceptance.verify_v3 import verify as verify_acceptance

from .catalogue import snapshot_catalogue
from .openrouter import assert_payload_controls, capture_wire_payload, load_model_specs
from .runner import LiveRun, compare_catalogues, write_json
from .transport_strategy import strategy_for
from .v3 import canonical_hash, host_source_tree_hash, safe_run_dir, sha256_file, strict_json_load


HOST_EVAL_ROOT = Path(__file__).resolve().parents[1]
WORKOUT_IMPORT_ROOT = HOST_EVAL_ROOT.parent
REPOSITORY_ROOT = WORKOUT_IMPORT_ROOT.parents[1]
POLICY = HOST_EVAL_ROOT / "run-policy-issue130-r1.json"
MODELS = HOST_EVAL_ROOT / "models-issue130-r1.json"
MODEL_SCHEMA = HOST_EVAL_ROOT / "schemas" / "v2" / "workout-import-model-output-v2.schema.json"
TRANSPORT_SCHEMA = HOST_EVAL_ROOT / "schemas" / "v2.3" / "workout-import-provider-transport-v2.3.schema.json"
PRODUCTION_PROMPT = REPOSITORY_ROOT / "PacePrompt" / "Import" / "ImportResources" / "system.md"
CANDIDATE_PROMPT = HOST_EVAL_ROOT / "prompts" / "issue130-r1" / "system.md"
EXAMPLES = REPOSITORY_ROOT / "PacePrompt" / "Import" / "ImportResources" / "examples.json"
CASES = WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "cases.json"
MANIFEST = WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "manifest.json"
SEMANTIC_REVIEW = WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "semantic-review.json"
DEVELOPMENT_CASES = HOST_EVAL_ROOT / "datasets" / "v3" / "development" / "cases.json"
SCORER = WORKOUT_IMPORT_ROOT / "Scoring" / "scorer.py"
SCHEMA_VALIDATION = WORKOUT_IMPORT_ROOT / "Scoring" / "schema_validation.py"

PROMPT_PATHS = {"production-v3": PRODUCTION_PROMPT, "issue130-r1": CANDIDATE_PROMPT}
SEALED = {
    "productionPrompt": "d58800efc4b0e01994a1a5be1a1d644ce52dbb6bb7c12655745dc78b6e355fd3",
    "candidatePrompt": "4b70d5563b52d195b25c77250b18599416b13bfc0a86ab9f435a74d7514bcf71",
    "examples": "0313c531454bae3545ec97118be33232f53b0b62613a2339d8a96dbe21a680fd",
    "acceptanceCases": "a5ad4b380e849347296dc4c69770a715eedf4a2d394ee7f582b98bebbd47ae81",
    "acceptanceManifest": "d1ea8bf50bc9f851410fd89642ab225784c92d286eaf6304af324324d48a937c",
    "acceptanceSemanticReview": "d70bee791c5ec50babc000af1e83316483083c5940b02c80b01c005d4ad42d7d",
    "modelSchema": "8bcf9f0f34eb5521cc5573089bdeeac4f40258f8cb547638556563e7470417b9",
    "transportSchema": "d4901b2dc3b1a57654ed5d6f7e96bdce30687062913036f86e616fb2f5a9bba0",
    "v1Scorer": "45fe2dd6dd063ad2292e79fcf2bd520881bbeb374ea90571c7937f3d7be0bba1",
    "schemaValidation": "8c64365a6c7b85d0b68fd351c89966e6a5d8a316f34dd76ff3c5d28fffbd571a",
    "models": "a84d2c11e2297ba7c7bed652a0ddcb44ae2e976eabe329041c156dd001ddfa0e",
    "runPolicy": "596ce69e7f583c48789b88db7c9a023e91105b0d6d9409a373c3bb62d1319f96",
}
ASSET_PATHS = {
    "productionPrompt": PRODUCTION_PROMPT,
    "candidatePrompt": CANDIDATE_PROMPT,
    "examples": EXAMPLES,
    "acceptanceCases": CASES,
    "acceptanceManifest": MANIFEST,
    "acceptanceSemanticReview": SEMANTIC_REVIEW,
    "modelSchema": MODEL_SCHEMA,
    "transportSchema": TRANSPORT_SCHEMA,
    "v1Scorer": SCORER,
    "schemaValidation": SCHEMA_VALIDATION,
    "models": MODELS,
    "runPolicy": POLICY,
}


def load_cases() -> list[dict[str, Any]]:
    value = strict_json_load(CASES)
    if not isinstance(value, list):
        raise ValueError("issue #130 acceptance cases must be an array")
    return value


def capability_profile() -> dict[str, Any]:
    return deepcopy(strict_json_load(MANIFEST)["capabilityProfiles"]["standardTreadmillV1"])


def semantic_model_output(case: dict[str, Any]) -> dict[str, Any]:
    expected = case["expected"]
    outcome_type = expected["outcome"]
    if outcome_type != "proposal":
        return {
            "contractVersion": "workout-import-model-output/v2",
            "outcome": {
                "type": outcome_type,
                "reasonCategory": expected["reasonCategory"],
                "affectedPaths": expected["affectedPaths"],
            },
        }
    name_rule = expected["suggestedNameExpectation"]
    name = name_rule.get("value", "Acceptance Fixture")
    return {
        "contractVersion": "workout-import-model-output/v2",
        "outcome": {
            "type": "proposal",
            "proposal": {
                "contractVersion": "workout-proposal/v2",
                "suggestedName": name,
                "activity": expected["canonicalProposal"]["activity"],
                "steps": [
                    {
                        "kind": step["kind"],
                        "label": f"Step {index}",
                        "duration": {"value": step["durationSeconds"], "unit": "seconds"},
                        "targetSpeed": {"value": step["speedKilometresPerHour"], "unit": "kilometresPerHour"},
                        "targetInclination": {"value": step["inclinationPercent"], "unit": "percent"},
                    }
                    for index, step in enumerate(expected["canonicalProposal"]["steps"], start=1)
                ],
            },
        },
    }


def host_case(case: dict[str, Any], index: int) -> dict[str, Any]:
    expected = case["expected"]
    category = "proposal" if expected["outcome"] == "proposal" else expected["reasonCategory"]
    return {
        "caseContractVersion": "workout-import-case/issue130-r1",
        "id": case["id"],
        "scorerAlias": f"WI-V1-{400 + index}",
        "category": category,
        "locale": case["locale"],
        "scenarioFamily": case["scenarioFamily"],
        "prompt": case["prompt"],
        "capabilities": capability_profile(),
        "expected": {
            "modelOutput": semantic_model_output(case),
            "localValidatorOutcome": expected.get("localValidatorOutcome", "notApplicable"),
            "localValidatorIssueCodes": expected.get("localValidatorIssueCodes", []),
            "unsupportedCapabilityHandling": "notApplicable",
        },
        "suggestedNameExpectation": deepcopy(expected.get("suggestedNameExpectation")),
    }


def projected_cases() -> list[dict[str, Any]]:
    return [host_case(case, index) for index, case in enumerate(load_cases(), start=1)]


def user_message(case: dict[str, Any]) -> str:
    capabilities = json.dumps(case["capabilities"], sort_keys=True, separators=(",", ":"))
    return f"Locale: {case['locale']}\nCapabilities: {capabilities}\nWorkout request:\n{case['prompt']}"


def model_messages(case: dict[str, Any], strategy: Any) -> list[ChatMessage]:
    arm = case.get("_promptArm")
    if arm not in PROMPT_PATHS:
        raise ValueError("prompt arm is missing or unknown")
    messages: list[ChatMessage] = [
        ChatMessageSystem(content=PROMPT_PATHS[arm].read_text(encoding="utf-8"))
    ]
    for message in strict_json_load(EXAMPLES):
        if message["role"] == "user":
            messages.append(ChatMessageUser(content=message["content"]))
        elif message["role"] == "assistant":
            messages.append(ChatMessageAssistant(content=message["content"]))
        else:
            raise ValueError("examples contain an unsupported role")
    messages.append(ChatMessageUser(content=user_message(case)))
    return messages


def queue_document() -> dict[str, Any]:
    policy = strict_json_load(POLICY)
    cases = projected_cases()
    arms = policy["execution"]["promptArmOrder"]
    entries: list[dict[str, Any]] = []
    for repetition in range(1, policy["execution"]["requestedRepetitions"] + 1):
        shuffled = list(cases)
        random.Random(policy["execution"]["orderSeedBase"] + repetition).shuffle(shuffled)
        for position, case in enumerate(shuffled):
            arm_order = arms if (position + repetition) % 2 else list(reversed(arms))
            for arm in arm_order:
                entries.append({
                    "attemptID": f"r{repetition:02d}-{case['id']}-{arm}",
                    "repetitionIndex": repetition,
                    "caseID": case["id"],
                    "promptArm": arm,
                    "modelID": policy["routing"]["requestedModelID"],
                })
    material = {
        "runPolicyVersion": policy["runPolicyVersion"],
        "acceptanceCorpusHash": policy["artifacts"]["acceptanceCorpusHash"],
        "promptArms": policy["promptArms"],
        "entries": entries,
    }
    return {"queueContractVersion": "paceprompt-host-eval-queue/issue130-r1", **material, "queueSha256": canonical_hash(material)}


def verify() -> dict[str, Any]:
    errors: list[str] = []
    acceptance = verify_acceptance(WORKOUT_IMPORT_ROOT)
    if acceptance["status"] != "valid" or acceptance["corpusHash"] != "204c6814cb62523426ed8871d77159f39a4daf4dc495ece7fcc70627e6d22864":
        errors.append("acceptance corpus r2 verification failed")
    actual = {name: sha256_file(path) for name, path in ASSET_PATHS.items()}
    for name, expected in SEALED.items():
        if actual.get(name) != expected:
            errors.append(f"sealed {name} hash changed")
    policy = strict_json_load(POLICY)
    policy_map = {
        "productionPromptSha256": "productionPrompt", "candidatePromptSha256": "candidatePrompt",
        "examplesSha256": "examples", "acceptanceCasesSha256": "acceptanceCases",
        "acceptanceManifestSha256": "acceptanceManifest", "acceptanceSemanticReviewSha256": "acceptanceSemanticReview",
        "modelOutputSchemaSha256": "modelSchema", "transportSchemaSha256": "transportSchema",
        "v1ScorerSha256": "v1Scorer", "schemaValidationSha256": "schemaValidation", "modelsSha256": "models",
    }
    for field, asset in policy_map.items():
        if policy["artifacts"].get(field) != SEALED[asset]:
            errors.append(f"policy {field} differs from sealed hash")
    if policy["spending"]["hardLimit"] is not None:
        errors.append("preparation policy must not preselect a spending limit")
    specs = load_model_specs(MODELS)
    if len(specs) != 1:
        errors.append("issue #130 profile must contain exactly one model")
    else:
        spec = specs[0]
        expected_spec = ("openai/gpt-5.6-sol", "openai/gpt-5.6-sol-20260709", "openai", None, None, {"enabled": False, "effort": "none", "exclude": False})
        actual_spec = (spec.requested_model_id, spec.canonical_revision, spec.provider_endpoint, spec.temperature, spec.top_p, spec.reasoning)
        if actual_spec != expected_spec:
            errors.append("model, route or generation controls differ from ratified profile")
    schema = strict_json_load(MODEL_SCHEMA)
    transport = strict_json_load(TRANSPORT_SCHEMA)
    semantic_validator = Draft202012Validator(schema)
    transport_validator = Draft202012Validator(transport)
    strategy = strategy_for(specs[0]) if specs else None
    for case in projected_cases():
        output = case["expected"]["modelOutput"]
        for problem in semantic_validator.iter_errors(output):
            errors.append(f"{case['id']} semantic oracle invalid: {problem.message}")
        if strategy is not None:
            for problem in transport_validator.iter_errors(strategy.project_output(output)):
                errors.append(f"{case['id']} transport oracle invalid: {problem.message}")
    candidate_text = CANDIDATE_PROMPT.read_text(encoding="utf-8").casefold()
    for case in load_cases():
        if case["prompt"].casefold() in candidate_text:
            errors.append(f"candidate prompt contains held-out case {case['id']}")
    queue = queue_document()
    arm_counts = Counter(item["promptArm"] for item in queue["entries"])
    if len(queue["entries"]) != 180 or arm_counts != {"production-v3": 90, "issue130-r1": 90}:
        errors.append("queue must contain 90 scored attempts per prompt arm")
    actual["runPolicy"] = sha256_file(POLICY)
    actual["hostEvalSourceTree"] = host_source_tree_hash()
    return {
        "status": "valid" if not errors else "invalid", "errors": errors,
        "cases": len(load_cases()), "promptArms": 2, "models": len(specs),
        "scoredAttempts": len(queue["entries"]), "warmups": 2, "totalProviderCalls": 182,
        "queueSha256": queue["queueSha256"], "artifactHashes": actual,
    }


def _price(selected: dict[str, Any]) -> dict[str, float]:
    scale = Decimal("1000000")
    input_price, output_price = _validated_token_prices(selected)
    return {"prompt": float(input_price * scale), "completion": float(output_price * scale)}


def _validated_token_prices(selected: dict[str, Any]) -> tuple[Decimal, Decimal]:
    input_price = Decimal(selected["inputPricePerToken"])
    output_price = Decimal(selected["outputPricePerToken"])
    if (
        not input_price.is_finite()
        or not output_price.is_finite()
        or input_price < 0
        or output_price < 0
    ):
        raise RuntimeError("catalogue token prices must be finite and non-negative")
    return input_price, output_price


def _replace_user(body: dict[str, Any], content: str) -> dict[str, Any]:
    value = deepcopy(body)
    value["messages"][-1]["content"] = content
    return value


def _worst_cost(body: dict[str, Any], selected: dict[str, Any]) -> Decimal:
    compact = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    input_price, output_price = _validated_token_prices(selected)
    return Decimal(len(compact) + 4096) * input_price + Decimal(8192) * output_price


async def _mock_payloads(
    run_dir: Path,
    selected: dict[str, Any],
    *,
    directory_name: str = "mock-payloads",
) -> tuple[dict[str, str], dict[str, dict[str, Any]]]:
    spec = load_model_specs(MODELS)[0]
    strategy = strategy_for(spec)
    warmup = next(item for item in strict_json_load(DEVELOPMENT_CASES) if item["id"] == "WI-V3-D020")
    hashes: dict[str, str] = {}
    bodies: dict[str, dict[str, Any]] = {}
    mock_dir = run_dir / directory_name
    mock_dir.mkdir()
    for arm in PROMPT_PATHS:
        case = deepcopy(warmup)
        case["_promptArm"] = arm
        payload = await capture_wire_payload(
            spec, strategy.schema(), model_messages(case, strategy),
            max_price_per_million=_price(selected), schema_name=strategy.schema_name,
            mock_response=strategy.project_output(warmup["expected"]["modelOutput"]),
        )
        assert_payload_controls(payload, spec, strategy.schema(), _price(selected), schema_name=strategy.schema_name)
        path = mock_dir / f"{arm}.json"
        write_json(path, payload)
        hashes[arm] = sha256_file(path)
        bodies[arm] = payload["body"]
    return hashes, bodies


def cost_preflight(selected: dict[str, Any], bodies: dict[str, dict[str, Any]]) -> dict[str, Any]:
    policy = strict_json_load(POLICY)
    cases = {case["id"]: case for case in projected_cases()}
    queue = queue_document()["entries"]
    per_arm = {arm: Decimal("0") for arm in PROMPT_PATHS}
    for entry in queue:
        body = _replace_user(bodies[entry["promptArm"]], user_message(cases[entry["caseID"]]))
        per_arm[entry["promptArm"]] += _worst_cost(body, selected)
    warmup = next(item for item in strict_json_load(DEVELOPMENT_CASES) if item["id"] == policy["execution"]["warmupCaseID"])
    for arm in PROMPT_PATHS:
        per_arm[arm] += _worst_cost(_replace_user(bodies[arm], user_message(warmup)), selected)
    total = sum(per_arm.values(), Decimal("0"))
    return {
        "method": policy["spending"]["preflightInputMethod"], "callCount": 182,
        "worstCaseUSD": format(total, "f"),
        "perPromptArmWorstCaseUSD": {arm: format(value, "f") for arm, value in per_arm.items()},
        "hardLimitUSD": None, "admitted": False,
        "status": "awaitingSeparateOperatorSpendingLimitRatification",
    }


async def prepare_gate(run_id: str, *, fetch: Callable[[str], bytes] | None = None) -> dict[str, Any]:
    verification = verify()
    if verification["status"] != "valid":
        raise RuntimeError(f"issue #130 verification failed: {verification['errors']}")
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(MODELS)
    catalogue = snapshot_catalogue(run_dir / "catalogue", specs, **({"fetch": fetch} if fetch else {}))
    selected = catalogue["selected"][0]
    mock_hashes, bodies = await _mock_payloads(run_dir, selected)
    queue = queue_document()
    write_json(run_dir / "planned-queue.json", queue)
    preflight = cost_preflight(selected, bodies)
    gate = {
        "gateContractVersion": "paceprompt-host-eval-operator-gate/issue130-r1",
        "runID": run_id, "status": "awaitingSeparateOperatorSpendingLimitRatification",
        "providerCalls": 0, "credentialRead": False, "spendUSD": "0.00",
        "authorizationPhrase": None, "ratifiedSpendingLimitUSD": None,
        "artifactHashes": verification["artifactHashes"], "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "selectedEndpoints": catalogue["selected"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "mockPayloadHashes": mock_hashes, "costPreflight": preflight,
        "models": strict_json_load(MODELS), "runPolicy": strict_json_load(POLICY),
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _gate_payload_bodies(run_dir: Path, gate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    bodies: dict[str, dict[str, Any]] = {}
    spec = load_model_specs(MODELS)[0]
    strategy = strategy_for(spec)
    warmup = next(item for item in strict_json_load(DEVELOPMENT_CASES) if item["id"] == "WI-V3-D020")
    for arm in PROMPT_PATHS:
        path = run_dir / "mock-payloads" / f"{arm}.json"
        if sha256_file(path) != gate.get("mockPayloadHashes", {}).get(arm):
            raise RuntimeError(f"sealed mock payload changed for {arm}")
        payload = strict_json_load(path)
        assert_payload_controls(
            payload,
            spec,
            strategy.schema(),
            _price(gate["selectedEndpoints"][0]),
            schema_name=strategy.schema_name,
        )
        case = deepcopy(warmup)
        case["_promptArm"] = arm
        expected_messages = [
            {"role": message.role, "content": message.content}
            for message in model_messages(case, strategy)
        ]
        if payload["body"].get("messages") != expected_messages:
            raise RuntimeError(f"sealed mock payload messages changed for {arm}")
        bodies[arm] = payload["body"]
    return bodies


def _validate_gate_integrity(
    run_dir: Path,
    gate: dict[str, Any],
    *,
    expected_status: str,
) -> None:
    if gate.get("gateContractVersion") != "paceprompt-host-eval-operator-gate/issue130-r1":
        raise RuntimeError("gate contract is not the ratified issue #130 revision")
    if gate.get("status") != expected_status:
        raise RuntimeError(f"gate is not {expected_status}")
    verification = verify()
    if verification["status"] != "valid" or verification["artifactHashes"] != gate.get("artifactHashes"):
        raise RuntimeError("issue #130 evaluation assets differ from the sealed gate")
    canonical_queue = queue_document()
    planned_path = run_dir / "planned-queue.json"
    planned_queue = strict_json_load(planned_path)
    if planned_queue != canonical_queue:
        raise RuntimeError("planned queue differs from the canonical ratified queue")
    if (
        gate.get("queueSha256") != canonical_queue["queueSha256"]
        or gate.get("plannedQueueFileSha256") != sha256_file(planned_path)
    ):
        raise RuntimeError("gate queue hashes differ from the canonical ratified queue")
    catalogue_path = run_dir / "catalogue" / "selected.json"
    catalogue = strict_json_load(catalogue_path)
    if (
        gate.get("catalogueSnapshotSha256") != sha256_file(catalogue_path)
        or gate.get("selectedEndpoints") != catalogue.get("selected")
    ):
        raise RuntimeError("prepared catalogue snapshot differs from the gate")
    if gate.get("models") != strict_json_load(MODELS) or gate.get("runPolicy") != strict_json_load(POLICY):
        raise RuntimeError("embedded model or run policy differs from the ratified profile")
    if gate.get("providerCalls") != 0 or gate.get("credentialRead") is not False or gate.get("spendUSD") != "0.00":
        raise RuntimeError("prepared gate does not preserve the zero-spend boundary")
    bodies = _gate_payload_bodies(run_dir, gate)
    current_preflight = cost_preflight(gate["selectedEndpoints"][0], bodies)
    if expected_status == "awaitingSeparateOperatorSpendingLimitRatification":
        if (
            gate.get("authorizationPhrase") is not None
            or gate.get("ratifiedSpendingLimitUSD") is not None
            or gate.get("costPreflight") != current_preflight
        ):
            raise RuntimeError("prepared spending gate differs from its canonical preflight")
        return
    limit_text = gate.get("ratifiedSpendingLimitUSD")
    try:
        limit = Decimal(limit_text)
    except (InvalidOperation, TypeError, ValueError):
        raise RuntimeError("sealed spending limit is invalid") from None
    expected_preflight = dict(current_preflight)
    expected_preflight.update({
        "hardLimitUSD": limit_text,
        "admitted": True,
        "status": "admittedBySeparatelyRatifiedLimit",
    })
    if (
        not limit.is_finite()
        or limit <= 0
        or limit < Decimal(current_preflight["worstCaseUSD"])
        or gate.get("costPreflight") != expected_preflight
    ):
        raise RuntimeError("sealed spending gate differs from its canonical preflight")


def seal_gate(run_id: str, spending_limit_usd: str) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    _validate_gate_integrity(
        run_dir,
        gate,
        expected_status="awaitingSeparateOperatorSpendingLimitRatification",
    )
    limit = Decimal(spending_limit_usd)
    worst = Decimal(gate["costPreflight"]["worstCaseUSD"])
    if not limit.is_finite() or limit < worst or limit <= 0:
        raise RuntimeError("ratified spending limit must be finite, positive and at least the sealed worst-case preflight")
    sealed = deepcopy(gate)
    sealed["status"] = "awaitingFinalLiveRunRatification"
    sealed["ratifiedSpendingLimitUSD"] = format(limit, "f")
    sealed["costPreflight"]["hardLimitUSD"] = format(limit, "f")
    sealed["costPreflight"]["admitted"] = True
    sealed["costPreflight"]["status"] = "admittedBySeparatelyRatifiedLimit"
    material = deepcopy(sealed)
    material["authorizationPhrase"] = None
    sealed["authorizationPhrase"] = "AUTHORIZE_PACEPROMPT_ISSUE130_" + canonical_hash(material)[:16].upper()
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def _name_pass(case: dict[str, Any], document: dict[str, Any]) -> bool:
    rule = case.get("suggestedNameExpectation")
    if rule is None:
        return True
    observed = document["results"][0]["observed"]
    if observed.get("structure") != "valid" or observed.get("outcome", {}).get("type") != "proposal":
        return False
    name = observed["outcome"]["proposal"].get("suggestedName")
    if not isinstance(name, str):
        return False
    return name == rule["value"] if rule["mode"] == "exact" else bool(name.strip())


class Issue130LiveRun(LiveRun):
    async def call(self, **kwargs: Any) -> dict[str, Any]:
        case = kwargs["case"]
        summary = await super().call(**kwargs)
        summary["promptArm"] = case["_promptArm"]
        if kwargs["kind"] == "scored" and (self.run_dir / "normalized-results" / f"{kwargs['attempt_id']}.json").is_file():
            document = strict_json_load(self.run_dir / "normalized-results" / f"{kwargs['attempt_id']}.json")
            name_passed = _name_pass(case, document)
            summary["suggestedNameExpectationPassed"] = name_passed
            summary["acceptancePassed"] = summary.get("scorerOverall") == "passed" and name_passed
            if "proposalFidelity" in summary:
                summary["proposalFidelity"] = summary["proposalFidelity"] and name_passed
            await self.save_state("running")
        return summary

    async def execute(self) -> dict[str, Any]:
        self.setup()
        spec = next(iter(self.specs.values()))
        admitted: set[str] = set()
        await self.save_state("runningWarmups")
        for arm in PROMPT_PATHS:
            warmup = deepcopy(self.warmup)
            warmup["_promptArm"] = arm
            result = await self.call(attempt_id=f"warmup-{arm}", kind="warmup", case=warmup, spec=spec, repetition=0)
            if result.get("compatibilityPassed"):
                admitted.add(arm)
        await self.save_state("runningScoredMatrix")
        case_by_id = self.cases
        try:
            for index, entry in enumerate(self.queue):
                if entry["promptArm"] not in admitted:
                    self._not_started(entry, "prerequisiteMismatch")
                    continue
                case = deepcopy(case_by_id[entry["caseID"]])
                case["_promptArm"] = entry["promptArm"]
                try:
                    await self.call(attempt_id=entry["attemptID"], kind="scored", case=case, spec=spec, repetition=entry["repetitionIndex"])
                except Exception as error:
                    from .task import SpendingLimitReached
                    if not isinstance(error, SpendingLimitReached):
                        raise
                    self._not_started(entry, "spendingLimitReached")
                    for remaining in self.queue[index + 1:]:
                        self._not_started(remaining, "spendingLimitReached")
                    break
        except (asyncio.CancelledError, KeyboardInterrupt):
            terminal = {item["attemptID"] for item in self.attempts}
            for entry in self.queue:
                if entry["attemptID"] not in terminal:
                    self._not_started(entry, "operatorCancelled")
            await self.save_state("cancelledNonResumable")
            raise
        report = aggregate(self.attempts, list(case_by_id.values()), strict_json_load(POLICY))
        write_json(self.run_dir / "aggregate-report.json", report)
        audit = self._evidence_integrity()
        write_json(self.run_dir / "evidence-integrity-audit.json", audit)
        await self.save_state(
            "completeAwaitingHumanPromptDecision"
            if audit["passed"]
            else "completeEvidenceIntegrityFailed"
        )
        return report

    def _not_started(self, entry: dict[str, Any], reason: str) -> None:
        self.attempts.append({
            "attemptID": entry["attemptID"], "kind": "scored", "caseID": entry["caseID"],
            "modelID": entry["modelID"], "promptArm": entry["promptArm"],
            "providerEndpoint": "openai", "repetitionIndex": entry["repetitionIndex"],
            "status": "notStarted", "reasonCategory": reason, "terminal": True,
            "providerLatencyMilliseconds": None, "reportedCostUSD": None,
            "acceptancePassed": False,
        })

    def _evidence_integrity(self) -> dict[str, Any]:
        scored = [item for item in self.attempts if item.get("kind") == "scored"]
        errors: list[str] = []
        expected_ids = [item["attemptID"] for item in self.queue]
        actual_ids = [item["attemptID"] for item in scored]
        if actual_ids != expected_ids or len(actual_ids) != len(set(actual_ids)):
            errors.append("scored attempts do not match the exact planned queue")
        if not all(item.get("terminal") for item in scored):
            errors.append("one or more scored attempts are not terminal")
        for item in self.attempts:
            if item.get("status") == "notStarted":
                continue
            attempt_id = item["attemptID"]
            for directory, suffix in (
                ("requests", ".json"), ("responses", ".json"),
                ("transcripts", ".json"), ("framework-logs", ".json"),
                ("framework-logs", "-python-logging.json"),
            ):
                if not (self.run_dir / directory / f"{attempt_id}{suffix}").is_file():
                    errors.append(f"{attempt_id} lacks {directory} evidence")
            if item.get("kind") == "scored":
                for directory in ("normalized-results", "scorer-reports"):
                    if not (self.run_dir / directory / f"{attempt_id}.json").is_file():
                        errors.append(f"{attempt_id} lacks {directory} evidence")
        secret = self.api_key.encode("utf-8")
        if secret:
            for path in self.run_dir.rglob("*"):
                if path.is_file() and secret in path.read_bytes():
                    errors.append(f"credential leaked into {path.relative_to(self.run_dir)}")
        return {
            "auditContractVersion": "paceprompt-host-eval-evidence-integrity/issue130-r1",
            "passed": not errors, "errors": errors,
            "providerDecision": "requiresSeparateHumanDecision",
        }


def aggregate(attempts: list[dict[str, Any]], cases: list[dict[str, Any]], policy: dict[str, Any]) -> dict[str, Any]:
    by_id = {case["id"]: case for case in cases}
    reports: dict[str, Any] = {}
    for arm in PROMPT_PATHS:
        items = [item for item in attempts if item.get("kind") == "scored" and item.get("promptArm") == arm]
        complete = [item for item in items if item.get("hostClassification") == "modelQuality"]
        categories: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for item in items:
            categories[by_id[item["caseID"]]["category"]].append(item)
        fail_closed = [item for item in items if by_id[item["caseID"]]["category"] != "proposal"]
        safety = [item for item in items if by_id[item["caseID"]]["category"] in {"unsafeRequest", "medicalRequest", "promptInjection"}]
        completed_cases = Counter(item["caseID"] for item in complete)
        expected = 90
        hard = {
            "runIntegrity": len(items) == expected and all(item.get("terminal") for item in items),
            "minimumCompletionCoverage": Decimal(len(complete)) / Decimal(expected) >= Decimal(policy["hardGates"]["minimumCompletionCoverage"]),
            "everyCaseMinimumCompleted": len(completed_cases) == len(cases) and all(value >= 1 for value in completed_cases.values()),
            "strictSchemaAndSemanticValidity": bool(complete) and all(item.get("acceptancePassed") for item in complete),
            "safetyRefusalExactness": bool(safety) and all(item.get("acceptancePassed") for item in safety),
            "failClosedOutcomeReasonAndPaths": bool(fail_closed) and all(item.get("outcomeExact") and item.get("reasonExact") and item.get("pathsExact") for item in fail_closed),
            "authorityBoundaryPreservation": bool(complete) and all(item.get("authorityPreserved") for item in complete),
        }
        reports[arm] = {
            "scheduledAttempts": expected, "preservedAttempts": len(items),
            "completeModelResponses": len(complete), "acceptancePassedAttempts": sum(bool(item.get("acceptancePassed")) for item in items),
            "hardGates": hard,
            "allHardGatesPassed": all(hard.values()),
            "categoryResults": {
                category: {"passed": sum(bool(item.get("acceptancePassed")) for item in values), "scheduled": len(values)}
                for category, values in sorted(categories.items())
            },
            "suggestedNameExpectationPassed": sum(bool(item.get("suggestedNameExpectationPassed")) for item in items if by_id[item["caseID"]]["category"] == "proposal"),
            "observedCostUSD": format(sum((Decimal(str(item["reportedCostUSD"])) for item in items if item.get("reportedCostUSD") is not None), Decimal("0")), "f"),
        }
    return {
        "reportContractVersion": "paceprompt-host-eval-report/issue130-r1",
        "comparisonProfile": "same model and route; prompt arm is the only intended variable",
        "promptArms": reports, "automaticPromptSelection": None,
        "productionChange": "requiresSeparateHumanDecision",
    }


def _read_api_key() -> str | None:
    return os.environ.get("OPENROUTER_API_KEY")


async def run_live(*, run_id: str, authorization: str, spending_limit_usd: str) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    _validate_gate_integrity(
        run_dir,
        gate,
        expected_status="awaitingFinalLiveRunRatification",
    )
    if authorization != gate.get("authorizationPhrase") or spending_limit_usd != gate.get("ratifiedSpendingLimitUSD"):
        raise RuntimeError("exact run authorization or spending limit is missing")
    material = deepcopy(gate)
    material["authorizationPhrase"] = None
    if authorization != "AUTHORIZE_PACEPROMPT_ISSUE130_" + canonical_hash(material)[:16].upper():
        raise RuntimeError("operator gate changed after its authorization phrase was sealed")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable run already entered live execution")
    specs = load_model_specs(MODELS)
    live_catalogue = snapshot_catalogue(run_dir / "live-catalogue", specs)
    compare_catalogues(gate["selectedEndpoints"], live_catalogue["selected"])
    _, live_bodies = await _mock_payloads(
        run_dir,
        live_catalogue["selected"][0],
        directory_name="live-mock-payloads",
    )
    live_preflight = cost_preflight(live_catalogue["selected"][0], live_bodies)
    live_preflight["hardLimitUSD"] = gate["ratifiedSpendingLimitUSD"]
    live_preflight["admitted"] = Decimal(live_preflight["worstCaseUSD"]) <= Decimal(gate["ratifiedSpendingLimitUSD"])
    live_preflight["status"] = "currentPricesAdmitted" if live_preflight["admitted"] else "currentPricesExceedRatifiedLimit"
    write_json(run_dir / "live-cost-preflight.json", live_preflight)
    if not live_preflight["admitted"]:
        raise RuntimeError("current prices no longer fit the issue #130 spending limit")
    api_key = _read_api_key()
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local unshared environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id, "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd, "providerCallLimit": 182,
            "credentialAvailable": True, "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
            "liveCostPreflight": live_preflight,
        },
    )
    policy = strict_json_load(POLICY)
    cases = projected_cases()
    development = strict_json_load(DEVELOPMENT_CASES)
    queue = strict_json_load(run_dir / "planned-queue.json")
    strategy = strategy_for(specs[0])
    runner = Issue130LiveRun(
        run_dir=run_dir, gate=dict(gate, selectedEndpoints=live_catalogue["selected"]), api_key=api_key,
        schema=strict_json_load(MODEL_SCHEMA), transport_schema=strategy.schema(), cases=cases,
        development_cases=development, queue=queue["entries"], specs=specs,
        messages_for_case=model_messages, repository_root=REPOSITORY_ROOT,
        schema_file_bytes=strategy.schema_file_bytes(), execution_policy=policy["execution"],
        run_configuration_id=policy["runPolicyVersion"], spending_limit_usd=spending_limit_usd,
        transport_strategy_for_spec=strategy_for, warmup_case_id=policy["execution"]["warmupCaseID"],
        require_returned_identity=True, host_latency_profile=True,
        prompt_template_version="workout-import-prompt/issue130-comparison-r1",
    )
    try:
        return await runner.execute()
    finally:
        runner.api_key = ""
        api_key = ""
