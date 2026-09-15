# PacePrompt repository instructions

These instructions apply to the entire repository.

## Authority and scope

- Read the current user-authorised slice, this file and the relevant checked-in design/specification sources before changing code.
- Treat an accepted and merged product capability as part of the current product baseline. Maintenance, integration and testing of that existing capability do not require inventing another capability-authorisation slice; only a new or broadened behaviour does.
- Treat `design/treadmill-controller-product-spec.html` and `design/TreadmillDesign.pdf` as eventual-product context, not permission to implement every depicted feature.
- Treat `design/prompt.md` as the proposed first implementation contract only when the user authorises that slice.
- If product identity, safety behaviour or slice boundaries conflict, surface the conflict and stop before the affected implementation.
- Deliver only the current slice. Do not add speculative foundations for excluded features unless they are strictly required by an accepted interface in the current slice.

## Treadmill safety

- Human operation of the physical console and safety key is authoritative.
- The accepted FR30z production-control baseline is defined by the current tracker and `design/fr30z-physical-console-execution-profile.md`: PacePrompt may request control and set validated speed and inclination targets, while physical Start and Stop remain console actions.
- Production must not expose or send FTMS Start, Stop or Pause. Any new Control Point opcode, automatic behaviour, broader equipment profile or changed command semantics requires a separately authorised product slice and updated acceptance contract.
- Do not add automatic reconnection that could later resume a programme.
- Characteristic presence is not proof of capability. Decode the relevant feature fields and preserve unknown or unavailable states.
- Never present a command or transition as successful without protocol acknowledgement and observed machine state.
- Prefer machine-verifiable execution invariants over repeated operator attestations. Proof-only authorisation, arming and evidence-capture ceremony must not leak into the ordinary product flow.
- Simulator results are not evidence of physical Bluetooth behaviour.

## Privacy and dependencies

- Keep the app local-first. Do not add accounts, analytics, advertising, telemetry, cloud storage or background delivery unless a later slice explicitly authorises them.
- Do not add network API calls, API-key UI, HealthKit permissions, watchOS targets or personal workout/health storage outside their authorised slices.
- Prefer Apple frameworks. Add a third-party dependency only when the current slice strictly requires it and the trade-off is documented.
- Keep developer-team identifiers, signing material, credentials, personal health/workout values and device diagnostics out of Git. Use synthetic fixtures in tests and documentation.

## Architecture and validation

- Keep CoreBluetooth operations, pure binary parsing, observable presentation state and SwiftUI views separate.
- Views must not parse bytes or issue CoreBluetooth operations directly.
- Test parsers with synthetic little-endian fixtures, including short, malformed, unsupported and unavailable values.
- Validate in this order: focused checks while iterating; complete-diff review and safety inspection; then one complete `scripts/validate_local.sh` run on the final executable, test, build and validation-script content when required by the issue or its risk.
- A passing complete gate remains valid across commit, push and merge, and after changes limited to `DEVELOPMENT_NOTES.md`, issue/PR/tracker text or non-executable documentation, provided all executable, test and build inputs remain byte-identical. Run the relevant documentation checks and `git diff --check` for those later changes.
- Any later change to app code, tests, Xcode project/build settings, dependencies, validation scripts, executable resources or safety logic invalidates the gate and requires affected focused checks followed by one replacement complete gate.
- Do not duplicate a complete local suite in hosted CI unless the issue acceptance criteria explicitly require both; retain the fast hosted repository checks.
- Before handoff, run `git diff --check`, inspect the full diff and report repository status.
- Label unperformed, simulator-only and physical-device validation precisely. Do not infer FR30z capabilities before reading them from the real treadmill.

## Repository operations

- Preserve unrelated or user-authored work.
- Do not create or change a remote, commit, push, publish or operate physical hardware unless the user explicitly authorises that action.
- One explicit operator direction is sufficient for the stated bounded physical session while its device, plan, limits, supervision and stop conditions remain unchanged. Do not interrupt that session with repeated repository-process permission prompts; obtain new direction only when the scope changes, the session ends, authority is withdrawn or an unsafe/ambiguous condition requires a new decision.
- Keep signing configuration local and ignored; commit only safe examples when one is required.

## Development usage accounting

- For every Codex-assisted commit, add one row to `DEVELOPMENT_NOTES.md` using a stable PacePrompt change ID and include the same ID in the commit message as a `PacePrompt-Change:` trailer.
- Capture exact task counters at the beginning and end of the commit's implementation phase. Record total input, cached input, cache-write input, output and total tokens; treat reasoning output as a subset of output rather than adding it twice.
- If an exact phase delta is unavailable, label the row as an aggregate or unmeasured. Never invent or infer a token count.
- Calculate only a clearly labelled API-equivalent estimate using the exact model and the official rates checked on the recorded pricing date. Show the pricing basis, account for cache writes or long-context pricing when applicable, and do not present a ChatGPT subscription session as an API bill.
- Capture the final counters and update the development note immediately before committing so documentation work is included in the measurement.
