# Issue #145 eleven-model Together matrix — 26 September 2026

Accepted aggregate evidence; no new production model is selected. This publication is additive. Earlier v3/v4, issue #130 and Stage A/B publications remain unchanged.

## Outcome and coverage

The authorised lineage recorded all 3,608 logical positions: 11 warm-ups and 3,597 scored slots (2,607 held-out regression; 990 issue #130 acceptance). It made 2,265 physical sends, at most three per position, with no replay. Conservative cumulative charge was USD 66.418313025 against the USD 300.00 hard cap. This is a budget-ledger charge, not a provider invoice.

The amended eleven-model profile excludes unavailable `mistralai/mistral-small-2603`; MiniMax M3 uses the separately ratified Together route. This is not the original unamended twelve-model proposal. Gemini 3.7 Flash and Nemotron 3 Ultra failed warm-up admission and received no scored calls. GLM 5.3 Flash, Mistral Small 3.2 and Nemotron Lightning were paused after three HTTP 429 responses; subsequent slots remain skipped. Four uncertain sends remain unreplayed, including one interrupted root position conservatively represented as `terminalUnprojected`.

All scheduled slots remain in the denominator. An HTTP-complete response is not proof of schema validity, semantic correctness or admission. No candidate is decision-eligible on either stratum under the unchanged gates.

## Per-model, separately reported strata

Exact attempts mean unchanged deterministic scorer `overall == passed`, not merely outcome-category agreement. Latencies are development-host OpenRouter p95, not iPhone latency. Composite, hard gates, category floors, confusion counts, mapping/local-validator agreement and transport simplicity are retained in the byte-preserved aggregate JSON.

| Stratum | Model | Completed / scheduled | Schema valid | Strict exact | Composite | Host p95 ms | Eligible |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| issue130-acceptance-r2 | `deepseek/deepseek-v4-flash-0731` | 90/90 | 88 | 82/90 | 90.3333% | 19200 | false |
| issue130-acceptance-r2 | `google/gemini-3.7-flash` | 0/90 | 0 | 0/90 | 0.0000% | unavailable | false |
| issue130-acceptance-r2 | `minimax/minimax-m3` | 90/90 | 90 | 63/90 | 77.6901% | 2606 | false |
| issue130-acceptance-r2 | `mistralai/mistral-small-3.2-24b-instruct` | 0/90 | 0 | 0/90 | 0.0000% | unavailable | false |
| issue130-acceptance-r2 | `nvidia/nemotron-3-ultra-550b-a55b` | 0/90 | 0 | 0/90 | 0.0000% | unavailable | false |
| issue130-acceptance-r2 | `nvidia/nemotron-3.5-lightning` | 0/90 | 0 | 0/90 | 0.0000% | unavailable | false |
| issue130-acceptance-r2 | `openai/gpt-5.6-luna` | 90/90 | 90 | 75/90 | 85.6930% | 2984 | false |
| issue130-acceptance-r2 | `openai/gpt-5.6-sol` | 90/90 | 90 | 90/90 | 100.0000% | 3440 | false |
| issue130-acceptance-r2 | `qwen/qwen-2.5-7b-instruct` | 82/90 | 45 | 25/90 | 36.2310% | 5254 | false |
| issue130-acceptance-r2 | `qwen/qwen3.8-27b` | 89/90 | 87 | 86/90 | 94.5497% | unavailable | false |
| issue130-acceptance-r2 | `z-ai/glm-5.3-flash` | 0/90 | 0 | 0/90 | 0.0000% | unavailable | false |
| v3-heldout-regression | `deepseek/deepseek-v4-flash-0731` | 237/237 | 192 | 170/237 | 82.6624% | 26211 | false |
| v3-heldout-regression | `google/gemini-3.7-flash` | 0/237 | 0 | 0/237 | 0.0000% | unavailable | false |
| v3-heldout-regression | `minimax/minimax-m3` | 237/237 | 199 | 148/237 | 73.1944% | 2424 | false |
| v3-heldout-regression | `mistralai/mistral-small-3.2-24b-instruct` | 72/237 | 65 | 51/237 | 22.9843% | unavailable | false |
| v3-heldout-regression | `nvidia/nemotron-3-ultra-550b-a55b` | 0/237 | 0 | 0/237 | 0.0000% | unavailable | false |
| v3-heldout-regression | `nvidia/nemotron-3.5-lightning` | 185/237 | 134 | 75/237 | 46.2987% | unavailable | false |
| v3-heldout-regression | `openai/gpt-5.6-luna` | 237/237 | 235 | 198/237 | 85.8965% | 3514 | false |
| v3-heldout-regression | `openai/gpt-5.6-sol` | 236/237 | 236 | 219/237 | 97.1961% | unavailable | false |
| v3-heldout-regression | `qwen/qwen-2.5-7b-instruct` | 237/237 | 113 | 77/237 | 42.3799% | 4344 | false |
| v3-heldout-regression | `qwen/qwen3.8-27b` | 235/237 | 218 | 201/237 | 88.8565% | unavailable | false |
| v3-heldout-regression | `z-ai/glm-5.3-flash` | 1/237 | 1 | 1/237 | 0.2764% | unavailable | false |

Per-model/stratum token totals, reported-cost subtotals, conservative charges, physical-send counts and missing-usage coverage are in `issue145-together-matrix-usage-data.json`. Unreported usage/cost is unavailable, not zero. Warm-up cost is included in the lineage charge but excluded from scored-stratum totals.

## Evidence audit

Both wire ledgers and the child gate passed verification. All 2,223 saved scored projections were reproduced from saved wire evidence in an isolated temporary directory; normalized records (excluding fresh audit timestamps), deterministic scorer reports and both stratum reports matched. All 1,373 skipped records matched their explicit policy dispositions. The one interrupted parent projection is retained as an infrastructure gap, not manufactured model output. Pre-audit and external final tree digests matched. Independent read-only review at source commit `fe306369ba11bdfaa934cc2879c428582f5e3ae6` found no actionable replay, request-identity, reservation or cumulative-budget violation. Raw evidence stays local and ignored.

## Gate interpretation and decision boundary

The issue #130 acceptance stratum contains no `knownCapabilityUnsupported` cases. The inherited capability gate is therefore false for every model on that stratum, as in the protected Stage A/B publication. No scorer, category floor, safety gate or eligibility rule has been relaxed. Composite or strict-exact diagnostics do not override hard-gate failures. Neither the harness nor this publication selects a winner or changes production.

The operator accepted the audited evidence and directed aggregate publication. A later production decision, reviewed implementation, merge, issue closure and TestFlight release remain distinct actions. Completing this amended matrix does not claim complete responses from all eleven models or physical-device acceptance.

## Reproducibility

The publication manifest binds the new report, exact aggregate, aggregate usage supplement, evidence audit and authority record, plus every pre-existing summary artifact except the additive directory index. It also pins source/profile/queue, root and child gates, and both ignored evidence-tree hashes. The accepted corpora, prompt/examples, schemas, scorer and production inputs remain unchanged. This publication makes no provider call and reads no credential.
