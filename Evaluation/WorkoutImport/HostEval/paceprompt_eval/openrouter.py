"""Inspect AI/OpenRouter configuration with an offline wire-payload capture."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
from types import MethodType
from typing import Any

import httpx2
from inspect_ai.model import (
    ChatMessage,
    GenerateConfig,
    Model,
    ModelOutput,
    ResponseSchema,
    get_model,
)


OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
MODEL_OUTPUT_SCHEMA_NAME = "paceprompt_workout_import_transport_v2_3"
MOCK_API_KEY = "paceprompt-mock-key-never-live"


class CapturedGenerationError(RuntimeError):
    def __init__(self, cause: BaseException, exchange: dict[str, Any]) -> None:
        super().__init__(str(cause))
        self.cause_type = type(cause).__name__
        self.exchange = exchange


@dataclass(frozen=True)
class ModelSpec:
    requested_model_id: str
    canonical_revision: str | None
    provider_endpoint: str
    quantization: str | None
    role: str
    temperature: float | None
    top_p: float | None
    reasoning: dict[str, Any] | None
    transport_strategy_id: str | None = None
    transport_registry_id: str | None = None

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "ModelSpec":
        return cls(
            requested_model_id=value["requestedModelID"],
            canonical_revision=value["canonicalRevision"],
            provider_endpoint=value["providerEndpoint"],
            quantization=value["quantization"],
            role=value["role"],
            temperature=value["temperature"],
            top_p=value["topP"],
            reasoning=value["reasoning"],
            transport_strategy_id=value.get("transportStrategy"),
            transport_registry_id=value.get("transportRegistry"),
        )


def load_model_specs(path: Path) -> tuple[ModelSpec, ...]:
    document = json.loads(path.read_text(encoding="utf-8"))
    return tuple(ModelSpec.from_json(value) for value in document["models"])


def provider_controls(
    spec: ModelSpec, max_price_per_million: dict[str, float] | None = None
) -> dict[str, Any]:
    controls: dict[str, Any] = {
        "order": [spec.provider_endpoint],
        "only": [spec.provider_endpoint],
        "allow_fallbacks": False,
        "require_parameters": True,
        "data_collection": "deny",
    }
    if spec.quantization is not None:
        controls["quantizations"] = [spec.quantization]
    if max_price_per_million is not None:
        controls["max_price"] = max_price_per_million
    return controls


def configure_http_environment() -> None:
    """Apply the frozen timeouts and remove Inspect/httpcore retries."""

    exact = {
        "INSPECT_HTTP_CONNECT_TIMEOUT": "15",
        "INSPECT_HTTP_REQUEST_TIMEOUT": "180",
        "INSPECT_HTTP_CONNECT_RETRIES": "0",
    }
    for name, value in exact.items():
        existing = os.environ.get(name)
        if existing is not None and existing != value:
            raise RuntimeError(f"{name} must be {value}, not {existing}")
        os.environ[name] = value


def generation_config(
    spec: ModelSpec,
    schema: dict[str, Any],
    schema_name: str = MODEL_OUTPUT_SCHEMA_NAME,
) -> GenerateConfig:
    reasoning = spec.reasoning or {}
    return GenerateConfig(
        max_retries=0,
        timeout=180,
        attempt_timeout=180,
        max_connections=1,
        adaptive_connections=False,
        max_tokens=8192,
        temperature=spec.temperature,
        top_p=spec.top_p,
        reasoning_effort=reasoning.get("effort"),
        response_schema=ResponseSchema(
            name=schema_name,
            description="One untrusted PacePrompt workout-import outcome.",
            json_schema=schema,
            strict=True,
        ),
        cache=False,
        cache_prompt=False,
    )


def build_model(
    spec: ModelSpec,
    schema: dict[str, Any],
    api_key: str,
    *,
    http_client: httpx2.AsyncClient | None = None,
    max_price_per_million: dict[str, float] | None = None,
    schema_name: str = MODEL_OUTPUT_SCHEMA_NAME,
) -> Model:
    configure_http_environment()
    config = generation_config(spec, schema, schema_name)
    reasoning = spec.reasoning

    async def enforce_timeout(request: httpx2.Request) -> None:
        request.extensions["timeout"] = {
            "connect": 15.0,
            "read": 180.0,
            "write": 180.0,
            "pool": 180.0,
        }

    if http_client is None:
        http_client = httpx2.AsyncClient(
            timeout=httpx2.Timeout(180.0, connect=15.0),
            transport=httpx2.AsyncHTTPTransport(retries=0),
            follow_redirects=True,
            event_hooks={"request": [enforce_timeout], "response": []},
        )
    else:
        http_client.event_hooks["request"].insert(0, enforce_timeout)
    model_args: dict[str, Any] = {
        "provider": provider_controls(spec, max_price_per_million),
        "stream": False,
        "http_client": http_client,
        "max_retries": 0,
    }
    if reasoning is not None:
        model_args["reasoning_enabled"] = reasoning["enabled"]
    model = get_model(
        f"openrouter/{spec.requested_model_id}",
        api_key=api_key,
        config=config,
        memoize=False,
        **model_args,
    )
    original = model.api.completion_params

    def completion_params(self: Any, config: GenerateConfig, tools: bool) -> dict[str, Any]:
        params = original(config, tools)
        if spec.requested_model_id in {"openai/gpt-5.6-sol", "openai/gpt-5.6-luna"}:
            if "max_completion_tokens" in params:
                params["max_tokens"] = params.pop("max_completion_tokens")
        params["response_format"] = {
            "type": "json_schema",
            "json_schema": {
                "name": schema_name,
                "description": "One untrusted PacePrompt workout-import outcome.",
                "schema": deepcopy(schema),
                "strict": True,
            },
        }
        if not (reasoning and reasoning.get("exclude")):
            return params
        extra_body = params.setdefault("extra_body", {})
        reasoning_body = extra_body.setdefault("reasoning", {})
        reasoning_body["exclude"] = True
        return params

    model.api.completion_params = MethodType(completion_params, model.api)
    return model


async def generate_with_capture(
    spec: ModelSpec,
    schema: dict[str, Any],
    messages: list[ChatMessage],
    api_key: str,
    *,
    transport: httpx2.AsyncBaseTransport | None = None,
    max_price_per_million: dict[str, float] | None = None,
    schema_name: str = MODEL_OUTPUT_SCHEMA_NAME,
) -> tuple[ModelOutput, dict[str, Any]]:
    """Generate once through Inspect while retaining the exact HTTP exchange."""

    exchanges: dict[str, list[dict[str, Any]]] = {"requests": [], "responses": []}

    async def capture_request(request: httpx2.Request) -> None:
        body = await request.aread()
        exchanges["requests"].append(
            {
                "method": request.method,
                "url": str(request.url),
                "headers": dict(request.headers),
                "timeout": dict(request.extensions.get("timeout", {})),
                "body": json.loads(body.decode("utf-8")),
            }
        )

    async def capture_response(response: httpx2.Response) -> None:
        body = await response.aread()
        try:
            decoded: Any = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            decoded = {"undecodableUtf8ByteCount": len(body)}
        exchanges["responses"].append(
            {
                "statusCode": response.status_code,
                "headers": dict(response.headers),
                "body": decoded,
            }
        )

    async with httpx2.AsyncClient(
        timeout=httpx2.Timeout(180.0, connect=15.0),
        transport=transport or httpx2.AsyncHTTPTransport(retries=0),
        follow_redirects=True,
        event_hooks={"request": [capture_request], "response": [capture_response]},
    ) as client:
        model = build_model(
            spec,
            schema,
            api_key,
            http_client=client,
            max_price_per_million=max_price_per_million,
            schema_name=schema_name,
        )
        try:
            output = await model.generate(messages, tool_choice="none")
        except BaseException as error:
            raise CapturedGenerationError(error, redact(exchanges, (api_key,))) from error
        finally:
            await model.api.aclose()
    if len(exchanges["requests"]) != 1 or len(exchanges["responses"]) != 1:
        raise RuntimeError(
            "one-attempt/no-retry invariant failed: "
            f"{len(exchanges['requests'])} requests, {len(exchanges['responses'])} responses"
        )
    return output, redact(exchanges, (api_key,))


async def capture_wire_payload(
    spec: ModelSpec,
    schema: dict[str, Any],
    messages: list[ChatMessage],
    *,
    max_price_per_million: dict[str, float] | None = None,
    schema_name: str = MODEL_OUTPUT_SCHEMA_NAME,
    mock_response: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Exercise Inspect and the OpenAI client against a local mock transport."""

    captured: dict[str, Any] = {}
    response_content = json.dumps(
        mock_response
        or {
            "contractVersion": "workout-import-model-output/v2",
            "outcome": {
                "type": "refusal",
                "reasonCategory": "promptInjection",
                "affectedPaths": [],
                "proposal": {
                    "present": False,
                    "contractVersion": "notApplicable",
                    "suggestedName": "",
                    "activity": "notApplicable",
                    "steps": [],
                },
            },
        },
        separators=(",", ":"),
    )

    async def handler(request: httpx2.Request) -> httpx2.Response:
        captured["method"] = request.method
        captured["url"] = str(request.url)
        captured["headers"] = dict(request.headers)
        captured["timeout"] = dict(request.extensions.get("timeout", {}))
        captured["body"] = json.loads((await request.aread()).decode("utf-8"))
        return httpx2.Response(
            200,
            request=request,
            json={
                "id": "mock-generation",
                "object": "chat.completion",
                "created": 0,
                "model": spec.canonical_revision or spec.requested_model_id,
                "provider": spec.provider_endpoint,
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {"role": "assistant", "content": response_content},
                    }
                ],
                "usage": {
                    "prompt_tokens": 1,
                    "completion_tokens": 1,
                    "total_tokens": 2,
                    "cost": 0,
                },
            },
        )

    transport = httpx2.MockTransport(handler)
    async with httpx2.AsyncClient(transport=transport) as client:
        model = build_model(
            spec,
            schema,
            MOCK_API_KEY,
            http_client=client,
            max_price_per_million=max_price_per_million,
            schema_name=schema_name,
        )
        await model.generate(messages, tool_choice="none")
        await model.api.aclose()
    if not captured:
        raise RuntimeError("mock transport did not capture an outbound request")
    return redact(captured, (MOCK_API_KEY,))


