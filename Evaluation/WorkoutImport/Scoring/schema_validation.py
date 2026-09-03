"""Small deterministic validator for the JSON Schema subset used by issue #12.

This module deliberately has no network lookup and no third-party dependency. It
supports only the keywords used by the checked-in v1 contracts and rejects an
unknown keyword so schema evolution cannot silently weaken validation.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
import re
from typing import Any, Mapping


@dataclass(frozen=True)
class ValidationProblem:
    path: str
    message: str


class SchemaContractError(ValueError):
    """Raised when a checked-in schema uses an unsupported construct."""


_ANNOTATION_KEYWORDS = {"$schema", "$id", "title", "description"}
_VALIDATION_KEYWORDS = {
    "$ref",
    "$defs",
    "type",
    "required",
    "properties",
    "additionalProperties",
    "items",
    "minItems",
    "uniqueItems",
    "minLength",
    "pattern",
    "minimum",
    "exclusiveMinimum",
    "enum",
    "const",
    "oneOf",
}


def validate_instance(
    instance: Any,
    schema: Mapping[str, Any],
    registry: Mapping[str, Mapping[str, Any]],
) -> list[ValidationProblem]:
    """Return every deterministic validation problem for an instance."""

    _check_schema_keywords(schema, "$schema")
    return _validate(instance, schema, registry, schema, "$")


def assert_schema_supported(schema: Mapping[str, Any]) -> None:
    """Validate every nested schema before it is used for evidence."""

    _walk_schema(schema, "$schema")


def _walk_schema(schema: Any, path: str) -> None:
    if not isinstance(schema, dict):
        raise SchemaContractError(f"{path} must be an object")
    _check_schema_keywords(schema, path)
    for key in ("properties", "$defs"):
        for name, child in schema.get(key, {}).items():
            _walk_schema(child, f"{path}.{key}.{name}")
    if isinstance(schema.get("items"), dict):
        _walk_schema(schema["items"], f"{path}.items")
    for index, child in enumerate(schema.get("oneOf", [])):
        _walk_schema(child, f"{path}.oneOf[{index}]")
    additional = schema.get("additionalProperties")
    if isinstance(additional, dict):
        _walk_schema(additional, f"{path}.additionalProperties")


def _check_schema_keywords(schema: Mapping[str, Any], path: str) -> None:
    unknown = set(schema) - _ANNOTATION_KEYWORDS - _VALIDATION_KEYWORDS
    if unknown:
        joined = ", ".join(sorted(unknown))
        raise SchemaContractError(f"{path} uses unsupported keyword(s): {joined}")


def _validate(
    instance: Any,
    schema: Mapping[str, Any],
    registry: Mapping[str, Mapping[str, Any]],
    root_schema: Mapping[str, Any],
    path: str,
) -> list[ValidationProblem]:
    _check_schema_keywords(schema, path)

    if "$ref" in schema:
        target, target_root = _resolve_ref(schema["$ref"], registry, root_schema)
        return _validate(instance, target, registry, target_root, path)

    if "oneOf" in schema:
        branches = [
            _validate(instance, child, registry, root_schema, path)
            for child in schema["oneOf"]
        ]
        matches = sum(not problems for problems in branches)
        if matches != 1:
            return [
                ValidationProblem(
                    path,
                    f"must match exactly one oneOf branch; matched {matches}",
                )
            ]

    problems: list[ValidationProblem] = []
    if "const" in schema and instance != schema["const"]:
        problems.append(ValidationProblem(path, f"must equal {schema['const']!r}"))
    if "enum" in schema and instance not in schema["enum"]:
        problems.append(ValidationProblem(path, "must be one of the declared values"))

    expected_type = schema.get("type")
    if expected_type is not None and not _matches_type(instance, expected_type):
        return problems + [ValidationProblem(path, f"must have type {expected_type}")]

    if expected_type == "object":
        required = schema.get("required", [])
        for name in required:
            if name not in instance:
                problems.append(ValidationProblem(path, f"missing required property {name!r}"))
        properties = schema.get("properties", {})
        for name, value in instance.items():
            child_path = f"{path}.{name}"
            if name in properties:
                problems.extend(
                    _validate(value, properties[name], registry, root_schema, child_path)
                )
            elif schema.get("additionalProperties") is False:
                problems.append(ValidationProblem(child_path, "additional property is not allowed"))
            elif isinstance(schema.get("additionalProperties"), dict):
                problems.extend(
                    _validate(
                        value,
                        schema["additionalProperties"],
                        registry,
                        root_schema,
                        child_path,
                    )
                )

    if expected_type == "array":
        if len(instance) < schema.get("minItems", 0):
            problems.append(ValidationProblem(path, "contains fewer than minItems"))
        if schema.get("uniqueItems") and not _items_are_unique(instance):
            problems.append(ValidationProblem(path, "items must be unique"))
        item_schema = schema.get("items")
        if item_schema:
            for index, value in enumerate(instance):
                problems.extend(
                    _validate(
                        value,
                        item_schema,
                        registry,
                        root_schema,
                        f"{path}[{index}]",
                    )
                )

    if expected_type == "string":
        if len(instance) < schema.get("minLength", 0):
            problems.append(ValidationProblem(path, "is shorter than minLength"))
        pattern = schema.get("pattern")
        if pattern is not None and re.fullmatch(pattern, instance) is None:
            problems.append(ValidationProblem(path, f"does not match pattern {pattern!r}"))

    if expected_type in {"integer", "number"}:
        if "minimum" in schema and instance < _number(schema["minimum"]):
            problems.append(ValidationProblem(path, "is below minimum"))
        if "exclusiveMinimum" in schema and instance <= _number(schema["exclusiveMinimum"]):
            problems.append(ValidationProblem(path, "is not above exclusiveMinimum"))

    return problems


def _resolve_ref(
    reference: str,
    registry: Mapping[str, Mapping[str, Any]],
    current_root: Mapping[str, Any],
) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    document, separator, fragment = reference.partition("#")
    root = current_root if not document else registry.get(document)
    if root is None:
        raise SchemaContractError(f"unresolved schema reference {reference!r}")
    target: Any = root
    if separator and fragment:
        if not fragment.startswith("/"):
            raise SchemaContractError(f"unsupported schema fragment {reference!r}")
        for encoded_part in fragment[1:].split("/"):
            part = encoded_part.replace("~1", "/").replace("~0", "~")
            if not isinstance(target, dict) or part not in target:
                raise SchemaContractError(f"unresolved schema fragment {reference!r}")
            target = target[part]
    if not isinstance(target, dict):
        raise SchemaContractError(f"schema reference {reference!r} is not an object")
    return target, root


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return not isinstance(value, bool) and isinstance(value, (int, Decimal)) and value % 1 == 0
    if expected == "number":
        return not isinstance(value, bool) and isinstance(value, (int, float, Decimal))
    if expected == "null":
        return value is None
    raise SchemaContractError(f"unsupported JSON Schema type {expected!r}")


def _number(value: Any) -> Decimal:
    return value if isinstance(value, Decimal) else Decimal(str(value))


def _items_are_unique(values: list[Any]) -> bool:
    for index, value in enumerate(values):
        if value in values[:index]:
            return False
    return True
