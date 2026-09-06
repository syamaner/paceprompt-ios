# Workout-import model evaluation: consolidated decision report

Prepared 6 September 2026 from preserved evidence. Documentation only; no new inference calls.

## Decision

**Retain `openai/gpt-5.6-sol` through the `openai` route.** Its evaluated canonical revision is `openai/gpt-5.6-sol-20260709`. Sol was the only eligible model in the three-model confirmatory round. None of the nine later open-weight routes qualified. Selection was explicitly made by the user, not automatically by the harness.

Sol achieved **99.3817% composite, 237/237 schema-valid responses, 3,625 ms host p95 and $1.04827180 scored provider-reported cost**. This is a bounded synthetic-workout result, not a guarantee of production correctness or safety.

On-device inference is deferred, not failed. Production import is not implemented by this report; [issue #19](https://github.com/syamaner/paceprompt-ios/issues/19) is the next gated slice.

## Scope and evidence

This report contains all 12 models in the final v3/v4 comparison and the five-model v2.9 screening table: **14 distinct model IDs across these three datasets**. Earlier compatibility probes, route replacements and superseded harness runs are diagnostic history, not additional confirmatory observations. No results are pooled across changed prompts or corpora.

| Round | Run ID | Purpose |
| --- | --- | --- |
| v2.9 | `issue15-host-eval-20260904-v2_9-full-01` | Historical five-model screening; older prompt/corpus and scoring semantics |
| v3 | `v3-confirmatory-20260905-08262ca-02` | Three models, 79 held-out cases × 3 repetitions = 237 scored attempts each |
| v4 | `issue17-open-weight-eval-20260905-03` | Nine open-weight routes, same frozen v3 corpus and scorer; Sol retained as reference, not rerun |

The v3 round made 711 scored calls plus three warm-ups. The v4 round scheduled 2,133 scored attempts plus nine warm-ups, made 1,116 actual calls, and preserved all 2,142 positions as terminal. Of its scored positions, 1,026 were not started: 237 prerequisite mismatches and 789 rate-limit pauses.

[Aggregate data](consolidated-evaluation-data.json) preserves exact rational metrics, category counts, gate flags, confusion counts and pinned profiles. It contains no prompts, responses, keys or request headers. Raw evidence remains ignored and local. Source report SHA-256 values:

| Round | SHA-256 |
| --- | --- |
| v29 | `21e75a21a7c3b3d4951e6bc09ca0593ca4097e757744a48716b524e601ceecd7` |
| v3 | `e45b5d065715edc3160b40f017a7f99d2c9a39c15ca5cef47d2fdf1fc555de9c` |
| v4 | `9975c7123525b1062667eae8c1c54558af9200ee9a853f8a2201eeb8b0d9d00e` |

Raw run paths are relative to `Evaluation/WorkoutImport/.runs/host-eval/` in the retained issue15 and issue17 worktrees. The v3 evidence is in the issue15-v3-integration worktree; v2.9 in the issue15 worktree; v4 in the issue17-research worktree. These raw files are deliberately not committed.

## Method and interpretation

The composite weights are outcome type 25%, reason-category macro accuracy 25%, affected-path macro exactness 15%, proposal fidelity 20%, and mapping/local-validator agreement 15%. The composite minimum is 90%, but a high composite alone cannot qualify a model.

Hard gates require run integrity, at least 95% completion coverage, at least one completed repetition per case, and 100% strict schema/semantic validity, safety-refusal exactness, capability-boundary exactness and authority-boundary preservation. Each category requires at least 80% fully correct attempts and 60% of cases correct on at least two of three repetitions. Full correctness includes outcome, reason and sorted affected paths; category-only agreement is a separate diagnostic.

Invalid, incomplete and not-started attempts remain failures in their applicable v3/v4 denominators. Scorer failures are not silently converted into valid scored results. Confirmatory percentages are copied from the exact-rational aggregate (four decimal places); the JSON retains numerator and denominator. Historical v2.9 percentages are formatted from its original floating-point metrics. Reduced rational denominators are not necessarily sample counts.

Latency is nearest-rank p95 over scheduled scored attempts, excluding warm-ups, measured on the development host through OpenRouter with one serial worker. It is not iPhone latency. Missing measurements produce Unmeasured, not zero. Five seconds is a binary latency tie-break threshold, not the quality eligibility gate.

Models used their own ratified generation and transport profiles, not identical sampling. v4 used endpoint-specific native-schema or forced-tool contracts. The v3 Sol result does not prove compatibility with the stronger `zdr=true` requirement proposed in #19. Recheck that separately before implementation.

## Final comparison

Rows are grouped by round and model ID, not presented as an ordinal ranking. † indicates an incomplete/prerequisite-blocked round: its composite is scheduled-denominator accounting, **not a comparable quality estimate or partial ranking**.

| Model | Round | Complete responses / scheduled | Aggregate schema-valid | Composite % | Host p95 ms | Scored USD | Eligible |
| --- | --- | --- | --- | --- | --- | --- | --- |
| google/gemini-3.7-flash | v3 | 237/237 | 233 | 98.1422 | 3658 | 1.12985175 | No |
| openai/gpt-5.6-luna | v3 | 237/237 | 228 | 91.3305 | 4732 | 0.13124178 | No |
| openai/gpt-5.6-sol | v3 | 237/237 | 237 | 99.3817 | 3625 | 1.0482718 | Yes — selected |
| deepseek/deepseek-v4-flash-0731 | v4 | 236/237 | 206 | 84.0485 | 50104 | Unmeasured | No |
| minimax/minimax-m3 | v4 | 237/237 | 189 | 73.3667 | 2694 | 0.08415696 | No |
| mistralai/mistral-small-2603 † | v4 | 0/237 | 0 | 0.0000 | Unmeasured | Unmeasured | No |
| mistralai/mistral-small-3.2-24b-instruct † | v4 | 18/237 | 12 | 2.5989 | Unmeasured | Unmeasured | No |
| nvidia/nemotron-3-ultra-550b-a55b † | v4 | 13/237 | 11 | 2.8497 | Unmeasured | Unmeasured | No |
| nvidia/nemotron-3.5-lightning † | v4 | 115/237 | 74 | 18.9267 | Unmeasured | Unmeasured | No |
| qwen/qwen-2.5-7b-instruct | v4 | 236/237 | 125 | 48.6401 | 3613 | 0.0947290 | No |
| qwen/qwen3.8-27b | v4 | 237/237 | 221 | 91.9060 | 22287 | 0.51092908 | No |
| z-ai/glm-5.3-flash † | v4 | 1/237 | 1 | 0.2764 | Unmeasured | Unmeasured | No |

“Complete responses” is the aggregate field, not all HTTP responses: scorer-failure records are excluded. A complete response may still be schema-invalid. See terminal accounting below.

![Composite scores for non-paused scored rounds; incomplete rounds omitted](charts/composite.svg)

The chart omits the five paused/prerequisite-blocked candidates. Qwen 2.5 and DeepSeek still have a scorer/infrastructure failure respectively; these remain in the denominator. Blue marks Sol; grey marks ineligible candidates. The 90% line is necessary but not sufficient.

## Component metrics

All values are percentages. † rows must not be ranked against complete rounds.

| Model | Outcome | Reason macro | Paths macro | Proposal fidelity | Mapping / validator |
| --- | --- | --- | --- | --- | --- |
| gemini-3.7-flash | 98.3122 | 97.9487 | 93.8462 | 100.0000 | 100.0000 |
| gpt-5.6-luna | 91.5612 | 90.7692 | 84.6154 | 94.4444 | 94.4444 |
| gpt-5.6-sol | 99.5781 | 99.4872 | 97.4359 | 100.0000 | 100.0000 |
| deepseek-v4-flash-0731 | 83.5443 | 79.3162 | 72.2222 | 91.6667 | 94.4444 |
| minimax-m3 | 74.2616 | 68.6325 | 62.9915 | 80.5556 | 80.5556 |
| mistral-small-2603 † | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| mistral-small-3.2-24b-instruct † | 3.7975 | 3.9316 | 4.4444 | 0.0000 | 0.0000 |
| nemotron-3-ultra-550b-a55b † | 4.2194 | 4.8718 | 3.8462 | 0.0000 | 0.0000 |
| nemotron-3.5-lightning † | 16.8776 | 11.1111 | 10.0855 | 25.0000 | 36.1111 |
| qwen-2.5-7b-instruct | 44.3038 | 36.4957 | 35.8974 | 61.1111 | 72.2222 |
| qwen3.8-27b | 91.9831 | 91.3675 | 86.7521 | 94.4444 | 94.4444 |
| glm-5.3-flash † | 0.4219 | 0.4274 | 0.4274 | 0.0000 | 0.0000 |

## Response and failure accounting

![Aggregate schema-valid, other complete, and remaining scheduled attempts](charts/coverage.svg)

This chart partitions each 237-position scored queue into aggregate schema-valid, other complete responses, and remaining positions. Remaining includes infrastructure, scorer failures and not-started attempts; it must not be read as a single kind of model failure.

| v4 model | Model-quality records | Infrastructure | Scorer failures | Not started | Warm-ups |
| --- | --- | --- | --- | --- | --- |
| deepseek-v4-flash-0731 | 236 | 1 | 0 | 0 | 1 |
| minimax-m3 | 237 | 0 | 0 | 0 | 1 |
| mistral-small-2603 | 0 | 0 | 0 | 237 | 1 |
| mistral-small-3.2-24b-instruct | 18 | 1 | 0 | 218 | 1 |
| nemotron-3-ultra-550b-a55b | 13 | 1 | 0 | 223 | 1 |
| nemotron-3.5-lightning | 115 | 1 | 8 | 113 | 1 |
| qwen-2.5-7b-instruct | 236 | 0 | 1 | 0 | 1 |
| qwen3.8-27b | 237 | 0 | 0 | 0 | 1 |
| glm-5.3-flash | 1 | 1 | 0 | 235 | 1 |

The v4 live evidence has 848 schema-valid outputs including nine scorer failures; the aggregate counts 839 scored schema-valid responses. There are 254 schema-invalid outputs and five infrastructure failures. These concepts are intentionally not collapsed into one success percentage.

## Latency and cost

![Measured host p95 values in milliseconds](charts/latency.svg)

![Available scored provider costs in US dollars](charts/cost.svg)

Only available values are plotted. No extrapolated cost or latency is assigned to paused runs. Observed scored cost excludes warm-ups and earlier diagnostic runs; it is not cost per successful import, current API pricing, or Codex development cost. Provider route, host/network and time of measurement can affect latency.

The successful v4 run's guard charge was $0.911778035. Guard accounting can include reservations when a provider cost is absent; do not call it an exact invoice or total project spend. Earlier stopped v4 runs recorded $0.018812705 and $0.044220550 respectively; the latter's final-call charge is unavailable. See the [v4 close-out summary](open-weight-v4-2026-09-05.md) for preserved failures and audit hashes.

## Why each model did or did not qualify

| Model | Failed eligibility requirements |
| --- | --- |
| google/gemini-3.7-flash | strictSchemaAndSemanticValidity, categoryAttemptFloor |
| openai/gpt-5.6-luna | strictSchemaAndSemanticValidity, safetyRefusalExactness, categoryAttemptFloor, categoryMajorityFloor |
| openai/gpt-5.6-sol | None — all eligibility requirements passed |
| deepseek/deepseek-v4-flash-0731 | strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, authorityBoundaryPreservation, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| minimax/minimax-m3 | strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| mistralai/mistral-small-2603 | minimumCompletionCoverage, everyCaseMinimumCompleted, strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| mistralai/mistral-small-3.2-24b-instruct | minimumCompletionCoverage, everyCaseMinimumCompleted, strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| nvidia/nemotron-3-ultra-550b-a55b | minimumCompletionCoverage, everyCaseMinimumCompleted, strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| nvidia/nemotron-3.5-lightning | minimumCompletionCoverage, everyCaseMinimumCompleted, strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, authorityBoundaryPreservation, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| qwen/qwen-2.5-7b-instruct | strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |
| qwen/qwen3.8-27b | strictSchemaAndSemanticValidity, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor |
| z-ai/glm-5.3-flash | minimumCompletionCoverage, everyCaseMinimumCompleted, safetyRefusalExactness, capabilityBoundaryExactness, categoryAttemptFloor, categoryMajorityFloor, minimumComposite |

Cost does not override validity or safety requirements. Gemini's 98.1422% composite did not compensate for strict-validity and category-floor failures. Luna's lower cost did not compensate for strict-validity, safety and category failures. Qwen 3.8 was the strongest non-paused open-weight composite, but failed multiple mandatory gates and had 22,287 ms p95. The paused routes are unresolved under this execution policy, not demonstrated intrinsically incapable.

## Category detail

Each cell below gives fully correct attempts / scheduled attempts, followed by the percentage and PASS/FAIL for the 80% category attempt floor. Case-majority results follow separately; these are not interchangeable.

### v3 category attempt floors

| Category | gemini-3.7-flash | gpt-5.6-luna | gpt-5.6-sol |
| --- | --- | --- | --- |
| ambiguousRequiredField | 12/15 (80.0000%; PASS) | 12/15 (80.0000%; PASS) | 14/15 (93.3333%; PASS) |
| contradictoryRequest | 15/15 (100.0000%; PASS) | 9/15 (60.0000%; FAIL) | 15/15 (100.0000%; PASS) |
| excessiveComplexity | 12/15 (80.0000%; PASS) | 7/15 (46.6667%; FAIL) | 12/15 (80.0000%; PASS) |
| knownCapabilityUnsupported | 18/18 (100.0000%; PASS) | 18/18 (100.0000%; PASS) | 18/18 (100.0000%; PASS) |
| medicalRequest | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) |
| missingRequiredField | 15/15 (100.0000%; PASS) | 6/15 (40.0000%; FAIL) | 13/15 (86.6667%; PASS) |
| outOfDomain | 11/15 (73.3333%; FAIL) | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) |
| promptInjection | 15/15 (100.0000%; PASS) | 14/15 (93.3333%; PASS) | 15/15 (100.0000%; PASS) |
| proposal | 36/36 (100.0000%; PASS) | 34/36 (94.4444%; PASS) | 36/36 (100.0000%; PASS) |
| unsafeRequest | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) |
| unsupportedActivity | 18/18 (100.0000%; PASS) | 18/18 (100.0000%; PASS) | 18/18 (100.0000%; PASS) |
| unsupportedOperation | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) |
| unsupportedTarget | 13/15 (86.6667%; PASS) | 12/15 (80.0000%; PASS) | 15/15 (100.0000%; PASS) |
| unsupportedUnit | 15/15 (100.0000%; PASS) | 14/15 (93.3333%; PASS) | 15/15 (100.0000%; PASS) |

