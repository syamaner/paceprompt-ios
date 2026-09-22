"""Zero-spend preparation for the three-model issue #145 Stage B profile."""

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
    cost_preflight,
    model_messages,
    mock_payloads,
    required_parameter_contracts,
    scored_strata,
)
from .issue145_stage_a import (
    MODELS as STAGE_A_MODELS,
    verify as verify_stage_a,
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


MODELS = HOST_EVAL_ROOT / "models-v5-issue145-stage-b.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v5-issue145-stage-b.json"
REVIEW = HOST_EVAL_ROOT / "issue145-stage-b-review-r1.json"
PROPOSAL = HOST_EVAL_ROOT / "issue145-stage-b-proposal-r1.json"
RATIFICATION = HOST_EVAL_ROOT / "issue145-stage-b-ratification-r1.json"
STAGE_A_AGGREGATE = (
    REPOSITORY_ROOT
    / "Evaluation"
    / "WorkoutImport"
    / "Summaries"
    / "issue145-stage-a-data.json"
)
STAGE_A_MANIFEST = (
    REPOSITORY_ROOT
    / "Evaluation"
    / "WorkoutImport"
    / "Summaries"
    / "issue145-stage-a-publication-manifest.json"
)
QUEUE_CONTRACT = "paceprompt-host-eval-queue/issue145-v5-stage-b"
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/issue145-v5-stage-b"
MODELS_SHA256 = "fe262cd3c2c9c9b640fae309becfe227bc42274f769e1ac33e92c647150bdf5a"
RUN_POLICY_SHA256 = "8ee31d253bac71869e2f38b821a201231a5405265ccfa00ab88ec9eb19a6240c"
REVIEW_SHA256 = "276f8deb740be6774af2c4c9134b1410d471ab7a5a8708623ca969d9625f0bbc"
PROPOSAL_SHA256 = "1646c57a6da4edeb444ffcae752862824b1fe83ec43dd2357b5cb29faf5bc302"
RATIFICATION_SHA256 = "3e07429e2d869dec3c44c8e0a805bfc4e833301f2aa77d9ccb46b18b4433dd36"
STAGE_A_AGGREGATE_SHA256 = (
    "bf922a6302e78ac47064ce578991e2205ca2d59592a123f29b65515dca2c2e0e"
)
STAGE_A_MANIFEST_SHA256 = (
    "ac9350f3a2876a387548d44931922f197f937f23692ed1e1111b5594786e514b"
)
EXPECTED_MODELS = (
    "openai/gpt-5.6-sol",
    "qwen/qwen3.8-27b",
    "openai/gpt-5.6-luna",
)
PROPOSED_RUN_ID = "issue145-top3-stage-b-v5-20260921-01"
EXPECTED_STAGE_A_MAXIMA = {
    "openai/gpt-5.6-sol": 3313,
    "qwen/qwen3.8-27b": 3959,
    "openai/gpt-5.6-luna": 3312,
}
AUTHORIZATION_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_STAGE_B_"


def _policy() -> dict[str, Any]:
    return strict_json_load(RUN_POLICY)


def queue_document() -> dict[str, Any]:
    policy = _policy()
    specs = load_model_specs(MODELS)
    if tuple(spec.requested_model_id for spec in specs) != EXPECTED_MODELS:
        raise ValueError("issue #145 Stage B model order differs from the reviewed profile")
    repetitions = policy["execution"]["repetitionIndices"]
    if repetitions != [2, 3]:
        raise ValueError("issue #145 Stage B must contain global repetitions 2 and 3")
    entries: list[dict[str, Any]] = []
    seed_base = policy["execution"]["orderSeedBase"]
    for stratum_id, cases in scored_strata():
        for repetition in repetitions:
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
        "stageAProposalSha256": policy["parentStageAProposalSha256"],
        "stageAPublicationManifestSha256": STAGE_A_MANIFEST_SHA256,
        "stageBReviewSha256": REVIEW_SHA256,
        "strata": [
            {
                "id": stratum_id,
                "caseCount": len(cases),
                "caseIDsSha256": canonical_hash([case["id"] for case in cases]),
            }
            for stratum_id, cases in scored_strata()
        ],
        "repetitionIndices": repetitions,
        "entries": entries,
    }
    return {
        "queueContractVersion": QUEUE_CONTRACT,
        **material,
        "queueSha256": canonical_hash(material),
    }


