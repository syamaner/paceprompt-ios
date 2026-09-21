"""Zero-spend preparation for the three-model issue #145 Stage B profile."""

from __future__ import annotations

import asyncio
from collections import Counter
from copy import deepcopy
from pathlib import Path
import random
from typing import Any, Callable

from .catalogue import snapshot_catalogue
from .issue145 import (
    cost_preflight,
    mock_payloads,
    required_parameter_contracts,
    scored_strata,
)
from .issue145_stage_a import (
    MODELS as STAGE_A_MODELS,
    verify as verify_stage_a,
)
from .openrouter import load_model_specs
from .runner import write_json
from .transport_strategy import ISSUE145_V5_REGISTRY_ID, strategy_for
from .v3 import (
    HOST_EVAL_ROOT,
    REPOSITORY_ROOT,
    canonical_hash,
    host_source_tree_hash,
    safe_run_dir,
    sha256_file,
    strict_json_load,
)


MODELS = HOST_EVAL_ROOT / "models-v5-issue145-stage-b.json"
RUN_POLICY = HOST_EVAL_ROOT / "run-policy-v5-issue145-stage-b.json"
REVIEW = HOST_EVAL_ROOT / "issue145-stage-b-review-r1.json"
PROPOSAL = HOST_EVAL_ROOT / "issue145-stage-b-proposal-r1.json"
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
GATE_CONTRACT = "paceprompt-host-eval-operator-gate/issue145-v5-stage-b-preparation"
MODELS_SHA256 = "fe262cd3c2c9c9b640fae309becfe227bc42274f769e1ac33e92c647150bdf5a"
RUN_POLICY_SHA256 = "8ee31d253bac71869e2f38b821a201231a5405265ccfa00ab88ec9eb19a6240c"
REVIEW_SHA256 = "276f8deb740be6774af2c4c9134b1410d471ab7a5a8708623ca969d9625f0bbc"
PROPOSAL_SHA256 = "1646c57a6da4edeb444ffcae752862824b1fe83ec43dd2357b5cb29faf5bc302"
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
        "liveExecutionImplemented": False,
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
        "requiredBeforeLive": [
            "operator-ratifies-the-exact-committed-stage-b-proposal-hash",
            "operator-ratifies-the-exact-hard-spending-limit",
            "a-separately-reviewed-live-runner-binds-the-ratified-profile",
            "operator-separately-authorizes-the-exact-live-run-instance",
        ],
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def main_prepare(run_id: str) -> dict[str, Any]:
    return asyncio.run(prepare_gate(run_id))
