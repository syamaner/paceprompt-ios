#!/usr/bin/env python3
"""Verify the issue #130 reviewer-authored acceptance corpus without a provider."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from copy import deepcopy
from decimal import Decimal
import hashlib
from pathlib import Path
import re
import sys
import unicodedata
from typing import Any, Iterable, Mapping

if __package__ in {None, ""}:  # Direct script execution from the repository root.
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from Evaluation.WorkoutImport.Scoring.schema_validation import (
    assert_schema_supported,
    validate_instance,
)
from Evaluation.WorkoutImport.Scoring.scorer import (
    canonical_json,
    local_validate,
    map_proposal,
    strict_load,
)


HASH_CONTRACT = "workout-import-acceptance-corpus-hash/v2"
CORPUS_VERSION = "workout-import-acceptance-corpus/v2"
CORPUS_REVISION = "issue-130-reviewer-acceptance/r1"
CASE_CONTRACT_VERSION = "workout-import-acceptance-case/v2"
REQUIRED_MODEL_VISIBLE_PROMPT_SOURCES = {
    "Evaluation/WorkoutImport/HostEval/prompts/v2/system.md",
    "Evaluation/WorkoutImport/HostEval/prompts/v3/system.md",
    "PacePrompt/Import/ImportResources/examples.json",
    "PacePrompt/Import/ImportResources/system.md",
}

SEALED_V1_SHA256 = {
    "Corpus/v1/cases.json": "8fb898071c7135d5fe7d83ab9feb48b2bcb4dabb5ee21d5e28bb50dbb56873f5",
    "Corpus/v1/manifest.json": "7508a5d8b4f6b5dd8a13b42426bd1895f8389d8d0d34dfc3cc947ecedb6b1d2e",
    "Contracts/workout-import-result-v1.schema.json": "af57217d2fb175c74c37b0c70487966f6850e0e55dc7a123a600217a4d527cb9",
    "Contracts/workout-proposal-v1.schema.json": "d83e628cedc99f1201efb05f22f52fb9c32f7fc888674fad54e0e62e70cc90cc",
    "Scoring/scorer.py": "45fe2dd6dd063ad2292e79fcf2bd520881bbeb374ea90571c7937f3d7be0bba1",
    "Scoring/schema_validation.py": "8c64365a6c7b85d0b68fd351c89966e6a5d8a316f34dd76ff3c5d28fffbd571a",
}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compute_corpus_hash(manifest: Mapping[str, Any], cases: Iterable[Mapping[str, Any]]) -> str:
    payload = {
        "caseContractVersion": manifest.get("caseContractVersion"),
        "capabilityProfiles": manifest.get("capabilityProfiles"),
        "cases": sorted((deepcopy(dict(case)) for case in cases), key=lambda case: case["id"]),
        "corpusRevision": manifest.get("corpusRevision"),
        "corpusVersion": manifest.get("corpusVersion"),
        "semanticReviewSha256": manifest.get("semanticReviewSha256"),
    }
    material = HASH_CONTRACT + "\n" + canonical_json(payload)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def normalized_prompt(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(re.findall(r"[a-z0-9%°/.]+", normalized))


def _capabilities(manifest: Mapping[str, Any], profile: str) -> Mapping[str, Any]:
    profiles = manifest.get("capabilityProfiles", {})
    if profile not in profiles:
        raise ValueError(f"unknown capability profile {profile!r}")
    return profiles[profile]


def _mapping_fixture(case: Mapping[str, Any]) -> dict[str, Any]:
    canonical = case["expected"]["canonicalProposal"]
    return {
        "contractVersion": "workout-proposal/v1",
        "suggestedName": canonical["suggestedName"],
        "activity": canonical["activity"],
        "steps": [
            {
                "kind": step["kind"],
                "label": f"Step {index + 1}",
                "duration": {"value": step["durationSeconds"], "unit": "seconds"},
                "targetSpeed": {
                    "value": step["speedKilometresPerHour"],
                    "unit": "kilometresPerHour",
                },
                "targetInclination": {
                    "value": step["inclinationPercent"],
                    "unit": "percent",
                },
            }
            for index, step in enumerate(canonical["steps"])
        ],
    }


def _canonical_projection(mapped: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "suggestedName": mapped["suggestedName"],
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
    }


def _target_value(canonical: Mapping[str, Any], path: str) -> Any:
    match = re.fullmatch(
        r"steps\[([0-9]+)\]\.(speedKilometresPerHour|inclinationPercent)", path
    )
    if match is None:
        raise ValueError(f"unsupported normalisation target path {path!r}")
    index = int(match.group(1))
    return canonical["steps"][index][match.group(2)]


def _expected_signature(case: Mapping[str, Any]) -> str:
    expected = case["expected"]
    if expected["outcome"] == "proposal":
        semantic = {"outcome": "proposal", "canonicalProposal": expected["canonicalProposal"]}
    else:
        semantic = {
            "outcome": expected["outcome"],
            "reasonCategory": expected["reasonCategory"],
            "affectedPaths": expected["affectedPaths"],
            "scenarioFamily": case["scenarioFamily"],
        }
    return hashlib.sha256(canonical_json(semantic).encode("utf-8")).hexdigest()


def verify(root: Path) -> dict[str, Any]:
    errors: list[str] = []
    corpus_dir = root / "Corpus" / "v2"
    manifest = strict_load(corpus_dir / "manifest.json")
    cases = strict_load(corpus_dir / "cases.json")
    review = strict_load(corpus_dir / "semantic-review.json")

    for relative, expected in SEALED_V1_SHA256.items():
        actual = sha256_file(root / relative)
        if actual != expected:
            errors.append(f"sealed v1 asset changed: {relative} has {actual}")

    required_manifest_keys = {
        "manifestVersion", "corpusVersion", "corpusRevision", "caseContractVersion",
        "proposalContractVersion", "resultContractVersion", "scorerVersion", "authoring",
        "supportedLocales", "capabilityProfiles", "requiredCoverageTags", "caseCount",
        "categoryCounts", "localeCounts", "caseIndex", "casesSha256",
        "semanticReviewSha256", "hashContract", "corpusHash",
    }
    if set(manifest) != required_manifest_keys:
        errors.append("manifest keys differ from the v2 acceptance contract")
    expected_versions = {
        "manifestVersion": 2,
        "corpusVersion": CORPUS_VERSION,
        "corpusRevision": CORPUS_REVISION,
        "caseContractVersion": CASE_CONTRACT_VERSION,
        "proposalContractVersion": "workout-proposal/v1",
        "resultContractVersion": "workout-import-result/v1",
        "scorerVersion": "workout-import-scorer/v1",
        "hashContract": HASH_CONTRACT,
    }
    for key, expected in expected_versions.items():
        if manifest.get(key) != expected:
            errors.append(f"manifest {key} must be {expected!r}")
    if manifest.get("authoring") != {
        "source": "reviewer-authored",
        "purpose": "held-out-acceptance",
        "promptExampleReuse": "prohibited",
        "ratificationStatus": "awaiting-operator-ratification-before-provider-run",
    }:
        errors.append("manifest authoring boundary changed")

    case_schema = strict_load(root / "Contracts" / "workout-import-acceptance-case-v2.schema.json")
    proposal_schema = strict_load(root / "Contracts" / "workout-proposal-v1.schema.json")
    assert_schema_supported(case_schema)
    assert_schema_supported(proposal_schema)
    registry = {
        case_schema["$id"]: case_schema,
        proposal_schema["$id"]: proposal_schema,
        "workout-import-acceptance-case-v2.schema.json": case_schema,
        "workout-proposal-v1.schema.json": proposal_schema,
    }

    if not isinstance(cases, list) or not cases:
        errors.append("cases.json must contain a non-empty array")
        cases = []
    ids = [case.get("id") for case in cases]
    if ids != sorted(ids):
        errors.append("cases must be ordered by stable ID")
    if len(ids) != len(set(ids)):
        errors.append("case IDs must be unique")
    prompts = [normalized_prompt(case.get("prompt", "")) for case in cases]
    if len(prompts) != len(set(prompts)):
        errors.append("normalised acceptance prompts must be unique")

    category_counts = Counter(case.get("category") for case in cases)
    locale_counts = Counter(case.get("locale") for case in cases)
    coverage = sorted({tag for case in cases for tag in case.get("coverageTags", [])})
    index = [{"id": case.get("id"), "category": case.get("category")} for case in cases]
    if manifest.get("caseCount") != len(cases):
        errors.append("manifest caseCount differs from cases.json")
    if manifest.get("categoryCounts") != dict(sorted(category_counts.items())):
        errors.append("manifest categoryCounts differ from cases.json")
    if manifest.get("localeCounts") != dict(sorted(locale_counts.items())):
        errors.append("manifest localeCounts differ from cases.json")
    if manifest.get("caseIndex") != index:
        errors.append("manifest caseIndex differs from ordered cases.json")
    if manifest.get("requiredCoverageTags") != coverage:
        errors.append("manifest requiredCoverageTags must exactly match exercised coverage")
    if manifest.get("casesSha256") != sha256_file(corpus_dir / "cases.json"):
        errors.append("manifest casesSha256 differs from cases.json bytes")
    if manifest.get("semanticReviewSha256") != sha256_file(corpus_dir / "semantic-review.json"):
        errors.append("manifest semanticReviewSha256 differs from semantic-review.json bytes")
    actual_corpus_hash = compute_corpus_hash(manifest, cases)
    if manifest.get("corpusHash") != actual_corpus_hash:
        errors.append(
            f"manifest corpusHash differs: expected {actual_corpus_hash}, found {manifest.get('corpusHash')}"
        )

    signatures: dict[str, list[str]] = defaultdict(list)
    families: dict[str, list[str]] = defaultdict(list)
    local_validator_counts: Counter[str] = Counter()
    for index_number, case in enumerate(cases):
        problems = validate_instance(case, case_schema, registry)
        errors.extend(
            f"{case.get('id', index_number)} schema {problem.path}: {problem.message}"
            for problem in problems
        )
        if case.get("caseContractVersion") != CASE_CONTRACT_VERSION:
            errors.append(f"{case.get('id')} has the wrong case contract version")
        signatures[_expected_signature(case)].append(case["id"])
        families[case["scenarioFamily"]].append(case["id"])
        expected = case["expected"]
        if expected["outcome"] != "proposal":
            continue
        fixture = _mapping_fixture(case)
        proposal_problems = validate_instance(fixture, proposal_schema, registry)
        errors.extend(
            f"{case['id']} mapping fixture {problem.path}: {problem.message}"
            for problem in proposal_problems
        )
        mapped = map_proposal(fixture)
        if _canonical_projection(mapped) != expected["canonicalProposal"]:
            errors.append(f"{case['id']} expected canonical mapping does not round-trip")
        validation = local_validate(
            mapped, _capabilities(manifest, case["capabilityProfile"])
        )
        local_validator_counts[validation["status"]] += 1
        if validation["status"] != expected["localValidatorOutcome"]:
            errors.append(f"{case['id']} local validator outcome differs")
        if validation["issueCodes"] != expected["localValidatorIssueCodes"]:
            errors.append(f"{case['id']} local validator issue codes differ")
        for normalisation in expected["normalisations"]:
            if normalisation["sourceText"] not in case["prompt"]:
                errors.append(f"{case['id']} normalisation source text is absent from prompt")
            target = _target_value(expected["canonicalProposal"], normalisation["targetPath"])
            if target != normalisation["canonicalValue"]:
                errors.append(f"{case['id']} normalisation changes the source numeric value")
            field = normalisation["targetPath"].rsplit(".", 1)[1]
            expected_unit = "kilometresPerHour" if field == "speedKilometresPerHour" else "percent"
            if normalisation["canonicalUnit"] != expected_unit:
                errors.append(f"{case['id']} normalisation uses the wrong canonical unit")

    review_ids = review.get("reviewedCaseIDs")
    if review_ids != ids:
        errors.append("semantic review must cover every case in corpus order")
    assertions = review.get("assertions")
    if not isinstance(assertions, dict) or not assertions or not all(assertions.values()):
        errors.append("semantic review assertions must all be true")
    declared_groups = {
        entry["scenarioFamily"]: entry["caseIDs"]
        for entry in review.get("intentionalEquivalenceGroups", [])
    }
    repeated_families = {family: case_ids for family, case_ids in families.items() if len(case_ids) > 1}
    if repeated_families != declared_groups:
        errors.append("repeated scenario families differ from intentional equivalence groups")
    repeated_signatures = {
        tuple(case_ids)
        for case_ids in signatures.values()
        if len(case_ids) > 1
    }
    declared_case_groups = {tuple(case_ids) for case_ids in declared_groups.values()}
    if repeated_signatures != declared_case_groups:
        errors.append("expected semantic duplicates differ from intentional equivalence groups")

    reviewed_prompt_text: set[str] = set()
    prompt_example_texts: list[str] = []
    repository_root = root.parents[1]
    reviewed_sources = set(review.get("reviewedAgainst", []))
    if not REQUIRED_MODEL_VISIBLE_PROMPT_SOURCES.issubset(reviewed_sources):
        errors.append("semantic review omits a required model-visible prompt source")
    for relative in review.get("reviewedAgainst", []):
        path = repository_root / relative
        if not path.is_file():
            errors.append(f"semantic review target is missing: {relative}")
            continue
        expected_review_hash = review.get("reviewedAgainstSha256", {}).get(relative)
        if expected_review_hash != sha256_file(path):
            errors.append(f"semantic review source hash differs: {relative}")
        if path.suffix == ".json" and path.name == "cases.json":
            document = strict_load(path)
            for item in document:
                if isinstance(item, dict) and isinstance(item.get("prompt"), str):
                    reviewed_prompt_text.add(normalized_prompt(item["prompt"]))
        else:
            prompt_example_texts.append(path.read_text(encoding="utf-8").casefold())
    if set(review.get("reviewedAgainstSha256", {})) != set(review.get("reviewedAgainst", [])):
        errors.append("semantic review hashes must cover every reviewed source exactly")
    for case, prompt in zip(cases, prompts):
        if prompt in reviewed_prompt_text:
            errors.append(f"{case['id']} duplicates a prompt in reviewed corpora")
        if any(case["prompt"].casefold() in text for text in prompt_example_texts):
            errors.append(f"{case['id']} was copied into a reviewed system prompt")

    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "corpusVersion": manifest.get("corpusVersion"),
        "corpusRevision": manifest.get("corpusRevision"),
        "corpusHash": actual_corpus_hash,
        "caseCount": len(cases),
        "proposalCaseCount": sum(case["expected"]["outcome"] == "proposal" for case in cases),
        "failClosedCaseCount": sum(case["expected"]["outcome"] != "proposal" for case in cases),
        "localValidatorCounts": dict(sorted(local_validator_counts.items())),
        "sealedV1Assets": len(SEALED_V1_SHA256),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Evaluation/WorkoutImport root",
    )
    arguments = parser.parse_args(argv)
    report = verify(arguments.root.resolve())
    print(canonical_json(report))
    return 0 if report["status"] == "valid" else 1


if __name__ == "__main__":
    sys.exit(main())
