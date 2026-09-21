# Issue #145 candidate and oracle review r1

Review date: 20 September 2026

This is a zero-spend proposal for separate operator ratification. It authorises
no credential read, compatibility probe, scored inference call or spend.

## Outcome

All 12 requested model IDs remain in OpenRouter's public catalogue and every
canonical revision still matches the earlier v3 or v4 configuration. Ten exact
provider routes also remain available. Two prior routes have disappeared:

- `mistralai/mistral-small-2603`: `venice/fp8` is absent. The recommended
  replacement is the current `mistral/zdr` endpoint. It reports native strict
  structured-output parameters, explicitly identifies the ZDR route, uses
  unreported quantisation, and requires a new compatibility probe.
- `deepseek/deepseek-v4-flash-0731`: `open-inference/fp8` is absent. The
  recommended replacement is `deepinfra/fp8`. It preserves FP8, reports the
  native strict-output parameters used by v4, and requires a new compatibility
  probe.

No replacement has been silently adopted. Both are recommendations in
`issue145-candidate-review-r1.json` and remain inert until ratified.

The BaseTen Nemotron Ultra endpoint still appears twice with materially
equivalent records. The prior fail-closed duplicate exception remains the
recommendation; it must be rechecked mechanically at gate preparation.

The refreshed public models catalogue SHA-256 is
`f3fdd0b0aa0e065dd56f3e7ba63b1ee3a798fef86563c51ceab8ad4c78285a47`.
Endpoint prices and supported parameters are volatile and are deliberately not
frozen here; a later zero-spend gate must snapshot and cost them again.

## Model and licence sources

The nine open-weight publisher artifacts and licence classifications remain
those documented in `open-weight-candidate-matrix-v4.md`. Their publisher model
cards were re-opened during this review. No evidence was found that changes the
recorded Apache-2.0, MIT, OpenMDW-1.1 or MiniMax Community Licence boundaries.
An OpenRouter canonical revision and hosted endpoint still do not prove which
publisher weight commit the provider deployed.

## Question and answer review

The proposed evaluation contains two separately reported, sealed strata:

- 79 unchanged v3 held-out regression cases;
- 30 issue #130 acceptance cases at revision
  `issue-130-reviewer-acceptance/r2`, corpus hash
  `204c6814cb62523426ed8871d77159f39a4daf4dc495ece7fcc70627e6d22864`.

Both existing mechanical verifiers pass. The issue #130 verifier confirms 19
proposal expectations, 11 fail-closed expectations, 17 locally valid proposals
and two deliberate local-validator rejections. Cross-stratum review found no
duplicate IDs, exact prompt collision or normalized semantic-skeleton
collision. The expected answers, reason categories, affected paths, canonical
mapping and local-validator outcomes therefore require no amendment for this
run. Both corpora remain byte-for-byte unchanged.

## Recommended execution profile

The JSON proposal freezes the recommendation before results: all 12 models,
both strata, three repetitions per stratum, 3,924 scored attempts, 12 warm-ups
and 3,936 total calls. It retains each model's prior ratified generation and
transport profile, one serial worker, a two-second minimum gap, zero retries,
15-second connect and 180-second attempt timeouts, non-resumable execution and
separate hard-gate/category reporting for every model and stratum.

This is intentionally not a spending gate. After candidate/profile
ratification and the two replacement-route compatibility probes, implementation
must mock every complete payload, generate the deterministic queue, refresh
prices and present a conservative hard spending limit for separate ratification.
