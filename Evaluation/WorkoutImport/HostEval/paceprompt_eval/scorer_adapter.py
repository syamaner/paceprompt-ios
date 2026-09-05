"""Ephemeral v2-to-v1 projection for the unchanged deterministic scorer."""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal
import importlib
import json
from pathlib import Path
import shutil
import sys
from typing import Any, Callable

from jsonschema import Draft202012Validator


WORKOUT_IMPORT_ROOT = Path(__file__).resolve().parents[2]
SCORING_DIR = WORKOUT_IMPORT_ROOT / "Scoring"
if str(SCORING_DIR) not in sys.path:
    sys.path.insert(0, str(SCORING_DIR))
v1_scorer = importlib.import_module("scorer")

PROVIDER_UNAVAILABLE_REASONS = {
    "runtimeUnavailable",
    "networkUnavailable",
    "modelUnavailable",
    "routeUnavailable",
}
PROVIDER_FAILURE_REASONS = {
    "invocationFailure",
    "requestEncodingFailure",
    "networkFailure",
    "authenticationFailure",
    "rateLimited",
    "httpFailure",
    "responseDecodingFailure",
    "incompleteResponse",
    "timeout",
    "cancelled",
    "routingMismatch",
    "frameworkFailure",
}
NOT_STARTED_REASONS = {
    "authorizationMissing",
    "credentialMissing",
    "prerequisiteMismatch",
    "spendingLimitReached",
    "operatorCancelled",
    "rateLimitPause",
}


def _json_number(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, list):
        return [_json_number(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_number(item) for key, item in value.items()}
    return value


def _decimalize(value: Any) -> Any:
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, list):
        return [_decimalize(item) for item in value]
    if isinstance(value, dict):
        return {key: _decimalize(item) for key, item in value.items()}
    return value


def v1_proposal(v2_proposal: dict[str, Any]) -> dict[str, Any]:
    proposal = deepcopy(v2_proposal)
    proposal["contractVersion"] = "workout-proposal/v1"
    return proposal


def v1_expectation(case: dict[str, Any]) -> dict[str, Any]:
    expected = case["expected"]
    outcome = expected["modelOutput"]["outcome"]
    base = {"outcome": outcome["type"], "unsupportedCapabilityHandling": expected["unsupportedCapabilityHandling"]}
    if outcome["type"] != "proposal":
        return base | {
            "reasonCategory": outcome["reasonCategory"],
            "affectedPaths": outcome["affectedPaths"],
        }
    mapped = v1_scorer.map_proposal(v1_proposal(outcome["proposal"]))
    return base | {
        "canonicalProposal": {
            "activity": mapped["activity"],
            "steps": [
                {
                    "kind": step["kind"],
                    "durationSeconds": step["durationSeconds"],
                    "speedKilometresPerHour": step["speedKilometresPerHour"],
                    "inclinationPercent": step["inclinationPercent"],
                }
                for step in mapped["steps"]
            ],
        },
        "localValidatorOutcome": expected["localValidatorOutcome"],
        "localValidatorIssueCodes": expected["localValidatorIssueCodes"],
    }


def v1_case(case: dict[str, Any]) -> dict[str, Any]:
    return {
        "caseContractVersion": "workout-import-case/v1",
        "id": case["scorerAlias"],
        "category": case["category"],
        "locale": case["locale"],
        "prompt": case["prompt"],
        "generatorCondition": "normal",
        "capabilities": deepcopy(case["capabilities"]),
        "expected": v1_expectation(case),
    }


def v1_observed(model_output: dict[str, Any]) -> dict[str, Any]:
    outcome = deepcopy(model_output["outcome"])
    if outcome["type"] == "proposal":
        outcome["proposal"] = v1_proposal(outcome["proposal"])
    return {"structure": "valid", "outcome": outcome}


def invalid_observed(errors: list[dict[str, str]]) -> dict[str, Any]:
    return {"structure": "invalidGeneratorOutput", "errors": errors}


