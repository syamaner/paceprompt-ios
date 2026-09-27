"""Pure retry decisions for a future, separately ratified issue #145 runner.

This module does not send requests, sleep, read credentials, or change the
sealed v5 zero-retry execution policy. A caller must persist and reserve each
wire send before dispatch, and may invoke this planner only after a complete
HTTP response has been captured.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from email.utils import parsedate_to_datetime
from math import ceil
from typing import Mapping

from .issue145_lineage import usd


@dataclass(frozen=True)
class RetryPolicy:
    max_sends_per_position: int
    retryable_status_codes: frozenset[int]
    fallback_backoff_seconds: tuple[int, ...]
    max_single_wait_seconds: int
    max_cumulative_wait_seconds: int

    def __post_init__(self) -> None:
        if type(self.max_sends_per_position) is not int or self.max_sends_per_position < 1:
            raise ValueError("retry policy needs a positive send limit")
        if len(self.fallback_backoff_seconds) != self.max_sends_per_position - 1:
            raise ValueError("fallback schedule must cover every permitted retry")
        if not self.retryable_status_codes or any(
            type(code) is not int or code < 400 or code > 599
            for code in self.retryable_status_codes
        ):
            raise ValueError("retryable statuses must be explicit HTTP errors")
        if (
            type(self.max_single_wait_seconds) is not int
            or type(self.max_cumulative_wait_seconds) is not int
            or self.max_single_wait_seconds < 0
            or self.max_cumulative_wait_seconds < 0
        ):
            raise ValueError("retry wait limits must be non-negative")
        if any(
            type(delay) is not int or delay < 0
            for delay in self.fallback_backoff_seconds
        ):
            raise ValueError("fallback delays must be non-negative whole seconds")


@dataclass(frozen=True)
class RetryDecision:
    retry: bool
    wait_seconds: int | None
    reason: str
    header_source: str | None


def _retry_after_seconds(value: str, received_at: datetime) -> int:
    if value.isascii() and value.isdecimal():
        return int(value)
    try:
        target = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        raise ValueError("invalid Retry-After header") from None
    if target is None or target.tzinfo is None or received_at.tzinfo is None:
        raise ValueError("Retry-After date requires a timezone")
    return max(0, ceil((target - received_at).total_seconds()))


def decide_retry(
    policy: RetryPolicy,
    *,
    status_code: int | None,
    response_headers: Mapping[str, str] | None,
    completed_sends: int,
    cumulative_wait_seconds: int,
    received_at: datetime,
) -> RetryDecision:
    """Decide whether one more exact-route send is allowed after a response.

    A missing status or headers denotes no complete HTTP response. Malformed or
    excessive Retry-After stops closed; it is never replaced with a shorter
    local delay. The frozen fallback schedule is used only when that header is
    absent. The caller remains responsible for a separate USD reservation.
    """
    if (
        type(completed_sends) is not int
        or type(cumulative_wait_seconds) is not int
        or completed_sends < 1
        or cumulative_wait_seconds < 0
    ):
        raise ValueError("retry accounting is invalid")
    if received_at.tzinfo is None:
        raise ValueError("retry clock must be timezone-aware")
    if status_code is None or response_headers is None:
        return RetryDecision(False, None, "noCompleteHTTPResponse", None)
    if type(status_code) is not int:
        return RetryDecision(False, None, "invalidHTTPStatus", None)
    if status_code not in policy.retryable_status_codes:
        return RetryDecision(False, None, "nonRetryableHTTPStatus", None)
    if completed_sends >= policy.max_sends_per_position:
        return RetryDecision(False, None, "sendLimitReached", None)

    if any(not isinstance(key, str) or not isinstance(value, str)
           for key, value in response_headers.items()):
        return RetryDecision(False, None, "invalidResponseHeaders", None)
    headers: dict[str, str] = {}
    for key, value in response_headers.items():
        folded = key.casefold()
        if folded in headers:
            return RetryDecision(False, None, "ambiguousResponseHeaders", None)
        headers[folded] = value
    if "retry-after" in headers:
        try:
            server_wait = _retry_after_seconds(headers["retry-after"].strip(), received_at)
        except ValueError:
            return RetryDecision(False, None, "invalidRetryAfter", "Retry-After")
        wait = max(policy.fallback_backoff_seconds[completed_sends - 1], server_wait)
        source = "Retry-After"
    else:
        wait = policy.fallback_backoff_seconds[completed_sends - 1]
        source = None
    if wait > policy.max_single_wait_seconds:
        return RetryDecision(False, None, "singleWaitLimitReached", source)
    if cumulative_wait_seconds + wait > policy.max_cumulative_wait_seconds:
        return RetryDecision(False, None, "cumulativeWaitLimitReached", source)
    return RetryDecision(True, wait, "retryableCompleteHTTPResponse", source)


def reserve_wire_send(
    *, hard_limit_usd: str, charged_usd: str, reserved_usd: str, worst_case_usd: str
) -> str:
    """Return the new reserved total, or reject before another physical send.

    Unknown charges must be moved from reserved to conservatively charged by
    the caller before it asks to reserve a retry. A retry never reuses the
    previous send's reservation.
    """
    cap = usd(hard_limit_usd)
    charged = usd(charged_usd)
    reserved = usd(reserved_usd)
    worst = usd(worst_case_usd)
    if cap <= 0 or worst <= 0 or charged + reserved + worst > cap:
        raise ValueError("wire send exceeds the finite lineage hard limit")
    return format(reserved + worst, "f")
