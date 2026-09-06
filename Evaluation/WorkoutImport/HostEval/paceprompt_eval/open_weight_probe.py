"""Sealed curl diagnostics for issue #17 open-weight candidates."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import subprocess
from typing import Any, Callable

from .catalogue import conservative_call_cost, snapshot_catalogue
from .curl_probe import CurlProbeRun
from .openrouter import ModelSpec, load_model_specs
from .runner import compare_catalogues, write_json
from .v3 import (
    HOST_EVAL_ROOT,
    canonical_hash,
    safe_run_dir,
    sha256_file,
    strict_json_load,
    verify as verify_v3,
)


MODELS = HOST_EVAL_ROOT / "models-v4-open-weight-curl-probe.json"
RUN_POLICY = HOST_EVAL_ROOT / "curl-probe-policy-v4-open-weight.json"
REPROBE_MODELS = HOST_EVAL_ROOT / "models-v4-open-weight-curl-reprobe.json"
REPROBE_RUN_POLICY = HOST_EVAL_ROOT / "curl-probe-policy-v4-open-weight-reprobe.json"
BASETEN_TOOL_MODELS = (
    HOST_EVAL_ROOT / "models-v4-open-weight-nemotron-baseten-tool-probe.json"
)
BASETEN_TOOL_RUN_POLICY = (
    HOST_EVAL_ROOT / "curl-probe-policy-v4-open-weight-nemotron-baseten-tool.json"
)
GATE_CONTRACT = "paceprompt-host-eval-open-weight-curl-probe-gate/v4"
REPORT_CONTRACT = "paceprompt-host-eval-open-weight-curl-probe-report/v4"
AUTHORIZATION_PREFIX = "AUTHORIZE_PACEPROMPT_OPEN_WEIGHT_CURL_V4_"

EXPECTED_MODELS = (
    ("qwen/qwen3.8-27b", "qwen/qwen3.8-27b-20260814", "parasail/fp8", "fp8"),
    ("mistralai/mistral-small-2603", "mistralai/mistral-small-2603", "venice/fp8", "fp8"),
    ("nvidia/nemotron-3.5-lightning", "nvidia/nemotron-3.5-lightning-20260807", "deepinfra/bf16", "bf16"),
    ("deepseek/deepseek-v4-flash-0731", "deepseek/deepseek-v4-flash-20260731", "open-inference/fp8", "fp8"),
    ("z-ai/glm-5.3-flash", "z-ai/glm-5.3-flash-20260826", "coreweave/fp8", "fp8"),
    ("minimax/minimax-m3", "minimax/minimax-m3-20260531", "parasail/fp8", "fp8"),
    ("nvidia/nemotron-3-ultra-550b-a55b", "nvidia/nemotron-3-ultra-550b-a55b-20260604", "deepinfra/fp4", "fp4"),
    ("qwen/qwen-2.5-7b-instruct", "qwen/qwen-2.5-7b-instruct", "phala", None),
    ("mistralai/mistral-small-3.2-24b-instruct", "mistralai/mistral-small-3.2-24b-instruct-2506", "parasail/bf16", "bf16"),
)

REPROBE_EXPECTED_MODELS = (
    ("z-ai/glm-5.3-flash", "z-ai/glm-5.3-flash-20260826", "deepinfra/fp4", "fp4"),
    ("minimax/minimax-m3", "minimax/minimax-m3-20260531", "coreweave/fp4", "fp4"),
    ("nvidia/nemotron-3-ultra-550b-a55b", "nvidia/nemotron-3-ultra-550b-a55b-20260604", "deepinfra/fp4", "fp4"),
    ("mistralai/mistral-small-3.2-24b-instruct", "mistralai/mistral-small-3.2-24b-instruct-2506", "deepinfra/fp8", "fp8"),
)

BASETEN_TOOL_EXPECTED_MODELS = (
    (
        "nvidia/nemotron-3-ultra-550b-a55b",
        "nvidia/nemotron-3-ultra-550b-a55b-20260604",
        "baseten/fp4",
        "fp4",
    ),
)

REPROBE_PRIOR_EVIDENCE = {
    "runID": "issue17-open-weight-curl-probe-20260905-03",
    "reportSha256": "e86c80119c187546f0fedb9862f73a612e2e194ad5130b643481914869be14c0",
    "lockedPassingRoutes": [
        {"requestedModelID": "qwen/qwen3.8-27b", "canonicalRevision": "qwen/qwen3.8-27b-20260814", "providerEndpoint": "parasail/fp8", "quantization": "fp8"},
        {"requestedModelID": "mistralai/mistral-small-2603", "canonicalRevision": "mistralai/mistral-small-2603", "providerEndpoint": "venice/fp8", "quantization": "fp8"},
        {"requestedModelID": "nvidia/nemotron-3.5-lightning", "canonicalRevision": "nvidia/nemotron-3.5-lightning-20260807", "providerEndpoint": "deepinfra/bf16", "quantization": "bf16"},
        {"requestedModelID": "deepseek/deepseek-v4-flash-0731", "canonicalRevision": "deepseek/deepseek-v4-flash-20260731", "providerEndpoint": "open-inference/fp8", "quantization": "fp8"},
        {"requestedModelID": "qwen/qwen-2.5-7b-instruct", "canonicalRevision": "qwen/qwen-2.5-7b-instruct", "providerEndpoint": "phala", "quantization": None},
    ],
}

BASETEN_TOOL_PRIOR_EVIDENCE = {
    "runID": "issue17-open-weight-curl-reprobe-20260905-02",
    "gateSha256": "58e8b5f6727c05786d0d32bf8750d0f83d1864919628b55ceacb1548857e9e59",
    "reportSha256": "ffc78df1afded01e59aa805b7e4d7e6463549f4fc995c70940f6b8453a340fb4",
    "lockedPassingRoutes": [
        {"requestedModelID": "z-ai/glm-5.3-flash", "canonicalRevision": "z-ai/glm-5.3-flash-20260826", "providerEndpoint": "deepinfra/fp4", "quantization": "fp4"},
        {"requestedModelID": "minimax/minimax-m3", "canonicalRevision": "minimax/minimax-m3-20260531", "providerEndpoint": "coreweave/fp4", "quantization": "fp4"},
        {"requestedModelID": "mistralai/mistral-small-3.2-24b-instruct", "canonicalRevision": "mistralai/mistral-small-3.2-24b-instruct-2506", "providerEndpoint": "deepinfra/fp8", "quantization": "fp8"},
    ],
}


@dataclass(frozen=True)
class ProbeProfile:
    name: str
    models: Path
    run_policy: Path
    model_set_version: str
    run_policy_version: str
    gate_contract: str
    report_contract: str
    authorization_prefix: str
    expected_models: tuple[tuple[str, str, str, str | None], ...]
    diagnostic_transport: str = "messageContentJson"
    prior_evidence: dict[str, Any] | None = None


INITIAL_PROFILE = ProbeProfile(
    name="initial",
    models=MODELS,
    run_policy=RUN_POLICY,
    model_set_version="paceprompt-host-eval-open-weight-curl-probe-models/v4",
    run_policy_version="paceprompt-host-eval-open-weight-curl-probe/v4",
    gate_contract=GATE_CONTRACT,
    report_contract=REPORT_CONTRACT,
    authorization_prefix=AUTHORIZATION_PREFIX,
    expected_models=EXPECTED_MODELS,
)

REPLACEMENT_PROFILE = ProbeProfile(
    name="replacement",
    models=REPROBE_MODELS,
    run_policy=REPROBE_RUN_POLICY,
    model_set_version="paceprompt-host-eval-open-weight-curl-reprobe-models/v4",
    run_policy_version="paceprompt-host-eval-open-weight-curl-reprobe/v4",
    gate_contract="paceprompt-host-eval-open-weight-curl-reprobe-gate/v4",
    report_contract="paceprompt-host-eval-open-weight-curl-reprobe-report/v4",
    authorization_prefix="AUTHORIZE_PACEPROMPT_OPEN_WEIGHT_CURL_REPROBE_V4_",
    expected_models=REPROBE_EXPECTED_MODELS,
    prior_evidence=REPROBE_PRIOR_EVIDENCE,
)

BASETEN_TOOL_PROFILE = ProbeProfile(
    name="nemotron-baseten",
    models=BASETEN_TOOL_MODELS,
    run_policy=BASETEN_TOOL_RUN_POLICY,
    model_set_version="paceprompt-host-eval-open-weight-nemotron-baseten-tool-models/v4",
    run_policy_version="paceprompt-host-eval-open-weight-nemotron-baseten-tool/v4",
    gate_contract="paceprompt-host-eval-open-weight-nemotron-baseten-tool-gate/v4",
    report_contract="paceprompt-host-eval-open-weight-nemotron-baseten-tool-report/v4",
    authorization_prefix="AUTHORIZE_PACEPROMPT_NEMOTRON_BASETEN_TOOL_CURL_V4_",
    expected_models=BASETEN_TOOL_EXPECTED_MODELS,
    diagnostic_transport="forcedToolArguments",
    prior_evidence=BASETEN_TOOL_PRIOR_EVIDENCE,
)


def profile_for_name(name: str) -> ProbeProfile:
    if name == "initial":
        return INITIAL_PROFILE
    if name == "replacement":
        return REPLACEMENT_PROFILE
    if name == "nemotron-baseten":
        return BASETEN_TOOL_PROFILE
    raise ValueError(f"unknown open-weight curl-probe profile: {name}")


def _expected_request(profile: ProbeProfile) -> dict[str, Any]:
    request: dict[str, Any] = {
        "message": "Return a JSON object whose ok property is true.",
        "maxOutputTokens": 1024,
        "temperature": None,
        "topP": None,
        "reasoning": None,
        "strictSchemaName": "paceprompt_open_weight_curl_probe_v4",
        "strictSchema": {
            "type": "object",
            "properties": {"ok": {"type": "boolean", "const": True}},
            "required": ["ok"],
            "additionalProperties": False,
        },
    }
    if profile.diagnostic_transport == "forcedToolArguments":
        request.update(
            {
                "message": (
                    "Call submit_probe_result with an ok argument whose value is true."
                ),
                "forcedToolName": "submit_probe_result",
                "forcedToolDescription": (
                    "Return the minimal provider compatibility result."
                ),
            }
        )
    return request


def _required_parameters(profile: ProbeProfile) -> set[str]:
    if profile.diagnostic_transport == "forcedToolArguments":
        return {"max_tokens", "tools", "tool_choice"}
    return {"max_tokens", "response_format", "structured_outputs"}


def _verify_prior_evidence_descriptor(prior: dict[str, Any]) -> None:
    prior_run_dir = safe_run_dir(prior["runID"], create=False)
    report_path = prior_run_dir / "curl-probe-report.json"
    gate_path = prior_run_dir / "operator-gate.json"
    if sha256_file(report_path) != prior["reportSha256"]:
        raise RuntimeError("prior open-weight curl-probe report hash changed")
    if prior.get("gateSha256") and sha256_file(gate_path) != prior["gateSha256"]:
        raise RuntimeError("prior open-weight curl-probe gate hash changed")
    report = strict_json_load(report_path)
    gate = strict_json_load(gate_path)
    attempts = {item["modelID"]: item for item in report["attempts"]}
    selected = {item["requestedModelID"]: item for item in gate["selectedEndpoints"]}
    for locked in prior["lockedPassingRoutes"]:
        model_id = locked["requestedModelID"]
        attempt = attempts.get(model_id, {})
        endpoint = selected.get(model_id, {})
        if not (
            attempt.get("statusCode") == 200
            and attempt.get("routeIdentityMatches") is True
            and attempt.get("strictSchemaSatisfied") is True
        ):
            raise RuntimeError(f"prior passing evidence is absent for {model_id}")
        if (
            endpoint.get("canonicalRevision") != locked["canonicalRevision"]
            or endpoint.get("providerEndpoint") != locked["providerEndpoint"]
            or endpoint.get("configuredQuantization") != locked["quantization"]
        ):
            raise RuntimeError(f"prior passing route identity changed for {model_id}")
    nested = gate.get("priorEvidence")
    if nested is not None:
        _verify_prior_evidence_descriptor(nested)


def verify_prior_evidence(profile: ProbeProfile) -> None:
    if profile.prior_evidence is not None:
        _verify_prior_evidence_descriptor(profile.prior_evidence)


def _curl_version() -> str:
    result = subprocess.run(
        ["curl", "--version"], check=True, capture_output=True, text=True
    )
    return result.stdout.splitlines()[0]


def verify_configuration(*, profile: ProbeProfile = INITIAL_PROFILE) -> dict[str, Any]:
    errors: list[str] = []
    models_document = strict_json_load(profile.models)
    policy = strict_json_load(profile.run_policy)
    specs = load_model_specs(profile.models)
    actual_models = tuple(
        (
            spec.requested_model_id,
            spec.canonical_revision,
            spec.provider_endpoint,
            spec.quantization,
        )
        for spec in specs
    )
    if models_document.get("modelSetVersion") != profile.model_set_version:
        errors.append("open-weight probe model-set version changed")
    if actual_models != profile.expected_models:
        errors.append("open-weight probe model, revision, endpoint or quantization changed")
    if any(
        spec.role != "compatibilityDiagnostic"
        or spec.temperature is not None
        or spec.top_p is not None
        or spec.reasoning is not None
        for spec in specs
    ):
        errors.append("open-weight probe generation controls changed")
    if policy.get("runPolicyVersion") != profile.run_policy_version:
        errors.append("open-weight curl-probe policy version changed")
    if policy.get("scope") != {
        "models": [item[0] for item in profile.expected_models],
        "stagesPerModel": 1,
        "maximumCalls": len(profile.expected_models),
        "developmentCalls": 0,
        "heldoutCalls": 0,
        "prompt": "minimalSyntheticOnly",
    }:
        errors.append("open-weight curl-probe scope changed")
    if policy.get("priorEvidence") != profile.prior_evidence:
        errors.append("open-weight curl-probe prior evidence changed")
    if policy.get("request") != _expected_request(profile):
        errors.append("open-weight curl-probe request changed")
    if policy.get("routing") != {
        "exactEndpointTag": True,
        "allowFallbacks": False,
        "requireParameters": True,
        "dataCollection": "deny",
        "zdr": True,
        "knownQuantizationFilter": True,
        "unknownQuantizationFilter": "omit",
        "endpointPriceCap": "catalogue-price-at-gate-preparation",
    }:
        errors.append("open-weight curl-probe routing controls changed")
    if policy.get("execution") != {
        "transport": "curl",
        "globalConcurrency": 1,
        "minimumInterCallDelaySeconds": 2,
        "automaticRetries": 0,
        "connectTimeoutSeconds": 15,
        "attemptTimeoutSeconds": 120,
        "cancelFlushSeconds": 15,
        "cache": False,
        "resumable": False,
        "abortHTTPStatusCodes": [401, 402, 403],
    }:
        errors.append("open-weight curl-probe execution controls changed")
    if policy.get("spending") != {
        "currency": "USD",
        "hardLimit": "0.25",
        "enforcement": "worstCaseBeforeEveryCallPlusEndpointPriceCap",
    }:
        errors.append("open-weight curl-probe spending controls changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "configurationHashes": {
            "models": sha256_file(profile.models),
            "runPolicy": sha256_file(profile.run_policy),
        },
    }


def _max_price_per_million(selected: dict[str, Any]) -> dict[str, float]:
    scale = Decimal("1000000")
    return {
        "prompt": float(Decimal(selected["inputPricePerToken"]) * scale),
        "completion": float(Decimal(selected["outputPricePerToken"]) * scale),
    }


def _provider_controls(spec: ModelSpec, selected: dict[str, Any]) -> dict[str, Any]:
    controls: dict[str, Any] = {
        "order": [spec.provider_endpoint],
        "only": [spec.provider_endpoint],
        "allow_fallbacks": False,
        "require_parameters": True,
        "data_collection": "deny",
        "zdr": True,
        "max_price": _max_price_per_million(selected),
    }
    if spec.quantization is not None:
        controls["quantizations"] = [spec.quantization]
    return controls


def _assert_payload(
    body: dict[str, Any],
    spec: ModelSpec,
    policy: dict[str, Any],
    profile: ProbeProfile,
) -> None:
    expected_fields = {
        "model",
        "messages",
        "provider",
        "max_tokens",
        "stream",
        *(
            {"tools", "tool_choice"}
            if profile.diagnostic_transport == "forcedToolArguments"
            else {"response_format"}
        ),
    }
    if set(body) != expected_fields:
        raise AssertionError(f"unexpected curl payload fields for {spec.requested_model_id}")
    if body["model"] != spec.requested_model_id or body["max_tokens"] != 1024 or body["stream"] is not False:
        raise AssertionError(f"open-weight curl payload request controls changed for {spec.requested_model_id}")
    if body["messages"] != [{"role": "user", "content": policy["request"]["message"]}]:
        raise AssertionError(f"open-weight curl payload prompt changed for {spec.requested_model_id}")
    provider = body["provider"]
    if provider["order"] != [spec.provider_endpoint] or provider["only"] != [spec.provider_endpoint]:
        raise AssertionError(f"open-weight curl payload endpoint changed for {spec.requested_model_id}")
    for key, expected in (
        ("allow_fallbacks", False),
        ("require_parameters", True),
        ("data_collection", "deny"),
        ("zdr", True),
    ):
        if provider.get(key) != expected:
            raise AssertionError(f"open-weight curl payload {key} changed for {spec.requested_model_id}")
    expected_quantizations = None if spec.quantization is None else [spec.quantization]
    if provider.get("quantizations") != expected_quantizations:
        raise AssertionError(f"open-weight curl payload quantization changed for {spec.requested_model_id}")
    if profile.diagnostic_transport == "forcedToolArguments":
        tool_name = policy["request"]["forcedToolName"]
        if body["tools"] != [
            {
                "type": "function",
                "function": {
                    "name": tool_name,
                    "description": policy["request"]["forcedToolDescription"],
                    "parameters": policy["request"]["strictSchema"],
                },
            }
        ]:
            raise AssertionError(
                f"open-weight curl tool schema changed for {spec.requested_model_id}"
            )
        if body["tool_choice"] != {
            "type": "function",
            "function": {"name": tool_name},
        }:
            raise AssertionError(
                f"open-weight curl forced tool changed for {spec.requested_model_id}"
            )
        return
    response_format = body["response_format"]
    if response_format != {
        "type": "json_schema",
        "json_schema": {
            "name": policy["request"]["strictSchemaName"],
            "description": "A minimal provider compatibility response.",
            "schema": policy["request"]["strictSchema"],
            "strict": True,
        },
    }:
        raise AssertionError(
            f"open-weight curl payload schema changed for {spec.requested_model_id}"
        )


def write_probe_payloads(
    run_dir: Path,
    selected_endpoints: list[dict[str, Any]],
    *,
    profile: ProbeProfile = INITIAL_PROFILE,
) -> list[dict[str, Any]]:
    policy = strict_json_load(profile.run_policy)
    specs = load_model_specs(profile.models)
    selected = {item["requestedModelID"]: item for item in selected_endpoints}
    payload_dir = run_dir / "curl-payloads"
    payload_dir.mkdir()
    manifest: list[dict[str, Any]] = []
    for index, spec in enumerate(specs, start=1):
        body = {
            "model": spec.requested_model_id,
            "messages": [{"role": "user", "content": policy["request"]["message"]}],
            "provider": _provider_controls(spec, selected[spec.requested_model_id]),
            "max_tokens": policy["request"]["maxOutputTokens"],
            "stream": False,
        }
        if profile.diagnostic_transport == "forcedToolArguments":
            tool_name = policy["request"]["forcedToolName"]
            body.update(
                {
                    "tools": [
                        {
                            "type": "function",
                            "function": {
                                "name": tool_name,
                                "description": policy["request"][
                                    "forcedToolDescription"
                                ],
                                "parameters": deepcopy(
                                    policy["request"]["strictSchema"]
                                ),
                            },
                        }
                    ],
                    "tool_choice": {
                        "type": "function",
                        "function": {"name": tool_name},
                    },
                }
            )
        else:
            body["response_format"] = {
                "type": "json_schema",
                "json_schema": {
                    "name": policy["request"]["strictSchemaName"],
                    "description": "A minimal provider compatibility response.",
                    "schema": deepcopy(policy["request"]["strictSchema"]),
                    "strict": True,
                },
            }
        _assert_payload(body, spec, policy, profile)
        if profile.diagnostic_transport == "forcedToolArguments":
            attempt_label = "minimal-forced-tool"
            stage_id = "01-minimal-forced-tool"
            schema_label = "trivialToolArguments"
        else:
            attempt_label = "minimal-strict"
            stage_id = "01-minimal-strict-schema"
            schema_label = "trivialStrict"
        attempt_id = (
            f"{index:02d}-{attempt_label}-{spec.requested_model_id.replace('/', '--')}"
        )
        relative_path = Path("curl-payloads") / f"{attempt_id}.json"
        path = run_dir / relative_path
        write_json(path, body)
        manifest.append(
            {
                "attemptID": attempt_id,
                "modelID": spec.requested_model_id,
                "stageID": stage_id,
                "messages": "minimalSynthetic",
                "schema": schema_label,
                "payloadPath": str(relative_path),
                "payloadSha256": sha256_file(path),
            }
        )
    if len(manifest) != policy["scope"]["maximumCalls"]:
        raise RuntimeError("open-weight curl-probe manifest call count differs from policy")
    write_json(run_dir / "curl-probe-manifest.json", manifest)
    write_json(
        run_dir / "curl-mock-summary.json",
        {
            "evidenceType": "offlineOpenWeightCurlPayloadsOnly",
            "runID": run_dir.name,
            "providerCalls": 0,
            "credentialRead": False,
            "spendUSD": "0.00",
            "payloadCount": len(manifest),
            "manifestSha256": sha256_file(run_dir / "curl-probe-manifest.json"),
        },
    )
    return manifest


def cost_preflight(
    snapshot: dict[str, Any],
    run_dir: Path,
    manifest: list[dict[str, Any]],
    *,
    profile: ProbeProfile = INITIAL_PROFILE,
) -> dict[str, Any]:
    policy = strict_json_load(profile.run_policy)
    selected = {item["requestedModelID"]: item for item in snapshot["selected"]}
    per_attempt: dict[str, Decimal] = {}
    for probe in manifest:
        endpoint = selected[probe["modelID"]]
        per_attempt[probe["attemptID"]] = conservative_call_cost(
            input_utf8_bytes=(run_dir / probe["payloadPath"]).stat().st_size,
            input_price=endpoint["inputPricePerToken"],
            output_price=endpoint["outputPricePerToken"],
            output_tokens=policy["request"]["maxOutputTokens"],
        )
    total = sum(per_attempt.values(), Decimal("0"))
    hard_limit = Decimal(policy["spending"]["hardLimit"])
    call_count = len(manifest)
    return {
        "method": "serialized-payload-utf8-byte-upper-bound-plus-4096-framing-tokens-and-1024-output-tokens-per-call",
        "hardLimitUSD": format(hard_limit, "f"),
        "callCount": call_count,
        "developmentCalls": 0,
        "heldoutCalls": 0,
        "worstCaseUSD": format(total, "f"),
        "admitted": call_count == policy["scope"]["maximumCalls"] and total <= hard_limit,
        "perAttemptWorstCaseUSD": {
            key: format(value, "f") for key, value in per_attempt.items()
        },
    }


async def prepare_gate(
    run_id: str,
    *,
    fetch: Callable[[str], bytes] | None = None,
    profile: ProbeProfile = INITIAL_PROFILE,
) -> dict[str, Any]:
    configuration = verify_configuration(profile=profile)
    if configuration["status"] != "valid":
        raise RuntimeError(f"open-weight curl-probe configuration failed: {configuration['errors']}")
    frozen = verify_v3()
    if frozen["status"] != "valid":
        raise RuntimeError(f"v3 verification failed: {frozen['errors']}")
    verify_prior_evidence(profile)
    run_dir = safe_run_dir(run_id, create=True)
    specs = load_model_specs(profile.models)
    snapshot = snapshot_catalogue(
        run_dir / "catalogue",
        specs,
        required_parameters=_required_parameters(profile),
        allow_equivalent_duplicate_tags=(
            profile.diagnostic_transport == "forcedToolArguments"
        ),
        **({"fetch": fetch} if fetch else {}),
    )
    manifest = write_probe_payloads(run_dir, snapshot["selected"], profile=profile)
    preflight = cost_preflight(snapshot, run_dir, manifest, profile=profile)
    policy = strict_json_load(profile.run_policy)
    call_count = len(profile.expected_models)
    gate_material = {
        "gateContractVersion": profile.gate_contract,
        "reportContractVersion": profile.report_contract,
        "runID": run_id,
        "status": "awaitingHumanRatification" if preflight["admitted"] else "blockedByCostPreflight",
        "providerCalls": 0,
        "credentialRead": False,
        "spendUSD": "0.00",
        "purpose": policy["purpose"],
        **(
            {"priorEvidence": policy["priorEvidence"]}
            if profile.prior_evidence is not None
            else {}
        ),
        "scope": policy["scope"],
        "request": policy["request"],
        "routing": policy["routing"],
        "execution": policy["execution"],
        "spending": policy["spending"],
        "frozenV3ArtifactHashes": frozen["artifactHashes"],
        "configurationHashes": configuration["configurationHashes"],
        "selectedEndpoints": snapshot["selected"],
        "catalogueSnapshotSha256": sha256_file(run_dir / "catalogue" / "selected.json"),
        "curlVersion": _curl_version(),
        "mockSummarySha256": sha256_file(run_dir / "curl-mock-summary.json"),
        "probeManifestSha256": sha256_file(run_dir / "curl-probe-manifest.json"),
        "probeManifest": manifest,
        "costPreflight": preflight,
        "diagnosticTransport": profile.diagnostic_transport,
        **(
            {"diagnosticToolName": policy["request"]["forcedToolName"]}
            if profile.diagnostic_transport == "forcedToolArguments"
            else {}
        ),
        "diagnosticExpectedOutput": {"ok": True},
        "requiredBeforeLive": [
            f"human-ratifies-this-complete-{call_count}-call-curl-gate",
            "local-OPENROUTER_API_KEY-is-available",
            f"human-explicitly-authorizes-{call_count}-provider-calls-and-zero-point-two-five-dollar-cap",
        ],
    }
    phrase = (
        profile.authorization_prefix + canonical_hash(gate_material)[:16].upper()
        if preflight["admitted"]
        else None
    )
    gate = dict(gate_material, authorizationPhrase=phrase)
    write_json(run_dir / "operator-gate.json", gate)
    return gate


def _validate_authorization(
    gate: dict[str, Any], authorization: str, *, profile: ProbeProfile
) -> None:
    if authorization != gate.get("authorizationPhrase"):
        raise RuntimeError("exact run-specific open-weight curl authorization is missing")
    material = dict(gate)
    material.pop("authorizationPhrase", None)
    expected = profile.authorization_prefix + canonical_hash(material)[:16].upper()
    if authorization != expected:
        raise RuntimeError("open-weight curl gate changed after authorization was sealed")


def _prices_do_not_increase(
    gated: list[dict[str, Any]], current: list[dict[str, Any]]
) -> None:
    gated_by_model = {item["requestedModelID"]: item for item in gated}
    for endpoint in current:
        before = gated_by_model[endpoint["requestedModelID"]]
        for key in ("inputPricePerToken", "outputPricePerToken"):
            if Decimal(endpoint[key]) > Decimal(before[key]):
                raise RuntimeError(
                    f"live catalogue {key} increased for {endpoint['requestedModelID']}"
                )


async def run_live(
    *,
    run_id: str,
    authorization: str,
    spending_limit_usd: str,
    profile: ProbeProfile = INITIAL_PROFILE,
) -> dict[str, Any]:
    run_dir = safe_run_dir(run_id, create=False)
    gate = strict_json_load(run_dir / "operator-gate.json")
    if gate.get("gateContractVersion") != profile.gate_contract:
        raise RuntimeError("operator gate is not the open-weight v4 curl-probe gate")
    if gate.get("status") != "awaitingHumanRatification":
        raise RuntimeError("open-weight curl-probe gate is not awaiting ratification")
    _validate_authorization(gate, authorization, profile=profile)
    if spending_limit_usd != "0.25" or gate["costPreflight"]["hardLimitUSD"] != "0.25":
        raise RuntimeError("open-weight curl-probe spending limit must be exactly 0.25 USD")
    configuration = verify_configuration(profile=profile)
    if configuration["status"] != "valid" or configuration["configurationHashes"] != gate["configurationHashes"]:
        raise RuntimeError("open-weight curl-probe configuration differs from the ratified gate")
    verify_prior_evidence(profile)
    frozen = verify_v3()
    if frozen["status"] != "valid" or frozen["artifactHashes"] != gate["frozenV3ArtifactHashes"]:
        raise RuntimeError("frozen v3 artifacts differ from the ratified curl gate")
    if (run_dir / "curl-live-state.json").exists():
        raise RuntimeError("this non-resumable open-weight curl-probe run already entered live execution")
    if _curl_version() != gate["curlVersion"]:
        raise RuntimeError("curl version changed after the open-weight operator gate")
    manifest = strict_json_load(run_dir / "curl-probe-manifest.json")
    if manifest != gate["probeManifest"]:
        raise RuntimeError("open-weight curl-probe manifest changed after the operator gate")
    if sha256_file(run_dir / "curl-probe-manifest.json") != gate["probeManifestSha256"]:
        raise RuntimeError("open-weight curl-probe manifest hash changed")
    for probe in manifest:
        if sha256_file(run_dir / probe["payloadPath"]) != probe["payloadSha256"]:
            raise RuntimeError(f"curl payload changed for {probe['attemptID']}")

    specs = load_model_specs(profile.models)
    live_snapshot = snapshot_catalogue(
        run_dir / "live-catalogue",
        specs,
        required_parameters=_required_parameters(profile),
        allow_equivalent_duplicate_tags=(
            profile.diagnostic_transport == "forcedToolArguments"
        ),
    )
    compare_catalogues(gate["selectedEndpoints"], live_snapshot["selected"])
    _prices_do_not_increase(gate["selectedEndpoints"], live_snapshot["selected"])
    live_preflight = cost_preflight(live_snapshot, run_dir, manifest, profile=profile)
    if not live_preflight["admitted"]:
        raise RuntimeError("current prices no longer fit the open-weight curl-probe spending limit")

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is absent from the local unshared environment")
    write_json(
        run_dir / "operator-ratification.json",
        {
            "runID": run_id,
            "ratifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorizationPhrase": authorization,
            "spendingLimitUSD": spending_limit_usd,
            "providerCallLimit": len(profile.expected_models),
            "developmentCalls": 0,
            "heldoutCalls": 0,
            "credentialAvailable": True,
            "credentialPersisted": False,
            "liveCatalogueSha256": sha256_file(run_dir / "live-catalogue" / "selected.json"),
            "liveCostPreflight": live_preflight,
        },
    )
    runner = CurlProbeRun(
        run_dir=run_dir,
        gate=dict(gate, selectedEndpoints=live_snapshot["selected"]),
        api_key=api_key,
        execution_policy=gate["execution"],
        spending_limit_usd="0.25",
    )
    try:
        return await runner.execute()
    finally:
        runner.api_key = ""
        api_key = ""
