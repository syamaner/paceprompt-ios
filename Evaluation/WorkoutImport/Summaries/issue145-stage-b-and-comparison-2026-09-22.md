# Issue #145 Stage A+B comparison and Stage B publication proposal

Status: proposed for separate human ratification. This document is not yet a
published result, selects no production model and changes no production model,
route, prompt, schema, parser, mapping, UI or release configuration.

## Accepted evidence

- Stage A run: `issue145-top4-stage-a-v5-20260920-01`
- Stage B run: `issue145-top3-stage-b-v5-20260921-01`
- Stage A aggregate SHA-256: `bf922a6302e78ac47064ce578991e2205ca2d59592a123f29b65515dca2c2e0e`
- Stage A evidence-audit SHA-256: `1748bec83ca90a9a75573e29e589f4595c25cc0c1416623e915be74d31a4738e`
- Stage B aggregate SHA-256: `eeff4536b0a7d6830e6457ed9ec9c1bdd95616a731af19158d4e56edb71adb33`
- Stage B evidence-audit SHA-256: `5dd8c5487596da0575a934f13887559c1f516ba6f1a77590c6e8311f80da86c6`
- Stage B final live-state SHA-256: `2dccdfa186f42ae232577dfafac794fca7e1fd69dafc3377d4e3211dc849be19`

Both mechanical evidence audits passed. The two executions reached all 1,097
scheduled terminal positions, made 988 provider calls and recorded a combined
guard charge of `$3.23370139`. The protected comparison retains only the
three models with all three scored repetitions, comprising 981 attempts over
109 distinct cases. Gemini remains represented in the Stage A publication and
is not introduced into the three-repetition comparison because it failed its
Stage A strict-schema warm-up and received no scored calls.

## Three-repetition comparison

| Model | Strict exact attempts | v3 composite | #130 composite | v3 eligible | #130 eligible |
| --- | ---: | ---: | ---: | --- | --- |
| `openai/gpt-5.6-sol` | 311/327 | 97.1961% | 100.0000% | false | false |
| `qwen/qwen3.8-27b` | 290/327 | 90.1018% | 97.6667% | false | false |
| `openai/gpt-5.6-luna` | 271/327 | 87.7941% | 83.2661% | false | false |

The exact per-category floors, hard-gate flags, confusion counts, latency and
scored cost remain in `issue145-stage-a-b-comparison-data.json`. No winner is
selected automatically.

## Gate interpretation requiring operator review

The issue #130 acceptance stratum has no `knownCapabilityUnsupported` cases.
The inherited v3 scorer defines `capabilityBoundaryExactness` as false when
that category is empty. Consequently every model is decision-ineligible on
that stratum even if all present acceptance cases are correct. This proposal
preserves that result and applies no scorer or gate relaxation. Human review
must decide separately whether the stratum is diagnostic-only for that gate,
whether a new scorer revision is needed, or whether no production selection
should be made.

## Proposed publication set

- A byte-preserved Stage B aggregate and evidence audit.
- This human report.
- A deterministic Stage A+B comparison over repetitions 1, 2 and 3.
- A manifest binding the protected Stage A publication, accepted ignored-run
  provenance, and every proposed new publication byte.

Raw requests, model responses, transcripts, prompts, headers, authorisation
phrases and local live state remain ignored and unpublished. Existing Stage A,
v3, v4 and issue #130 evidence remains byte-identical.

## Decision boundary

Ratifying this proposal would authorise the bounded publication implementation
and exact-head review only. Model selection, a production configuration change,
merge and issue closure remain separate decisions.
