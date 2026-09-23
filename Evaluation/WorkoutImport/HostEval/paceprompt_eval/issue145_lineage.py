"""Pure, zero-spend admission rules for a future issue #145 restart runner.

This module does not validate evidence files, read credentials, or make calls.
The caller must first verify each immutable parent evidence tree and the exact
ratified profile; this module then checks the lineage ledger and next plan.
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Any


TERMINAL_STATES = frozenset({"completed", "failed", "possiblySent", "notStarted"})
SENT_STATES = frozenset({"completed", "failed", "possiblySent"})


def usd(value: str) -> Decimal:
    """Accept only finite, non-negative, exactly represented USD amounts."""
    if not isinstance(value, str) or not value or value.strip() != value:
        raise ValueError("USD amount must be an exact decimal string")
    try:
        amount = Decimal(value)
    except InvalidOperation:
        raise ValueError("USD amount is not decimal") from None
    if not amount.is_finite() or amount < 0:
        raise ValueError("USD amount must be finite and non-negative")
    return amount


def admit_child(
    *,
    root_run_id: str,
    profile_sha256: str,
    queue_ids: list[str],
    hard_limit_usd: str,
    parents: list[dict[str, Any]],
    child_run_id: str,
    child_queue_ids: list[str],
    child_worst_case_usd: dict[str, str],
) -> dict[str, Any]:
    """Check an already evidence-verified ancestry and a finite manual child plan.

    `parents` is root-to-leaf. Each item includes a verified evidence-tree hash,
    the exact predecessor's hash, and a terminal attempt ledger. This function
    deliberately does not trust an unverified filesystem or choose a profile.
    """
    cap = usd(hard_limit_usd)
    if cap <= 0 or not root_run_id or not profile_sha256 or not parents:
        raise ValueError("root profile and positive finite lineage cap are required")
    if not queue_ids or len(queue_ids) != len(set(queue_ids)):
        raise ValueError("frozen queue has missing or duplicate IDs")
    queue_position = {item: index for index, item in enumerate(queue_ids)}
    seen_runs: set[str] = set()
    sent: set[str] = set()
    charged = Decimal("0")
    predecessor_id: str | None = None
    predecessor_hash: str | None = None
    for index, parent in enumerate(parents):
        run_id = parent.get("runID")
        evidence_hash = parent.get("verifiedEvidenceTreeSha256")
        if not isinstance(run_id, str) or not run_id or run_id in seen_runs:
            raise ValueError("lineage has a missing or duplicate run ID")
        if index == 0 and run_id != root_run_id:
            raise ValueError("lineage does not start at the bound root")
        if parent.get("rootRunID") != root_run_id or parent.get("profileSha256") != profile_sha256:
            raise ValueError("lineage root or profile changed")
        if usd(parent.get("lineageHardLimitUSD")) != cap:
            raise ValueError("lineage hard limit changed")
        if parent.get("parentRunID") != predecessor_id or parent.get("parentEvidenceSha256") != predecessor_hash:
            raise ValueError("lineage parent evidence link changed")
        if not isinstance(evidence_hash, str) or len(evidence_hash) != 64 or any(
            character not in "0123456789abcdef" for character in evidence_hash
        ):
            raise ValueError("lineage lacks a verified evidence-tree SHA-256")
        attempts = parent.get("attempts")
        if not isinstance(attempts, list):
            raise ValueError("lineage lacks a terminal attempt ledger")
        for attempt in attempts:
            attempt_id = attempt.get("attemptID")
            state = attempt.get("state")
            if attempt_id not in queue_position or state not in TERMINAL_STATES:
                raise ValueError("lineage contains an unknown or non-terminal position")
            if state in SENT_STATES:
                if attempt_id in sent:
                    raise ValueError("lineage replays a possibly sent position")
                sent.add(attempt_id)
                worst = usd(attempt.get("reservedWorstCaseUSD"))
                actual = attempt.get("actualUSD")
                if state == "possiblySent" and actual is not None:
                    raise ValueError("possibly sent call cannot claim a settled charge")
                charge = worst if actual is None else usd(actual)
                if charge > worst:
                    raise ValueError("actual charge exceeds the reserved bound")
                charged += charge
            elif attempt.get("actualUSD") is not None or attempt.get("reservedWorstCaseUSD") is not None:
                raise ValueError("not-started position cannot carry a charge")
        seen_runs.add(run_id)
        predecessor_id = run_id
        predecessor_hash = evidence_hash
    if charged > cap:
        raise ValueError("verified ancestry already exceeds lineage cap")
    if not child_run_id or child_run_id in seen_runs:
        raise ValueError("child needs a fresh run ID")
    if not child_queue_ids or len(child_queue_ids) != len(set(child_queue_ids)):
        raise ValueError("child plan must be finite, non-empty and unique")
    if set(child_queue_ids) != set(child_worst_case_usd):
        raise ValueError("child plan lacks per-call worst-case reservations")
    remaining_ids = [item for item in queue_ids if item not in sent]
    if child_queue_ids != remaining_ids[: len(child_queue_ids)]:
        raise ValueError("child plan must be a prefix of never-sent frozen positions")
    reservations: dict[str, str] = {}
    for attempt_id in child_queue_ids:
        worst = usd(child_worst_case_usd[attempt_id])
        if worst <= 0:
            raise ValueError("each planned call needs a positive bound")
        reservations[attempt_id] = format(worst, "f")
    return {
        "rootRunID": root_run_id,
        "runID": child_run_id,
        "parentRunID": predecessor_id,
        "parentEvidenceSha256": predecessor_hash,
        "profileSha256": profile_sha256,
        "lineageHardLimitUSD": format(cap, "f"),
        "priorChargedUSD": format(charged, "f"),
        "remainingUSD": format(cap - charged, "f"),
        "plannedAttemptIDs": child_queue_ids,
        "plannedReservationsUSD": reservations,
        "nextAttemptIndex": 0,
        "providerCalls": 0,
        "credentialRead": False,
        "liveAuthorized": False,
    }


def reserve_next(admission: dict[str, Any], attempt_id: str) -> dict[str, Any]:
    """Consume the bound next position and its exact worst-case reservation."""
    ids = admission["plannedAttemptIDs"]
    index = admission["nextAttemptIndex"]
    if not isinstance(index, int) or index < 0 or index >= len(ids) or ids[index] != attempt_id:
        raise ValueError("next call differs from the bound frozen plan")
    remaining = usd(admission["remainingUSD"])
    worst = usd(admission["plannedReservationsUSD"][attempt_id])
    if worst <= 0 or worst > remaining:
        raise ValueError("next call exceeds lineage-wide hard limit")
    return dict(
        admission,
        remainingUSD=format(remaining - worst, "f"),
        nextAttemptIndex=index + 1,
    )
