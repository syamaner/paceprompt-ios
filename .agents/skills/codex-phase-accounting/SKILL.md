---
name: codex-phase-accounting
description: Capture and verify a bounded Codex session-usage phase, inspect request sizes, and prepare PacePrompt's API-equivalent development accounting. Use for PacePrompt token-accounting or DEVELOPMENT_NOTES.md updates; do not infer missing boundaries, counters, rates, models, sessions, or agent usage.
---

# Codex Phase Accounting

Apply `AGENTS.md` and `DEVELOPMENT_NOTES.md` as the policy authority. This skill only makes their accounting procedure reproducible; it does not redefine the ledger or authorise a commit.

## Establish an exact boundary

Select the top-level Codex session JSONL explicitly. State which session, agents and execution channels the boundary includes, plus every known unmeasured channel.

Before implementation, capture the latest complete event:

```sh
python3 .agents/skills/codex-phase-accounting/scripts/phase_usage.py snapshot \
  /absolute/path/to/selected-session.jsonl \
  --output /private/tmp/paceprompt-phase-baseline.json
```

Keep the baseline outside Git. Do not substitute a file chosen only because it is the newest session. If the helper is itself being introduced, read [the bootstrap procedure](references/bootstrap.md) before editing.

## Produce the phase report

After implementation, tests, analysis and review, run:

```sh
python3 .agents/skills/codex-phase-accounting/scripts/phase_usage.py report \
  /absolute/path/to/selected-session.jsonl \
  --baseline /private/tmp/paceprompt-phase-baseline.json \
  --boundary-label 'issue N implementation through pre-ledger snapshot' \
  --included-agent 'root Codex task' \
  --included-channel 'selected Codex Desktop session' \
  --excluded-channel 'separate tasks, hosted review and unmeasured agents' \
  --long-context-threshold LEDGER_AUTHORISED_THRESHOLD \
  --json
```

Omit `--baseline` only for a deliberately labelled whole-session measurement. The helper validates cumulative and request counters, preserves missing optional counters as `null`, checks that request totals reconcile to the phase delta, and reports every measured request input size. A request crosses the supplied threshold only when its input is greater than the threshold.

Codex can emit an unchanged cumulative snapshot after context maintenance with all metered `last_token_usage` components explicitly zero and a standalone `total_tokens` context-size value. The helper validates and reports that record as a repeated cumulative snapshot, but does not count it as a request, usage or cost. Any non-zero metered component on an unchanged snapshot remains an actionable error.

## Calculate an API-equivalent estimate

Use rates and thresholds explicitly authorised by the current ledger or supplied by the user. Never silently refresh or hard-code them as permanently current. Cost arguments require the exact session model, pricing date, source, currency, all three base rates and the long-context threshold. Supply cache-write and long-context multipliers when the measured data makes them applicable.

```sh
  --model gpt-5.6-sol \
  --pricing-date YYYY-MM-DD \
  --pricing-source 'DEVELOPMENT_NOTES.md ledger entry' \
  --currency USD \
  --uncached-input-rate RATE_PER_MILLION \
  --cached-input-rate RATE_PER_MILLION \
  --output-rate RATE_PER_MILLION \
  --cache-write-multiplier MULTIPLIER \
  --long-context-input-multiplier MULTIPLIER \
  --long-context-output-multiplier MULTIPLIER
```

The result is an API-equivalent comparison estimate, not a ChatGPT subscription bill. Reasoning tokens remain a reported subset of output and are never added to total tokens or priced again.

## Update the PacePrompt ledger

- Preserve the existing columns, terminology, arithmetic and rounding in `DEVELOPMENT_NOTES.md`.
- Record the stable PacePrompt change ID and exact phase scope.
- State the start and final snapshots, request count, largest request, threshold crossings, included agents/channels and known exclusions.
- Mark absent or incompatible data unmeasured. Do not aggregate a separate session or subagent unless its exact JSONL is supplied and the aggregation is explicitly labelled.
- Treat the final numeric ledger insertion and any later commit or push as excluded unless a new measured boundary includes them.

Run the helper tests after changing this skill:

```sh
python3 -B -m unittest discover \
  -s .agents/skills/codex-phase-accounting/tests -v
```

Also run the repository's skill validator. Stop with the helper's actionable error instead of repairing malformed data or estimating a missing value.

The helper and its tests use only the Python standard library. Codex's bundled skill validator additionally imports PyYAML; install the pinned development-only dependency from `requirements-dev.txt` into an isolated environment, then invoke the bundled validator with that environment's Python. Do not add PyYAML as a helper runtime dependency.
