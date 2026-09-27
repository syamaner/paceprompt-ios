"""Offline verification of the proposed issue #145 route/retry revision."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from . import issue145
from .issue145_lineage_profile import verify as verify_lineage_proposal
from .issue145_retry import RetryPolicy
from .v3 import HOST_EVAL_ROOT, canonical_hash, safe_run_dir, sha256_file, strict_json_load


PROPOSAL = HOST_EVAL_ROOT / "issue145-route-retry-proposal-r2.json"
PROPOSAL_SHA256 = "1e62b0799f4cabc773b9bdf60c01471dea4b370d17d573b1be65f0c643dce25f"
PRIOR_COST = HOST_EVAL_ROOT / "issue145-public-cost-preflight-r1.json"
EVIDENCE = HOST_EVAL_ROOT / "issue145-route-retry-evidence-r1.json"
EVIDENCE_SHA256 = "1152ad79e75bb3aeb0c2702526bdf9529a611415f82edffcf4b16a3c89c5c45d"
SEALED_PROBE_PROPOSAL = HOST_EVAL_ROOT / "issue145-full-matrix-route-probe-proposal-r1.json"
SEALED_PROBE_RATIFICATION = HOST_EVAL_ROOT / "issue145-full-matrix-route-probe-ratification-r1.json"
SEALED_PROBE_PROPOSAL_SHA256 = "2c4b2a6122a50fd5acc029f9282cd8bd3bb429072afe6b174ed446058715b500"
SEALED_PROBE_RATIFICATION_SHA256 = "b879cdd6eec28626d102719ceb02aae4d58e0ef3f729c0318dfba7a323183485"
CATALOGUE_RUN_ID = "issue145-full-matrix-route-probes-v5-20260923-03"
PRIOR_RUN_IDS = (
    "issue145-full-matrix-route-probes-v5-20260922-01",
    CATALOGUE_RUN_ID,
)
PRIOR_TREES = (
    "95abcaee76a9a01ee679a1f53776f1ee0c659b0c6082c0c4482cf3ea75329fe1",
    "8cee0b8d907f5fa34f179f476b6668b5a0164e2054757662d3e085b226bc7db3",
)


def verify() -> dict[str, Any]:
    errors: list[str] = []
    if issue145.verify()["status"] != "valid":
        errors.append("sealed v5 base verification failed")
    if verify_lineage_proposal()["status"] != "valid":
        errors.append("prior public cost and lineage proposal verification failed")
    proposal = strict_json_load(PROPOSAL)
    if sha256_file(PROPOSAL) != PROPOSAL_SHA256:
        errors.append("route/retry proposal bytes changed")
    evidence = strict_json_load(EVIDENCE)
    if sha256_file(EVIDENCE) != EVIDENCE_SHA256:
        errors.append("committed route-change evidence bytes changed")
    if evidence.get("manifestVersion") != "paceprompt-host-eval-evidence/issue145-route-retry-r1":
        errors.append("route-change evidence version changed")
    sealed_probe = {
        "proposalSha256": SEALED_PROBE_PROPOSAL_SHA256,
        "ratificationSha256": SEALED_PROBE_RATIFICATION_SHA256,
    }
    if (
        evidence.get("sealedProbeContract") != sealed_probe
        or sha256_file(SEALED_PROBE_PROPOSAL) != SEALED_PROBE_PROPOSAL_SHA256
        or sha256_file(SEALED_PROBE_RATIFICATION) != SEALED_PROBE_RATIFICATION_SHA256
    ):
        errors.append("route-change evidence no longer binds the sealed probe contract")
    runs = evidence.get("priorProbeRuns", [])
    if len(runs) != 2 or any(
        run.get("runID") != run_id
        or run.get("evidenceTreeSha256") != tree
        or canonical_hash(run.get("fileSha256", {})) != tree
        or run.get("diagnosticClassification") != "rateLimited"
        or run.get("providerCalls") != 1
        or run.get("scoredCalls") != 0
        or run.get("secondModelCalled") is not False
        for run, run_id, tree in zip(runs, PRIOR_RUN_IDS, PRIOR_TREES)
    ):
        errors.append("terminal route-probe evidence manifest changed")
    snapshot = evidence.get("publicCatalogueSelectedEndpoint", {})
    endpoint = snapshot.get("endpoint", {})
    if (
        snapshot.get("sourceRunID") != CATALOGUE_RUN_ID
        or snapshot.get("sourceResponseSha256")
        != "cc253a8b5d583df737cf0db27ba0f0176b9843cb7590949492c5af5738174d0a"
        or endpoint.get("tag") != "mistral"
        or endpoint.get("model_id") != "mistralai/mistral-small-2603"
        or endpoint.get("provider_name") != "Mistral"
        or endpoint.get("status") != 0
        or endpoint.get("pricing", {}).get("prompt") != "0.00000015"
        or endpoint.get("pricing", {}).get("completion") != "0.0000006"
        or "structured_outputs" not in endpoint.get("supported_parameters", [])
    ):
        errors.append("committed public Mistral endpoint snapshot changed")
    if set(proposal) != {
        "proposalVersion", "status", "purpose", "supersedesForFutureRunsOnly",
        "supportingEvidence", "routeDelta", "retryDelta", "unchangedEvaluation", "spending",
        "unresolvedBeforeLive", "authority",
    } or (
        proposal.get("status") != "proposed-not-ratified"
        or proposal.get("proposalVersion") != "paceprompt-host-eval-proposal/issue145-route-retry-r2"
        or proposal.get("purpose")
        != "revise the issue145 full-matrix Mistral route and add bounded transient-response retries"
    ):
        errors.append("proposal shape or status changed")
    expected_base = {
        "modelsV5Sha256": sha256_file(issue145.MODELS),
        "runPolicyV5Sha256": sha256_file(issue145.RUN_POLICY),
        "queueV5Sha256": issue145.queue_document()["queueSha256"],
    }
    if proposal.get("supersedesForFutureRunsOnly") != expected_base:
        errors.append("proposal no longer binds the sealed v5 profile")
    if proposal.get("supportingEvidence") != {
        "committedManifestSha256": EVIDENCE_SHA256,
        "sealedProbeProposalSha256": SEALED_PROBE_PROPOSAL_SHA256,
        "sealedProbeRatificationSha256": SEALED_PROBE_RATIFICATION_SHA256,
        "firstTerminalEvidenceTreeSha256": PRIOR_TREES[0],
        "secondTerminalEvidenceTreeSha256": PRIOR_TREES[1],
    }:
        errors.append("proposal no longer binds route-change evidence")
    specs = {spec.requested_model_id: spec for spec in issue145.load_model_specs(issue145.MODELS)}
    old = specs["mistralai/mistral-small-2603"]
    route = proposal.get("routeDelta", {})
    if route != {
        "requestedModelID": old.requested_model_id,
        "canonicalRevision": old.canonical_revision,
        "oldProviderEndpoint": old.provider_endpoint,
        "proposedProviderEndpoint": "mistral",
        "unchangedProviderName": "Mistral",
        "unchangedInputPricePerTokenUSD": "0.00000015",
        "unchangedOutputPricePerTokenUSD": "0.0000006",
        "retainZdrRequirement": True,
        "retainDataCollectionDenied": True,
        "retainExactRouteAndNoFallback": True,
        "zdrEligibilityOfProposedEndpoint": "unproven-requires-separate-compatibility-probe",
        "publicCatalogueEndpointResponseSha256": "cc253a8b5d583df737cf0db27ba0f0176b9843cb7590949492c5af5738174d0a",
        "observedAvailableStatus": 0,
    } or old.zdr is not True:
        errors.append("Mistral route or existing ZDR boundary changed")
    retry = proposal.get("retryDelta", {})
    if retry != {
        "scope": "newly-ratified-future-route-probe-and-full-matrix-runners-only",
        "maxPhysicalSendsPerLogicalPosition": 3,
        "retryableCompleteHTTPResponseStatuses": [429, 502, 503, 504, 524, 529],
        "fallbackBackoffSeconds": [30, 120],
        "retryAfterHeader": "honour-case-insensitive-integer-seconds-or-HTTP-date-as-minimum-wait",
        "malformedOrExcessiveRetryAfter": "stop-without-shorter-retry",
        "maxSingleWaitSeconds": 900,
        "maxCumulativeWaitSecondsPerPosition": 900,
        "noResponseTimeoutConnectionCancellationOrAmbiguousSend": "do-not-retry",
        "permanentHTTPStatusOrResponseContractFailure": "do-not-retry",
        "afterExhaustedTransientResponses": "terminal-failure-and-pause-that-model-in-place",
        "concurrency": 1,
        "minimumDelayBetweenPhysicalSendsSeconds": 2,
        "httpClientAutomaticRetries": 0,
        "inspectAutomaticRetries": 0,
        "fallbackRoutesOrModels": False,
        "requestBodyOnRetry": "byte-identical-except-transport-generated-request-identity",
        "wireEvidence": "preserve-each-physical-send-with-unique-subattempt-identity-and-response-headers",
        "scoredDenominator": "one-frozen-logical-position-with-all-intermediate-transient-sends-visible-separately",
        "chargeRule": "reserve-worst-case-before-each-physical-send-and-charge-unknown-as-reserved",
        "possiblySentNonterminalAfterInterruption": "terminal-conservative-charge-never-replay",
    }:
        errors.append("proposed retry controls changed")
    else:
        RetryPolicy(
            max_sends_per_position=retry["maxPhysicalSendsPerLogicalPosition"],
            retryable_status_codes=frozenset(retry["retryableCompleteHTTPResponseStatuses"]),
            fallback_backoff_seconds=tuple(retry["fallbackBackoffSeconds"]),
            max_single_wait_seconds=retry["maxSingleWaitSeconds"],
            max_cumulative_wait_seconds=retry["maxCumulativeWaitSecondsPerPosition"],
        )
    policy = strict_json_load(issue145.RUN_POLICY)
    logical = policy["execution"]["totalProviderCalls"]
    if proposal.get("unchangedEvaluation") != {
        "productionPrompt": "issue130-r2", "candidateModels": 12,
        "scoredStrata": 2, "distinctScoredCases": 109,
        "repetitionsPerStratum": 3, "scoredLogicalPositions": 3924,
        "warmupLogicalPositions": 12, "totalLogicalPositions": logical,
        "maximumPhysicalProviderSendsIfEveryPositionUsesAllRetries": logical * 3,
        "queueCaseOrderAndLogicalAttemptIDs": "unchanged-from-v5",
        "scorerAndPerStratumGates": "unchanged-from-v5",
        "generationAndResponseContracts": "unchanged-from-v5",
        "allOtherModelRoutes": "unchanged-from-v5",
    }:
        errors.append("logical matrix or maximum physical sends changed")
    spending = proposal.get("spending", {})
    prior = strict_json_load(PRIOR_COST)
    expected_cost = format(Decimal(prior["estimatedUSD"]) * 3, "f")
    if spending != {
        "currency": "USD", "freshPublicCatalogueAndCompletePayloadPreflightRequired": True,
        "finiteLineageHardLimitUSD": None,
        "proposedUpperBoundFromPriorSnapshotUSD": expected_cost,
        "upperBoundIsNotRatifiedHardLimit": True,
    }:
        errors.append("proposal cost bound or unratified limit changed")
    if proposal.get("unresolvedBeforeLive") != {
        "privacyDecisionForProposedRoute": None,
        "replacementRouteCompatibilityProof": None,
        "versionedModelsAndPolicyWithMockedPayloads": None,
        "reviewedRetryingRunnerAndImmutableEvidenceLedger": None,
        "exactProfileRatification": None,
        "finiteLineageHardLimitRatification": None,
        "initialLiveAuthorization": None,
    } or proposal.get("authority") != {
        "credentialRead": False, "providerInference": False, "spend": False,
        "liveRun": False, "publishResults": False, "productionChange": False,
    }:
        errors.append("proposal incorrectly grants live authority")
    local_catalogue = "notPresentInCheckout"
    try:
        run_dir = safe_run_dir(CATALOGUE_RUN_ID, create=False)
    except (FileNotFoundError, ValueError):
        run_dir = None
    if run_dir is not None:
        source = run_dir / "live-catalogue" / "mistralai--mistral-small-2603.json"
        if source.is_file():
            if sha256_file(source) != route.get("publicCatalogueEndpointResponseSha256"):
                errors.append("local public endpoint response changed")
            else:
                endpoints = strict_json_load(source).get("data", {}).get("endpoints", [])
                matches = [entry for entry in endpoints if entry.get("tag") == "mistral"]
                if len(matches) != 1 or matches[0] != endpoint:
                    errors.append("proposed public Mistral route is not exact and available")
                elif matches[0].get("pricing", {}).get("prompt") != route["unchangedInputPricePerTokenUSD"] or matches[0].get("pricing", {}).get("completion") != route["unchangedOutputPricePerTokenUSD"]:
                    errors.append("proposed public Mistral route price changed")
                else:
                    local_catalogue = "exactLocalPublicCatalogueEvidence"
    for run, run_id in zip(runs, PRIOR_RUN_IDS):
        try:
            local_run = safe_run_dir(run_id, create=False)
        except (FileNotFoundError, ValueError):
            continue
        if local_run.is_dir():
            files = {
                str(path.relative_to(local_run)): sha256_file(path)
                for path in sorted(local_run.rglob("*")) if path.is_file()
            }
            if files != run["fileSha256"]:
                errors.append(f"local terminal evidence changed: {run_id}")
    return {
        "status": "valid" if not errors else "invalid",
        "errors": errors,
        "proposalSha256": sha256_file(PROPOSAL),
        "localCatalogue": local_catalogue,
        "liveAuthorized": False,
    }
