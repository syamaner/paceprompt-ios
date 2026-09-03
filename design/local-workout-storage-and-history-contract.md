# Local workout storage and history contract

Status: accepted documentation-only product contract for GitHub issue [#5](https://github.com/syamaner/paceprompt-ios/issues/5). This document does not implement persistence, a Plans or History product flow, workout execution, natural-language import, export, synchronisation, HealthKit, watchOS or treadmill control.

## Scope and authority

This contract defines the smallest local-first persistence boundary for user-confirmed workout plans and a later, deliberately limited execution history. It is constrained by:

- the repository's current `AGENTS.md` privacy, safety and slice rules;
- the accepted issue [#3](https://github.com/syamaner/paceprompt-ios/issues/3) `WorkoutPlan` schema and deterministic `WorkoutPlanValidator`;
- the issue [#4](https://github.com/syamaner/paceprompt-ios/issues/4) safety-gated execution design; and
- the issue [#6](https://github.com/syamaner/paceprompt-ios/issues/6) dependency on explicit prompt, provider-response, credential and export boundaries.

The product concept and `TreadmillDesign.pdf` remain eventual-product context. Their richer local traces, HealthKit status and Watch-derived data are not accepted storage fields here.

## Product decisions

1. PacePrompt remains local-only. There is no account, analytics, advertising, telemetry, cloud storage, app-managed backup, background upload or synchronisation.
2. A plan becomes persistent only after the complete `WorkoutPlan` has passed deterministic validation and the user has explicitly confirmed **Save**. A decoded plan, provider proposal, preview or validation attempt is not saved automatically.
3. The smallest planned persistence approach is a Foundation-only, versioned JSON store in the app's Application Support directory. Each replacement write is atomic.
4. Saved plans and future execution summaries are separate versioned collections. Implementing the saved-plan repository does not create an empty history repository or authorise history recording.
5. Complete file protection is required, and the store is excluded from system backup initially. Manual export is the only accepted way to make a user-controlled copy.
6. Raw natural-language prompts, provider requests and responses, API credentials, Bluetooth diagnostics, command records and high-frequency treadmill samples are not persistent by default.
7. Deletion is immediate on the next successful atomic write. There are no sync tombstones or hidden retained copies.
8. Missing, locked, unreadable, corrupt, partially written and unsupported-version data are distinct states. None may be presented as an empty collection or a zero-value workout.

## Saved-plan data

The initial `saved-plans.json` collection contains a store-format version and saved-plan records. Each record contains only:

| Field | Contract |
| --- | --- |
| `id` | A locally generated UUID that remains stable across edits. |
| `createdAt` | The UTC instant at which the first confirmed save succeeded. |
| `modifiedAt` | The UTC instant at which the most recent confirmed replacement succeeded. It equals `createdAt` on first save. |
| `plan` | The complete accepted `WorkoutPlan`, including its own `schemaVersion`, suggested name, activity and ordered steps. |

The store envelope has its own integer `formatVersion`; this is independent of `WorkoutPlan.schemaVersion`. The record does not duplicate the plan name, derive totals, retain a validation result or store a treadmill capability snapshot. Listing reads the name from `plan.suggestedName` and may derive display totals in memory.

The future repository must accept only a successfully validated plan from the deterministic domain boundary. An edit keeps the record `id` and `createdAt`, replaces the complete plan only after fresh validation and explicit confirmation, and advances `modifiedAt`. A cancelled or failed edit leaves the prior record byte-for-byte recoverable.

Validation at save time does not make a plan permanently executable. The issue #4 execution design still requires revalidation against a fresh capability snapshot and every separately accepted safety guard before execution.

## Future execution-summary data

No execution record is written in the current app or by the first saved-plan repository slice. A later history slice may introduce a separately versioned `workout-history.json` collection with one record per deliberate workout attempt. The minimum summary record is:

| Field | Contract |
| --- | --- |
| `id` | A locally generated stable UUID for the attempt. |
| `schemaVersion` | The execution-summary record version. |
| `sourcePlanID` | The saved-plan UUID when one exists; optional and never a referential-integrity requirement. |
| `planSnapshot` | The complete immutable `WorkoutPlan` reviewed for that attempt, so later plan edits or deletion cannot rewrite history. |
| `attemptedAt` | The UTC instant of the explicit user action that began the attempt. |
| `lastUpdatedAt` | The UTC instant represented by the last successful incremental summary write. |
| `outcome` | Exactly one of `inProgress`, `completed`, `stoppedByUser`, `interrupted` or `failed`, with a stable reason code where applicable. |
| `activeDuration` | Either measured seconds or an explicit unavailable state with a reason. Zero is valid only when it was actually measured. |
| `distance` | Either measured metres or an explicit unavailable state with a reason. Absence is never decoded as zero. |
| `progress` | Completed-step count plus an optional current step index and measured active seconds in that step. |
| `physicalStopConfirmation` | `notRequired`, a human-confirmed UTC instant, or `unconfirmed`; protocol acknowledgement and treadmill telemetry do not populate this field. |

`completed` is allowed only after the future execution reducer reaches its issue #4 terminal completed outcome, including required human stop evidence. `stoppedByUser` preserves a deliberate early ending. `interrupted` represents loss of execution continuity such as app termination or Bluetooth loss. `failed` represents a deterministic validation, protocol, capability or telemetry failure. These meanings are not interchangeable.

An `inProgress` record is a crash-recovery fact, not a live-state or completion claim. On a later launch it must be shown as interrupted with completion unknown unless separately accepted evidence proves a more specific terminal outcome. A partially completed record retains the plan snapshot, measured values and progress that were successfully written; it must not invent remaining steps, duration, distance, physical stop or treadmill state.

This minimum summary intentionally excludes heart-rate traces, inclination traces, per-packet treadmill samples, Control Point acknowledgements, HealthKit save status and Watch data. A later contract may add a justified summary field or separately protected collection, with a new version and explicit retention/export decision; the product concept alone is not authority to persist it.

## Deliberately non-persistent data

The following data may exist only in bounded process memory for the active user flow:

- raw natural-language workout text;
- provider request bodies, structured responses, errors and routing metadata;
- API credentials or credential-entry text;
- live capability, command, acknowledgement and treadmill packet records;
- the current in-memory 100-packet diagnostic log; and
- high-frequency speed, inclination, heart-rate or other sensor samples.

These values must not enter the JSON stores, application logs, crash metadata, analytics or synthetic fixtures. The owning flow clears its working value after save, cancellation or terminal failure and does not depend on restoration after app termination. The current diagnostics view may still copy or share its in-memory report after a deliberate user action; that existing action does not make diagnostics part of workout storage or export.

Issue #6 must define API-key storage separately before any network implementation. Credentials must never be placed in the workout store or its export.

## Retention, deletion and reset

- Saved plans remain until the user deletes an individual plan or performs a complete local-data reset. There is no automatic expiry.
- Future history remains until the user deletes an individual record, chooses **Clear history**, or performs a complete local-data reset. There is no automatic expiry.
- Deleting a saved plan does not delete execution summaries because each summary owns its immutable plan snapshot. Deleting history does not delete saved plans.
- **Clear history** removes only execution-summary records after explicit confirmation. It does not affect saved plans.
- **Reset local workout data** removes saved plans, execution summaries, store staging files and retained recovery copies governed by this contract after explicit confirmation. It also clears the current in-memory diagnostic and provider-flow buffers. A future credential contract must state whether and how its Keychain items join the complete app reset.
- A failed deletion or reset leaves the last valid canonical store in place and reports the failure. The UI must not report success from an in-memory change alone.

There is no app-managed trash, grace period or sync tombstone. Any later undo or retention feature requires a new contract because it would retain data after the user requested deletion.

## File location, protection and backup

The planned store directory is a PacePrompt-owned subdirectory of the app container's Application Support directory, resolved with Foundation APIs rather than a hard-coded device path. The saved-plan and future history collections use separate JSON files in that directory.

The storage layer must:

1. create the directory and every store or staging file with complete file protection (`FileProtectionType.complete` / `NSFileProtectionComplete`);
2. set the directory and store resources as excluded from backup;
3. verify those attributes before reporting the first save as successful;
4. encode a complete replacement to a sibling staging file, synchronise it, then atomically replace the canonical file; and
5. retain the previously valid canonical file if encoding, protection, synchronisation or replacement fails.

If protected data is unavailable while the device is locked, the repository reports **unavailable** and supports retry after unlock. It does not substitute an empty store, write a new file or cache an unprotected copy. Simulator tests can verify error handling and requested attributes, but complete Data Protection behaviour requires a separately authorised real-device validation slice.

The backup exclusion is an initial privacy default, not a guarantee that manual exports cannot be backed up by a destination the user chooses. PacePrompt provides no automatic restore, iCloud container, CloudKit, shared app group or other synchronisation.

## Empty, unavailable, corrupt and unsupported states

The repository exposes these states to presentation code without collapsing them:

| State | Meaning and required behaviour |
| --- | --- |
| `empty` | The canonical collection file does not yet exist, or a valid supported store contains no records. This is the only no-data state. |
| `available(records)` | A complete supported store decoded and passed structural checks. A record's optional measurement may still be explicitly unavailable. |
| `protectedDataUnavailable` | The store cannot currently be read because protected data is locked. Show retry guidance; do not write. |
| `readFailure` | A filesystem or permission error prevented a complete read. Preserve the file and report an actionable error. |
| `corrupt` | JSON decoding or structural validation failed. Preserve the exact canonical bytes, block mutation and offer retry, deliberate recovery export or confirmed reset. |
| `partialWriteDetected` | A canonical or staging file is incomplete or inconsistent. Do not promote, merge or guess. Preserve it for the same recovery choices. |
| `unsupportedVersion` | The store or contained record version is newer or otherwise unsupported. Preserve it unchanged and require a compatible app or an explicit future migration. |

A stale staging file is never silently promoted or discarded. A valid canonical file remains the readable authority while the staging artefact is reported for later explicit cleanup or reset. If the canonical file itself is not valid, no records are shown and all mutations remain blocked. Recovery export is a deliberate system-share action of the preserved bytes with an explicit warning that the file is unreadable; it is never sent automatically.

## Versioning and migration

Store format, `WorkoutPlan` and execution-summary versions evolve independently. Every reader validates the store version before decoding records and validates each nested schema version before exposing data. Unknown fields may be ignored only where the accepted decoder contract says they are forward-compatible; unknown enum values or versions are never reinterpreted as current values.

There is no migration in the first repository slice. A future migration requires its own bounded issue, synthetic fixtures for every supported source version, an explicit source-to-destination mapping, preservation of unavailable values, and failure-injection tests. It must write and validate a separate replacement before atomic promotion, retain the original on any failure, and visibly report the outcome. Launching a newer app must never silently delete, overwrite or heuristically repair personal data.

## Manual export

Export is deferred to a later UI slice. The accepted boundary is:

- no automatic export, upload, transmission or background sharing;
- a deliberate user action chooses selected saved plans, selected history records, or the complete local workout store;
- PacePrompt builds a newly versioned JSON export in protected temporary storage using only decoded, supported records;
- before the system share sheet opens, the user can preview the exact categories, record counts, included fields and destination filename;
- the export contains the complete selected records plus export-format version and creation time, but never credentials, raw prompts, provider exchanges, diagnostics or high-frequency samples;
- cancel leaves the persistent store unchanged and removes the temporary export when the share flow ends; and
- export is a copy, not evidence of backup success and not a deletion action.

If the store is locked, unreadable, corrupt or unsupported, normal structured export fails visibly rather than emitting an empty or partial JSON file. The separately labelled recovery export described above may share preserved raw bytes only after explicit preview and confirmation.

## Deferred implementation responsibilities

The accepted contract enables, but does not authorise, these separately bounded slices:

1. issue [#10](https://github.com/syamaner/paceprompt-ios/issues/10): a pure, versioned saved-plan repository with atomic Foundation JSON I/O, protection/backup attributes, explicit repository states and synthetic fault tests;
2. issue [#11](https://github.com/syamaner/paceprompt-ios/issues/11): manual plan creation, deterministic validation, readable preview, explicit confirmation and save in the Plans tab, using that repository;
3. a future execution-summary schema and incremental history repository aligned with the accepted issue #4 reducer;
4. Plans and History listing, editing, deletion, clear-history, reset and recovery presentation;
5. deliberate previewable JSON export through the system share sheet;
6. separately contracted natural-language import and credential handling under issue #6; and
7. separately authorised on-device Data Protection and recovery validation.

None of these slices may add network transmission, HealthKit, watchOS, FTMS writes, workout execution or physical hardware operation unless that exact work has separate current authority.