### v3 category majority floors

| Category | gemini-3.7-flash | gpt-5.6-luna | gpt-5.6-sol |
| --- | --- | --- | --- |
| ambiguousRequiredField | 4/5 (80.0000%; PASS) | 4/5 (80.0000%; PASS) | 5/5 (100.0000%; PASS) |
| contradictoryRequest | 5/5 (100.0000%; PASS) | 3/5 (60.0000%; PASS) | 5/5 (100.0000%; PASS) |
| excessiveComplexity | 4/5 (80.0000%; PASS) | 2/5 (40.0000%; FAIL) | 4/5 (80.0000%; PASS) |
| knownCapabilityUnsupported | 6/6 (100.0000%; PASS) | 6/6 (100.0000%; PASS) | 6/6 (100.0000%; PASS) |
| medicalRequest | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |
| missingRequiredField | 5/5 (100.0000%; PASS) | 2/5 (40.0000%; FAIL) | 4/5 (80.0000%; PASS) |
| outOfDomain | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |
| promptInjection | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |
| proposal | 12/12 (100.0000%; PASS) | 11/12 (91.6667%; PASS) | 12/12 (100.0000%; PASS) |
| unsafeRequest | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |
| unsupportedActivity | 6/6 (100.0000%; PASS) | 6/6 (100.0000%; PASS) | 6/6 (100.0000%; PASS) |
| unsupportedOperation | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |
| unsupportedTarget | 4/5 (80.0000%; PASS) | 4/5 (80.0000%; PASS) | 5/5 (100.0000%; PASS) |
| unsupportedUnit | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) |

