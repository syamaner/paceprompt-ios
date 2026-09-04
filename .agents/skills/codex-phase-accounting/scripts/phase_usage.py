#!/usr/bin/env python3
"""Reproducible accounting for one explicitly selected Codex session JSONL."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import json
from pathlib import Path
import sys
from typing import Any, Sequence


SCHEMA_VERSION = 1
REQUIRED_COUNTER_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "output_tokens",
    "total_tokens",
)
OPTIONAL_COUNTER_FIELDS = (
    "cache_write_input_tokens",
    "reasoning_output_tokens",
)


class AccountingError(ValueError):
    """An actionable session, boundary, counter or pricing error."""


@dataclass(frozen=True)
class Counter:
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int
    total_tokens: int
    cache_write_input_tokens: int | None = None
    reasoning_output_tokens: int | None = None

    @property
    def uncached_input_tokens(self) -> int:
        return self.input_tokens - self.cached_input_tokens

    @property
    def standard_uncached_input_tokens(self) -> int | None:
        if self.cache_write_input_tokens is None:
            return None
        return self.uncached_input_tokens - self.cache_write_input_tokens

    def as_dict(self) -> dict[str, int | None]:
        return {
            "input_tokens": self.input_tokens,
            "cached_input_tokens": self.cached_input_tokens,
            "uncached_input_tokens": self.uncached_input_tokens,
            "cache_write_input_tokens": self.cache_write_input_tokens,
            "standard_uncached_input_tokens": self.standard_uncached_input_tokens,
            "output_tokens": self.output_tokens,
            "reasoning_output_tokens": self.reasoning_output_tokens,
            "total_tokens": self.total_tokens,
        }


@dataclass(frozen=True)
class TokenEvent:
    ordinal: int
    line_number: int
    timestamp: str | None
    total: Counter
    request: Counter | None
    repeated_snapshot_last_total_tokens: int | None = None
    exact_replay_of: int | None = None
    info_fingerprint: str = ""


@dataclass(frozen=True)
class Session:
    path: Path
    session_id: str
    models: tuple[str, ...]
    token_events: tuple[TokenEvent, ...]


@dataclass(frozen=True)
class Baseline:
    session_id: str
    token_count_event: int
    timestamp: str | None
    counters: Counter


def _is_integer(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def nonempty_argument(value: str) -> str:
    if not value.strip():
        raise argparse.ArgumentTypeError("value must not be empty")
    return value


def parse_counter(value: object, *, label: str) -> Counter:
    if not isinstance(value, dict):
        raise AccountingError(f"{label} must be a JSON object")

    missing = [field for field in REQUIRED_COUNTER_FIELDS if field not in value]
    if missing:
        raise AccountingError(
            f"{label} is incomplete; missing required counter(s): {', '.join(missing)}"
        )

    invalid = [
        field
        for field in REQUIRED_COUNTER_FIELDS
        if not _is_integer(value.get(field))
    ]
    for field in OPTIONAL_COUNTER_FIELDS:
        if field in value and not _is_integer(value.get(field)):
            invalid.append(field)
    if invalid:
        raise AccountingError(
            f"{label} counter(s) must be integers, not booleans or null: "
            + ", ".join(invalid)
        )

    counter = Counter(
        input_tokens=value["input_tokens"],
        cached_input_tokens=value["cached_input_tokens"],
        output_tokens=value["output_tokens"],
        total_tokens=value["total_tokens"],
        cache_write_input_tokens=value.get("cache_write_input_tokens"),
        reasoning_output_tokens=value.get("reasoning_output_tokens"),
    )
    validate_counter(counter, label=label)
    return counter


def parse_repeated_snapshot_request(value: object, *, label: str) -> int:
    """Validate Codex's no-usage repeated-snapshot marker.

    After context maintenance Codex can emit an unchanged cumulative snapshot
    whose metered request components are explicitly zero while the standalone
    last_token_usage.total_tokens field contains context-size metadata. That
    total is not usage and must not be reconciled or priced.
    """
    if not isinstance(value, dict):
        raise AccountingError(f"{label} must be a JSON object")
    missing = [field for field in REQUIRED_COUNTER_FIELDS if field not in value]
    if missing:
        raise AccountingError(
            f"{label} is incomplete; missing required counter(s): {', '.join(missing)}"
        )
    fields = REQUIRED_COUNTER_FIELDS + OPTIONAL_COUNTER_FIELDS
    invalid = [
        field
        for field in fields
        if field in value and not _is_integer(value[field])
    ]
    if invalid:
        raise AccountingError(
            f"{label} counter(s) must be integers, not booleans or null: "
            + ", ".join(invalid)
        )
    if any(value[field] < 0 for field in fields if field in value):
        raise AccountingError(f"{label} counters must be non-negative")
    metered_fields = (
        "input_tokens",
        "cached_input_tokens",
        "output_tokens",
        "cache_write_input_tokens",
        "reasoning_output_tokens",
    )
    nonzero = [field for field in metered_fields if value.get(field, 0) != 0]
    if nonzero:
        raise AccountingError(
            f"{label} accompanies an unchanged cumulative snapshot but has "
            "non-zero metered counter(s): " + ", ".join(nonzero)
        )
    return value["total_tokens"]


def validate_counter(counter: Counter, *, label: str) -> None:
    values = [getattr(counter, field) for field in REQUIRED_COUNTER_FIELDS]
    values.extend(
        value
        for value in (
            counter.cache_write_input_tokens,
            counter.reasoning_output_tokens,
        )
        if value is not None
    )
    if any(value < 0 for value in values):
        raise AccountingError(f"{label} counters must be non-negative")
    if counter.cached_input_tokens > counter.input_tokens:
        raise AccountingError(f"{label} cached input exceeds total input")
    if (
        counter.cache_write_input_tokens is not None
        and counter.cached_input_tokens + counter.cache_write_input_tokens
        > counter.input_tokens
    ):
        raise AccountingError(
            f"{label} cached plus cache-write input exceeds total input"
        )
    if (
        counter.reasoning_output_tokens is not None
        and counter.reasoning_output_tokens > counter.output_tokens
    ):
        raise AccountingError(f"{label} reasoning output exceeds total output")
    expected_total = counter.input_tokens + counter.output_tokens
    if counter.total_tokens != expected_total:
        raise AccountingError(
            f"{label} total_tokens must equal input_tokens + output_tokens "
            f"({expected_total}), not {counter.total_tokens}; reasoning is already "
            "a subset of output"
        )


def load_session(path: Path) -> Session:
    try:
        handle = path.open(encoding="utf-8")
    except OSError as error:
        raise AccountingError(f"cannot read selected session {path}: {error}") from error

    session_ids: list[str] = []
    models: list[str] = []
    token_events: list[TokenEvent] = []
    with handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                raise AccountingError(
                    f"malformed JSONL at line {line_number}: blank lines are not records"
                )
            try:
                event: Any = json.loads(raw_line)
            except json.JSONDecodeError as error:
                raise AccountingError(
                    f"malformed JSONL at line {line_number}: {error.msg}"
                ) from error
            if not isinstance(event, dict):
                raise AccountingError(
                    f"malformed JSONL at line {line_number}: record must be an object"
                )

            payload = event.get("payload")
            if event.get("type") == "session_meta":
                if (
                    not isinstance(payload, dict)
                    or not isinstance(payload.get("id"), str)
                    or not payload["id"].strip()
                ):
                    raise AccountingError(
                        f"session_meta at line {line_number} has no string payload.id"
                    )
                session_ids.append(payload["id"])
            elif event.get("type") == "turn_context":
                if (
                    isinstance(payload, dict)
                    and isinstance(payload.get("model"), str)
                    and payload["model"].strip()
                ):
                    if payload["model"] not in models:
                        models.append(payload["model"])
            elif (
                event.get("type") == "event_msg"
                and isinstance(payload, dict)
                and payload.get("type") == "token_count"
            ):
                info = payload.get("info")
                if not isinstance(info, dict):
                    raise AccountingError(
                        f"token_count event at line {line_number} has no info object"
                    )
                ordinal = len(token_events) + 1
                total = parse_counter(
                    info.get("total_token_usage"),
                    label=f"token_count event {ordinal} total_token_usage",
                )
                repeated_snapshot_last_total_tokens = None
                exact_replay_of = None
                info_fingerprint = json.dumps(
                    info,
                    ensure_ascii=False,
                    separators=(",", ":"),
                    sort_keys=True,
                )
                if token_events and not counter_mismatch(token_events[-1].total, total):
                    request = None
                    if token_events[-1].info_fingerprint == info_fingerprint:
                        exact_replay_of = token_events[-1].ordinal
                    else:
                        repeated_snapshot_last_total_tokens = (
                            parse_repeated_snapshot_request(
                                info.get("last_token_usage"),
                                label=f"token_count event {ordinal} last_token_usage",
                            )
                        )
                else:
                    request = parse_counter(
                        info.get("last_token_usage"),
                        label=f"token_count event {ordinal} last_token_usage",
                    )
                timestamp = event.get("timestamp")
                if timestamp is not None and not isinstance(timestamp, str):
                    raise AccountingError(
                        f"token_count event {ordinal} timestamp must be a string or absent"
                    )
                token_events.append(
                    TokenEvent(
                        ordinal,
                        line_number,
                        timestamp,
                        total,
                        request,
                        repeated_snapshot_last_total_tokens,
                        exact_replay_of,
                        info_fingerprint,
                    )
                )

    if len(session_ids) != 1:
        raise AccountingError(
            "selected JSONL must contain exactly one session_meta payload.id; "
            f"found {len(session_ids)}"
        )
    if not token_events:
        raise AccountingError("selected session contains no complete token_count events")
    for previous, current in zip(token_events, token_events[1:]):
        subtract_counter(
            current.total,
            previous.total,
            label=(
                f"session counters between token_count events {previous.ordinal} "
                f"and {current.ordinal}"
            ),
        )
    return Session(path.resolve(), session_ids[0], tuple(models), tuple(token_events))


def subtract_counter(current: Counter, baseline: Counter, *, label: str) -> Counter:
    optional_deltas: dict[str, int | None] = {}
    for field in OPTIONAL_COUNTER_FIELDS:
        current_value = getattr(current, field)
        baseline_value = getattr(baseline, field)
        if (current_value is None) != (baseline_value is None):
            raise AccountingError(
                f"{label} cannot be exact because {field} is reported at only one boundary"
            )
        optional_deltas[field] = (
            None
            if current_value is None
            else current_value - baseline_value  # type: ignore[operator]
        )

    delta = Counter(
        input_tokens=current.input_tokens - baseline.input_tokens,
        cached_input_tokens=(
            current.cached_input_tokens - baseline.cached_input_tokens
        ),
        output_tokens=current.output_tokens - baseline.output_tokens,
        total_tokens=current.total_tokens - baseline.total_tokens,
        cache_write_input_tokens=optional_deltas["cache_write_input_tokens"],
        reasoning_output_tokens=optional_deltas["reasoning_output_tokens"],
    )
    if any(
        value < 0
        for value in delta.as_dict().values()
        if value is not None
    ):
        raise AccountingError(f"{label} decreased relative to the baseline")
    validate_counter(delta, label=label)
    return delta


def sum_counters(counters: Sequence[Counter], *, shape: Counter) -> Counter:
    def optional_sum(field: str) -> int | None:
        values = [getattr(counter, field) for counter in counters]
        present = [value is not None for value in values]
        if not counters:
            return 0 if getattr(shape, field) is not None else None
        if any(present) and not all(present):
            raise AccountingError(
                f"request-level {field} availability changes within the measured boundary"
            )
        return sum(value for value in values if value is not None) if all(present) else None

    result = Counter(
        input_tokens=sum(counter.input_tokens for counter in counters),
        cached_input_tokens=sum(counter.cached_input_tokens for counter in counters),
        output_tokens=sum(counter.output_tokens for counter in counters),
        total_tokens=sum(counter.total_tokens for counter in counters),
        cache_write_input_tokens=optional_sum("cache_write_input_tokens"),
        reasoning_output_tokens=optional_sum("reasoning_output_tokens"),
    )
    validate_counter(result, label="summed request usage")
    return result


def counter_mismatch(actual: Counter, expected: Counter) -> list[str]:
    fields = REQUIRED_COUNTER_FIELDS + OPTIONAL_COUNTER_FIELDS
    return [
        field
        for field in fields
        if getattr(actual, field) != getattr(expected, field)
    ]


def snapshot_dict(session: Session, token_count_event: int | None = None) -> dict[str, Any]:
    ordinal = (
        len(session.token_events)
        if token_count_event is None
        else token_count_event
    )
    if ordinal < 1 or ordinal > len(session.token_events):
        raise AccountingError(
            f"token-count event {ordinal} is outside the available range "
            f"1..{len(session.token_events)}"
        )
    event = session.token_events[ordinal - 1]
    counters = event.total.as_dict()
    counters.pop("uncached_input_tokens")
    counters.pop("standard_uncached_input_tokens")
    return {
        "schema_version": SCHEMA_VERSION,
        "selected_session": str(session.path),
        "session_id": session.session_id,
        "token_count_event": event.ordinal,
        "timestamp": event.timestamp,
        "counters": counters,
    }


def write_snapshot(output: Path, snapshot: dict[str, Any]) -> None:
    if output.exists():
        raise AccountingError(
            f"refusing to overwrite existing baseline {output}; choose a new path"
        )
    try:
        output.write_text(
            json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except OSError as error:
        raise AccountingError(f"cannot write baseline {output}: {error}") from error


def load_baseline(path: Path) -> Baseline:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise AccountingError(f"cannot read baseline {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise AccountingError(f"malformed baseline JSON: {error.msg}") from error
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION:
        raise AccountingError(
            f"baseline must be an object with schema_version {SCHEMA_VERSION}"
        )
    session_id = value.get("session_id")
    token_count_event = value.get("token_count_event")
    timestamp = value.get("timestamp")
    if not isinstance(session_id, str) or not session_id.strip():
        raise AccountingError("baseline session_id must be a non-empty string")
    if not _is_integer(token_count_event) or token_count_event < 1:
        raise AccountingError("baseline token_count_event must be a positive integer")
    if timestamp is not None and not isinstance(timestamp, str):
        raise AccountingError("baseline timestamp must be a string or null")
    return Baseline(
        session_id=session_id,
        token_count_event=token_count_event,
        timestamp=timestamp,
        counters=parse_counter(value.get("counters"), label="baseline counters"),
    )


def select_boundary(
    session: Session, baseline: Baseline | None
) -> tuple[str, Counter, tuple[TokenEvent, ...], dict[str, Any]]:
    final_event = session.token_events[-1]
    if baseline is None:
        usage = final_event.total
        events = session.token_events
        start = {
            "mode": "whole-session",
            "token_count_event": None,
            "timestamp": None,
            "counters": None,
        }
    else:
        if baseline.session_id != session.session_id:
            raise AccountingError(
                "baseline session_id does not match the explicitly selected session"
            )
        usage = subtract_counter(
            final_event.total, baseline.counters, label="phase counters"
        )
        if baseline.token_count_event > len(session.token_events):
            raise AccountingError(
                "baseline token_count_event is not present in the selected session"
            )
        captured_event = session.token_events[baseline.token_count_event - 1]
        mismatched = counter_mismatch(captured_event.total, baseline.counters)
        if captured_event.timestamp != baseline.timestamp or mismatched:
            details = []
            if captured_event.timestamp != baseline.timestamp:
                details.append("timestamp")
            details.extend(mismatched)
            raise AccountingError(
                "baseline does not match its selected session event: "
                + ", ".join(details)
            )
        events = session.token_events[baseline.token_count_event :]
        start = {
            "mode": "delta",
            "token_count_event": baseline.token_count_event,
            "timestamp": baseline.timestamp,
            "counters": baseline.counters.as_dict(),
        }

    request_events = tuple(event for event in events if event.request is not None)
    summed_requests = sum_counters(
        [event.request for event in request_events if event.request is not None],
        shape=usage,
    )
    mismatched = counter_mismatch(summed_requests, usage)
    if mismatched:
        raise AccountingError(
            "request-level counters do not reconcile to the measured boundary: "
            + ", ".join(mismatched)
        )
    return start["mode"], usage, events, start


def decimal_argument(value: str) -> Decimal:
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise argparse.ArgumentTypeError(f"not a decimal: {value}") from error
    if not result.is_finite() or result < 0:
        raise argparse.ArgumentTypeError("decimal values must be finite and non-negative")
    return result


def pricing_requested(args: argparse.Namespace) -> bool:
    fields = (
        "model",
        "pricing_date",
        "pricing_source",
        "currency",
        "uncached_input_rate",
        "cached_input_rate",
        "output_rate",
        "cache_write_multiplier",
        "long_context_input_multiplier",
        "long_context_output_multiplier",
    )
    return any(getattr(args, field) is not None for field in fields)


def validate_pricing_args(
    args: argparse.Namespace,
    session: Session,
    usage: Counter,
    crossing_count: int,
) -> None:
    required = (
        "model",
        "pricing_date",
        "pricing_source",
        "currency",
        "uncached_input_rate",
        "cached_input_rate",
        "output_rate",
        "long_context_threshold",
    )
    missing = [field for field in required if getattr(args, field) is None]
    if missing:
        raise AccountingError(
            "API-equivalent pricing is incomplete; supply: " + ", ".join(missing)
        )
    try:
        date.fromisoformat(args.pricing_date)
    except ValueError as error:
        raise AccountingError("pricing_date must use YYYY-MM-DD") from error
    if not session.models:
        raise AccountingError("selected session reports no model in turn_context")
    if len(session.models) != 1 or session.models[0] != args.model:
        raise AccountingError(
            "supplied model does not uniquely match the selected session model(s): "
            + ", ".join(session.models)
        )
    if usage.cache_write_input_tokens is None:
        raise AccountingError(
            "cache_write_input_tokens is not reported; a complete cost estimate is impossible"
        )
    if usage.cache_write_input_tokens > 0 and args.cache_write_multiplier is None:
        raise AccountingError(
            "measured cache-write input requires --cache-write-multiplier"
        )
    if crossing_count and (
        args.long_context_input_multiplier is None
        or args.long_context_output_multiplier is None
    ):
        raise AccountingError(
            "threshold-crossing requests require both long-context multipliers"
        )


def request_cost(
    usage: Counter,
    args: argparse.Namespace,
    *,
    input_multiplier: Decimal,
    output_multiplier: Decimal,
) -> Decimal:
    if usage.cache_write_input_tokens is None:
        raise AccountingError(
            "request cache_write_input_tokens is not reported; cannot price request"
        )
    standard_uncached = usage.uncached_input_tokens - usage.cache_write_input_tokens
    cache_write_multiplier = args.cache_write_multiplier or Decimal(1)
    million = Decimal(1_000_000)
    return (
        Decimal(standard_uncached)
        * args.uncached_input_rate
        * input_multiplier
        + Decimal(usage.cached_input_tokens)
        * args.cached_input_rate
        * input_multiplier
        + Decimal(usage.cache_write_input_tokens)
        * args.uncached_input_rate
        * cache_write_multiplier
        * input_multiplier
        + Decimal(usage.output_tokens)
        * args.output_rate
        * output_multiplier
    ) / million


def calculate_cost(
    args: argparse.Namespace, events: Sequence[TokenEvent]
) -> dict[str, Any]:
    threshold = args.long_context_threshold
    exact = Decimal(0)
    for event in events:
        request = event.request
        if request is None:
            continue
        crossing = request.input_tokens > threshold
        input_multiplier = (
            args.long_context_input_multiplier if crossing else Decimal(1)
        )
        output_multiplier = (
            args.long_context_output_multiplier if crossing else Decimal(1)
        )
        exact += request_cost(
            request,
            args,
            input_multiplier=input_multiplier,
            output_multiplier=output_multiplier,
        )
    rounded = exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return {
        "label": "API-equivalent comparison estimate",
        "chatgpt_subscription_bill": False,
        "model": args.model,
        "pricing_date": args.pricing_date,
        "pricing_source": args.pricing_source,
        "currency": args.currency,
        "rates_per_million_tokens": {
            "standard_uncached_input": format(args.uncached_input_rate, "f"),
            "cached_input": format(args.cached_input_rate, "f"),
            "output_including_reasoning": format(args.output_rate, "f"),
        },
        "cache_write_multiplier": (
            None
            if args.cache_write_multiplier is None
            else format(args.cache_write_multiplier, "f")
        ),
        "long_context_input_multiplier": (
            None
            if args.long_context_input_multiplier is None
            else format(args.long_context_input_multiplier, "f")
        ),
        "long_context_output_multiplier": (
            None
            if args.long_context_output_multiplier is None
            else format(args.long_context_output_multiplier, "f")
        ),
        "exact": format(exact, "f"),
        "rounded": format(rounded, ".2f"),
    }


def build_report(
    session: Session, baseline: Baseline | None, args: argparse.Namespace
) -> dict[str, Any]:
    mode, usage, events, start = select_boundary(session, baseline)
    request_events = tuple(event for event in events if event.request is not None)
    threshold = args.long_context_threshold
    request_inputs = [
        event.request.input_tokens
        for event in request_events
        if event.request is not None
    ]
    crossings = []
    if threshold is not None:
        if threshold < 0:
            raise AccountingError("long-context threshold must be non-negative")
        crossings = [
            {
                "phase_request": index,
                "token_count_event": event.ordinal,
                "input_tokens": event.request.input_tokens,
            }
            for index, event in enumerate(request_events, start=1)
            if event.request is not None and event.request.input_tokens > threshold
        ]

    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "boundary": {
            "mode": mode,
            "label": args.boundary_label,
            "start": start,
            "end": {
                "token_count_event": session.token_events[-1].ordinal,
                "timestamp": session.token_events[-1].timestamp,
                "counters": session.token_events[-1].total.as_dict(),
            },
        },
        "selected_session": str(session.path),
        "session_id": session.session_id,
        "session_models": list(session.models),
        "included_agents": args.included_agent,
        "included_channels": args.included_channel,
        "excluded_or_unmeasured_channels": args.excluded_channel,
        "usage": usage.as_dict(),
        "requests": {
            "count": len(request_events),
            "input_tokens": request_inputs,
            "largest_input_tokens": max(request_inputs, default=0),
            "long_context_threshold": threshold,
            "threshold_rule": "input_tokens > threshold" if threshold is not None else None,
            "threshold_crossings": crossings if threshold is not None else None,
            "repeated_cumulative_snapshots": [
                {
                    "token_count_event": event.ordinal,
                    "timestamp": event.timestamp,
                    "non_usage_last_total_tokens": (
                        event.repeated_snapshot_last_total_tokens
                    ),
                }
                for event in events
                if event.repeated_snapshot_last_total_tokens is not None
            ],
            "exact_replayed_token_events": [
                {
                    "token_count_event": event.ordinal,
                    "timestamp": event.timestamp,
                    "exact_replay_of": event.exact_replay_of,
                }
                for event in events
                if event.exact_replay_of is not None
            ],
        },
        "api_equivalent": None,
    }
    if pricing_requested(args):
        validate_pricing_args(args, session, usage, len(crossings))
        result["api_equivalent"] = calculate_cost(args, events)
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Capture or report reproducible usage from one explicitly selected "
            "Codex session JSONL."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot", help="capture a verified baseline")
    snapshot.add_argument("session", type=Path)
    snapshot.add_argument("--output", type=Path, required=True)
    snapshot.add_argument(
        "--token-count-event",
        type=int,
        help="one-based event captured earlier; defaults to the latest complete event",
    )

    report = subparsers.add_parser("report", help="report whole-session or delta usage")
    report.add_argument("session", type=Path)
    report.add_argument("--baseline", type=Path)
    report.add_argument("--boundary-label", type=nonempty_argument, required=True)
    report.add_argument(
        "--included-agent", type=nonempty_argument, action="append", required=True
    )
    report.add_argument(
        "--included-channel", type=nonempty_argument, action="append", required=True
    )
    report.add_argument(
        "--excluded-channel", type=nonempty_argument, action="append", required=True
    )
    report.add_argument("--long-context-threshold", type=int)
    report.add_argument("--model", type=nonempty_argument)
    report.add_argument("--pricing-date", type=nonempty_argument)
    report.add_argument("--pricing-source", type=nonempty_argument)
    report.add_argument("--currency", type=nonempty_argument)
    report.add_argument("--uncached-input-rate", type=decimal_argument)
    report.add_argument("--cached-input-rate", type=decimal_argument)
    report.add_argument("--output-rate", type=decimal_argument)
    report.add_argument("--cache-write-multiplier", type=decimal_argument)
    report.add_argument("--long-context-input-multiplier", type=decimal_argument)
    report.add_argument("--long-context-output-multiplier", type=decimal_argument)
    report.add_argument("--json", action="store_true", dest="as_json")
    return parser


def print_human_report(report: dict[str, Any]) -> None:
    usage = report["usage"]
    boundary = report["boundary"]
    print(f"boundary_mode={boundary['mode']}")
    print(f"boundary_label={boundary['label']}")
    print(f"session_id={report['session_id']}")
    print(f"input_tokens={usage['input_tokens']}")
    print(f"cached_input_tokens={usage['cached_input_tokens']}")
    print(f"uncached_input_tokens={usage['uncached_input_tokens']}")
    cache_write = usage["cache_write_input_tokens"]
    print(
        "cache_write_input_tokens="
        + ("not reported" if cache_write is None else str(cache_write))
    )
    print(f"output_tokens={usage['output_tokens']}")
    reasoning = usage["reasoning_output_tokens"]
    print(
        "reasoning_output_tokens="
        + ("not reported" if reasoning is None else str(reasoning))
        + " (subset of output)"
    )
    print(f"total_tokens={usage['total_tokens']}")
    requests = report["requests"]
    print(f"measured_requests={requests['count']}")
    print(f"largest_request_input_tokens={requests['largest_input_tokens']}")
    if requests["threshold_crossings"] is not None:
        print(f"long_context_crossings={len(requests['threshold_crossings'])}")
    estimate = report["api_equivalent"]
    if estimate is not None:
        print(
            f"api_equivalent_comparison={estimate['currency']} "
            f"{estimate['rounded']} (not a ChatGPT subscription bill)"
        )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        session = load_session(args.session)
        if args.command == "snapshot":
            snapshot = snapshot_dict(session, args.token_count_event)
            write_snapshot(args.output, snapshot)
            print(json.dumps(snapshot, indent=2, sort_keys=True))
        else:
            baseline = load_baseline(args.baseline) if args.baseline else None
            report = build_report(session, baseline, args)
            if args.as_json:
                print(json.dumps(report, indent=2, sort_keys=True))
            else:
                print_human_report(report)
    except AccountingError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
