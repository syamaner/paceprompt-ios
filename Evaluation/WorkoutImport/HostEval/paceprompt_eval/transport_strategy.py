"""Closed provider-transport strategies for exact, repeatable model routes."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import json
from pathlib import Path
from types import MappingProxyType
from typing import Any, Callable, Mapping, Protocol

from .scorer_adapter import (
    flat_envelope_transport_output,
    normalize_flat_envelope_transport,
    normalize_provider_transport,
    normalize_semantic_json_transport,
    normalize_shallow_step_transport,
    provider_transport_output,
    semantic_json_transport_output,
    shallow_step_transport_output,
)


HOST_EVAL_ROOT = Path(__file__).resolve().parents[1]


class ModelRoute(Protocol):
    requested_model_id: str
    canonical_revision: str | None
    provider_endpoint: str
    transport_strategy_id: str | None
    transport_registry_id: str | None


class TransportStrategyID(str, Enum):
    NESTED_V2_3 = "nestedV23"
    SHALLOW_STEP_V2_7 = "shallowStepV27"
    FLAT_ENVELOPE_V2_8 = "flatEnvelopeV28"
    SEMANTIC_JSON_V2_9 = "semanticJsonV29"


class SchemaProfileID(str, Enum):
    PORTABLE_STRICT_V2_3 = "portableStrictV23"
    GOOGLE_GEMINI_MINIMAL_V2_9 = "googleGeminiMinimalV29"


@dataclass(frozen=True)
class ProviderRoute:
    requested_model_id: str
    canonical_revision: str
    provider_endpoint: str


@dataclass(frozen=True)
class ProviderSchemaProfile:
    identifier: SchemaProfileID
    allowed_keywords: frozenset[str]
    maximum_properties_per_object: int | None = None
    maximum_object_depth: int | None = None
    maximum_total_enum_values: int | None = None

    def validate(self, schema: dict[str, Any]) -> tuple[str, ...]:
        errors: list[str] = []
        total_enum_values = 0

        def walk(node: Any, path: str, object_depth: int) -> None:
            nonlocal total_enum_values
            if not isinstance(node, dict):
                return
            for keyword in node:
                if keyword not in self.allowed_keywords:
                    errors.append(f"{path} uses unsupported keyword {keyword}")
            node_type = node.get("type")
            if node_type == "object":
                depth = object_depth + 1
                if self.maximum_object_depth is not None and depth > self.maximum_object_depth:
                    errors.append(f"{path} exceeds object depth {self.maximum_object_depth}")
                properties = node.get("properties")
                if not isinstance(properties, dict):
                    errors.append(f"{path} object has no properties object")
                    properties = {}
                if (
                    self.maximum_properties_per_object is not None
                    and len(properties) > self.maximum_properties_per_object
                ):
                    errors.append(
                        f"{path} has {len(properties)} properties; maximum is "
                        f"{self.maximum_properties_per_object}"
                    )
                if node.get("additionalProperties") is not False:
                    errors.append(f"{path} object is not closed")
                required = node.get("required")
                if not isinstance(required, list) or set(required) != set(properties):
                    errors.append(f"{path} does not require every declared property exactly")
                for name, child in properties.items():
                    walk(child, f"{path}.properties.{name}", depth)
            elif node_type == "array":
                walk(node.get("items"), f"{path}.items", object_depth)
            enum = node.get("enum")
            if isinstance(enum, list):
                total_enum_values += len(enum)

        walk(schema, "$", 0)
        if (
            self.maximum_total_enum_values is not None
            and total_enum_values > self.maximum_total_enum_values
        ):
            errors.append(
                f"schema has {total_enum_values} enum values; maximum is "
                f"{self.maximum_total_enum_values}"
            )
        return tuple(errors)

    def require_valid(self, schema: dict[str, Any]) -> None:
        errors = self.validate(schema)
        if errors:
            raise ValueError(f"{self.identifier.value}: {'; '.join(errors)}")


PROVIDER_SCHEMA_PROFILES: Mapping[SchemaProfileID, ProviderSchemaProfile] = (
    MappingProxyType(
        {
            SchemaProfileID.PORTABLE_STRICT_V2_3: ProviderSchemaProfile(
                identifier=SchemaProfileID.PORTABLE_STRICT_V2_3,
                allowed_keywords=frozenset(
                    {
                        "type",
                        "description",
                        "required",
                        "properties",
                        "items",
                        "enum",
                        "additionalProperties",
                        "maxItems",
                    }
                ),
            ),
            SchemaProfileID.GOOGLE_GEMINI_MINIMAL_V2_9: ProviderSchemaProfile(
                identifier=SchemaProfileID.GOOGLE_GEMINI_MINIMAL_V2_9,
                allowed_keywords=frozenset(
                    {"type", "required", "properties", "additionalProperties"}
                ),
                maximum_properties_per_object=1,
                maximum_object_depth=1,
                maximum_total_enum_values=0,
            ),
        }
    )
)


@dataclass(frozen=True)
class ProviderTransportStrategy:
    identifier: TransportStrategyID
    schema_name: str
    schema_path: Path
    project_output: Callable[[dict[str, Any]], dict[str, Any]]
    normalize_output: Callable[[dict[str, Any]], dict[str, Any]]
    schema_profile: ProviderSchemaProfile

    def schema(self) -> dict[str, Any]:
        schema = _strict_json_load(self.schema_path)
        self.schema_profile.require_valid(schema)
        return schema

    def schema_file_bytes(self) -> int:
        return len(self.schema_path.read_bytes())


def _strict_json_load(path: Path) -> dict[str, Any]:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate key {key!r} in {path}")
            result[key] = value
        return result

    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain an object")
    return value


STRATEGIES: Mapping[TransportStrategyID, ProviderTransportStrategy] = MappingProxyType(
    {
        TransportStrategyID.NESTED_V2_3: ProviderTransportStrategy(
            identifier=TransportStrategyID.NESTED_V2_3,
            schema_name="paceprompt_workout_import_transport_v2_3",
            schema_path=HOST_EVAL_ROOT
            / "schemas"
            / "v2.3"
            / "workout-import-provider-transport-v2.3.schema.json",
            project_output=provider_transport_output,
            normalize_output=normalize_provider_transport,
            schema_profile=PROVIDER_SCHEMA_PROFILES[
                SchemaProfileID.PORTABLE_STRICT_V2_3
            ],
        ),
        TransportStrategyID.SHALLOW_STEP_V2_7: ProviderTransportStrategy(
            identifier=TransportStrategyID.SHALLOW_STEP_V2_7,
            schema_name="paceprompt_workout_import_transport_shallow_step_v2_7",
            schema_path=HOST_EVAL_ROOT
            / "schemas"
            / "v2.7"
            / "workout-import-provider-transport-shallow-step-v2.7.schema.json",
            project_output=shallow_step_transport_output,
            normalize_output=normalize_shallow_step_transport,
            schema_profile=PROVIDER_SCHEMA_PROFILES[
                SchemaProfileID.PORTABLE_STRICT_V2_3
            ],
        ),
        TransportStrategyID.FLAT_ENVELOPE_V2_8: ProviderTransportStrategy(
            identifier=TransportStrategyID.FLAT_ENVELOPE_V2_8,
            schema_name="paceprompt_workout_import_transport_flat_envelope_v2_8",
            schema_path=HOST_EVAL_ROOT
            / "schemas"
            / "v2.8"
            / "workout-import-provider-transport-flat-envelope-v2.8.schema.json",
            project_output=flat_envelope_transport_output,
            normalize_output=normalize_flat_envelope_transport,
            schema_profile=PROVIDER_SCHEMA_PROFILES[
                SchemaProfileID.PORTABLE_STRICT_V2_3
            ],
        ),
        TransportStrategyID.SEMANTIC_JSON_V2_9: ProviderTransportStrategy(
            identifier=TransportStrategyID.SEMANTIC_JSON_V2_9,
            schema_name="paceprompt_workout_import_transport_semantic_json_v2_9",
            schema_path=HOST_EVAL_ROOT
            / "schemas"
            / "v2.9"
            / "workout-import-provider-transport-semantic-json-v2.9.schema.json",
            project_output=semantic_json_transport_output,
            normalize_output=normalize_semantic_json_transport,
            schema_profile=PROVIDER_SCHEMA_PROFILES[
                SchemaProfileID.GOOGLE_GEMINI_MINIMAL_V2_9
            ],
        ),
    }
)


V2_7_REGISTRY_ID = "strategyRegistryV27"
V2_8_REGISTRY_ID = "strategyRegistryV28"
V2_9_REGISTRY_ID = "strategyRegistryV29"


V2_7_ROUTE_STRATEGIES: Mapping[ProviderRoute, TransportStrategyID] = MappingProxyType(
    {
        ProviderRoute(
            "openai/gpt-5.6-sol", "openai/gpt-5.6-sol-20260709", "openai"
        ): TransportStrategyID.NESTED_V2_3,
        ProviderRoute(
            "anthropic/claude-sonnet-5",
            "anthropic/claude-sonnet-5-20260630",
            "anthropic",
        ): TransportStrategyID.NESTED_V2_3,
        ProviderRoute(
            "openai/gpt-5.6-luna", "openai/gpt-5.6-luna-20260709", "openai"
        ): TransportStrategyID.NESTED_V2_3,
        ProviderRoute(
            "google/gemini-3.5-flash-lite",
            "google/gemini-3.5-flash-lite-20260721",
            "google-ai-studio",
        ): TransportStrategyID.SHALLOW_STEP_V2_7,
        ProviderRoute(
            "google/gemini-3.7-flash",
            "google/gemini-3.7-flash-20260813",
            "google-ai-studio",
        ): TransportStrategyID.SHALLOW_STEP_V2_7,
    }
)


V2_8_ROUTE_STRATEGIES: Mapping[ProviderRoute, TransportStrategyID] = MappingProxyType(
    {
        route: (
            TransportStrategyID.FLAT_ENVELOPE_V2_8
            if strategy_id is TransportStrategyID.SHALLOW_STEP_V2_7
            else strategy_id
        )
        for route, strategy_id in V2_7_ROUTE_STRATEGIES.items()
    }
)


V2_9_ROUTE_STRATEGIES: Mapping[ProviderRoute, TransportStrategyID] = MappingProxyType(
    {
        route: (
            TransportStrategyID.SEMANTIC_JSON_V2_9
            if strategy_id is TransportStrategyID.FLAT_ENVELOPE_V2_8
            else strategy_id
        )
        for route, strategy_id in V2_8_ROUTE_STRATEGIES.items()
    }
)


ROUTE_STRATEGY_REGISTRIES: Mapping[
    str, Mapping[ProviderRoute, TransportStrategyID]
] = MappingProxyType(
    {
        V2_7_REGISTRY_ID: V2_7_ROUTE_STRATEGIES,
        V2_8_REGISTRY_ID: V2_8_ROUTE_STRATEGIES,
        V2_9_REGISTRY_ID: V2_9_ROUTE_STRATEGIES,
    }
)


def strategy_for(route: ModelRoute) -> ProviderTransportStrategy:
    if route.canonical_revision is None:
        raise ValueError(f"{route.requested_model_id} has no canonical revision")
    key = ProviderRoute(
        route.requested_model_id,
        route.canonical_revision,
        route.provider_endpoint,
    )
    registry_id = getattr(route, "transport_registry_id", None) or V2_7_REGISTRY_ID
    try:
        registry = ROUTE_STRATEGY_REGISTRIES[registry_id]
    except KeyError as error:
        raise ValueError(f"unknown provider-transport registry {registry_id}") from error
    try:
        strategy_id = registry[key]
    except KeyError as error:
        raise ValueError(
            "no provider-transport strategy for exact route "
            f"{key.requested_model_id}/{key.canonical_revision}/{key.provider_endpoint}"
        ) from error
    declared = route.transport_strategy_id
    if declared is not None and declared != strategy_id.value:
        raise ValueError(
            f"{route.requested_model_id} declares {declared}, registry requires {strategy_id.value}"
        )
    return STRATEGIES[strategy_id]
