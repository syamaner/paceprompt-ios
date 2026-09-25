"""Zero-spend, source-bound gate for the ratified issue #145 eleven-model matrix.

Import, verification and preparation cannot read a credential or send inference.
The ignored operator gate is deliberately distinct from the sealed profile.
"""

from __future__ import annotations

import argparse
import asyncio
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any, Callable

from .catalogue import conservative_call_cost, snapshot_catalogue
from .issue145 import (
    BASETEN_DUPLICATE_ALLOWLIST, _body_for_case, mock_payloads,
    PRODUCTION_PROMPT, RUN_POLICY, required_parameter_contracts, scored_strata,
)
from .issue130 import EXAMPLES
from .issue145_full_matrix_r3 import materialized_models
from .issue145_lineage import admit_child
from .issue145_post_deepseek_11_r3 import (
    EXPECTED_QUEUE_SHA256, PROPOSAL_RUN_ID, PROPOSED_ROOT_RUN_ID,
    profile_material,
)
from .issue145_retry_execution import evidence_tree_sha256, verify_wire_ledger
from .issue145_source_repair import verify_source_chain
from .openrouter import ModelSpec
from .runner import write_json
from .v3 import (
    HOST_EVAL_ROOT, RUNS_ROOT, WORKOUT_IMPORT_ROOT, asset_paths, canonical_hash,
    host_source_tree_hash, load_cases, safe_run_dir, sha256_file,
    strict_json_load,
)


RATIFICATION = HOST_EVAL_ROOT / "issue145-11model-r3-ratification-r1.json"
PROFILE_SHA256 = "ac3bd1269e1b6f219f5624bdef3978a18bb17b6fec3eb7f80e9ed1bee9246bfe"
PROFILE_EVIDENCE_SHA256 = "1c1416717f9797ace355957ec4e7627133eb72c307f83ac534ee55be54a5e40e"
PROFILE_SOURCE_SHA256 = "168276a1bacde64d75c69815fd51491d5a87fa97e2eb819b040f2f3f97b63bfc"
HARD_LIMIT_USD = "300.00"
GATE_VERSION = "paceprompt-host-eval-operator-gate/issue145-11model-r3-r1"
CHILD_GATE_VERSION = "paceprompt-host-eval-operator-gate/issue145-11model-child-r1"
AUTH_PREFIX = "AUTHORIZE_PACEPROMPT_ISSUE145_11MODEL_MATRIX_"
EXCLUDED_MODEL = "mistralai/mistral-small-2603"


def checked_run_dir(run_id: str, *, create: bool) -> Path:
    """Reject an in-root symlink alias before safe_run_dir resolves it."""
    if (RUNS_ROOT / run_id).is_symlink():
        raise RuntimeError("run directory is a symlink alias")
    directory = safe_run_dir(run_id, create=create)
    if directory.name != run_id or directory.is_symlink():
        raise RuntimeError("run directory identity changed")
    return directory


def _expected_ratification() -> dict[str, Any]:
    return {
        "ratificationVersion": "paceprompt-host-eval-ratification/issue145-11model-r3-r1",
        "status": "profile-and-cap-ratified-live-run-not-authorized",
        "source": "operator exact ratification on 2026-09-25",
        "preparedRunID": PROPOSAL_RUN_ID,
        "profileSha256": PROFILE_SHA256,
        "profileEvidenceTreeSha256": PROFILE_EVIDENCE_SHA256,
        "preparationSourceTreeSha256": PROFILE_SOURCE_SHA256,
        "proposedRootRunID": PROPOSED_ROOT_RUN_ID,
        "queueSha256": EXPECTED_QUEUE_SHA256,
        "cumulativeHardLimitUSD": HARD_LIMIT_USD,
        "currency": "USD",
        "warmupLogicalPositions": 11,
        "scoredLogicalPositions": 3597,
        "maximumPhysicalSends": 10824,
        "liveAuthorization": None,
        "authority": {"credentialRead": False, "providerInference": False,
                      "spend": False, "liveRun": False},
    }


