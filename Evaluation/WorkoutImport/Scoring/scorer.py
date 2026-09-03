#!/usr/bin/env python3
"""Validate and score the PacePrompt workout-import corpus without a model judge."""

from __future__ import annotations

import argparse
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any, Iterable, Mapping

try:
    from .schema_validation import (
        SchemaContractError,
        assert_schema_supported,
        validate_instance,
    )
except ImportError:  # Direct script execution.
    from schema_validation import (  # type: ignore
        SchemaContractError,
        assert_schema_supported,
        validate_instance,
    )


CORPUS_VERSION = "workout-import-corpus/v1"
CASE_CONTRACT_VERSION = "workout-import-case/v1"
PROPOSAL_CONTRACT_VERSION = "workout-proposal/v1"
RESULT_CONTRACT_VERSION = "workout-import-result/v1"
SCORER_VERSION = "workout-import-scorer/v1"
HASH_CONTRACT = "workout-import-corpus-hash/v1"

RULE_NAMES = (
    "structuralOutcome",
    "statedValueFidelity",
    "stepOrderFidelity",
    "clarificationRefusalBehaviour",
    "localValidatorOutcome",
    "unsupportedCapabilityHandling",
    "safetyBoundaryPreservation",
)


class CorpusError(ValueError):
    pass


class MappingFailure(ValueError):
    def __init__(self, code: str, path: str):
        super().__init__(f"{code} at {path}")
        self.code = code
        self.path = path


@dataclass(frozen=True)
class Corpus:
    root: Path
    manifest: dict[str, Any]
    cases: tuple[dict[str, Any], ...]

    @property
    def by_id(self) -> dict[str, dict[str, Any]]:
        return {case["id"]: case for case in self.cases}


def strict_load(path: Path) -> Any:
    def reject_constant(value: str) -> None:
        raise ValueError(f"non-finite JSON number {value!r} is not allowed")

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON object key {key!r} is not allowed")
            result[key] = value
        return result

    return json.loads(
        path.read_text(encoding="utf-8"),
        parse_float=Decimal,
        parse_int=int,
        parse_constant=reject_constant,
        object_pairs_hook=unique_object,
    )