def _stage_a_readiness_errors() -> list[str]:
    errors: list[str] = []
    aggregate = strict_json_load(STAGE_A_AGGREGATE)
    readiness = aggregate.get("stageBReadiness", {})
    token_evidence = aggregate.get("reportedOutputTokenEvidence", {})
    for model_id in EXPECTED_MODELS:
        model = readiness.get(model_id, {})
        coverage = model.get("completionCoverage", {})
        if (
            model.get("warmupPassed") is not True
            or coverage != {"completed": 109, "scheduled": 109}
            or model.get("rateLimitPaused") is not False
            or model.get("outputLimitFailure") is not False
        ):
            errors.append(f"Stage A readiness changed for {model_id}")
        evidence = token_evidence.get(model_id, {})
        if (
            evidence.get("reportedAttempts") != 110
            or evidence.get("maximumOutputTokens") != EXPECTED_STAGE_A_MAXIMA[model_id]
        ):
            errors.append(f"Stage A output-token evidence changed for {model_id}")
    gemini = readiness.get("google/gemini-3.7-flash", {})
    if gemini.get("warmupPassed") is not False or gemini.get("completionCoverage") != {
        "completed": 0,
        "scheduled": 109,
    }:
        errors.append("Gemini exclusion evidence changed")
    return errors