def ratified_profile() -> tuple[dict[str, Any], dict[str, Any]]:
    if strict_json_load(RATIFICATION) != _expected_ratification():
        raise RuntimeError("eleven-model ratification changed")
    run_dir = checked_run_dir(PROPOSAL_RUN_ID, create=False)
    if evidence_tree_sha256(run_dir) != PROFILE_EVIDENCE_SHA256:
        raise RuntimeError("ratified profile evidence tree changed")
    expected, queue = profile_material()
    expected["hostSourceTreeSha256"] = PROFILE_SOURCE_SHA256
    expected["profileSha256"] = canonical_hash(expected)
    actual = strict_json_load(run_dir / "profile.json")
    if (actual != expected or actual["profileSha256"] != PROFILE_SHA256
            or strict_json_load(run_dir / "planned-queue.json") != queue
            or queue["queueSha256"] != EXPECTED_QUEUE_SHA256
            or actual["recommendedCumulativeHardLimitUSD"] != HARD_LIMIT_USD
            or actual["liveAuthorized"] is not False):
        raise RuntimeError("ratified profile or deterministic queue changed")
    return actual, queue


def model_specs(profile: dict[str, Any]) -> tuple[ModelSpec, ...]:
    materialized = materialized_models()
    by_id = {item["requestedModelID"]: item for item in materialized["models"]}
    if set(by_id) != set(profile["candidateModelIDs"]) | {EXCLUDED_MODEL}:
        raise RuntimeError("materialized model set changed")
    specs = tuple(ModelSpec.from_json(by_id[item]) for item in profile["candidateModelIDs"])
    routes = [{key: by_id[item][key] for key in (
        "requestedModelID", "canonicalRevision", "providerEndpoint",
        "quantization", "responseContract", "maxOutputTokens",
    )} for item in profile["candidateModelIDs"]]
    if routes != profile["candidateRoutes"]:
        raise RuntimeError("ratified candidate route changed")
    return specs


def cases_by_id() -> dict[str, dict[str, Any]]:
    cases = [case for _, stratum in scored_strata() for case in stratum]
    warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                  if case["id"] == "WI-V3-D020")
    if len(cases) != 109 or len({case["id"] for case in cases}) != 109:
        raise RuntimeError("scored case identity changed")
    return {case["id"]: case for case in [warmup, *cases]}


def planned_calls(
    profile: dict[str, Any], queue: dict[str, Any],
    templates: dict[str, dict[str, Any]], selected: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, bytes]]:
    specs = model_specs(profile)
    by_model = {spec.requested_model_id: spec for spec in specs}
    prices = {item["requestedModelID"]: item for item in selected}
    cases = cases_by_id()
    warmups = [{"attemptID": f"warmup-{model.replace('/', '--')}",
                "modelID": model, "caseID": "WI-V3-D020", "kind": "warmup",
                "stratumID": None, "repetitionIndex": 0}
               for model in profile["candidateModelIDs"]]
    scored = [dict(entry, kind="scored") for entry in queue["entries"]]
    calls: list[dict[str, Any]] = []
    requests: dict[str, bytes] = {}
    for item in [*warmups, *scored]:
        model = item["modelID"]
        body = _body_for_case(templates[model], cases[item["caseID"]])
        controls = body.get("provider", {})
        if (body.get("model") != model or controls.get("allow_fallbacks") is not False
                or controls.get("data_collection") != "deny"
                or controls.get("require_parameters") is not True
                or controls.get("order") != [by_model[model].provider_endpoint]
                or controls.get("only") != [by_model[model].provider_endpoint]
                or body.get("max_tokens") != by_model[model].max_output_tokens):
            raise RuntimeError(f"outbound controls changed for {model}")
        encoded = json.dumps(body, ensure_ascii=False, sort_keys=True,
                             separators=(",", ":")).encode("utf-8")
        request_hash = hashlib.sha256(encoded).hexdigest()
        bound = conservative_call_cost(
            input_utf8_bytes=len(encoded),
            input_price=prices[model]["inputPricePerToken"],
            output_price=prices[model]["outputPricePerToken"],
            output_tokens=by_model[model].max_output_tokens,
        )
        if not bound.is_finite() or bound <= 0:
            raise RuntimeError("per-send bound must be finite and positive")
        logical_id = item["attemptID"]
        if logical_id in requests:
            raise RuntimeError("logical position duplicated")
        requests[logical_id] = encoded
        calls.append({**item, "requestSha256": request_hash,
                      "requestUTF8Bytes": len(encoded),
                      "oneSendWorstCaseUSD": format(bound, "f")})
    if len(calls) != 3608 or len(requests) != 3608:
        raise RuntimeError("ratified matrix denominator changed")
    return calls, requests