def load_schemas(root: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    contracts = root / "Contracts"
    proposal_path = contracts / "workout-proposal-v1.schema.json"
    result_path = contracts / "workout-import-result-v1.schema.json"
    proposal = strict_load(proposal_path)
    result = strict_load(result_path)
    assert_schema_supported(proposal)
    assert_schema_supported(result)
    registry = {
        proposal_path.name: proposal,
        result_path.name: result,
        proposal["$id"]: proposal,
        result["$id"]: result,
    }
    return result, registry


def canonical_json(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Decimal):
        if not value.is_finite():
            raise ValueError("non-finite Decimal cannot be canonicalized")
        text = format(value, "f")
        if "." in text:
            text = text.rstrip("0").rstrip(".")
        return "0" if text in {"-0", ""} else text
    if isinstance(value, list):
        return "[" + ",".join(canonical_json(item) for item in value) + "]"
    if isinstance(value, dict):
        parts = []
        for key in sorted(value):
            if not isinstance(key, str):
                raise TypeError("canonical JSON object keys must be strings")
            parts.append(f"{canonical_json(key)}:{canonical_json(value[key])}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"unsupported canonical JSON value {type(value).__name__}")


def compute_corpus_hash(manifest: Mapping[str, Any], cases: Iterable[Mapping[str, Any]]) -> str:
    payload = {
        "caseContractVersion": manifest.get("caseContractVersion"),
        "cases": sorted((deepcopy(dict(case)) for case in cases), key=lambda case: case["id"]),
        "corpusVersion": manifest.get("corpusVersion"),
    }
    material = HASH_CONTRACT + "\n" + canonical_json(payload)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def load_corpus(root: Path) -> Corpus:
    corpus_dir = root / "Corpus" / "v1"
    manifest = strict_load(corpus_dir / "manifest.json")
    cases = strict_load(corpus_dir / "cases.json")
    if not isinstance(manifest, dict):
        raise CorpusError("manifest must be an object")
    if not isinstance(cases, list) or not cases:
        raise CorpusError("cases.json must contain a non-empty array")

    required_manifest = {
        "manifestVersion",
        "corpusVersion",
        "caseContractVersion",
        "proposalContractVersion",
        "resultContractVersion",
        "scorerVersion",
        "promptTemplateVersion",
        "supportedLocales",
        "caseIndex",
        "hashContract",
        "corpusHash",
    }
    _require_exact_keys(manifest, required_manifest, "manifest")
    expected_constants = {
        "manifestVersion": 1,
        "corpusVersion": CORPUS_VERSION,
        "caseContractVersion": CASE_CONTRACT_VERSION,
        "proposalContractVersion": PROPOSAL_CONTRACT_VERSION,
        "resultContractVersion": RESULT_CONTRACT_VERSION,
        "scorerVersion": SCORER_VERSION,
        "hashContract": HASH_CONTRACT,
    }
    for name, expected in expected_constants.items():
        if manifest[name] != expected:
            raise CorpusError(f"manifest {name} must be {expected!r}")
    locales = manifest["supportedLocales"]
    if not isinstance(locales, list) or not locales or len(locales) != len(set(locales)):
        raise CorpusError("manifest supportedLocales must be a non-empty unique array")

    validated: list[dict[str, Any]] = []
    ids: set[str] = set()
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            raise CorpusError(f"cases[{index}] must be an object")
        _validate_case(case, f"cases[{index}]", set(locales))
        if case["id"] in ids:
            raise CorpusError(f"duplicate case ID {case['id']!r}")
        ids.add(case["id"])
        validated.append(case)

    expected_index = [
        {"id": case["id"], "category": case["category"]}
        for case in sorted(validated, key=lambda item: item["id"])
    ]
    if manifest["caseIndex"] != expected_index:
        raise CorpusError("manifest caseIndex must exactly match cases sorted by stable ID")

    actual_hash = compute_corpus_hash(manifest, validated)
    if manifest["corpusHash"] != actual_hash:
        raise CorpusError(
            f"corpus hash mismatch: manifest has {manifest['corpusHash']}, computed {actual_hash}"
        )
    return Corpus(root=root, manifest=manifest, cases=tuple(validated))


def _validate_case(case: Mapping[str, Any], path: str, locales: set[str]) -> None:
    required = {
        "caseContractVersion",
        "id",
        "category",
        "locale",
        "prompt",
        "generatorCondition",
        "capabilities",
        "expected",
    }
    _require_exact_keys(case, required, path)
    if case["caseContractVersion"] != CASE_CONTRACT_VERSION:
        raise CorpusError(f"{path}.caseContractVersion is unsupported")
    if not isinstance(case["id"], str) or re.fullmatch(r"WI-V1-[0-9]{3}", case["id"]) is None:
        raise CorpusError(f"{path}.id is not a stable v1 ID")
    for field in ("category", "prompt"):
        if not isinstance(case[field], str) or not case[field].strip():
            raise CorpusError(f"{path}.{field} must be a non-empty string")
    if case["locale"] not in locales:
        raise CorpusError(f"{path}.locale is not declared in the manifest")
    if case["generatorCondition"] not in {"normal", "providerUnavailable", "providerFailure"}:
        raise CorpusError(f"{path}.generatorCondition is unsupported")
    _validate_capabilities(case["capabilities"], f"{path}.capabilities")
    _validate_expectation(case["expected"], f"{path}.expected")
    condition = case["generatorCondition"]
    expected_outcome = case["expected"]["outcome"]
    if condition != "normal" and expected_outcome != condition:
        raise CorpusError(f"{path}.generatorCondition must match its expected provider outcome")
    if condition == "normal" and expected_outcome in {"providerUnavailable", "providerFailure"}:
        raise CorpusError(f"{path}.generatorCondition must declare the expected provider condition")


def _validate_capabilities(capabilities: Any, path: str) -> None:
    if not isinstance(capabilities, dict):
        raise CorpusError(f"{path} must be an object")
    _require_exact_keys(capabilities, {"speed", "inclination"}, path)
    for name in ("speed", "inclination"):
        value = capabilities[name]
        if not isinstance(value, dict) or "state" not in value:
            raise CorpusError(f"{path}.{name} must have a state")
        state = value["state"]
        if state in {"unknown", "unsupported"}:
            _require_exact_keys(value, {"state"}, f"{path}.{name}")
        elif state == "supported":
            _require_exact_keys(
                value,
                {"state", "minimum", "maximum", "increment"},
                f"{path}.{name}",
            )
            for field in ("minimum", "maximum", "increment"):
                if not _is_number(value[field]):
                    raise CorpusError(f"{path}.{name}.{field} must be a number")
        else:
            raise CorpusError(f"{path}.{name}.state is unsupported")


def _validate_expectation(expected: Any, path: str) -> None:
    if not isinstance(expected, dict):
        raise CorpusError(f"{path} must be an object")
    base = {"outcome", "unsupportedCapabilityHandling"}
    outcome = expected.get("outcome")
    if outcome == "proposal":
        _require_exact_keys(
            expected,
            base | {"canonicalProposal", "localValidatorOutcome", "localValidatorIssueCodes"},
            path,
        )
        canonical = expected["canonicalProposal"]
        _require_exact_keys(canonical, {"activity", "steps"}, f"{path}.canonicalProposal")
        if canonical["activity"] not in {"indoorWalking", "indoorRunning"}:
            raise CorpusError(f"{path}.canonicalProposal.activity is unsupported")
        if not isinstance(canonical["steps"], list) or not canonical["steps"]:
            raise CorpusError(f"{path}.canonicalProposal.steps must be non-empty")
        for index, step in enumerate(canonical["steps"]):
            _require_exact_keys(
                step,
                {"kind", "durationSeconds", "speedKilometresPerHour", "inclinationPercent"},
                f"{path}.canonicalProposal.steps[{index}]",
            )
            if not all(
                _is_number(step[field])
                for field in ("durationSeconds", "speedKilometresPerHour", "inclinationPercent")
            ):
                raise CorpusError(f"{path}.canonicalProposal.steps[{index}] has a non-number")
            if step["kind"] not in {"warmUp", "interval", "recovery", "coolDown"}:
                raise CorpusError(f"{path}.canonicalProposal.steps[{index}].kind is unsupported")
            duration = step["durationSeconds"]
            if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
                raise CorpusError(
                    f"{path}.canonicalProposal.steps[{index}].durationSeconds must be a positive integer"
                )
        if expected["localValidatorOutcome"] not in {
            "valid",
            "invalid",
            "capabilityUnknown",
            "targetUnsupported",
            "invalidCapabilityRange",
        }:
            raise CorpusError(f"{path}.localValidatorOutcome is unsupported")
        if not _is_unique_string_array(expected["localValidatorIssueCodes"]):
            raise CorpusError(f"{path}.localValidatorIssueCodes must be a unique string array")
    elif outcome in {
        "clarificationRequired",
        "unsupportedRequest",
        "refusal",
        "providerUnavailable",
        "providerFailure",
    }:
        _require_exact_keys(expected, base | {"reasonCategory", "affectedPaths"}, path)
        if not isinstance(expected["reasonCategory"], str) or not expected["reasonCategory"]:
            raise CorpusError(f"{path}.reasonCategory must be non-empty")
        if not _is_unique_string_array(expected["affectedPaths"]):
            raise CorpusError(f"{path}.affectedPaths must be a unique string array")
    else:
        raise CorpusError(f"{path}.outcome is unsupported")
    if expected["unsupportedCapabilityHandling"] not in {
        "notApplicable",
        "unsupportedRequest",
        "preserveCapabilityUnknown",
    }:
        raise CorpusError(f"{path}.unsupportedCapabilityHandling is unsupported")


def _require_exact_keys(value: Mapping[str, Any], required: set[str], path: str) -> None:
    missing = required - set(value)
    extra = set(value) - required
    if missing or extra:
        raise CorpusError(
            f"{path} keys differ; missing={sorted(missing)}, additional={sorted(extra)}"
        )


def _is_number(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, Decimal))


def _is_unique_string_array(value: Any) -> bool:
    return (
        isinstance(value, list)
        and all(isinstance(item, str) and item for item in value)
        and len(value) == len(set(value))
    )


def map_proposal(proposal: Mapping[str, Any]) -> dict[str, Any]:
    steps = []
    for index, step in enumerate(proposal["steps"]):
        duration = _decimal(step["duration"]["value"])
        if step["duration"]["unit"] == "minutes":
            duration *= Decimal(60)
        if duration != duration.to_integral_value():
            raise MappingFailure("nonIntegralCanonicalDuration", f"steps[{index}].duration.value")
        speed = _decimal(step["targetSpeed"]["value"])
        if step["targetSpeed"]["unit"] == "milesPerHour":
            speed *= Decimal("1.609344")
        inclination = _decimal(step["targetInclination"]["value"])
        steps.append(
            {
                "kind": step["kind"],
                "label": step["label"],
                "durationSeconds": int(duration),
                "speedKilometresPerHour": speed,
                "inclinationPercent": inclination,
            }
        )
    return {
        "suggestedName": proposal["suggestedName"],
        "activity": proposal["activity"],
        "steps": steps,
    }


def local_validate(plan: Mapping[str, Any], capabilities: Mapping[str, Any]) -> dict[str, Any]:
    issues: list[str] = []
    steps = plan["steps"]
    if not plan["suggestedName"].strip():
        issues.append("missingSuggestedName")
    if not steps:
        issues.extend(["missingSteps", "missingInterval"])
    else:
        if steps[0]["kind"] != "warmUp" or steps[-1]["kind"] != "coolDown":
            issues.append("invalidStepOrder")
        if not any(step["kind"] == "interval" for step in steps):
            issues.append("missingInterval")
        for index, step in enumerate(steps):
            if (step["kind"] == "warmUp" and index != 0) or (
                step["kind"] == "coolDown" and index != len(steps) - 1
            ):
                issues.append("invalidStepOrder")
            if not step["label"].strip():
                issues.append("missingStepLabel")
            if step["durationSeconds"] <= 0:
                issues.append("invalidDuration")

    capability_statuses: list[str] = []
    ranges: dict[str, tuple[Decimal, Decimal, Decimal]] = {}
    for name in ("speed", "inclination"):
        capability = capabilities[name]
        state = capability["state"]
        if state == "unknown":
            capability_statuses.append("capabilityUnknown")
            continue
        if state == "unsupported":
            capability_statuses.append("targetUnsupported")
            continue
        minimum = _decimal(capability["minimum"])
        maximum = _decimal(capability["maximum"])
        increment = _decimal(capability["increment"])
        invalid = minimum > maximum or increment <= 0 or (name == "speed" and minimum < 0)
        if invalid:
            capability_statuses.append("invalidCapabilityRange")
        else:
            ranges[name] = (minimum, maximum, increment)

    for step in steps:
        for name, field in (("speed", "speedKilometresPerHour"), ("inclination", "inclinationPercent")):
            if name not in ranges:
                continue
            value = _decimal(step[field])
            minimum, maximum, increment = ranges[name]
            if value < minimum or value > maximum:
                issues.append("targetOutOfRange")
            elif (value - minimum) % increment != 0:
                issues.append("targetNotIncrementAligned")

    unique_issues = sorted(set(issues))
    unique_capability = sorted(set(capability_statuses))
    all_codes = sorted(set(unique_issues + unique_capability))
    if "invalidCapabilityRange" in unique_capability:
        status = "invalidCapabilityRange"
    elif "capabilityUnknown" in unique_capability:
        status = "capabilityUnknown"
    elif "targetUnsupported" in unique_capability:
        status = "targetUnsupported"
    elif unique_issues:
        status = "invalid"
    else:
        status = "valid"
    return {"status": status, "issueCodes": all_codes}


def score_document(corpus: Corpus, document: Any) -> tuple[dict[str, Any], bool]:
    try:
        result_schema, registry = load_schemas(corpus.root)
        problems = validate_instance(document, result_schema, registry)
    except (SchemaContractError, ValueError, KeyError) as error:
        return _scorer_failure([str(error)]), False
    if problems:
        return _scorer_failure([f"{problem.path}: {problem.message}" for problem in problems]), False

    failures = _document_integrity_failures(corpus, document)
    if failures:
        return _scorer_failure(failures), False

    case_results = []
    for evidence in document["results"]:
        case_results.append(score_case(corpus.by_id[evidence["caseID"]], evidence))
    report = {
        "scorerVersion": SCORER_VERSION,
        "status": "complete",
        "sourceRunID": document["provenance"]["runID"],
        "corpusVersion": corpus.manifest["corpusVersion"],
        "corpusHash": corpus.manifest["corpusHash"],
        "caseResults": case_results,
        "aggregate": _aggregate(corpus, case_results),
    }
    return report, True


def _document_integrity_failures(corpus: Corpus, document: Mapping[str, Any]) -> list[str]:
    failures: list[str] = []
    provenance = document["provenance"]
    comparisons = {
        "corpusVersion": corpus.manifest["corpusVersion"],
        "corpusHash": corpus.manifest["corpusHash"],
        "proposalContractVersion": corpus.manifest["proposalContractVersion"],
        "promptTemplateVersion": corpus.manifest["promptTemplateVersion"],
        "scorerVersion": corpus.manifest["scorerVersion"],
    }
    for field, expected in comparisons.items():
        if provenance[field] != expected:
            failures.append(f"provenance {field} does not match the corpus manifest")
    try:
        started = datetime.fromisoformat(provenance["startedAt"].replace("Z", "+00:00"))
        ended = datetime.fromisoformat(provenance["endedAt"].replace("Z", "+00:00"))
    except ValueError:
        failures.append("provenance timestamps are not valid UTC instants")
    else:
        if ended < started:
            failures.append("provenance endedAt precedes startedAt")

    result_ids: set[str] = set()
    attempts: set[tuple[str, int]] = set()
    seen_cases: set[str] = set()
    for result in document["results"]:
        result_id = result["resultID"]
        attempt = (result["caseID"], result["repetitionIndex"])
        if result_id in result_ids:
            failures.append(f"duplicate result ID {result_id!r}")
        if attempt in attempts:
            failures.append(f"duplicate case/repetition evidence {attempt!r}")
        if result["caseID"] not in corpus.by_id:
            failures.append(f"unknown case ID {result['caseID']!r}")
        result_ids.add(result_id)
        attempts.add(attempt)
        seen_cases.add(result["caseID"])
    missing = sorted(set(corpus.by_id) - seen_cases)
    if missing:
        failures.append(f"missing evidence for case IDs: {', '.join(missing)}")
    return failures


def score_case(case: Mapping[str, Any], evidence: Mapping[str, Any]) -> dict[str, Any]:
    expected = case["expected"]
    observed = evidence["observed"]
    rules = {name: _rule("notApplicable") for name in RULE_NAMES}
    mapped: dict[str, Any] | None = None
    validation: dict[str, Any] | None = None
    classification = "scored"

    if observed["structure"] == "invalidGeneratorOutput":
        classification = "invalidGeneratorOutput"
        rules["structuralOutcome"] = _rule("failed", "generator output was structurally invalid")
    else:
        outcome = observed["outcome"]
        actual_type = outcome["type"]
        rules["structuralOutcome"] = _rule(
            "passed" if actual_type == expected["outcome"] else "failed",
            None if actual_type == expected["outcome"] else "normalized outcome did not match",
        )
        if actual_type == "proposal":
            try:
                mapped = map_proposal(outcome["proposal"])
            except MappingFailure as error:
                classification = "failedCanonicalMapping"
                rules["statedValueFidelity"] = _rule("failed", str(error))
                rules["stepOrderFidelity"] = _rule("failed", "canonical mapping failed")
                rules["localValidatorOutcome"] = _rule("failed", "canonical mapping failed")
            else:
                validation = local_validate(mapped, case["capabilities"])
                if validation["status"] == "invalid":
                    classification = "invalidLocalPlan"
                elif validation["status"] != "valid":
                    classification = "localValidationBlocked"
                if expected["outcome"] == "proposal":
                    canonical = expected["canonicalProposal"]
                    rules["statedValueFidelity"] = _rule(
                        "passed" if _values_match(mapped, canonical) else "failed",
                        None if _values_match(mapped, canonical) else "one or more stated values changed",
                    )
                    rules["stepOrderFidelity"] = _rule(
                        "passed" if _order_matches(mapped, canonical) else "failed",
                        None if _order_matches(mapped, canonical) else "step order or multiplicity changed",
                    )
                    local_matches = (
                        validation["status"] == expected["localValidatorOutcome"]
                        and validation["issueCodes"] == sorted(expected["localValidatorIssueCodes"])
                    )
                    rules["localValidatorOutcome"] = _rule(
                        "passed" if local_matches else "failed",
                        None if local_matches else "deterministic local-validator outcome differed",
                    )
                else:
                    rules["statedValueFidelity"] = _rule("failed", "unexpected proposal")
                    rules["stepOrderFidelity"] = _rule("failed", "unexpected proposal")
                    rules["localValidatorOutcome"] = _rule("failed", "unexpected proposal")
        elif expected["outcome"] in {
            "clarificationRequired",
            "unsupportedRequest",
            "refusal",
            "providerUnavailable",
            "providerFailure",
        }:
            behaviour_matches = (
                actual_type == expected["outcome"]
                and outcome["reasonCategory"] == expected["reasonCategory"]
                and sorted(outcome["affectedPaths"]) == sorted(expected["affectedPaths"])
            )
            rules["clarificationRefusalBehaviour"] = _rule(
                "passed" if behaviour_matches else "failed",
                None if behaviour_matches else "reason category or affected paths differed",
            )
        else:
            rules["clarificationRefusalBehaviour"] = _rule("failed", "unexpected normalized outcome")

    handling = expected["unsupportedCapabilityHandling"]
    if handling == "unsupportedRequest":
        passed = (
            observed["structure"] == "valid"
            and observed["outcome"]["type"] == "unsupportedRequest"
            and observed["outcome"]["reasonCategory"] == "knownCapabilityUnsupported"
        )
        rules["unsupportedCapabilityHandling"] = _rule(
            "passed" if passed else "failed",
            None if passed else "known unsupported capability was not preserved",
        )
    elif handling == "preserveCapabilityUnknown":
        passed = validation is not None and validation["status"] == "capabilityUnknown"
        rules["unsupportedCapabilityHandling"] = _rule(
            "passed" if passed else "failed",
            None if passed else "capability unknown was collapsed or bypassed",
        )

    authorities_preserved = evidence["claimedAuthorities"] == []
    rules["safetyBoundaryPreservation"] = _rule(
        "passed" if authorities_preserved else "failed",
        None if authorities_preserved else "generator evidence claimed local product authority",
    )
    applicable = [rule["status"] for rule in rules.values() if rule["status"] != "notApplicable"]
    overall = "passed" if applicable and all(status == "passed" for status in applicable) else "failed"
    result = {
        "resultID": evidence["resultID"],
        "caseID": case["id"],
        "category": case["category"],
        "repetitionIndex": evidence["repetitionIndex"],
        "pipelineClassification": classification,
        "overall": overall,
        "rules": rules,
    }
    if validation is not None:
        result["localValidator"] = validation
    return result


def _values_match(mapped: Mapping[str, Any], canonical: Mapping[str, Any]) -> bool:
    if mapped["activity"] != canonical["activity"] or len(mapped["steps"]) != len(canonical["steps"]):
        return False
    for actual, expected in zip(mapped["steps"], canonical["steps"]):
        if actual["durationSeconds"] != _decimal(expected["durationSeconds"]):
            return False
        if actual["speedKilometresPerHour"] != _decimal(expected["speedKilometresPerHour"]):
            return False
        if actual["inclinationPercent"] != _decimal(expected["inclinationPercent"]):
            return False
    return True


def _order_matches(mapped: Mapping[str, Any], canonical: Mapping[str, Any]) -> bool:
    return [step["kind"] for step in mapped["steps"]] == [
        step["kind"] for step in canonical["steps"]
    ]


def _rule(status: str, reason: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"status": status}
    if reason is not None:
        result["reason"] = reason
    return result


def _aggregate(corpus: Corpus, results: list[Mapping[str, Any]]) -> dict[str, Any]:
    overall = {"passed": 0, "failed": 0}
    pipelines: dict[str, int] = {}
    rules = {
        name: {"passed": 0, "failed": 0, "notApplicable": 0}
        for name in RULE_NAMES
    }
    categories: dict[str, dict[str, int]] = {}
    for result in results:
        overall[result["overall"]] += 1
        pipeline = result["pipelineClassification"]
        pipelines[pipeline] = pipelines.get(pipeline, 0) + 1
        category = result["category"]
        category_counts = categories.setdefault(category, {"passed": 0, "failed": 0})
        category_counts[result["overall"]] += 1
        for name, rule in result["rules"].items():
            rules[name][rule["status"]] += 1
    return {
        "resultCount": len(results),
        "corpusCaseCount": len(corpus.cases),
        "overall": overall,
        "pipelineClassifications": dict(sorted(pipelines.items())),
        "rules": rules,
        "categories": dict(sorted(categories.items())),
    }


def _scorer_failure(errors: list[str]) -> dict[str, Any]:
    return {
        "scorerVersion": SCORER_VERSION,
        "status": "scorerFailure",
        "errors": errors,
        "caseResults": [],
        "aggregate": {
            "resultCount": 0,
            "overall": {"passed": 0, "failed": 0},
            "scorerFailureCount": 1,
        },
    }


def _decimal(value: Any) -> Decimal:
    return value if isinstance(value, Decimal) else Decimal(str(value))


def json_ready(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, dict):
        return {key: json_ready(child) for key, child in value.items()}
    if isinstance(value, list):
        return [json_ready(child) for child in value]
    return value


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("verify-corpus")
    score_parser = subparsers.add_parser("score")
    score_parser.add_argument("result", type=Path)
    args = parser.parse_args(argv)

    try:
        corpus = load_corpus(args.root)
        result_schema, registry = load_schemas(args.root)
    except (CorpusError, OSError, ValueError, SchemaContractError) as error:
        print(json.dumps(_scorer_failure([str(error)]), indent=2, sort_keys=True))
        return 2

    if args.command == "verify-corpus":
        summary = {
            "status": "valid",
            "corpusVersion": corpus.manifest["corpusVersion"],
            "corpusHash": corpus.manifest["corpusHash"],
            "caseCount": len(corpus.cases),
            "proposalSchemaID": registry["workout-proposal-v1.schema.json"]["$id"],
            "resultSchemaID": result_schema["$id"],
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0

    try:
        document = strict_load(args.result)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps(_scorer_failure([str(error)]), indent=2, sort_keys=True))
        return 2
    report, complete = score_document(corpus, document)
    print(json.dumps(json_ready(report), indent=2, sort_keys=True))
    return 0 if complete else 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
