# Development Notes

## Codex usage experiment

PacePrompt records Codex model-usage counters for each Codex-assisted commit. This is an engineering-process experiment modelled on WeeklyHealthReport's development notes. The figures measure repeated model processing across a task, not source-code size, unique conversation text, developer productivity or human effort.

The API-equivalent value is a comparison estimate only. This work runs through a ChatGPT subscription and is not billed as API usage. Token pricing does not include any separately priced API tools or external services unless a row explicitly says otherwise.

## Recording protocol

1. Assign the change a stable ID in the form `PP-YYYYMMDD-NN`.
2. Record the task's exact cumulative usage snapshot before implementation begins.
3. Immediately before the commit, record another snapshot after code, tests, review and this note are complete.
4. Subtract the start snapshot from the end snapshot. If no valid start snapshot exists, label the result as a task aggregate rather than a per-commit delta.
5. Add one row to the table below and include `PacePrompt-Change: <change-id>` as a commit-message trailer. The trailer maps the row to the resulting commit without attempting to place a commit's own hash inside itself.
6. Record the exact model, official pricing URL and pricing date used. Recheck pricing whenever the model or published rate changes.

Record these counters separately:

- total input tokens;
- cached input tokens, which are included within total input;
- cache-write input tokens, when reported;
- output tokens, including any reasoning tokens already counted within output;
- total tokens.

Do not reconstruct missing counters from source size, elapsed time or subscription usage. Mark missing measurements as `Unmeasured`.

## API-equivalent calculation

For GPT-5.6 Sol, the official promotional rates checked on 2 September 2026 and rechecked on 3 September 2026 are $4.00 per million uncached input tokens, $0.40 per million cached input tokens and $20.00 per million output tokens. Cache writes are billed at 1.25 times the uncached-input rate. Prompts above the model's published long-context threshold require request-level calculation rather than applying a single aggregate rate.

For a phase with no cache-write or long-context adjustment:

```text
uncached input = total input - cached input
API-equivalent =
    (uncached input / 1,000,000 × input rate)
  + (cached input / 1,000,000 × cached-input rate)
  + (output / 1,000,000 × output rate)
```