async def prepare_gate(
    run_id: str, *, fetch: Callable[[str], bytes] | None = None,
) -> dict[str, Any]:
    """Fetch public metadata and capture mock payloads; no key or model call."""
    if run_id != PROPOSED_ROOT_RUN_ID:
        raise RuntimeError("root run ID differs from ratification")
    profile, queue = await asyncio.to_thread(ratified_profile)
    specs = model_specs(profile)
    run_dir = checked_run_dir(run_id, create=True)
    if any(run_dir.iterdir()):
        raise RuntimeError("root gate directory must be fresh")
    models = materialized_models()
    models["models"] = [item for item in models["models"]
                        if item["requestedModelID"] != EXCLUDED_MODEL]
    models_path = run_dir / "models-11-materialized.json"
    write_json(models_path, models)
    snapshot = snapshot_catalogue(
        run_dir / "catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        **({"fetch": fetch} if fetch else {}),
    )
    if any(type(item.get("status")) is not int or item["status"] != 0
           for item in snapshot["selected"]):
        raise RuntimeError("a ratified endpoint is unavailable")
    _, templates = await mock_payloads(run_dir, snapshot, models_path=models_path)
    calls, _ = planned_calls(profile, queue, templates, snapshot["selected"])
    three_send = sum((Decimal(item["oneSendWorstCaseUSD"]) * 3
                      for item in calls), Decimal("0"))
    if three_send > Decimal(HARD_LIMIT_USD):
        raise RuntimeError("fresh public price exceeds the cumulative hard limit")
    write_json(run_dir / "planned-queue.json", queue)
    write_json(run_dir / "planned-calls.json", calls)
    gate = {
        "gateVersion": GATE_VERSION,
        "status": "awaitingZeroSpendSealing",
        "runID": run_id,
        "rootRunID": run_id,
        "parentRunID": None,
        "parentEvidenceSha256": None,
        "profileSha256": PROFILE_SHA256,
        "profileEvidenceTreeSha256": PROFILE_EVIDENCE_SHA256,
        "profilePreparationSourceTreeSha256": PROFILE_SOURCE_SHA256,
        "ratificationSha256": sha256_file(RATIFICATION),
        "hostSourceTreeSha256": host_source_tree_hash(),
        "queueSha256": EXPECTED_QUEUE_SHA256,
        "materializedModelsSha256": sha256_file(models_path),
        "plannedCallsSha256": sha256_file(run_dir / "planned-calls.json"),
        "selectedCatalogueSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "catalogueEvidenceTreeSha256": evidence_tree_sha256(run_dir / "catalogue"),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "maximumLogicalPositions": 3608,
        "maximumPhysicalSends": 10824,
        "threeSendConservativeUSD": format(three_send, "f"),
        "cumulativeHardLimitUSD": HARD_LIMIT_USD,
        "authorizationPhrase": None,
        "credentialRead": False,
        "providerCalls": 0,
        "spendUSD": "0.00",
    }
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _expected_gate(run_dir: Path, *, source_hash: str | None = None) -> dict[str, Any]:
    profile, queue = ratified_profile()
    if strict_json_load(run_dir / "planned-queue.json") != queue:
        raise RuntimeError("gate queue changed")
    selected = strict_json_load(run_dir / "catalogue" / "selected.json")
    models = strict_json_load(run_dir / "models-11-materialized.json")
    expected_models = materialized_models()
    expected_models["models"] = [item for item in expected_models["models"]
                                  if item["requestedModelID"] != EXCLUDED_MODEL]
    if models != expected_models:
        raise RuntimeError("gate materialized model document changed")
    if [item["requestedModelID"] for item in models["models"]] != profile["candidateModelIDs"]:
        raise RuntimeError("gate model set changed")
    templates = {item["requestedModelID"]: strict_json_load(
        run_dir / "mock-payloads" / f"{item['requestedModelID'].replace('/', '--')}.json"
    )["body"] for item in models["models"]}
    mock_summary = strict_json_load(run_dir / "mock-summary.json")
    if mock_summary.get("providerCalls") != 0 or mock_summary.get("credentialRead") is not False:
        raise RuntimeError("mock evidence claims live activity")
    for model_id in profile["candidateModelIDs"]:
        path = run_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        if mock_summary["payloadHashes"].get(model_id) != sha256_file(path):
            raise RuntimeError("mock payload bytes changed")
    calls, _ = planned_calls(profile, queue, templates, selected["selected"])
    if strict_json_load(run_dir / "planned-calls.json") != calls:
        raise RuntimeError("gate request mapping or cost changed")
    three_send = sum((Decimal(item["oneSendWorstCaseUSD"]) * 3
                      for item in calls), Decimal("0"))
    if three_send > Decimal(HARD_LIMIT_USD):
        raise RuntimeError("gate exceeds cumulative hard limit")
    return {
        "gateVersion": GATE_VERSION, "status": "awaitingZeroSpendSealing",
        "runID": PROPOSED_ROOT_RUN_ID, "rootRunID": PROPOSED_ROOT_RUN_ID,
        "parentRunID": None, "parentEvidenceSha256": None,
        "profileSha256": PROFILE_SHA256,
        "profileEvidenceTreeSha256": PROFILE_EVIDENCE_SHA256,
        "profilePreparationSourceTreeSha256": PROFILE_SOURCE_SHA256,
        "ratificationSha256": sha256_file(RATIFICATION),
        "hostSourceTreeSha256": source_hash or host_source_tree_hash(),
        "queueSha256": EXPECTED_QUEUE_SHA256,
        "materializedModelsSha256": sha256_file(run_dir / "models-11-materialized.json"),
        "plannedCallsSha256": sha256_file(run_dir / "planned-calls.json"),
        "selectedCatalogueSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "catalogueEvidenceTreeSha256": evidence_tree_sha256(run_dir / "catalogue"),
        "mockSummarySha256": sha256_file(run_dir / "mock-summary.json"),
        "maximumLogicalPositions": 3608,
        "maximumPhysicalSends": 10824,
        "threeSendConservativeUSD": format(three_send, "f"),
        "cumulativeHardLimitUSD": HARD_LIMIT_USD,
        "authorizationPhrase": None, "credentialRead": False,
        "providerCalls": 0, "spendUSD": "0.00",
    }