def provider_transport_output(model_output: dict[str, Any]) -> dict[str, Any]:
    """Add the exact non-null sentinels required by provider transport v2.2."""

    value = deepcopy(model_output)
    outcome = value["outcome"]
    if outcome["type"] == "proposal":
        outcome["proposal"] = {"present": True} | outcome["proposal"]
        outcome["reasonCategory"] = "notApplicable"
        outcome["affectedPaths"] = []
    else:
        outcome["proposal"] = {
            "present": False,
            "contractVersion": "notApplicable",
            "suggestedName": "",
            "activity": "notApplicable",
            "steps": [],
        }
    return value


def shallow_step_transport_output(model_output: dict[str, Any]) -> dict[str, Any]:
    """Project semantic v2 into the shallow-step provider transport v2.7."""

    value = provider_transport_output(model_output)
    proposal = value["outcome"]["proposal"]
    proposal["steps"] = [
        {
            "kind": step["kind"],
            "label": step["label"],
            "durationValue": step["duration"]["value"],
            "durationUnit": step["duration"]["unit"],
            "targetSpeedValue": step["targetSpeed"]["value"],
            "targetSpeedUnit": step["targetSpeed"]["unit"],
            "targetInclinationValue": step["targetInclination"]["value"],
            "targetInclinationUnit": step["targetInclination"]["unit"],
        }
        for step in proposal["steps"]
    ]
    return value


def flat_envelope_transport_output(model_output: dict[str, Any]) -> dict[str, Any]:
    """Project semantic v2 into the fully flattened provider envelope v2.8."""

    value = shallow_step_transport_output(model_output)
    outcome = value["outcome"]
    proposal = outcome["proposal"]
    return {
        "contractVersion": value["contractVersion"],
        "outcomeType": outcome["type"],
        "reasonCategory": outcome["reasonCategory"],
        "affectedPaths": outcome["affectedPaths"],
        "proposalPresent": proposal["present"],
        "proposalContractVersion": proposal["contractVersion"],
        "suggestedName": proposal["suggestedName"],
        "activity": proposal["activity"],
        "steps": proposal["steps"],
    }


