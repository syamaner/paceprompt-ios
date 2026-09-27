"""Zero-spend two-route warm-up proposal for the ratified issue #145 r3 matrix.

This prepares a separately ratifiable compatibility probe. It cannot read a
credential or call a model; no live entrypoint is defined here.
"""

from __future__ import annotations

from decimal import Decimal
import json
from typing import Any

from .catalogue import conservative_call_cost
from .issue145 import _body_for_case
from .issue145_full_matrix_r3 import RATIFICATION as MATRIX_RATIFICATION, RATIFICATION_SHA256 as MATRIX_RATIFICATION_SHA256, verify_ratification
from .issue145_retry_profile_r3 import PROPOSAL_SHA256 as RETRY_PROPOSAL_SHA256
from .issue145_retry_execution import evidence_tree_sha256
from .openrouter import ModelSpec
from .runner import write_json
from .v3 import HOST_EVAL_ROOT, asset_paths, canonical_hash, load_cases, safe_run_dir, sha256_file, strict_json_load


ORDERED_MODELS = (
    "mistralai/mistral-small-2603",
    "deepseek/deepseek-v4-flash-0731",
)
WARMUP_CASE_ID = "WI-V3-D020"
RATIFICATION = HOST_EVAL_ROOT / "issue145-r3-route-probe-ratification-r1.json"
RATIFICATION_SHA256 = "25be71a59053e69b1031530e5fdf6132d9d6b1616869069f00591fb3add5d94a"


