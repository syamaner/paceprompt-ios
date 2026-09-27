"""Verify the evaluation-only non-ZDR revision without rewriting r2 evidence."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from .issue145_retry_profile import PROPOSAL as R2_PROPOSAL
from .issue145_retry_profile import PROPOSAL_SHA256 as R2_SHA256
from .issue145_retry_profile import verify as verify_r2
from .v3 import HOST_EVAL_ROOT, sha256_file, strict_json_load


PROPOSAL = HOST_EVAL_ROOT / "issue145-route-retry-proposal-r3.json"
PROPOSAL_SHA256 = "ad6762c835ad6266e81754dae1742c6aecceb884592e677940ed288442e5af3b"


def verify() -> dict[str, Any]:
    """Require r3 to differ from verified r2 only in the operator's ZDR decision."""
    errors: list[str] = []
    if verify_r2()["status"] != "valid":
        errors.append("sealed r2 proposal or supporting evidence failed verification")
    if sha256_file(R2_PROPOSAL) != R2_SHA256:
        errors.append("r2 proposal bytes changed")

    expected = deepcopy(strict_json_load(R2_PROPOSAL))
    expected["proposalVersion"] = "paceprompt-host-eval-proposal/issue145-route-retry-r3"
    expected["supersedesProposalR2Sha256"] = R2_SHA256
    expected["routeDelta"]["retainZdrRequirement"] = False
    expected["routeDelta"]["proposedZdrRequestField"] = "omit"
    expected["routeDelta"]["zdrEligibilityOfProposedEndpoint"] = (
        "not-required-for-synthetic-evaluation"
    )
    del expected["unresolvedBeforeLive"]["privacyDecisionForProposedRoute"]
    expected["privacyDecision"] = {
        "scope": "developer-only-synthetic-workout-import-evaluation",
        "zdrRequired": False,
        "dataCollectionDenied": True,
        "productionPrivacyUnchanged": True,
        "source": "operator-stated-zdr-not-material-for-this-use-case-2026-09-23",
    }
    proposal = strict_json_load(PROPOSAL)
    if proposal != expected:
        errors.append("r3 changed more than the bounded evaluation-only ZDR decision")
    if sha256_file(PROPOSAL) != PROPOSAL_SHA256:
        errors.append("r3 proposal bytes changed")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "proposalSha256": sha256_file(PROPOSAL),
        "supersededProposalSha256": R2_SHA256,
        "liveAuthorized": False,
    }