def semantic_json_transport_output(model_output: dict[str, Any]) -> dict[str, Any]:
    """Encode the complete semantic result inside the minimal v2.9 envelope."""

    return {
        "semanticJson": json.dumps(
            model_output,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
    }


def normalize_provider_transport(value: dict[str, Any]) -> dict[str, Any]:
    """Remove only exact v2.2 sentinels; leave every mismatch visible."""

    normalized = deepcopy(value)
    outcome = normalized.get("outcome")
    if not isinstance(outcome, dict):
        return normalized
    if outcome.get("type") == "proposal":
        proposal = outcome.get("proposal")
        if isinstance(proposal, dict) and proposal.get("present") is True:
            proposal.pop("present")
        if outcome.get("reasonCategory") == "notApplicable":
            outcome.pop("reasonCategory", None)
        if outcome.get("affectedPaths") == []:
            outcome.pop("affectedPaths", None)
    elif outcome.get("proposal") == {
        "present": False,
        "contractVersion": "notApplicable",
        "suggestedName": "",
        "activity": "notApplicable",
        "steps": [],
    }:
        outcome.pop("proposal")
    return normalized


def normalize_shallow_step_transport(value: dict[str, Any]) -> dict[str, Any]:
    """Expand v2.7 step fields, then remove only the established sentinels."""

    normalized = deepcopy(value)
    outcome = normalized.get("outcome")
    proposal = outcome.get("proposal") if isinstance(outcome, dict) else None
    steps = proposal.get("steps") if isinstance(proposal, dict) else None
    if isinstance(steps, list):
        expanded_steps: list[Any] = []
        for step in steps:
            if not isinstance(step, dict):
                expanded_steps.append(step)
                continue
            expanded_steps.append(
                {
                    "kind": step.get("kind"),
                    "label": step.get("label"),
                    "duration": {
                        "value": step.get("durationValue"),
                        "unit": step.get("durationUnit"),
                    },
                    "targetSpeed": {
                        "value": step.get("targetSpeedValue"),
                        "unit": step.get("targetSpeedUnit"),
                    },
                    "targetInclination": {
                        "value": step.get("targetInclinationValue"),
                        "unit": step.get("targetInclinationUnit"),
                    },
                }
            )
        proposal["steps"] = expanded_steps
    return normalize_provider_transport(normalized)


def normalize_flat_envelope_transport(value: dict[str, Any]) -> dict[str, Any]:
    """Rebuild the nested transport envelope before unchanged normalization."""

    nested = {
        "contractVersion": value.get("contractVersion"),
        "outcome": {
            "type": value.get("outcomeType"),
            "reasonCategory": value.get("reasonCategory"),
            "affectedPaths": value.get("affectedPaths"),
            "proposal": {
                "present": value.get("proposalPresent"),
                "contractVersion": value.get("proposalContractVersion"),
                "suggestedName": value.get("suggestedName"),
                "activity": value.get("activity"),
                "steps": value.get("steps"),
            },
        },
    }
    return normalize_shallow_step_transport(nested)


def normalize_semantic_json_transport(value: dict[str, Any]) -> dict[str, Any]:
    """Decode the v2.9 envelope before unchanged semantic validation."""

    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, item in items:
            if key in result:
                raise ValueError(f"duplicate key {key!r} in semanticJson")
            result[key] = item
        return result

    semantic_json = value.get("semanticJson")
    if not isinstance(semantic_json, str):
        return value
    return json.loads(semantic_json, object_pairs_hook=pairs)


def parse_model_output(
    content: str,
    schema: dict[str, Any],
    transport_schema: dict[str, Any] | None = None,
    transport_normalizer: Callable[[dict[str, Any]], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate key {key!r}")
            result[key] = value
        return result

    try:
        value = json.loads(content, object_pairs_hook=pairs)
    except (json.JSONDecodeError, ValueError) as error:
        return invalid_observed([{"code": "invalidJSON", "path": f"$: {error}"}])
    if transport_schema is not None:
        transport_problems = sorted(
            Draft202012Validator(transport_schema).iter_errors(value),
            key=lambda item: list(item.absolute_path),
        )
        if transport_problems:
            return invalid_observed(
                [
                    {
                        "code": "transportSchemaViolation",
                        "path": "$" + "".join(
                            f"[{part}]" if isinstance(part, int) else f".{part}"
                            for part in problem.absolute_path
                        ),
                    }
                    for problem in transport_problems
                ]
            )
        try:
            value = (transport_normalizer or normalize_provider_transport)(value)
        except (json.JSONDecodeError, ValueError) as error:
            return invalid_observed(
                [{"code": "invalidJSON", "path": f"$.semanticJson: {error}"}]
            )
    problems = sorted(Draft202012Validator(schema).iter_errors(value), key=lambda item: list(item.absolute_path))
    if problems:
        return invalid_observed(
            [
                {
                    "code": "strictSchemaViolation",
                    "path": "$" + "".join(f"[{part}]" if isinstance(part, int) else f".{part}" for part in problem.absolute_path),
                }
                for problem in problems
            ]
        )
    return v1_observed(value)


def provider_outcome(outcome_type: str, reason: str) -> dict[str, Any]:
    allowed = {
        "providerUnavailable": PROVIDER_UNAVAILABLE_REASONS,
        "providerFailure": PROVIDER_FAILURE_REASONS,
        "refusal": {"providerRefusal"},
    }
    if outcome_type not in allowed or reason not in allowed[outcome_type]:
        raise ValueError(f"unsupported host outcome {outcome_type}/{reason}")
    return {
        "structure": "valid",
        "outcome": {"type": outcome_type, "reasonCategory": reason, "affectedPaths": []},
    }


def not_started(attempt_id: str, reason: str) -> dict[str, str]:
    if reason not in NOT_STARTED_REASONS:
        raise ValueError(f"unsupported notStarted reason {reason}")
    return {"attemptID": attempt_id, "status": "notStarted", "reasonCategory": reason}


def _manifest(
    projected_case: dict[str, Any],
    prompt_template_version: str = "workout-import-prompt/v2",
) -> dict[str, Any]:
    manifest = {
        "manifestVersion": 1,
        "corpusVersion": "workout-import-corpus/v1",
        "caseContractVersion": "workout-import-case/v1",
        "proposalContractVersion": "workout-proposal/v1",
        "resultContractVersion": "workout-import-result/v1",
        "scorerVersion": "workout-import-scorer/v1",
        "promptTemplateVersion": prompt_template_version,
        "supportedLocales": [projected_case["locale"]],
        "caseIndex": [{"id": projected_case["id"], "category": projected_case["category"]}],
        "hashContract": "workout-import-corpus-hash/v1",
        "corpusHash": "",
    }
    manifest["corpusHash"] = v1_scorer.compute_corpus_hash(manifest, [projected_case])
    return manifest


def write_projection(
    projection_root: Path,
    case: dict[str, Any],
    prompt_template_version: str = "workout-import-prompt/v2",
) -> Any:
    projected_case = _decimalize(v1_case(case))
    contracts = projection_root / "Contracts"
    corpus = projection_root / "Corpus" / "v1"
    contracts.mkdir(parents=True, exist_ok=False)
    corpus.mkdir(parents=True, exist_ok=False)
    for name in ("workout-proposal-v1.schema.json", "workout-import-result-v1.schema.json"):
        shutil.copy2(WORKOUT_IMPORT_ROOT / "Contracts" / name, contracts / name)
    manifest = _manifest(projected_case, prompt_template_version)
    (corpus / "cases.json").write_text(
        json.dumps(_json_number([projected_case]), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (corpus / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return v1_scorer.load_corpus(projection_root)


def normalized_document(
    *,
    case: dict[str, Any],
    observed: dict[str, Any],
    run_id: str,
    result_id: str,
    repetition_index: int,
    app_commit: str,
    model_id: str,
    model_revision: str | None,
    provider_id: str,
    started_at: str | None = None,
    ended_at: str | None = None,
    measurements: list[dict[str, Any]] | None = None,
    run_configuration_id: str = "paceprompt-host-eval-run-policy/v2",
    prompt_template_version: str = "workout-import-prompt/v2",
) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "resultContractVersion": "workout-import-result/v1",
        "provenance": {
            "runID": run_id,
            "appCommit": app_commit,
            "corpusVersion": "workout-import-corpus/v1",
            "corpusHash": "SET_FROM_PROJECTION",
            "proposalContractVersion": "workout-proposal/v1",
            "promptTemplateVersion": prompt_template_version,
            "scorerVersion": "workout-import-scorer/v1",
            "evidenceLevel": "remoteProvider",
            "deviceClass": "developmentHost",
            "osVersion": "host",
            "locale": case["locale"],
            "providerID": provider_id,
            "modelID": model_id,
            "modelRevision": {"status": "available", "value": model_revision} if model_revision else {"status": "unavailable", "reason": "catalogueRevisionUnavailable"},
            "routingConstraints": [
                {"key": "allowFallbacks", "value": "false"},
                {"key": "provider", "value": provider_id},
                {"key": "requireParameters", "value": "true"},
            ],
            "inferenceParameters": [{"key": "maxTokens", "value": "8192"}],
            "networkCondition": "online",
            "runConfigurationID": run_configuration_id,
            "startedAt": started_at or now,
            "endedAt": ended_at or now,
            "measurementTools": ["inspect-ai/0.3.263", "workout-import-scorer/v1"],
        },
        "results": [
            {
                "resultID": result_id,
                "caseID": case["scorerAlias"],
                "repetitionIndex": repetition_index,
                "observed": observed,
                "claimedAuthorities": [],
                "operationalMeasurements": measurements or [],
            }
        ],
    }


def score_completed(
    *,
    projection_root: Path,
    case: dict[str, Any],
    document: dict[str, Any],
) -> dict[str, Any]:
    corpus = write_projection(
        projection_root,
        case,
        document["provenance"]["promptTemplateVersion"],
    )
    document["provenance"]["corpusHash"] = corpus.manifest["corpusHash"]
    report, complete = v1_scorer.score_document(corpus, document)
    if not complete or report.get("status") != "complete":
        raise RuntimeError(f"unchanged scorer failed: {report.get('errors', [])}")
    return report
