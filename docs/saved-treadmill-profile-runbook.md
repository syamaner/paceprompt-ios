# Saved treadmill profiles: setup and recovery

Issue #141 implements screens 4i–4l of the [accepted v1 contract](../design/saved-treadmill-planning-profile-contract.md). This is local historical capability storage. Plan authoring integration and live preflight changes belong to #142–#144; selecting **Use for planning** currently persists the selection only. It does not change plan validation or provider requests.

## Setup and normal use

1. Open Home → **Set up treadmill**, or Settings → Connections → **Treadmill**. Open **Saved treadmills** to inspect the empty or populated collection.
2. Use the existing explicit scan and connection controls. Both speed and inclination target support and valid ranges/increments must be read during the same connection. Unknown, unsupported, incomplete or invalid evidence cannot create a usable profile. No new automatic scanning or reconnection is added.
3. A first complete read atomically saves **Treadmill N** and then presents **Treadmill profile saved**. **Use for planning** persists that record as the last selection; discovery alone never selects it. **Rename** opens the same detail flow as management; **Done** leaves the saved record without selecting it.
4. A later complete read of the same local peer and unchanged ranges refreshes its last-confirmed date. Changed bounds or increments open **Treadmill capabilities changed**. Compare **Saved** with **Newly read**, then deliberately **Update profile** or **Keep saved profile**. Cancellation keeps the original snapshot/date. Disconnect or changed/invalid evidence cancels the pending candidate; reconnect explicitly for a new read.
5. In **Saved treadmills**, open a profile to read its accepted ranges, increments and date. **Rename** uses explicit **Save name** or **Cancel rename**. Names may repeat; identity never depends on name or ranges. Names are trimmed, 1–80 grapheme clusters, at most 512 UTF-8 bytes, and exclude control/newline characters.
6. **Delete profile** requires a confirmation naming the profile. Deleting a selected profile returns selection to **No treadmill selected**. Plans, history, connection and an active workout are unaffected. A late repeated read cannot recreate it in that generation; a later explicit connection may discover it again with a new profile ID.

Saved rows remain historical even when a separate **Current treadmill** badge indicates a complete current connection read. At 30 days, an age warning appears without expiring the record. A future confirmation date shows **Confirmation date cannot be verified**. Neither establishes readiness to execute.

## Storage and failure handling

The app creates `Application Support/PlanningProfiles/profiles-v1.json` on the first successful discovery; no manual file setup, account, credential or cloud configuration is needed. The envelope contains the private installation secret, opaque HMAC identities, accepted snapshots and selection. It is bounded to 100 records and 256 KiB. Do not copy it into Git, exports, diagnostics or bug reports.

Directory, canonical and staging paths require complete file protection and backup exclusion. The adapter verifies them before exposing data or writing profile bytes and after replacement. Raw peer IDs/names, packets and connection epochs are not stored in this subsystem. Platform-provided path aliases are resolved at the trusted parent; symlink substitutes in owned profile paths fail closed.

Locked data shows unavailable storage, rather than an empty collection. Read errors, corruption, unsupported versions, missing identity material and orphan staging have distinct errors. **Reload saved profiles** retries a validated read; it does not reset or migrate the store. A failed change never creates a success-only in-memory profile. After an ambiguous replacement failure, the app re-reads canonical state before exposing records and shows the failure.

Do not manually promote staging or replace an unreadable envelope with an empty one. v1 has no predecessor migration. A separately confirmed whole-profile reset/recovery UI is future scope; existing workout-data reset remains unchanged. For a full collection, delete a saved profile deliberately before adding another. Reinstallation may lose this private local namespace; no cross-installation identity or physical serial-number uniqueness is promised.

## Developer validation

Run focused profile tests before the repository's complete local gate:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePrompt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:PacePromptTests/PlanningProfileTests \
  -only-testing:PacePromptUITests/PlanningProfileFlowUITests test
scripts/validate_local.sh
```

CI and the complete local gate run `scripts/verify_planning_profile_boundaries.py` to check for infrastructure types in profile domain/presentation, prohibited profile side effects, and #141 dependencies in excluded provider/plan/history/Health/execution subsystems. The check must be revised deliberately with a later authorised slice.

Tests use synthetic identities and an isolated memory repository for UI scenarios. Shared memory/file contracts exercise revisions and selection; fault injection exercises pre/post-replacement truth; Foundation seam tests confirm trusted aliases/owned symlink handling, backup exclusion and rejection of unavailable protection metadata on the simulator; they do not bypass that check to write private bytes. Successful persistence semantics use the injected file adapter contract. Signed-device observation is still required to confirm actual lock-time Data Protection and backup behaviour. These tests do not prove physical Bluetooth behaviour. No device, release upload, distribution or provider call is authorised by this runbook.
