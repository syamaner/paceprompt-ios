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

For GPT-5.6 Sol, the official promotional rates checked on 2 September 2026 are $4.00 per million uncached input tokens, $0.40 per million cached input tokens and $20.00 per million output tokens. Cache writes are billed at 1.25 times the uncached-input rate. Prompts above the model's published long-context threshold require request-level calculation rather than applying a single aggregate rate.

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

`PP-20260902-01` covers the full Codex Desktop task from repository orientation through implementation, simulator validation, the user-run physical capability check, evidence reconciliation and pre-commit review. The cutoff is the final counter snapshot before inserting this numeric row; the small final insertion, commit and push operations are excluded. No linked subagent usage is included.

`PP-20260902-02` covers the uncommitted implementation and simulator validation of GitHub issue #1. This task interface did not expose an exact starting counter snapshot, ending counter snapshot or model identifier, so no token count or API-equivalent cost was reconstructed. If this change is later authorised for commit, use `PacePrompt-Change: PP-20260902-02` as the commit-message trailer.
