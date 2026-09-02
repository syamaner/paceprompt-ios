# Product orientation

## What is already coherent

- The app is local-first and native to Apple platforms.
- AI proposes a strict workout-plan schema; deterministic local code validates, clamps or rejects it.
- The physical treadmill console and safety key remain authoritative.
- Actual machine state must remain distinct from a requested target and from protocol acknowledgement.
- The app has four persistent destinations: Home, Plans, History and Settings. Exercise becomes a separate full-screen operating mode later.
- Risk-first delivery starts with passive FTMS discovery and capability reading before any motion-control work.

## Planned delivery ladder

1. Repository baseline and ratified product identity.
2. iPhone shell plus non-motion FTMS capability explorer.
3. Separately authorised, tightly bounded physical-device control proof.
4. Deterministic plan model, execution state machine and recovery.
5. Plans, preview and local history.
6. OpenRouter structured import followed by local validation.
7. Apple Watch companion and one-owner HealthKit workout pipeline.

Each item requires its own current contract. A later item does not leak into an earlier slice.

## Design observations

- The PDF is a seven-page, image-only future-state deck covering import preview, preflight, portrait and landscape exercise, history detail, and Watch screens.
- Its strongest reusable interaction rule is the explicit separation of requested, acknowledged and actual treadmill state.
- The future exercise design prioritises a large countdown, glanceable status, thumb-reachable controls and an always-prominent stop action.
- The editable design board reuses a RoastPilot dark console palette and an iOS 26-style device frame. That source is inspiration, not a native iOS component dependency.
- The first capability-explorer slice needs operational Bluetooth states and diagnostics, not the later exercise-screen controls shown in the deck.

## Ratified application baseline

- Product, app target and display name: `PacePrompt`
- Minimum deployment target: iOS 17
- Appearance: follow the system light/dark setting
- Project form: standard checked-in Xcode project with no third-party generator
- Bundle identifier: `com.sertanyamaner.PacePrompt`
- Personal Apple development-team identifier: local and ignored
- Physical acceptance equipment: iPhone and FR30z with its fitness Bluetooth dongle are available

## Physical validation status

A user-run iPhone/FR30z check on 2 September 2026 confirmed discovery, connection, the expected FTMS characteristic inventory, and successful reads and decoding of `0x2ACC`, `0x2AD4` and `0x2AD5`. The evidence did not show passive values from `0x2ACD`, `0x2AD3` or `0x2ADA`; stationary notification behaviour therefore remains unresolved. No Control Point procedure was attempted, so controllability remains entirely unproven and outside this slice.
