"""Read-only OpenRouter catalogue snapshot and conservative cost preflight."""

from __future__ import annotations

from decimal import Decimal
import hashlib
import json
from pathlib import Path
from typing import Any, Callable
from urllib.request import Request, urlopen

from .openrouter import ModelSpec


MODELS_URL = "https://openrouter.ai/api/v1/models"


def endpoint_url(canonical_revision: str) -> str:
    return f"https://openrouter.ai/api/v1/models/{canonical_revision}/endpoints"


def fetch_json(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "PacePrompt-HostEval/2 catalogue-only"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def snapshot_catalogue(
    directory: Path,
    specs: tuple[ModelSpec, ...],
    *,
    fetch: Callable[[str], bytes] = fetch_json,
) -> dict[str, Any]:
    directory.mkdir(parents=True, exist_ok=False)
    models_raw = fetch(MODELS_URL)
    (directory / "models.json").write_bytes(models_raw)
    model_document = json.loads(models_raw)
    by_id = {item["id"]: item for item in model_document["data"]}
    selected: list[dict[str, Any]] = []
    for spec in specs:
        current = by_id.get(spec.requested_model_id)
        if current is None:
            raise RuntimeError(f"catalogue does not contain {spec.requested_model_id}")
        current_revision = current.get("canonical_slug")
        if spec.canonical_revision is not None and current_revision != spec.canonical_revision:
            raise RuntimeError(
                f"canonical revision changed for {spec.requested_model_id}: {current_revision}"
            )
        revision_for_endpoint = spec.canonical_revision or current_revision
        raw = fetch(endpoint_url(revision_for_endpoint))
        endpoint_path = directory / (spec.requested_model_id.replace("/", "--") + ".json")
        endpoint_path.write_bytes(raw)
        endpoint_document = json.loads(raw)
        matches = [
            endpoint
            for endpoint in endpoint_document["data"]["endpoints"]
            if endpoint.get("tag") == spec.provider_endpoint
        ]
        if len(matches) != 1:
            raise RuntimeError(
                f"expected one endpoint tag {spec.provider_endpoint} for {spec.requested_model_id}, found {len(matches)}"
            )
        endpoint = matches[0]
        parameters = set(endpoint.get("supported_parameters", []))
        required = {"max_tokens", "response_format", "structured_outputs"}
        if spec.temperature is not None:
            required.update({"temperature", "top_p"})
        if spec.reasoning is not None:
            required.add("reasoning")
        missing = sorted(required - parameters)
        if missing:
            raise RuntimeError(
                f"endpoint {spec.provider_endpoint} lacks required parameters for {spec.requested_model_id}: {missing}"
            )
        reported_quantization = endpoint.get("quantization")
        if spec.quantization is not None and reported_quantization != spec.quantization:
            raise RuntimeError(f"quantization changed for {spec.requested_model_id}")
        pricing = endpoint.get("pricing", {})
        if "prompt" not in pricing or "completion" not in pricing:
            raise RuntimeError(f"endpoint pricing incomplete for {spec.requested_model_id}")
        selected.append(
            {
                "requestedModelID": spec.requested_model_id,
                "canonicalRevision": current_revision,
                "configuredCanonicalRevision": spec.canonical_revision,
                "providerEndpoint": spec.provider_endpoint,
                "reportedProviderName": endpoint.get("provider_name"),
                "configuredQuantization": spec.quantization,
                "reportedQuantization": reported_quantization or "unreported",
                "inputPricePerToken": pricing["prompt"],
                "outputPricePerToken": pricing["completion"],
                "supportedParameters": sorted(parameters),
                "status": endpoint.get("status"),
                "rawEndpointSha256": hashlib.sha256(raw).hexdigest(),
            }
        )
    snapshot = {
        "snapshotContractVersion": "paceprompt-openrouter-catalogue-snapshot/v2",
        "modelsURL": MODELS_URL,
        "modelsSha256": hashlib.sha256(models_raw).hexdigest(),
        "selected": selected,
    }
    (directory / "selected.json").write_text(
        json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return snapshot


def conservative_call_cost(
    *,
    input_utf8_bytes: int,
    input_price: str,
    output_price: str,
    output_tokens: int = 8192,
) -> Decimal:
    # Byte count is a conservative upper bound for text tokens with byte-fallback
    # tokenizers. The fixed 4,096-token allowance covers request framing/schema
    # overhead beyond the serialized message text.
    input_upper_bound = Decimal(input_utf8_bytes + 4096)
    if output_tokens <= 0 or output_tokens > 8192:
        raise ValueError("output token estimate must be between 1 and the 8,192 hard cap")
    return input_upper_bound * Decimal(input_price) + Decimal(output_tokens) * Decimal(output_price)


def choose_repetitions(
    *, five_repetition_worst_case: Decimal, one_repetition_worst_case: Decimal
) -> int:
    limit = Decimal("20.00")
    if five_repetition_worst_case <= limit:
        return 5
    if one_repetition_worst_case <= limit:
        return 1
    return 0
