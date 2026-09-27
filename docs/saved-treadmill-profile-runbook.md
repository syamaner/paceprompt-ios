# Saved treadmill profiles: setup and recovery

Issues #141–#143 implement lifecycle screens 4i–4l, the shared authoring selector 4a–4e and historical compatibility previews 4f–4h of the [accepted v1 contract](../design/saved-treadmill-planning-profile-contract.md). This is local historical capability storage. New live preflight changes remain in #144. Selection is shared authoring state and never enters a saved plan or provider request.

## Setup and normal use

1. Open Home → **Set up treadmill**, or Settings → Connections → **Treadmill**. Open **Saved treadmills** to inspect the empty or populated collection.
2. Use the existing explicit scan and connection controls. Both speed and inclination target support and valid ranges/increments must be read during the same connection. Unknown, unsupported, incomplete or invalid evidence cannot create a usable profile. No new automatic scanning or reconnection is added.
3. A first complete read atomically saves **Treadmill N** and then presents **Treadmill profile saved**. **Use for planning** persists that record as the last selection; discovery alone never selects it. **Rename** opens the same detail flow as management; **Done** leaves the saved record without selecting it.
4. A later complete read of the same local peer and unchanged ranges refreshes its last-confirmed date. Changed bounds or increments open **Treadmill capabilities changed**. Compare **Saved** with **Newly read**, then deliberately **Update profile** or **Keep saved profile**. Cancellation keeps the original snapshot/date. Disconnect or changed/invalid evidence cancels the pending candidate; reconnect explicitly for a new read.
5. In **Saved treadmills**, open a profile to read its accepted ranges, increments and date. **Rename** uses explicit **Save name** or **Cancel rename**. Names may repeat; identity never depends on name or ranges. Names are trimmed, 1–80 grapheme clusters, at most 512 UTF-8 bytes, and exclude control/newline characters.
6. **Delete profile** requires a confirmation naming the profile. Deleting a selected profile returns selection to **No treadmill selected**. Plans, history, connection and an active workout are unaffected. A late repeated read cannot recreate it in that generation; a later explicit connection may discover it again with a new profile ID.

Saved rows remain historical even when a separate **Current treadmill** badge indicates a complete current connection read. At 30 days, an age warning appears without expiring the record. A future confirmation date shows **Confirmation date cannot be verified**. Neither establishes readiness to execute.

## Authoring with or without a profile

Open Plans and use the **Treadmill profile** row before **New plan** or **AI import**. The same row appears above manual fields and import text. Select a historical row or **No treadmill selected**, then tap **Done**. Cancel or swipe dismissal preserves selection. Done rechecks that a selected record still exists before persisting it. A deleted selection falls back to none. A separate mint **Current treadmill** badge means complete current connection evidence; historical selection itself remains neutral. Stale or uncertain dates show a separate warning without disabling authoring.

If profile storage is unavailable, the row explains that failure. Deliberately choosing **No treadmill selected** allows authoring without rewriting or resetting blocked storage. That deliberate no-profile session choice survives successful recovery; if Done occurred while storage was blocked, it remains process-only until Done can safely persist it. A fresh launch restores the last successfully persisted selection. Profile management is available from the picker; an empty collection explains how to close the picker and return to Home → **Set up treadmill**. No picker action scans or connects.

Selection does not edit draft values or import text. Manual increment buttons use the selected profile's increments; no-profile controls use 0.01 km/h and 0.1 %. Direct exact editing remains available beyond recorded ranges; nothing is clamped. Invalid or unrepresentable decimal text is rejected. Manual and mapped AI proposals use canonical authoring validation independently of equipment: structure, positive durations, finite exact targets and non-negative speed; signed inclination is allowed. This authoring token cannot establish live execution readiness. Extreme targets can make the distance estimate unavailable while preserving the exact plan.

A canonical-valid plan can be previewed and deliberately saved while disconnected; the plan repository must still be writable. Preview compares the exact plan with the current selected historical record. Run preparation still uses the existing live capability validator. AI import still requires a stored provider credential, per-request remote-send disclosure and affirmative consent. Existing live support-state vocabulary is sent; saved identity, name, equipment and ranges are excluded. Changing a selection never authorises a request or changes those transmitted fields.

## Historical preview and exact save

Manual plans and AI proposals share the same local comparison. **Validated against saved profile** is neutral: every target is within the recorded inclusive bounds and aligned with the recorded increment measured from its minimum. The name, ranges and last-confirmed date refer to historical information; **Live compatibility will be checked before execution** remains explicit. Age ≥30 days and uncertain future dates have separate amber warnings, even when targets match.

With no profile, preview says **Treadmill compatibility not yet checked** and offers the optional profile picker. Save remains available. Unavailable, corrupt, incomplete or unsupported profile data cannot produce a historical pass: the preview explains the unavailable evidence and remains unchecked. Deliberate no-profile authoring remains available without resetting storage.

An amber **Outside saved profile range** or **Outside saved profile increment** verdict names every affected step, exact target, saved bounds and minimum-origin increment. **Edit step N** opens the unchanged canonical draft and scrolls/focuses that step; an AI proposal becomes an exact editable manual draft, without another provider request. Nothing is clamped or substituted. Review the edited plan again before saving.

**Save plan anyway** opens a separate exact-plan confirmation displaying the affected requirements. **Confirm and save exact plan** acknowledges only that historical mismatch; Cancel writes nothing. The acknowledgement is transient and is never stored with the plan. Profile selection, record revision, name, ranges, availability or exact plan changes require a fresh comparison/acknowledgement. Before writing, the app reloads the selected profile store and compares again; changed evidence leaves the exact proposal/draft open, shows **Planning information changed**, and requires another deliberate Save. This also applies during AI confirmation. Canonical-invalid values still block preview/save. Saved plans contain no profile identity or compatibility verdict, and live execution has no bypass.

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

CI and the complete local gate run `scripts/verify_planning_profile_boundaries.py` to check for infrastructure types in profile domain/presentation, prohibited profile side effects, and profile dependencies in domain/provider-transport/plan/history/Health/execution subsystems (the import presentation row is allowed). The check must be revised deliberately with a later authorised slice.

Tests use synthetic identities and an isolated memory repository for UI scenarios. Shared memory/file contracts exercise revisions and selection; fault injection exercises pre/post-replacement truth; Foundation seam tests confirm trusted aliases/owned symlink handling, backup exclusion and rejection of unavailable protection metadata on the simulator; they do not bypass that check to write private bytes. Successful persistence semantics use the injected file adapter contract. Signed-device observation is still required to confirm actual lock-time Data Protection and backup behaviour. These tests do not prove physical Bluetooth behaviour. No device, release upload, distribution or provider call is authorised by this runbook.