def proposal_material(run_id: str) -> dict[str, Any]:
    checked = verify_ratification(require_prepared_evidence=True)
    if checked["status"] != "valid":
        raise RuntimeError(f"r3 profile/cap ratification failed: {checked['errors']}")
    ratification = strict_json_load(MATRIX_RATIFICATION)
    ratified_dir = safe_run_dir(ratification["preparedRunID"], create=False)
    ratified = strict_json_load(ratified_dir / "r3-proposal.json")
    catalogue = strict_json_load(ratified_dir / "catalogue" / "selected.json")
    models = strict_json_load(ratified_dir / "models-r3-materialized.json")
    by_model = {item["requestedModelID"]: ModelSpec.from_json(item)
                for item in models["models"]}
    selected = {item["requestedModelID"]: item for item in catalogue["selected"]}
    warmup = next(case for case in load_cases(asset_paths()["developmentCases"])
                  if case["id"] == WARMUP_CASE_ID)
    calls: list[dict[str, Any]] = []
    total = Decimal("0")
    for model_id in ORDERED_MODELS:
        spec = by_model[model_id]
        endpoint = selected[model_id]
        template = strict_json_load(
            ratified_dir / "mock-payloads" / f"{model_id.replace('/', '--')}.json"
        )["body"]
        body = _body_for_case(template, warmup)
        size = len(json.dumps(body, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")).encode("utf-8"))
        one_send = conservative_call_cost(
            input_utf8_bytes=size,
            input_price=endpoint["inputPricePerToken"],
            output_price=endpoint["outputPricePerToken"],
            output_tokens=spec.max_output_tokens,
        )
        total += one_send * 3
        calls.append({
            "logicalID": f"warmup-{model_id.replace('/', '--')}",
            "warmupCaseID": WARMUP_CASE_ID,
            "requestedModelID": model_id,
            "canonicalRevision": spec.canonical_revision,
            "providerEndpoint": spec.provider_endpoint,
            "responseContract": spec.response_contract,
            "requestUTF8Bytes": size,
            "oneSendWorstCaseUSD": format(one_send, "f"),
            "maximumPhysicalSends": 3,
        })
    return {
        "proposalVersion": "paceprompt-host-eval-proposal/issue145-r3-route-probes-r1",
        "status": "awaiting-separate-probe-cap-and-live-gate-ratification",
        "runID": run_id,
        "parentFullMatrixProfileSha256": ratified["profileSha256"],
        "parentRatificationSha256": MATRIX_RATIFICATION_SHA256,
        "parentPreparedEvidenceTreeSha256": ratification[
            "supportingPreparedEvidenceTreeSha256"
        ],
        "retryProposalSha256": RETRY_PROPOSAL_SHA256,
        "orderedCalls": calls,
        "logicalPositions": 2,
        "maximumPhysicalSends": 6,
        "scoredHeldoutCalls": 0,
        "threeSendConservativeUSD": format(total, "f"),
        "recommendedProbeHardLimitUSD": format(total, "f"),
        "ratifiedProbeHardLimitUSD": None,
        "routeCompatibilityProof": None,
        "credentialRead": False,
        "providerCalls": 0,
        "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def prepare_proposal(run_id: str) -> dict[str, Any]:
    material = proposal_material(run_id)
    run_dir = safe_run_dir(run_id, create=True)
    material["proposalSha256"] = canonical_hash(material)
    write_json(run_dir / "r3-route-probe-proposal.json", material)
    return material


def verify_prepared_proposal(run_id: str) -> dict[str, Any]:
    """Audit the ignored two-warm-up proposal before any probe ratification."""
    run_dir = safe_run_dir(run_id, create=False)
    expected = proposal_material(run_id)
    expected["proposalSha256"] = canonical_hash(expected)
    actual = strict_json_load(run_dir / "r3-route-probe-proposal.json")
    errors = [] if actual == expected else ["route-probe proposal changed"]
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "proposalSha256": expected["proposalSha256"],
        "evidenceTreeSha256": evidence_tree_sha256(run_dir),
        "recommendedProbeHardLimitUSD": expected["recommendedProbeHardLimitUSD"],
        "credentialRead": False, "providerCalls": 0, "spendUSD": "0.00",
        "liveAuthorized": False,
    }


def verify_probe_ratification() -> dict[str, Any]:
    """Bind the operator's narrow cap approval to the sealed ignored proposal."""
    errors: list[str] = []
    if sha256_file(RATIFICATION) != RATIFICATION_SHA256:
        errors.append("probe ratification bytes changed")
    ratification = strict_json_load(RATIFICATION)
    expected = {
        "ratificationVersion": "paceprompt-host-eval-ratification/issue145-r3-route-probes-r1",
        "status": "probe-profile-and-cap-ratified-live-run-not-authorized",
        "source": "operator replied 'I ratify' on 2026-09-24 to the exact two-route probe profile and USD 0.03577518 hard-limit question",
        "operatorRatifiedFields": ["proposalSha256", "probeHardLimitUSD"],
        "proposalSha256": "133091376a862247ce72a4413c988e5c2fa9dd23be62f66960cf9d71c755ddce",
        "supportingPreparedEvidenceTreeSha256": "da389803ca4c7c71ca6583579f83295e2c13283281ec8d3ed6470cdd08259920",
        "preparedRunID": "issue145-r3-route-probe-proposal-20260924-01",
        "probeHardLimitUSD": "0.03577518", "currency": "USD",
        "scope": "two r3 replacement-route development warm-ups only; no scored cases",
        "maximumLogicalPositions": 2, "maximumPhysicalSends": 6,
        "separateFromFullMatrixLineageCap": True,
        "routeCompatibilityProof": None, "liveGate": None,
        "initialLiveAuthorization": None,
        "authority": {"credentialRead": False, "providerInference": False,
                      "spend": False, "liveRun": False},
    }
    if ratification != expected:
        errors.append("probe ratification scope changed")
    prepared = verify_prepared_proposal(ratification["preparedRunID"])
    if (prepared["status"] != "valid"
            or prepared["proposalSha256"] != ratification["proposalSha256"]
            or prepared["evidenceTreeSha256"] != ratification["supportingPreparedEvidenceTreeSha256"]
            or prepared["recommendedProbeHardLimitUSD"] != ratification["probeHardLimitUSD"]):
        errors.append("ratified proposal, evidence or hard limit changed")
    return {"status": "valid" if not errors else "invalid", "errors": errors,
            "ratificationSha256": RATIFICATION_SHA256,
            "proposalSha256": ratification["proposalSha256"],
            "hardLimitUSD": ratification["probeHardLimitUSD"],
            "liveAuthorized": False}