def verify() -> dict[str, Any]:
    errors: list[str] = []
    parent = verify_stage_a()
    if parent["status"] != "valid":
        errors.append("preserved Stage A profile verification failed")
    for path, expected, label in (
        (MODELS, MODELS_SHA256, "models"),
        (RUN_POLICY, RUN_POLICY_SHA256, "run policy"),
        (REVIEW, REVIEW_SHA256, "review"),
        (PROPOSAL, PROPOSAL_SHA256, "proposal"),
        (RATIFICATION, RATIFICATION_SHA256, "ratification"),
        (STAGE_A_AGGREGATE, STAGE_A_AGGREGATE_SHA256, "Stage A aggregate"),
        (STAGE_A_MANIFEST, STAGE_A_MANIFEST_SHA256, "Stage A publication manifest"),
    ):
        if sha256_file(path) != expected:
            errors.append(f"Stage B {label} hash changed")
    errors.extend(_stage_a_readiness_errors())

    specs = load_model_specs(MODELS)
    stage_a = {
        spec.requested_model_id: spec for spec in load_model_specs(STAGE_A_MODELS)
    }
    if tuple(spec.requested_model_id for spec in specs) != EXPECTED_MODELS:
        errors.append("Stage B selected model set or order changed")
    for spec in specs:
        parent_spec = stage_a.get(spec.requested_model_id)
        if parent_spec is None:
            errors.append(f"Stage B added non-Stage-A model {spec.requested_model_id}")
            continue
        current = (
            spec.canonical_revision,
            spec.provider_endpoint,
            spec.quantization,
            spec.temperature,
            spec.top_p,
            spec.reasoning,
            spec.response_contract,
            strategy_for(spec).identifier,
        )
        prior = (
            parent_spec.canonical_revision,
            parent_spec.provider_endpoint,
            parent_spec.quantization,
            parent_spec.temperature,
            parent_spec.top_p,
            parent_spec.reasoning,
            parent_spec.response_contract,
            strategy_for(parent_spec).identifier,
        )
        if current != prior:
            errors.append(f"Stage B changed the retained profile for {spec.requested_model_id}")
        if spec.transport_registry_id != ISSUE145_V5_REGISTRY_ID:
            errors.append(f"Stage B changed the transport registry for {spec.requested_model_id}")
        if spec.max_output_tokens != 6144:
            errors.append(f"Stage B output ceiling changed for {spec.requested_model_id}")

    policy = _policy()
    if policy["spending"]["hardLimit"] is not None:
        errors.append("Stage B preparation must not preselect a spending limit")
    if policy["execution"] != {
        "stage": "B",
        "repetitionIndices": [2, 3],
        "requestedRepetitionsPerStratum": 2,
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "orderSeedBase": 15003405,
        "modelOrder": list(EXPECTED_MODELS),
        "orderRule": "shuffle-each-stratum-per-global-repetition-index-then-rotate-models-in-declared-order",
        "warmupsPerModel": 1,
        "warmupGate": "per-model-response-contract-transport-and-full-v2-schema-validity",
        "warmupOracleAgreement": "diagnostic-only",
        "cache": False,
        "cachePrompt": False,
        "automaticRetries": 0,
        "httpConnectRetries": 0,
        "connectTimeoutSeconds": 15,
        "attemptTimeoutSeconds": 180,
        "overallRunTimeoutSeconds": None,
        "cancelFlushSeconds": 15,
        "resumable": False,
        "rateLimitDisposition": "pause-model-skip-remaining-in-place",
        "scoredAttempts": 654,
        "warmups": 3,
        "totalProviderCalls": 657,
    }:
        errors.append("Stage B execution controls changed")
    if policy["decision"].get("automaticWinner") is not False:
        errors.append("Stage B must not select a winner automatically")
    if policy["reporting"].get("publication") != "requires-separate-approval":
        errors.append("Stage B publication boundary changed")

    proposal = strict_json_load(PROPOSAL)
    ratification = strict_json_load(RATIFICATION)
    if proposal.get("proposedRunID") != PROPOSED_RUN_ID:
        errors.append("Stage B proposed run ID changed")
    if proposal.get("profile") != {
        "maxOutputTokens": 6144,
        "models": list(EXPECTED_MODELS),
        "plannedQueueFileSha256": "3b90d505c753100b50298f85d9f5869e6012091c46a0352853ef757555e936d2",
        "queueSha256": "e505a355a81c9c810c26b6718c0a1324a3cf2ddbc70733ca96dc717852a80346",
        "repetitionIndices": [2, 3],
        "review": REVIEW_SHA256,
        "runPolicy": RUN_POLICY_SHA256,
        "scoredAttempts": 654,
        "stageAAggregate": STAGE_A_AGGREGATE_SHA256,
        "stageAPublicationManifest": STAGE_A_MANIFEST_SHA256,
        "strata": ["v3-heldout-regression", "issue130-acceptance-r2"],
        "totalProviderCalls": 657,
        "warmups": 3,
    }:
        errors.append("Stage B committed proposal profile changed")
    spending = proposal.get("spending", {})
    if (
        spending.get("recommendedHardLimit") != "32.07052912"
        or spending.get("conservativeWorstCase") != "32.07052912"
        or spending.get("hardLimitRatified") is not False
    ):
        errors.append("Stage B committed proposal spending state changed")
    if any(proposal.get("authority", {}).values()):
        errors.append("Stage B committed proposal must grant no authority")
    if ratification.get("ratifiedProposalSha256") != PROPOSAL_SHA256:
        errors.append("Stage B ratification does not bind the exact proposal")
    if ratification.get("ratifiedRunID") != PROPOSED_RUN_ID:
        errors.append("Stage B ratification changed the proposed run ID")
    if ratification.get("ratifiedSpendingLimitUSD") != spending.get(
        "recommendedHardLimit"
    ):
        errors.append("Stage B ratification changed the proposed spending limit")
    if (
        ratification.get("ratifiedModelCount") != 3
        or ratification.get("ratifiedScoredAttempts") != 654
        or ratification.get("ratifiedWarmups") != 3
        or ratification.get("ratifiedTotalProviderCalls") != 657
        or ratification.get("ratifiedMaxOutputTokens") != 6144
    ):
        errors.append("Stage B ratification changed the reviewed profile counts")
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
        errors.append("Stage B ratification authority boundary changed")

    queue = queue_document() if len(specs) == 3 else None
    if queue is not None:
        model_counts = Counter(item["modelID"] for item in queue["entries"])
        stratum_counts = Counter(item["stratumID"] for item in queue["entries"])
        repetitions = Counter(item["repetitionIndex"] for item in queue["entries"])
        if len(queue["entries"]) != 654 or set(model_counts.values()) != {218}:
            errors.append("Stage B queue must contain 654 attempts and 218 per model")
        if stratum_counts != {
            "v3-heldout-regression": 474,
            "issue130-acceptance-r2": 180,
        }:
            errors.append("Stage B stratum counts changed")
        if repetitions != {2: 327, 3: 327}:
            errors.append("Stage B repetition counts changed")
        attempt_ids = [item["attemptID"] for item in queue["entries"]]
        if len(attempt_ids) != len(set(attempt_ids)):
            errors.append("Stage B attempt IDs are not unique")

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
            "stageAAggregate": sha256_file(STAGE_A_AGGREGATE),
            "stageAPublicationManifest": sha256_file(STAGE_A_MANIFEST),
        },
    }