def seal_gate(run_id: str) -> dict[str, Any]:
    if run_id != PROPOSED_ROOT_RUN_ID:
        raise RuntimeError("root run ID differs from ratification")
    run_dir = checked_run_dir(run_id, create=False)
    _verify_frozen_eval_inputs()
    actual = strict_json_load(run_dir / "operator-gate.json")
    expected = _expected_gate(run_dir)
    if actual != expected:
        raise RuntimeError("prepared gate changed")
    sealed = dict(expected, status="awaitingFinalLiveRunAuthorization")
    sealed["authorizationPhrase"] = AUTH_PREFIX + canonical_hash(expected)[:16].upper()
    write_json(run_dir / "operator-gate.json", sealed)
    return sealed


def verify_sealed_gate(
    run_id: str, *, repair_seals: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    if run_id != PROPOSED_ROOT_RUN_ID:
        raise RuntimeError("root run ID differs from ratification")
    _verify_frozen_eval_inputs()
    run_dir = checked_run_dir(run_id, create=False)
    actual = strict_json_load(run_dir / "operator-gate.json")
    source_hash = actual.get("hostSourceTreeSha256")
    verify_source_chain(source_hash, host_source_tree_hash(), repair_seals or [])
    expected = _expected_gate(run_dir, source_hash=source_hash)
    sealed = dict(expected, status="awaitingFinalLiveRunAuthorization")
    sealed["authorizationPhrase"] = AUTH_PREFIX + canonical_hash(expected)[:16].upper()
    if actual != sealed:
        raise RuntimeError("sealed gate changed")
    return {"status": "valid", "runID": run_id,
            "gateSha256": sha256_file(run_dir / "operator-gate.json"),
            "authorizationPhrase": sealed["authorizationPhrase"],
            "profileSha256": PROFILE_SHA256, "hardLimitUSD": HARD_LIMIT_USD,
            "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
            "liveAuthorized": False}


def _verify_frozen_eval_inputs() -> None:
    """Recheck ratified corpus, prompt, schemas and scorer outside HostEval too."""
    policy = strict_json_load(RUN_POLICY)
    frozen = policy["artifacts"]
    paths = asset_paths()
    bound = {
        "productionPromptSha256": PRODUCTION_PROMPT,
        "productionExamplesSha256": EXAMPLES,
        "heldoutCasesSha256": paths["heldoutCases"],
        "heldoutManifestSha256": paths["heldoutManifest"],
        "acceptanceCasesSha256": WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "cases.json",
        "acceptanceManifestSha256": WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "manifest.json",
        "acceptanceSemanticReviewSha256": WORKOUT_IMPORT_ROOT / "Corpus" / "v3" / "semantic-review.json",
        "modelOutputSchemaSha256": paths["modelSchema"],
        "nestedTransportSchemaSha256": paths["nestedV23Schema"],
        "semanticJsonTransportSchemaSha256": paths["semanticJsonV29Schema"],
        "scorerSha256": WORKOUT_IMPORT_ROOT / "Scoring" / "scorer.py",
        "schemaValidationSha256": WORKOUT_IMPORT_ROOT / "Scoring" / "schema_validation.py",
    }
    for field, path in bound.items():
        if sha256_file(path) != frozen[field]:
            raise RuntimeError(f"frozen evaluation input changed: {field}")
    contracts = {
        "workout-proposal-v1.schema.json": "d83e628cedc99f1201efb05f22f52fb9c32f7fc888674fad54e0e62e70cc90cc",
        "workout-import-result-v1.schema.json": "af57217d2fb175c74c37b0c70487966f6850e0e55dc7a123a600217a4d527cb9",
    }
    for name, expected in contracts.items():
        if sha256_file(WORKOUT_IMPORT_ROOT / "Contracts" / name) != expected:
            raise RuntimeError(f"frozen scorer contract changed: {name}")


def _verified_ancestors(
    seals: list[dict[str, str]], *, repair_seals: list[dict[str, str]],
) -> tuple[list[dict[str, Any]], list[str]]:
    """Accept only externally supplied, exact immutable ancestor tree hashes."""
    if not seals or seals[0].get("runID") != PROPOSED_ROOT_RUN_ID:
        raise RuntimeError("restart ancestry must begin at the ratified root")
    profile, queue = ratified_profile()
    all_ids = [f"warmup-{model.replace('/', '--')}" for model in profile["candidateModelIDs"]]
    all_ids.extend(item["attemptID"] for item in queue["entries"])
    parents: list[dict[str, Any]] = []
    seen_runs: set[str] = set()
    root_phrase: str | None = None
    for index, seal in enumerate(seals):
        if set(seal) != {"runID", "gateSha256", "evidenceTreeSha256"}:
            raise RuntimeError("ancestor seal requires exact run, gate and tree hashes")
        run_id = seal["runID"]
        if run_id in seen_runs:
            raise RuntimeError("ancestor run ID repeats")
        seen_runs.add(run_id)
        directory = checked_run_dir(run_id, create=False)
        gate_path = directory / "operator-gate.json"
        if (gate_path.is_symlink() or sha256_file(gate_path) != seal["gateSha256"]
                or evidence_tree_sha256(directory) != seal["evidenceTreeSha256"]):
            raise RuntimeError("ancestor gate or evidence differs from external seal")
        gate = strict_json_load(gate_path)
        if index == 0:
            verified = verify_sealed_gate(run_id, repair_seals=repair_seals)
            if verified["gateSha256"] != seal["gateSha256"]:
                raise RuntimeError("root gate differs from external seal")
            instance_cap = HARD_LIMIT_USD
            root_phrase = verified["authorizationPhrase"]
        else:
            if (gate.get("gateVersion") != CHILD_GATE_VERSION
                    or gate.get("status") != "awaitingFinalLiveRunAuthorization"
                    or gate.get("ancestorSeals") != seals[:index]
                    or gate.get("rootRunID") != PROPOSED_ROOT_RUN_ID
                    or gate.get("profileSha256") != PROFILE_SHA256
                    or gate.get("cumulativeHardLimitUSD") != HARD_LIMIT_USD
                    or not isinstance(gate.get("hostSourceTreeSha256"), str)):
                raise RuntimeError("child ancestor gate changed")
            verify_source_chain(
                gate["hostSourceTreeSha256"], host_source_tree_hash(), repair_seals,
            )
            expected = _child_material(
                run_id, seals[:index], directory,
                gate_repair_seals=gate["sourceRepairSeals"],
                verification_repair_seals=repair_seals,
                source_hash=gate["hostSourceTreeSha256"],
                verified_parents=(parents, all_ids),
            )
            if gate != dict(
                expected, status="awaitingFinalLiveRunAuthorization",
                authorizationPhrase=root_phrase,
            ):
                raise RuntimeError("child ancestor admission differs from its seal")
            instance_cap = gate["instanceHardLimitUSD"]
        calls = strict_json_load(directory / "planned-calls.json")
        ids = tuple(item["attemptID"] for item in calls)
        if index == 0 and list(ids) != all_ids:
            raise RuntimeError("root planned call order changed")
        checked = verify_wire_ledger(
            directory, evidence_root=RUNS_ROOT,
            profile_sha256=PROFILE_SHA256, planned_position_ids=ids,
            hard_limit_usd=instance_cap,
            sealed_evidence_tree_sha256=seal["evidenceTreeSha256"],
        )
        if checked["status"] != "valid":
            raise RuntimeError(f"ancestor wire ledger invalid: {checked['errors']}")
        parents.append({
            "runID": run_id, "rootRunID": PROPOSED_ROOT_RUN_ID,
            "profileSha256": PROFILE_SHA256,
            "lineageHardLimitUSD": HARD_LIMIT_USD,
            "parentRunID": None if index == 0 else seals[index - 1]["runID"],
            "parentEvidenceSha256": None if index == 0 else seals[index - 1]["evidenceTreeSha256"],
            "verifiedEvidenceTreeSha256": seal["evidenceTreeSha256"],
            "attempts": checked["attempts"],
        })
    return parents, all_ids


def _child_material(
    run_id: str, seals: list[dict[str, str]], directory: Path, *,
    gate_repair_seals: list[dict[str, str]],
    verification_repair_seals: list[dict[str, str]],
    source_hash: str | None = None,
    verified_parents: tuple[list[dict[str, Any]], list[str]] | None = None,
) -> dict[str, Any]:
    parents, all_ids = verified_parents or _verified_ancestors(
        seals, repair_seals=verification_repair_seals,
    )
    terminal = {item["attemptID"] for parent in parents for item in parent["attempts"]
                if item["state"] != "notStarted"}
    remaining = [item for item in all_ids if item not in terminal]
    if not remaining:
        raise RuntimeError("no never-started logical positions remain")
    profile, queue = ratified_profile()
    selected = strict_json_load(directory / "catalogue" / "selected.json")
    root_dir = checked_run_dir(PROPOSED_ROOT_RUN_ID, create=False)
    if (sha256_file(directory / "models-11-materialized.json")
            != sha256_file(root_dir / "models-11-materialized.json")
            or sha256_file(directory / "mock-summary.json")
            != sha256_file(root_dir / "mock-summary.json")):
        raise RuntimeError("child model or mock summary differs from root")
    for model in profile["candidateModelIDs"]:
        name = f"{model.replace('/', '--')}.json"
        if (sha256_file(directory / "mock-payloads" / name)
                != sha256_file(root_dir / "mock-payloads" / name)):
            raise RuntimeError("child mock payload differs from root")
    root_calls = {item["attemptID"]: item for item in
                  strict_json_load(root_dir / "planned-calls.json")}
    templates = {model: strict_json_load(
        root_dir / "mock-payloads" / f"{model.replace('/', '--')}.json"
    )["body"] for model in profile["candidateModelIDs"]}
    derived, _ = planned_calls(profile, queue, templates, selected["selected"])
    calls = [item for item in derived if item["attemptID"] in remaining]
    if [item["attemptID"] for item in calls] != remaining:
        raise RuntimeError("child plan is not the remaining frozen order")
    for call in calls:
        root = root_calls[call["attemptID"]]
        if (call["requestSha256"] != root["requestSha256"]
                or Decimal(call["oneSendWorstCaseUSD"])
                   > Decimal(root["oneSendWorstCaseUSD"])):
            raise RuntimeError("child request changed or price increased")
    reservations = {item["attemptID"]: format(
        Decimal(item["oneSendWorstCaseUSD"]) * 3, "f",
    ) for item in calls}
    admission = admit_child(
        root_run_id=PROPOSED_ROOT_RUN_ID, profile_sha256=PROFILE_SHA256,
        queue_ids=all_ids, hard_limit_usd=HARD_LIMIT_USD,
        parents=parents, child_run_id=run_id,
        child_queue_ids=remaining, child_worst_case_usd=reservations,
    )
    total = sum((Decimal(value) for value in reservations.values()), Decimal("0"))
    if total > Decimal(admission["remainingUSD"]):
        raise RuntimeError("child worst-case plan exceeds remaining lineage budget")
    if strict_json_load(directory / "planned-calls.json") != calls:
        raise RuntimeError("child planned calls changed")
    return {
        "gateVersion": CHILD_GATE_VERSION,
        "status": "awaitingZeroSpendSealing",
        "runID": run_id,
        "rootRunID": PROPOSED_ROOT_RUN_ID,
        "parentRunID": seals[-1]["runID"],
        "parentEvidenceSha256": seals[-1]["evidenceTreeSha256"],
        "ancestorSeals": seals,
        "profileSha256": PROFILE_SHA256,
        "queueSha256": EXPECTED_QUEUE_SHA256,
        "hostSourceTreeSha256": source_hash or host_source_tree_hash(),
        "sourceRepairSeals": gate_repair_seals,
        "ratificationSha256": sha256_file(RATIFICATION),
        "materializedModelsSha256": sha256_file(directory / "models-11-materialized.json"),
        "mockSummarySha256": sha256_file(directory / "mock-summary.json"),
        "selectedCatalogueSha256": sha256_file(directory / "catalogue" / "selected.json"),
        "catalogueEvidenceTreeSha256": evidence_tree_sha256(directory / "catalogue"),
        "plannedCallsSha256": sha256_file(directory / "planned-calls.json"),
        "cumulativeHardLimitUSD": HARD_LIMIT_USD,
        "priorChargedUSD": admission["priorChargedUSD"],
        "instanceHardLimitUSD": admission["remainingUSD"],
        "threeSendConservativeUSD": format(total, "f"),
        "maximumLogicalPositions": len(calls),
        "maximumPhysicalSends": len(calls) * 3,
        "authorizationPhrase": None,
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
    }


def prepare_child_gate(
    run_id: str, *, ancestor_seals: list[dict[str, str]],
    source_repair_seals: list[dict[str, str]] | None = None,
    fetch: Callable[[str], bytes] | None = None,
) -> dict[str, Any]:
    """Manually initiate a child, with caller-supplied immutable ancestry."""
    if run_id == PROPOSED_ROOT_RUN_ID:
        raise RuntimeError("child needs a fresh run ID")
    repairs = source_repair_seals or []
    parents, all_ids = _verified_ancestors(ancestor_seals, repair_seals=repairs)
    terminal = {item["attemptID"] for parent in parents for item in parent["attempts"]
                if item["state"] != "notStarted"}
    remaining = [item for item in all_ids if item not in terminal]
    if not remaining:
        raise RuntimeError("no never-started logical positions remain")
    directory = checked_run_dir(run_id, create=True)
    if any(directory.iterdir()):
        raise RuntimeError("child directory must be fresh")
    profile, queue = ratified_profile()
    root_dir = checked_run_dir(PROPOSED_ROOT_RUN_ID, create=False)
    specs = model_specs(profile)
    selected = snapshot_catalogue(
        directory / "catalogue", specs,
        required_parameters=required_parameter_contracts(specs),
        allow_equivalent_duplicate_tags=BASETEN_DUPLICATE_ALLOWLIST,
        **({"fetch": fetch} if fetch else {}),
    )
    if any(type(item.get("status")) is not int or item["status"] != 0
           for item in selected["selected"]):
        raise RuntimeError("child public route is unavailable")
    shutil.copy2(root_dir / "models-11-materialized.json",
                 directory / "models-11-materialized.json")
    shutil.copytree(root_dir / "mock-payloads", directory / "mock-payloads")
    shutil.copy2(root_dir / "mock-summary.json", directory / "mock-summary.json")
    templates = {model: strict_json_load(
        directory / "mock-payloads" / f"{model.replace('/', '--')}.json"
    )["body"] for model in profile["candidateModelIDs"]}
    derived, _ = planned_calls(profile, queue, templates, selected["selected"])
    calls = [item for item in derived if item["attemptID"] in remaining]
    write_json(directory / "planned-calls.json", calls)
    gate = _child_material(
        run_id, ancestor_seals, directory,
        gate_repair_seals=repairs, verification_repair_seals=repairs,
    )
    write_json(directory / "operator-gate.json", gate)
    return gate


def seal_child_gate(run_id: str) -> dict[str, Any]:
    directory = checked_run_dir(run_id, create=False)
    actual = strict_json_load(directory / "operator-gate.json")
    repairs = actual["sourceRepairSeals"]
    expected = _child_material(
        run_id, actual["ancestorSeals"], directory,
        gate_repair_seals=repairs, verification_repair_seals=repairs,
    )
    if actual != expected:
        raise RuntimeError("prepared child gate changed")
    root_phrase = verify_sealed_gate(
        PROPOSED_ROOT_RUN_ID, repair_seals=repairs,
    )["authorizationPhrase"]
    sealed = dict(expected, status="awaitingFinalLiveRunAuthorization",
                  authorizationPhrase=root_phrase)
    write_json(directory / "operator-gate.json", sealed)
    return sealed


def verify_sealed_child_gate(
    run_id: str, *, repair_seals: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    directory = checked_run_dir(run_id, create=False)
    actual = strict_json_load(directory / "operator-gate.json")
    own_repairs = actual["sourceRepairSeals"]
    verification_repairs = repair_seals if repair_seals is not None else own_repairs
    source_hash = actual.get("hostSourceTreeSha256")
    verify_source_chain(source_hash, host_source_tree_hash(), verification_repairs)
    expected = _child_material(
        run_id, actual["ancestorSeals"], directory,
        gate_repair_seals=own_repairs,
        verification_repair_seals=verification_repairs,
        source_hash=source_hash,
    )
    sealed = dict(expected, status="awaitingFinalLiveRunAuthorization",
                  authorizationPhrase=verify_sealed_gate(
                      PROPOSED_ROOT_RUN_ID, repair_seals=verification_repairs,
                  )["authorizationPhrase"])
    if actual != sealed:
        raise RuntimeError("sealed child gate changed")
    return {"status": "valid", "runID": run_id,
            "gateSha256": sha256_file(directory / "operator-gate.json"),
            "authorizationPhrase": sealed["authorizationPhrase"],
            "profileSha256": PROFILE_SHA256,
            "hardLimitUSD": sealed["instanceHardLimitUSD"],
            "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
            "liveAuthorized": False}


def main() -> None:
    parser = argparse.ArgumentParser(description="Zero-spend issue #145 eleven-model gate")
    parser.add_argument("action", choices=(
        "verify-ratification", "prepare-root", "seal-root", "verify-root",
        "prepare-child", "seal-child", "verify-child",
    ))
    parser.add_argument("--run-id")
    parser.add_argument(
        "--ancestor-seal", action="append", default=[],
        help="Externally pinned RUN_ID:GATE_SHA256:EVIDENCE_TREE_SHA256 (root first)",
    )
    parser.add_argument(
        "--source-repair-seal", action="append", default=[],
        help="Reviewed repository-relative repair JSON path and SHA-256, joined by ':'",
    )
    args = parser.parse_args()
    repairs = []
    for item in args.source_repair_seal:
        parts = item.rsplit(":", 1)
        if len(parts) != 2:
            parser.error("source repair seal must have path and SHA-256")
        repairs.append({"path": parts[0], "sha256": parts[1]})
    if args.action == "verify-ratification":
        profile, queue = ratified_profile()
        result = {"status": "valid", "profileSha256": profile["profileSha256"],
                  "queueSha256": queue["queueSha256"], "hardLimitUSD": HARD_LIMIT_USD,
                  "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00"}
    else:
        if not args.run_id:
            parser.error("--run-id is required")
        if args.action == "prepare-root":
            result = asyncio.run(prepare_gate(args.run_id))
        elif args.action == "seal-root":
            result = seal_gate(args.run_id)
        elif args.action == "verify-root":
            result = verify_sealed_gate(args.run_id, repair_seals=repairs)
        elif args.action == "prepare-child":
            seals = []
            for item in args.ancestor_seal:
                parts = item.split(":")
                if len(parts) != 3:
                    parser.error("ancestor seal must have run, gate and tree hashes")
                seals.append(dict(zip(("runID", "gateSha256", "evidenceTreeSha256"), parts)))
            result = prepare_child_gate(
                args.run_id, ancestor_seals=seals, source_repair_seals=repairs,
            )
        elif args.action == "seal-child":
            result = seal_child_gate(args.run_id)
        else:
            result = verify_sealed_child_gate(
                args.run_id, repair_seals=repairs or None,
            )
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