def redact(value: Any, secrets: tuple[str, ...]) -> Any:
    if isinstance(value, str):
        result = value
        for secret in secrets:
            if secret:
                result = result.replace(secret, "[REDACTED]")
        result = re.sub(r"\buser_[A-Za-z0-9_-]+\b", "[REDACTED_USER_ID]", result)
        return result
    if isinstance(value, list):
        return [redact(item, secrets) for item in value]
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            normalized_key = key.casefold()
            if normalized_key == "authorization":
                scheme = "Bearer " if isinstance(item, str) and item.casefold().startswith("bearer ") else ""
                result[key] = f"{scheme}[REDACTED]"
            elif normalized_key in {"cookie", "proxy-authorization", "set-cookie", "user_id"}:
                result[key] = "[REDACTED]"
            else:
                result[key] = redact(item, secrets)
        return result
    return deepcopy(value)


def assert_payload_controls(
    payload: dict[str, Any], spec: ModelSpec, schema: dict[str, Any],
    max_price_per_million: dict[str, float] | None = None,
    schema_name: str = MODEL_OUTPUT_SCHEMA_NAME,
) -> None:
    if payload["method"] != "POST" or payload["url"] != OPENROUTER_URL:
        raise AssertionError("unexpected OpenRouter endpoint")
    body = payload["body"]
    if body["model"] != spec.requested_model_id:
        raise AssertionError("requested model changed")
    token_field = "max_completion_tokens" if "max_completion_tokens" in body else "max_tokens"
    if body[token_field] != 8192 or {"max_tokens", "max_completion_tokens"} <= set(body):
        raise AssertionError("output-token limit changed")
    if "n" in body or "seed" in body or "stop" in body:
        raise AssertionError("unratified generation control appeared")
    if spec.temperature is None:
        if "temperature" in body or "top_p" in body:
            raise AssertionError("unsupported sampling fields appeared")
    elif body.get("temperature") != 0 or body.get("top_p") != 1:
        raise AssertionError("sampling controls changed")
    if body.get("provider") != provider_controls(spec, max_price_per_million):
        raise AssertionError("provider controls changed")
    if "zdr" in body["provider"]:
        raise AssertionError("unratified ZDR control appeared")
    response_format = body.get("response_format", {})
    if response_format.get("type") != "json_schema":
        raise AssertionError("structured output is not json_schema")
    json_schema = response_format.get("json_schema", {})
    if json_schema.get("name") != schema_name:
        raise AssertionError("schema name changed")
    if json_schema.get("strict") is not True:
        raise AssertionError("schema strictness changed")
    if json_schema.get("schema") != schema:
        raise AssertionError("complete schema body changed")
    if payload.get("timeout") != {"connect": 15.0, "read": 180.0, "write": 180.0, "pool": 180.0}:
        raise AssertionError("HTTP timeout controls changed")
    if payload["headers"].get("x-stainless-retry-count") != "0":
        raise AssertionError("OpenAI client retry control changed")
    expected_reasoning = spec.reasoning
    actual_reasoning = body.get("reasoning")
    if expected_reasoning is None:
        if actual_reasoning is not None:
            raise AssertionError("reasoning unexpectedly configured")
    else:
        expected: dict[str, Any] = {}
        if expected_reasoning.get("effort") is not None:
            expected["effort"] = expected_reasoning["effort"]
        expected["enabled"] = expected_reasoning["enabled"]
        if expected_reasoning.get("exclude"):
            expected["exclude"] = True
        if actual_reasoning != expected:
            raise AssertionError(f"reasoning controls changed: {actual_reasoning!r}")
    authorization = payload["headers"].get("authorization", "")
    if MOCK_API_KEY in authorization or "bearer [redacted]" not in authorization.lower():
        raise AssertionError("authorization was not redacted")