Pricing authority: [OpenAI GPT-5.6 Sol model documentation](https://developers.openai.com/api/docs/models/gpt-5.6-sol).

## Commit measurements

| Date | Change ID | Feature or change | Model | Input tokens (cached; cache write) | Output tokens | Total tokens | Token-only API-equivalent | Measurement scope |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 2 Sep 2026 | `PP-20260902-01` | Repository baseline and non-motion FTMS capability explorer | `gpt-5.6-sol` | 22,180,485 (21,742,208; 0) | 100,109 | 22,280,594 | $12.45 | Initial task aggregate |
| 2 Sep 2026 | `PP-20260902-02` | Issue #1 read-only FTMS live telemetry and diagnostic capture | Unmeasured | Unmeasured | Unmeasured | Unmeasured | Unmeasured | Exact start/end task counters and model identifier unavailable |
| 2 Sep 2026 | `PP-20260902-03` | Issue #2 safe FR30z FTMS Control Point handshake specification | `gpt-5.6-sol` | 12,396,013 (11,889,664; 0) | 50,316 | 12,446,329 | $7.79 | Task aggregate through pre-commit snapshot |
| 3 Sep 2026 | `PP-20260903-01` | Training Status initial read and diagnostic source provenance | Unmeasured | Unmeasured | Unmeasured | Unmeasured | Unmeasured | Exact start/end task counters and model identifier unavailable |
| 3 Sep 2026 | `PP-20260903-02` | Correct issue #2 Codex usage accounting | `gpt-5.6-sol` | 2,075,901 (1,902,464; 0) | 7,522 | 2,083,423 | $1.61 | Exact phase delta through final counter snapshot |
| 3 Sep 2026 | `PP-20260903-03` | Issue #3 deterministic workout-plan schema and validator | `gpt-5.6-sol` | 10,697,748 (10,567,552; 0) | 35,945 | 10,733,693 | $5.47 | Exact implementation-phase delta through final pre-commit snapshot |
| 3 Sep 2026 | `PP-20260903-04` | Issue #8 reproducible Codex phase-accounting tooling | `gpt-5.6-sol` | 9,519,742 (9,277,952; 0) | 73,706 | 9,593,448 | $6.15 | Exact implementation-phase delta through final pre-ledger snapshot |

`PP-20260902-01` covers the full Codex Desktop task from repository orientation through implementation, simulator validation, the user-run physical capability check, evidence reconciliation and pre-commit review. The cutoff is the final counter snapshot before inserting this numeric row; the small final insertion, commit and push operations are excluded. No linked subagent usage is included.

`PP-20260902-02` covers the implementation and simulator validation of GitHub issue #1, committed as `5aea8ca` with the matching `PacePrompt-Change` trailer. The task interface did not expose an exact starting counter snapshot, ending counter snapshot or model identifier, so no token count or API-equivalent cost was reconstructed.

`PP-20260902-03` covers the GitHub issue #2 protocol specification, integration with `e41bbae`, primary-source review, documentation checks and simulator validation. The exact cumulative task snapshot immediately before commit `b2d6526` reported 12,396,013 input tokens, of which 11,889,664 were cached, 0 cache-write input tokens, and 50,316 output tokens, including 24,968 reasoning tokens. The total was 12,446,329 tokens. The model was `gpt-5.6-sol`. The largest request input was 215,462 tokens, so none of the 101 measured requests crossed the published 272,000-token long-context threshold. With 506,349 uncached input tokens, the token-only API-equivalent is `(506,349 × $4.00 + 11,889,664 × $0.40 + 50,316 × $20.00) / 1,000,000 = $7.7875816`, rounded to $7.79. This is a task aggregate because no separate zero-valued start snapshot was recorded; the final numeric insertion, commit and push are excluded.

`PP-20260903-01` covers the follow-up investigation of passive FTMS telemetry, the Training Status initial-read implementation, simulator validation and the user-operated physical-treadmill capture. The capture confirmed successful subscriptions to `0x2ACD`, `0x2AD3` and `0x2ADA`, an initial `0x2AD3` value of `00 00`, and live `0x2ACD` notifications while the belt was operated exclusively from the physical console. No Control Point write was performed. This task interface did not expose exact start/end counters or a reliable exact model identifier, so token usage and API-equivalent cost remain unmeasured.

`PP-20260903-02` covers recovery of the exact local session counters, request-level threshold checking, pricing verification and this accounting correction. Subtracting the exact phase-start snapshot from the final snapshot produced 2,075,901 input tokens, of which 1,902,464 were cached, 0 cache-write input tokens, and 7,522 output tokens, including 4,983 reasoning tokens. The total phase delta was 2,083,423 tokens. No request crossed the 272,000-token threshold. With 173,437 uncached input tokens, the token-only API-equivalent is `(173,437 × $4.00 + 1,902,464 × $0.40 + 7,522 × $20.00) / 1,000,000 = $1.6051736`, rounded to $1.61. The final numeric insertion, commit and push are excluded.

`PP-20260903-03` covers the authorised GitHub issue #3 source review, user-ratified pure workout-plan schema and validator implementation, synthetic focused and complete simulator tests, simulator build, static analysis, autonomous completion audit and final diff review. The exact phase-start snapshot reported 691,725 input tokens, of which 610,304 were cached, 0 cache-write input tokens, and 8,358 output tokens, including 6,039 reasoning tokens. The final snapshot reported 11,389,473 input tokens, of which 11,177,856 were cached, 0 cache-write input tokens, and 44,303 output tokens, including 19,659 reasoning tokens. Subtracting the start snapshot produced 10,697,748 input tokens, of which 10,567,552 were cached, 0 cache-write input tokens, and 35,945 output tokens, including 13,620 reasoning tokens. The total phase delta was 10,733,693 tokens. None of the 67 measured implementation-phase requests crossed the 272,000-token threshold; the largest request input was 205,658 tokens. With 130,196 uncached input tokens, the token-only API-equivalent is `(130,196 × $4.00 + 10,567,552 × $0.40 + 35,945 × $20.00) / 1,000,000 = $5.4667048`, rounded to $5.47. No subagent usage, physical-device operation or FTMS Control Point write is included. The final numeric insertion, commit and push are excluded.

`PP-20260903-04` covers the authorised GitHub issue #8 repository-local phase-accounting skill and standard-library helper, synthetic acceptance tests, bootstrap verification against the selected live session, the pinned development-only PyYAML dependency and isolated validator installation, skill validation, complete simulator tests, simulator build, static analysis and full diff review. PyYAML is used only by Codex's bundled skill validator; the helper and its tests retain a standard-library-only runtime. Because the helper did not exist at phase start, the bootstrap boundary was captured directly from token-count event 3 in session `01a06689-8622-7670-9847-7790f6ec0153`, then re-materialised and verified after the helper existed. The exact phase-start snapshot reported 122,369 input tokens, of which 91,008 were cached, 0 cache-write input tokens, and 1,949 output tokens, including 943 reasoning tokens. The final pre-ledger snapshot reported 9,642,111 input tokens, of which 9,368,960 were cached, 0 cache-write input tokens, and 75,655 output tokens, including 28,549 reasoning tokens. Subtracting the start snapshot produced 9,519,742 input tokens, of which 9,277,952 were cached, 0 cache-write input tokens, and 73,706 output tokens, including 27,606 reasoning tokens. The total phase delta was 9,593,448 tokens. None of the 83 measured implementation-phase requests crossed the ledger-authorised 272,000-token threshold; the largest request input was 214,632 tokens. One unchanged cumulative snapshot after context maintenance reported zero metered request components plus a standalone 21,593-token context-size value; the helper reports that record but does not count it as a request, usage or cost. With 241,790 uncached input tokens, the token-only API-equivalent comparison estimate is `(241,790 × $4.00 + 9,277,952 × $0.40 + 73,706 × $20.00) / 1,000,000 = $6.1524608`, rounded to $6.15. The measurement includes only the root Codex Desktop task in the selected session; no subagent was created, and separate tasks, reused threads, hosted review and unmeasured external execution are excluded. No product-code change, physical-device operation or FTMS Control Point write is included. The final numeric insertion, post-insertion mechanical checks, any later commit and any push are excluded.