def _proposal_material(
    verification: dict[str, Any],
    queue: dict[str, Any],
    run_dir: Path,
    preflight: dict[str, Any],
) -> dict[str, Any]:
    return {
        "proposalContractVersion": "paceprompt-issue145-stage-b-proposal/r1",
        "status": "awaiting-operator-ratification",
        "proposedRunID": PROPOSED_RUN_ID,
        "profile": {
            **{
                key: verification["configurationHashes"][key]
                for key in (
                    "models",
                    "review",
                    "runPolicy",
                    "stageAAggregate",
                    "stageAPublicationManifest",
                )
            },
            "queueSha256": queue["queueSha256"],
            "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
            "models": list(EXPECTED_MODELS),
            "strata": [name for name, _ in scored_strata()],
            "repetitionIndices": [2, 3],
            "scoredAttempts": 654,
            "warmups": 3,
            "totalProviderCalls": 657,
            "maxOutputTokens": 6144,
        },
        "publicCatalogue": {
            "snapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
            "allConfiguredRoutesAvailable": True,
        },
        "spending": {
            "currency": "USD",
            "conservativeWorstCase": preflight["estimatedUSD"],
            "recommendedHardLimit": preflight["estimatedUSD"],
            "hardLimitRatified": False,
            "perModelWorstCase": preflight["perModelEstimatedUSD"],
        },
        "controls": {
            key: _policy()["execution"][key]
            for key in (
                "globalConcurrency",
                "minimumInterCallDelaySeconds",
                "automaticRetries",
                "httpConnectRetries",
                "connectTimeoutSeconds",
                "attemptTimeoutSeconds",
                "overallRunTimeoutSeconds",
                "cancelFlushSeconds",
                "resumable",
                "rateLimitDisposition",
            )
        },
        "authority": {
            "credentialRead": False,
            "providerInference": False,
            "spend": False,
            "liveRun": False,
            "publication": False,
            "productionChange": False,
        },
    }