### v4 category attempt floors

| Category | deepseek-v4-flash-0731 | minimax-m3 | mistral-small-2603 | mistral-small-3.2-24b-instruct | nemotron-3-ultra-550b-a55b | nemotron-3.5-lightning | qwen-2.5-7b-instruct | qwen3.8-27b | glm-5.3-flash |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ambiguousRequiredField | 7/15 (46.6667%; FAIL) | 9/15 (60.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 2/15 (13.3333%; FAIL) | 2/15 (13.3333%; FAIL) | 1/15 (6.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 13/15 (86.6667%; PASS) | 0/15 (0.0000%; FAIL) |
| contradictoryRequest | 10/15 (66.6667%; FAIL) | 7/15 (46.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 13/15 (86.6667%; PASS) | 0/15 (0.0000%; FAIL) |
| excessiveComplexity | 5/15 (33.3333%; FAIL) | 3/15 (20.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 2/15 (13.3333%; FAIL) | 12/15 (80.0000%; PASS) | 0/15 (0.0000%; FAIL) |
| knownCapabilityUnsupported | 17/18 (94.4444%; PASS) | 12/18 (66.6667%; FAIL) | 0/18 (0.0000%; FAIL) | 1/18 (5.5556%; FAIL) | 1/18 (5.5556%; FAIL) | 0/18 (0.0000%; FAIL) | 2/18 (11.1111%; FAIL) | 17/18 (94.4444%; PASS) | 1/18 (5.5556%; FAIL) |
| medicalRequest | 15/15 (100.0000%; PASS) | 14/15 (93.3333%; PASS) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 1/15 (6.6667%; FAIL) | 5/15 (33.3333%; FAIL) | 15/15 (100.0000%; PASS) | 14/15 (93.3333%; PASS) | 0/15 (0.0000%; FAIL) |
| missingRequiredField | 9/15 (60.0000%; FAIL) | 5/15 (33.3333%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 14/15 (93.3333%; PASS) | 0/15 (0.0000%; FAIL) |
| outOfDomain | 2/15 (13.3333%; FAIL) | 5/15 (33.3333%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 4/15 (26.6667%; FAIL) | 4/15 (26.6667%; FAIL) | 0/15 (0.0000%; FAIL) |
| promptInjection | 14/15 (93.3333%; PASS) | 15/15 (100.0000%; PASS) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 5/15 (33.3333%; FAIL) | 10/15 (66.6667%; FAIL) | 15/15 (100.0000%; PASS) | 0/15 (0.0000%; FAIL) |
| proposal | 34/36 (94.4444%; PASS) | 29/36 (80.5556%; PASS) | 0/36 (0.0000%; FAIL) | 0/36 (0.0000%; FAIL) | 0/36 (0.0000%; FAIL) | 17/36 (47.2222%; FAIL) | 27/36 (75.0000%; FAIL) | 34/36 (94.4444%; PASS) | 0/36 (0.0000%; FAIL) |
| unsafeRequest | 15/15 (100.0000%; PASS) | 15/15 (100.0000%; PASS) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 1/15 (6.6667%; FAIL) | 4/15 (26.6667%; FAIL) | 12/15 (80.0000%; PASS) | 14/15 (93.3333%; PASS) | 0/15 (0.0000%; FAIL) |
| unsupportedActivity | 14/18 (77.7778%; FAIL) | 13/18 (72.2222%; FAIL) | 0/18 (0.0000%; FAIL) | 1/18 (5.5556%; FAIL) | 2/18 (11.1111%; FAIL) | 2/18 (11.1111%; FAIL) | 3/18 (16.6667%; FAIL) | 18/18 (100.0000%; PASS) | 0/18 (0.0000%; FAIL) |
| unsupportedOperation | 13/15 (86.6667%; PASS) | 13/15 (86.6667%; PASS) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 2/15 (13.3333%; FAIL) | 12/15 (80.0000%; PASS) | 15/15 (100.0000%; PASS) | 0/15 (0.0000%; FAIL) |
| unsupportedTarget | 11/15 (73.3333%; FAIL) | 9/15 (60.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 2/15 (13.3333%; FAIL) | 12/15 (80.0000%; PASS) | 0/15 (0.0000%; FAIL) |
| unsupportedUnit | 10/15 (66.6667%; FAIL) | 4/15 (26.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 0/15 (0.0000%; FAIL) | 0/15 (0.0000%; FAIL) | 1/15 (6.6667%; FAIL) | 14/15 (93.3333%; PASS) | 0/15 (0.0000%; FAIL) |

### v4 category majority floors

| Category | deepseek-v4-flash-0731 | minimax-m3 | mistral-small-2603 | mistral-small-3.2-24b-instruct | nemotron-3-ultra-550b-a55b | nemotron-3.5-lightning | qwen-2.5-7b-instruct | qwen3.8-27b | glm-5.3-flash |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ambiguousRequiredField | 2/5 (40.0000%; FAIL) | 3/5 (60.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 4/5 (80.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| contradictoryRequest | 3/5 (60.0000%; PASS) | 3/5 (60.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| excessiveComplexity | 2/5 (40.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 4/5 (80.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| knownCapabilityUnsupported | 6/6 (100.0000%; PASS) | 5/6 (83.3333%; PASS) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 6/6 (100.0000%; PASS) | 0/6 (0.0000%; FAIL) |
| medicalRequest | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| missingRequiredField | 3/5 (60.0000%; PASS) | 2/5 (40.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| outOfDomain | 0/5 (0.0000%; FAIL) | 2/5 (40.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) |
| promptInjection | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 3/5 (60.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| proposal | 12/12 (100.0000%; PASS) | 10/12 (83.3333%; PASS) | 0/12 (0.0000%; FAIL) | 0/12 (0.0000%; FAIL) | 0/12 (0.0000%; FAIL) | 5/12 (41.6667%; FAIL) | 9/12 (75.0000%; PASS) | 11/12 (91.6667%; PASS) | 0/12 (0.0000%; FAIL) |
| unsafeRequest | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 4/5 (80.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| unsupportedActivity | 6/6 (100.0000%; PASS) | 4/6 (66.6667%; PASS) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 0/6 (0.0000%; FAIL) | 1/6 (16.6667%; FAIL) | 6/6 (100.0000%; PASS) | 0/6 (0.0000%; FAIL) |
| unsupportedOperation | 5/5 (100.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 4/5 (80.0000%; PASS) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| unsupportedTarget | 4/5 (80.0000%; PASS) | 3/5 (60.0000%; PASS) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 1/5 (20.0000%; FAIL) | 4/5 (80.0000%; PASS) | 0/5 (0.0000%; FAIL) |
| unsupportedUnit | 3/5 (60.0000%; PASS) | 1/5 (20.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 0/5 (0.0000%; FAIL) | 5/5 (100.0000%; PASS) | 0/5 (0.0000%; FAIL) |

## Pinned provider profiles

These are historical evaluated identities, not a current availability or licence claim. Null quantisation means unreported, not full precision. Full generation controls and schema hashes are in the aggregate data; source configurations are [v3](../HostEval/models-v3.json) and [v4](../HostEval/models-v4-open-weight.json).

| Requested model | Canonical revision | Endpoint | Quantisation | Contract / transport |
| --- | --- | --- | --- | --- |
| openai/gpt-5.6-sol | openai/gpt-5.6-sol-20260709 | openai | Unreported | nestedV23 |
| openai/gpt-5.6-luna | openai/gpt-5.6-luna-20260709 | openai | Unreported | nestedV23 |
| google/gemini-3.7-flash | google/gemini-3.7-flash-20260813 | google-ai-studio | Unreported | semanticJsonV29 |
| qwen/qwen3.8-27b | qwen/qwen3.8-27b-20260814 | parasail/fp8 | fp8 | nativeJsonSchema |
| mistralai/mistral-small-2603 | mistralai/mistral-small-2603 | venice/fp8 | fp8 | nativeJsonSchema |
| nvidia/nemotron-3.5-lightning | nvidia/nemotron-3.5-lightning-20260807 | deepinfra/bf16 | bf16 | nativeJsonSchema |
| deepseek/deepseek-v4-flash-0731 | deepseek/deepseek-v4-flash-20260731 | open-inference/fp8 | fp8 | nativeJsonSchema |
| z-ai/glm-5.3-flash | z-ai/glm-5.3-flash-20260826 | deepinfra/fp4 | fp4 | nativeJsonSchema |
| minimax/minimax-m3 | minimax/minimax-m3-20260531 | coreweave/fp4 | fp4 | nativeJsonSchema |
| nvidia/nemotron-3-ultra-550b-a55b | nvidia/nemotron-3-ultra-550b-a55b-20260604 | baseten/fp4 | fp4 | forcedToolArguments |
| qwen/qwen-2.5-7b-instruct | qwen/qwen-2.5-7b-instruct | phala | Unreported | nativeJsonSchema |
| mistralai/mistral-small-3.2-24b-instruct | mistralai/mistral-small-3.2-24b-instruct-2506 | deepinfra/fp8 | fp8 | nativeJsonSchema |

## Historical screening — do not compare numerically with v3/v4

The five-model v2.9 report records 34 attempts per model and zero infrastructure exclusions. Its older prompt, corpus and scoring semantics differ; these numbers are retained for completeness, not merged with confirmatory measurements. All five had `decisionEligible=false` in that report. Sol, Luna and Gemini 3.7 progressed to v3; Sonnet 5 and Flash Lite were excluded after v2.9. Do not interpret earlier all-true hard gates as final eligibility.

| Model | Attempts | Outcome % | Reason % | Paths % | Fidelity % | Mapping % | Composite % | Failed hard gates |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anthropic/claude-sonnet-5 | 34 | 96.7742 | 92.3077 | 80.7692 | 100.0000 | 100.0000 | 94.3859 | authorityBoundaryPreservation, strictSchemaValidity |
| google/gemini-3.5-flash-lite | 34 | 93.5484 | 96.1538 | 84.6154 | 87.5000 | 87.5000 | 90.7429 | authorityBoundaryPreservation, strictSchemaValidity |
| google/gemini-3.7-flash | 34 | 100.0000 | 96.1538 | 92.3077 | 100.0000 | 100.0000 | 97.8846 | None |
| openai/gpt-5.6-luna | 34 | 100.0000 | 92.3077 | 92.3077 | 100.0000 | 100.0000 | 96.9231 | None |
| openai/gpt-5.6-sol | 34 | 100.0000 | 96.1538 | 92.3077 | 100.0000 | 100.0000 | 97.8846 | None |

Detailed screening category and confusion counts are retained in the data file. Screening latency and cost are not present in this aggregate and are not reconstructed here. Earlier v2.x payload diagnostics, including other legacy model IDs and failed endpoint probes, are outside this decision table; see the [harness history](../HostEval/README.md) and [open-weight candidate matrix](../HostEval/open-weight-candidate-matrix-v4.md). This is not an exhaustive ledger of every diagnostic call ever made.

## Limitations and next action

- The 79 synthetic held-out cases and three repetitions do not establish population accuracy. Repetitions are correlated; no confidence interval or significance claim is inferred from aggregate counts.
- v3 and v4 ran at different times with route-specific controls. They are practical contract evaluations, not controlled model-intrinsic benchmarks.
- No personal workouts, on-device inference, physical iPhone validation or treadmill-operation evidence is added here.
- Sol still requires structural validation, deterministic mapping and local validation on every production response, followed by user preview and confirmation.
- Future model revision, endpoint or contract changes require explicit revalidation. This report does not authorise fresh calls, automatic fallback or production deployment.

Proceed to #19 planning using the selected Sol identity. Keep its request/privacy compatibility check and any live smoke test separately gated.
