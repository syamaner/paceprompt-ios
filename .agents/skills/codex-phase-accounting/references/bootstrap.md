# Bootstrap the helper-introduction change

Use this procedure only when the phase-accounting helper does not yet exist at the start of the change that introduces it.

1. Explicitly identify the active top-level session JSONL. Confirm its `session_meta.payload.id`, working directory, model in `turn_context`, and execution topology. Do not choose a session from recency alone.
2. Before editing, enumerate the file's `event_msg` entries whose payload type is `token_count`. Retain the one-based token-count event number, timestamp, complete `total_token_usage` object and the selected session ID. State the included agents and channels at the same time.
3. Preserve every reported field, including explicit zeroes. Do not add a missing cache-write or reasoning field, derive total tokens, or reconstruct another session or subagent.
4. After the helper exists, materialise that already captured event without moving the boundary:

   ```sh
   python3 .agents/skills/codex-phase-accounting/scripts/phase_usage.py snapshot \
     /absolute/path/to/selected-session.jsonl \
     --token-count-event CAPTURED_ONE_BASED_EVENT \
     --output /private/tmp/paceprompt-phase-baseline.json
   ```

5. Compare the generated snapshot with the retained session ID, event number, timestamp and counters before using it. A mismatch means the baseline is not defensible; report the phase as unmeasured instead of selecting a convenient replacement.
6. Run `report` with that baseline at the final pre-ledger boundary. The final numeric insertion into `DEVELOPMENT_NOTES.md`, a later commit, push or issue update remains outside the measurement unless another exact boundary is captured.

The helper reads local files only. Keep the baseline and raw session JSONL outside Git because they can contain task context and machine-specific paths.
