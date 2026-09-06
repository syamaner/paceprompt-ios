# Open-weight workout-import evaluation v4

Status: reviewed aggregate evidence for GitHub issue #17. The human decision
was ratified on 6 September 2026: no evaluated open-weight candidate qualifies,
and the existing `openai/gpt-5.6-sol` selection remains unchanged.

This summary contains no complete prompt, model response, request header,
credential, personal data or device identifier. Complete evidence remains only
in the ignored local `.runs/` directory.

## Evidence scope

- Source base: `9c90200779bb08180c0592d26802b18d2ab39e56`
- Successful run: `issue17-open-weight-eval-20260905-03`
- Report contract: `paceprompt-host-eval-open-weight-report/v4`
- Frozen queue: 9 warm-ups and 2,133 scored attempts across 9 routes
- Actual provider calls: 1,116, comprising 9 warm-ups and 1,107 scored calls
- Explicitly not started: 1,026 scored attempts, comprising 237 prerequisite
  mismatches after a failed warm-up and 789 rate-limit pauses
- Terminal accounting: all 2,142 scheduled attempts are terminal
- Scored outcomes: 848 schema-valid live outputs, including 9 scorer failures;
  254 schema-invalid outputs; and 5 infrastructure failures. Scorer failures
  remain excluded from aggregate scored-valid counts.
- Provider-reported charge recorded by the successful run guard: `$0.911778035`
- Mechanical evidence audit: passed with no errors

The run reused the sealed prompt-v3 development and held-out corpus, unchanged
deterministic scorer, fixed Sol reference evidence and pre-ratified v4 model,
route, response-contract and run-policy files. The complete candidate and
licence rationale is recorded in
`HostEval/open-weight-candidate-matrix-v4.md`.

## Candidate results

All candidates were ineligible. Composite percentages retain the ratified
denominators, including failed and not-started attempts. A missing p95 or cost
means the policy did not permit a complete comparable measurement.

| Candidate | Complete responses | Aggregate schema-valid | Composite | Host p95 | Scored cost | Primary outcome |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `qwen/qwen3.8-27b` | 237 | 221 | 91.9060% | 22,287 ms | $0.51092908 | Failed strict validity, safety, capability and category floors |
| `deepseek/deepseek-v4-flash-0731` | 236 | 206 | 84.0485% | 50,104 ms | Unmeasured | Failed strict validity, safety, capability, authority, category and composite gates |
| `minimax/minimax-m3` | 237 | 189 | 73.3667% | 2,694 ms | $0.08415696 | Failed strict validity, safety, capability, category and composite gates |
| `qwen/qwen-2.5-7b-instruct` | 236 | 125 | 48.6401% | 3,613 ms | $0.0947290 | Failed strict validity, safety, capability, category and composite gates |
| `nvidia/nemotron-3.5-lightning` | 115 | 74 | 18.9267% | Unmeasured | Unmeasured | Rate-limit pause; partial ranking prohibited |
| `nvidia/nemotron-3-ultra-550b-a55b` | 13 | 11 | 2.8497% | Unmeasured | Unmeasured | Rate-limit pause; partial ranking prohibited |
| `mistralai/mistral-small-3.2-24b-instruct` | 18 | 12 | 2.5989% | Unmeasured | Unmeasured | Rate-limit pause; partial ranking prohibited |
| `z-ai/glm-5.3-flash` | 1 | 1 | 0.2764% | Unmeasured | Unmeasured | Rate-limit pause; partial ranking prohibited |
| `mistralai/mistral-small-2603` | 0 | 0 | 0.0000% | Unmeasured | Unmeasured | Warm-up ended at the output limit; scored calls not started |

The fixed Sol reference remains eligible at 99.3817% composite, 237 of 237
schema-valid responses, 3,625 ms development-host p95 and `$1.04827180`
provider-reported scored cost.

## Preserved harness failures

Two earlier attempts remain local evidence rather than being silently replaced:

- `issue17-open-weight-eval-20260905-01` made 10 provider calls and recorded
  `$0.018812705` before an inherited v4 runner-state defect stopped the harness.
- `issue17-open-weight-eval-20260905-02` made 33 provider calls and had recorded
  `$0.044220550` in its last persisted state before an unchanged-scorer
  rejection stopped the harness. The exact final-call charge is unavailable.

Both defects were repaired and regression-tested before the successful run.

## Integrity hashes

- Aggregate report:
  `9975c7123525b1062667eae8c1c54558af9200ee9a853f8a2201eeb8b0d9d00e`
- Evidence-integrity audit:
  `c05c8ac09439cd7c34914282ca318cba54e2117c452c304fd1bb4a051419847c`
- Final live state:
  `8e752cc0df5dee3ebe82f6cd102f40225b85ef709c724766487421a886a851ee`

These hashes identify ignored local files under
`.runs/host-eval/issue17-open-weight-eval-20260905-03/`; the files themselves
are not committed.

## Human decision and boundary

The automatically eligible set and top tie group are empty. There is no
automatic winner. The human decision is to select no open-weight candidate and
retain `openai/gpt-5.6-sol` as the selected provider. This does not itself
change production inference.

No production provider integration, API-key UI or storage, app network call,
iPhone or Apple Foundation Models operation, treadmill connection or operation,
FTMS Control Point write, workout execution, HealthKit or watchOS work was part
of this evaluation.