async def prepare_gate(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None
) -> dict[str, Any]:
    verification = verify()
    if verification["status"] != "valid":
        raise RuntimeError(f"issue #145 Stage B verification failed: {verification['errors']}")
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
    proposal = _proposal_material(verification, queue, run_dir, preflight)
    write_json(run_dir / "proposal-material.json", proposal)
    gate = {
        "gateContractVersion": GATE_CONTRACT,
        "runID": run_id,
        "status": "awaitingExactProfileAndSpendingLimitRatification",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "authorizationPhrase": None,
        "ratifiedSpendingLimitUSD": None,
        "liveExecutionImplemented": True,
        "hostSourceTreeSha256": host_source_tree_hash(),
        "configurationHashes": verification["configurationHashes"],
        "queueSha256": queue["queueSha256"],
        "plannedQueueFileSha256": sha256_file(run_dir / "planned-queue.json"),
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "selectedEndpoints": snapshot["selected"],
        "mockPayloadHashes": mocks["payloadHashes"],
        "responseContracts": mocks["responseContracts"],
        "costPreflight": preflight,
        "proposalMaterialSha256": sha256_file(run_dir / "proposal-material.json"),
        "profileRatification": strict_json_load(RATIFICATION),
        "requiredBeforeLive": [
            "the-ratified-stage-b-proposal-and-limit-remain-byte-identical",
            "the-reviewed-live-runner-and-host-source-remain-byte-identical",
            "operator-separately-authorizes-the-exact-live-run-instance",
        ],
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def main_prepare(run_id: str) -> dict[str, Any]:
    return asyncio.run(prepare_gate(run_id))


def _payload_templates(run_dir: Path, gate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for model_id, expected_hash in gate["mockPayloadHashes"].items():
        path = run_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        if sha256_file(path) != expected_hash:
            raise RuntimeError(f"sealed Stage B mock payload changed for {model_id}")
        templates[model_id] = strict_json_load(path)["body"]
    return templates


def _validate_gate_integrity(
    run_dir: Path, gate: dict[str, Any], *, expected_status: str
) -> dict[str, dict[str, Any]]:
    if gate.get("gateContractVersion") != GATE_CONTRACT:
        raise RuntimeError("gate contract is not issue #145 Stage B")
    if gate.get("status") != expected_status:
        raise RuntimeError(f"gate is not {expected_status}")
    verification = verify()
    if (
        verification["status"] != "valid"
        or verification["configurationHashes"] != gate.get("configurationHashes")
    ):
        raise RuntimeError("Stage B assets differ from the prepared gate")
    if gate.get("hostSourceTreeSha256") != host_source_tree_hash():
        raise RuntimeError("HostEval source changed after Stage B gate preparation")
    queue = queue_document()
    queue_path = run_dir / "planned-queue.json"
    if strict_json_load(queue_path) != queue:
        raise RuntimeError("planned queue differs from the canonical Stage B queue")
    if (
        gate.get("queueSha256") != queue["queueSha256"]
        or gate.get("plannedQueueFileSha256") != sha256_file(queue_path)
    ):
        raise RuntimeError("Stage B queue hashes changed")
    catalogue_path = run_dir / "catalogue" / "selected.json"
    catalogue = strict_json_load(catalogue_path)
    if (
        gate.get("catalogueSnapshotSha256") != sha256_file(catalogue_path)
        or gate.get("selectedEndpoints") != catalogue.get("selected")
    ):
        raise RuntimeError("Stage B catalogue evidence changed")
    proposal_path = run_dir / "proposal-material.json"
    if gate.get("proposalMaterialSha256") != sha256_file(proposal_path):
        raise RuntimeError("Stage B proposal material changed")
    if gate.get("profileRatification") != strict_json_load(RATIFICATION):
        raise RuntimeError("Stage B ratification differs from the gate")
    if gate.get("liveExecutionImplemented") is not True:
        raise RuntimeError("Stage B live runner is not bound to the gate")
    if (
        gate.get("providerCalls") != 0
        or gate.get("credentialRead") is not False
        or gate.get("spendUSD") != "0.00"
    ):
        raise RuntimeError("Stage B gate crossed the zero-spend boundary")
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
            raise RuntimeError("prepared Stage B spending gate changed")
        return templates
    limit_text = gate.get("ratifiedSpendingLimitUSD")
    try:
        limit = Decimal(limit_text)
    except (InvalidOperation, TypeError, ValueError):
        raise RuntimeError("sealed Stage B spending limit is invalid") from None
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
        raise RuntimeError("sealed Stage B spending gate changed")
    return templates


def seal_gate(run_id: str) -> dict[str, Any]:
    ratification = strict_json_load(RATIFICATION)
    if run_id != ratification["ratifiedRunID"]:
        raise RuntimeError("Stage B run ID is not the ratified run instance")
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    _validate_gate_integrity(
        run_dir,
        gate,
        expected_status="awaitingExactProfileAndSpendingLimitRatification",
    )
    limit_text = ratification["ratifiedSpendingLimitUSD"]
    if Decimal(limit_text) < Decimal(gate["costPreflight"]["estimatedUSD"]):
        raise RuntimeError("ratified limit is below the prepared Stage B worst case")
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
        raise RuntimeError("sealed Stage B payload lacks its final user message")
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
                    f"live Stage B catalogue {key} increased for "
                    f"{endpoint['requestedModelID']}"
                )


def _admit_live_cost_preflight(
    preflight: dict[str, Any], spending_limit_usd: str
) -> dict[str, Any]:
    admitted = deepcopy(preflight)
    if Decimal(admitted["estimatedUSD"]) > Decimal(spending_limit_usd):
        raise RuntimeError("current Stage B prices exceed the ratified limit")
    admitted["hardLimitUSD"] = spending_limit_usd
    admitted["admitted"] = True
    admitted["status"] = "admittedUnderExactRatifiedHardLimit"
    return admitted


def _stage_b_aggregate(
    attempts: list[dict[str, Any]], specs: tuple[Any, ...]
) -> dict[str, Any]:
    diagnostic_policy = deepcopy(strict_json_load(V3_RUN_POLICY))
    diagnostic_policy["execution"]["requestedRepetitions"] = 2
    diagnostic_policy["categoryFloors"]["majorityCorrectAttempts"] = 2
    diagnostic_policy["categoryFloors"]["majorityRepetitions"] = 2
    strata_reports: dict[str, Any] = {}
    for stratum_id, cases in scored_strata():
        ids = {case["id"] for case in cases}
        selected_attempts = [
            item
            for item in attempts
            if item.get("kind") == "scored" and item.get("caseID") in ids
        ]
        report = aggregate_v3(selected_attempts, cases, specs, diagnostic_policy)
        report["stageBDiagnosticOnly"] = True
        report["eligibleModels"] = []
        report["automaticWinner"] = None
        for model in report["models"].values():
            model["decisionEligible"] = False
            model["ineligibilityReasons"] = sorted(
                set(model["ineligibilityReasons"] + ["requiresCombinedStageAAndBReview"])
            )
        strata_reports[stratum_id] = report
    return {
        "reportContractVersion": "paceprompt-host-eval-report/issue145-v5-stage-b",
        "stage": "B",
        "repetitionIndices": [2, 3],
        "strata": strata_reports,
        "automaticWinner": None,
        "providerDecision": "requiresSeparateHumanEvidenceAcceptance",
        "combinedStageAAndBComparison": "notPerformed",
    }


class StageBLiveRun(V3LiveRun):
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
        report = _stage_b_aggregate(self.attempts, tuple(self.specs.values()))
        write_json(self.run_dir / "aggregate-report.json", report)
        audit = self._evidence_integrity()
        audit["auditContractVersion"] = (
            "paceprompt-host-eval-evidence-integrity/issue145-v5-stage-b"
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
        raise RuntimeError("exact Stage B authorization or spending limit is missing")
    material = deepcopy(gate)
    material["authorizationPhrase"] = None
    if authorization != AUTHORIZATION_PREFIX + canonical_hash(material)[:16].upper():
        raise RuntimeError("Stage B gate changed after authorization was sealed")
    if (run_dir / "live-state.json").exists():
        raise RuntimeError("this non-resumable Stage B run already entered live execution")
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
            "providerCallLimit": 657,
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
    runner = StageBLiveRun(
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
