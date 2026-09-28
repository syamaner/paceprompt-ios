# Issue #115 architecture gate

Status: architecture gate accepted for implementation with the operator-selected [zero-prefix discard amendment](watch-health-empty-prefix-amendment.md). Architecture inspected on `adc4a230e8b488a92ffc9d1a50784558364b5163`. This is not device acceptance.

## Responsibilities and dependency direction

The accepted [v1 contract](watch-primary-health-interchange-contract.md) remains authoritative. A Foundation-only shared domain owns strict wire decoding, immutable cumulative interval validation, send budgets, acknowledgement/finalisation state and persisted lifecycle decisions. Consumer-owned ports supply journal persistence, session/builder operations, transport, clocks and identifiers. Domain code cannot import HealthKit, WatchKit, SwiftUI or CoreBluetooth.

The iPhone coordinator reserves an identity durably before launching the Watch, waits for its matching bound response, and only then calls the existing execution entry point. Execution remains the sole owner of treadmill targets, local intervals and distance evidence. A read-only projection feeds the mirror; mirror callbacks have no treadmill transport capability. A versioned History ownership envelope prevents all iPhone Health-save paths for Watch-owned records. Existing v1/v2 records retain their original interpretation and save behaviour.

Watch orchestration owns one primary session, its associated live builder, an atomic bounded journal and one finish attempt. Recovery restores the existing active session; uncertain identity or mutation is quarantined without replacement or retry. The HealthKit adapter translates domain activities/metadata, disables automatic distance collection before recording, checks the actual builder contents before finishing, and exposes available live metrics only to the Watch UI. Sensor samples never enter the journal or phone History.

Extension seams are journal storage, mirrored transport and HealthKit operations. Ownership, identity, metadata, cumulative-prefix rules and wire schema are closed/versioned. SwiftUI only renders state and forwards explicit recording-end intent. Composition roots inject real adapters; deterministic tests inject fake ports.

## Stable invariants and required checks

- Reservation is irreversible, including launch, binding, disconnection and save failures. A newly begun phone-only attempt cannot be converted to Watch ownership.
- All incoming messages pass strict UTF-8, duplicate-key, field, finite-decimal, timestamp and bounded-size checks before state mutation. Journalling precedes acknowledgement.
- Collection cannot begin before binding is persisted. Start/finish effects are journalled before execution so restart cannot repeat uncertain effects.
- Cumulative revisions preserve exact prior intervals; errors latch incomplete. Final confirmation, not ack transmission, determines completeness.
- Terminal capacity and deadlines use injected monotonic time. Transport cannot block execution/safety actions.
- The adapter must reconcile the complete actual activity list with the frozen interval list. Automatic extra activities cannot be ignored or labelled complete. Independent review found a documented zero-prefix cardinality conflict; the operator resolved it by selecting zero-prefix discard. Nonempty late-added activity mapping is API-supported in principle and still needs actual builder checks and later signed-device acceptance.
- Only the accepted final FR30z distance may be added after source exclusion and permission checks. An unexpected automatic distance contribution prevents saving that builder.
- End stops mirroring before finish; no phone save-result receipt is invented. Watch receipt persistence failure is ambiguous.
- Tests exercise production orchestration through fake ports for all contract state-table rows; compile/static dependency checks prohibit a Watch-to-treadmill path. iPhone legacy regression tests and Watch simulator build/UI checks remain software evidence.

## Permitted supporting work and exclusions

Add a watchOS 10 companion and iOS 17 mirroring integration, narrowly scoped HealthKit entitlements/purpose strings, protected local journal storage, schema/tests and build validation. Update runbooks/privacy/tracker and development accounting. Preserve local signing settings. No FTMS command or reconnect change, secondary transport, provider call, WeeklyHealthReport implementation, physical operation or release upload. Signed paired-device acceptance and #116 remain separate.

The architecture gate must resolve adapter feasibility before production implementation. Subsequent executable/build/test changes require focused checks, complete-diff review and one complete local gate on final inputs, then independent exact-head review, required CI and protected merge.

## Release boundary found during inspection

The current signed-archive handoff intentionally rejects nested app/extension content (`docs/testflight/setup.md`). A Watch companion changes the archive shape. This slice must document that current signed distribution remains blocked for that new shape; do not weaken the trusted signer's nested-code, entitlement or profile checks merely to obtain a build. Simulator builds can validate both targets without changing local signing or distribution credentials. A separately reviewed trusted-tools/profile update and explicit upload authority are prerequisites for a later Watch release.

## Independent API review

The independent reviewer inspected current #115, the frozen contract and Xcode/Apple primary sources. It confirmed the zero-prefix conflict and found no documentary proof that nonempty late-added activities are impossible. Recovery must retrieve the existing session's associated builder; an ended/uncertain builder is not recoverable merely because active-session recovery exists. Configure a recovered data source with distance disabled before reattaching it, and quarantine if earlier source provenance is uncertain. The zero-prefix decision records the selected discard outcome; independent review is not product agreement or exact-head implementation approval.
