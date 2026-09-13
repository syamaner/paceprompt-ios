# PacePrompt

[![Codecov coverage](https://codecov.io/gh/syamaner/paceprompt-ios/graph/badge.svg?branch=main)](https://app.codecov.io/gh/syamaner/paceprompt-ios)

PacePrompt is a local-first iPhone app for turning plain-English interval workouts into validated treadmill plans and, in later authorised slices, running them on a Reebok FR30z over Bluetooth FTMS.

The core product rule is: AI may propose a plan; deterministic local code validates it and controls the treadmill.

## Current slice

This version contains:

- a native SwiftUI iPhone shell with Home, Plans, History and Settings;
- explicit Bluetooth availability and treadmill connection states;
- a user-initiated scan restricted to devices advertising Fitness Machine Service `0x1826`;
- explicit device selection, connection, service and characteristic discovery;
- initial reads of Fitness Machine Feature `0x2ACC`, Training Status `0x2AD3`, Supported Speed Range `0x2AD4` and Supported Inclination Range `0x2AD5` where the Read property is present;
- passive subscriptions to Treadmill Data `0x2ACD`, Training Status `0x2AD3` and Fitness Machine Status `0x2ADA`, with explicit inactive, subscribing, subscribed, not-subscribable and failed states;
- full flag-driven decoding of supported Treadmill Data fields, Training Status values and Fitness Machine Status opcodes, while preserving unavailable sentinels, unknown values and malformed packets;
- a newest-100 on-screen packet log plus a 10,000-record, read-only measurement capture with wall-clock and monotonic timing, `0x2ACD` intervals, field presence, initial-read or notification provenance, raw hexadecimal bytes, decoded values, app-lifecycle markers and explicitly human-entered observation markers;
- deliberate copy and system-share actions, with no automatic persistence or transmission;
- pure FTMS parsers tested with synthetic payloads;
- a versioned, Codable workout-plan schema with ordered warm-up, interval, recovery and cool-down steps, explicit seconds, kilometres-per-hour and percent units;
- a pure deterministic validator that returns a validated-plan wrapper only after structural and known-capability range checks succeed;
- an accepted [local workout storage and history contract](design/local-workout-storage-and-history-contract.md);
- an accepted [provider-neutral workout proposal, privacy and evaluation contract](design/workout-proposal-privacy-and-evaluation-contract.md) that keeps every model output untrusted, preserves local validation and confirmation authority, and defines the developer-only comparison boundary without selecting or integrating a provider;
- a developer-only [workout-import evaluation system](Evaluation/WorkoutImport/README.md) with the unchanged provider-neutral corpus, schemas and deterministic scorer, separate iOS 26 app/test targets, an exact local mapping/validation runner, Apple Foundation Models guided-generation and strict-schema OpenRouter adapters, and fixture/fake coverage;
- a Foundation-only saved-plan repository that accepts only validated plans, preserves complete versioned plans and lifecycle identity in a separately versioned local JSON store, and exposes unavailable, corrupt, partial, stale-staging and unsupported data without treating it as empty;
- a separate Foundation-only workout-history repository that preserves complete versioned execution summaries and immutable plan snapshots, keeps measured zero distinct from explicitly unavailable duration or distance, accepts only storage-consistent incremental replacements, and exposes protected, unreadable, corrupt, partial, stale-staging and unsupported data without treating it as empty;
- a pure workout-execution reducer and injected orchestrator that keep connection epochs, foreground state, capabilities, target intent, submission, ATT result, FTMS acknowledgement, later telemetry and local history evidence distinct;
- version-2 execution summaries that preserve closed execution-clock intervals with immutable prescribed values, independent effective-target sources, separate settled treadmill observations and a same-attempt cumulative-distance delta when its provenance is complete;
- a production CoreBluetooth Control Point edge bound through a target-only adapter that can encode only Request Control, Set Target Speed and Set Target Inclination, rechecks all current guards immediately before each write, and has no FTMS Start, Stop or Pause command model;
- a repository-backed Plans tab for manual walking or running plan creation, identity-preserving edits and explicitly confirmed permanent single-plan deletion, with ordered step entry, current-capability validation, an exact complete-plan preview with derived duration and estimated distance, and a separate confirmation-only save action;
- a deliberate saved-plan JSON export flow that requires record selection, previews the exact filename, category, count and included fields before sharing, writes only decoded supported records to protected temporary storage, and removes the temporary copy when sharing finishes or is cancelled; and
- an optional consent-gated production workout import through OpenRouter and the selected OpenAI Sol route, with a device-only Keychain credential, a fresh disclosure for every request, strict response parsing, deterministic local mapping and capability validation, exact preview, and a separate confirmation-only save action; and
- a bounded History surface for deliberately saving the latest eligible version-2 workout to Apple Health as one indoor walking or running workout, with optional accepted distance and namespaced prescribed, effective-target and separately observed interval metadata. Authorization is write-only, requested only after confirmation, and retry state is kept separate from the local workout facts.

The target-only execution binding is fail-closed in ordinary production use: its app-owned authority always returns no active proof session, no setting, launch argument or persisted value can unlock it, and unmatched FTMS machines remain passive. A later, separately authorised #62 proof session must inject an exact local peripheral/equipment identity and current session authority before the binding can even enable Control Point indications. Compilation and simulator tests do not authorise or prove physical treadmill behaviour.

The production app does **not** contain plan recovery, recovery-byte export, complete-store or history export, general History listing or deletion UI, bulk deletion or local-data reset UI, automatic or background inference, Apple Foundation Models integration, provider fallback, model comparison results, an FTMS Start/Stop/Pause command, HealthKit reads, automatic Health saving or a watchOS app. The developer-only evaluation target, corpus, scorer and raw-run boundary remain excluded from the production bundle. The production OpenRouter path sends nothing until the user reviews the exact disclosure and agrees to that one request.

The FTMS mappings, behaviours and field layouts were checked on 2 September 2026 against Bluetooth SIG [Fitness Machine Service 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/), the 5 February 2026 [GATT Specification Supplement](https://www.bluetooth.com/specifications/gss/) and current [Assigned Numbers](https://www.bluetooth.com/specifications/assigned-numbers/).

## Architecture

- `FTMSClient` owns CoreBluetooth scanning, connection, discovery, reads and passive subscriptions.
- `CoreBluetoothFTMSControlPointLink` is the single production characteristic-write edge. It reports indication subscription, ATT write and indication callbacks without selecting commands, retrying or reconnecting.
- `FTMSParser` and its value types decode little-endian fields, optional flags, unavailable sentinels and unknown protocol values without CoreBluetooth or SwiftUI.
- `TreadmillSetupViewModel` adapts client events into explicit observable presentation state.
- `TreadmillSetupViewModel` bounds the on-screen packet list to the newest 100 entries while retaining up to 10,000 records for an explicit issue #52 report. It uses a monotonic clock for packet intervals, keeps lifecycle and human-observation markers distinct from protocol evidence, reports capture overflow, and builds reports only in memory.
- SwiftUI views render state and forward deliberate scan, connection, copy, share and clear actions; they do not parse bytes or call CoreBluetooth.
- `WorkoutPlan` models untrusted plan data without UI, Bluetooth or storage dependencies. `WorkoutPlanValidator` keeps capability unknown, unsupported targets, malformed capability ranges and invalid target values distinct, and never clamps or rounds a target.
- The workout-proposal contract keeps `WorkoutProposal` distinct from `WorkoutPlan` and requires deterministic local mapping and validation for every provider response. `OpenRouterImportAdapter` owns the single-request production transport, credential use and closed response envelope; `WorkoutImportViewModel` owns disclosure identity, cancellation, transient outcome handling, preview eligibility and separate save authority.
- The workout-import evaluation boundary contains only synthetic corpus data, strict provider-neutral JSON contracts, standard-library deterministic scoring, developer-only provider adapters and a runner that always maps and validates proposals locally. Raw future runs are restricted to the ignored `.runs/` boundary, reviewed summaries exclude complete transcripts, and no evaluation file is part of the production target, archive or navigation.
- `SavedPlanRepository` is independent of SwiftUI, Bluetooth and network code. It preserves stored record order, stages and verifies full-file replacements, and requires complete file protection plus backup exclusion before atomic promotion.
- `WorkoutHistoryRepository` is likewise independent of SwiftUI, Bluetooth and network code. It stores complete version-1 and version-2 summaries in a separate file without reconstructing legacy records, preserves attempt identity and order across monotonic updates, validates timeline, distance-provenance and Health-export transitions, and never interprets an outcome as proof that treadmill activity occurred.
- `ProductionWorkoutExecutionBinding` composes the app-owned client, one-procedure transport, reducer/orchestrator, clock and history repository. Its target adapter has an exhaustive three-intent mapping and rechecks proof-session identity, epoch, foreground state, exact FR30z capability/profile evidence, current reducer procedure, one-procedure transport state, frozen ceilings and complete fresh telemetry immediately before transmission.
- `PlansViewModel` owns repository presentation, create/edit/preview/save and exact-record deletion confirmation. A successful deletion is reflected only after the atomic repository mutation completes and the repository is read again; cancellation or failure never removes a row in memory. `ManualWorkoutDraftParser` converts localised text entry into explicit domain units without clamping, rounding or silently reinterpreting malformed values; every resulting plan must still pass `WorkoutPlanValidator` against the current capability state before the repository can receive it.
- `PlansView` renders saved, empty and blocked repository states and forwards deliberate editing, deletion and export actions. `SavedPlanExporter` owns the versioned JSON envelope and protected temporary-file lifecycle; `PlansViewModel` keeps selection, exact preview, artifact creation and persistent repository mutation separate. Debug-only synthetic dependencies support XCUITests without placing personal workout values in fixtures or touching the production store.
- The local storage contract keeps saved plans, execution summaries and deliberately ephemeral data separate. The current History surface is limited to the latest eligible Apple Health save; general history presentation, reset, recovery UI, recovery-byte export and complete-store/history export remain deferred.

SwiftUI never receives a characteristic-write operation. `TreadmillSetupViewModel` forwards lifecycle and client evidence to the separately injected execution binding, while ordinary production construction supplies the permanently locked proof-session authority.

## Privacy

The production PacePrompt target has no account, analytics, advertising, telemetry, cloud storage or background delivery. It requests no HealthKit read permission and requests workout plus optional walking/running-distance write permission only after the user previews and confirms **Save to Apple Health**. Capability and packet diagnostics stay in memory and are not persisted; they leave that view only after the user deliberately copies them or opens the system share sheet.

Optional workout import makes one foreground request only after a per-request disclosure and affirmative consent. It sends the exact entered workout text, en-GB locale, fixed versioned instructions/schema/examples, supported unit vocabulary and only the current speed/inclination capability states to OpenRouter and OpenAI. Capability ranges, saved plans, workout history, health data and device identifiers stay local. The OpenRouter key is stored non-synchronising and accessible-when-unlocked-this-device-only in Keychain. The route is pinned to OpenAI with no fallback; data-collection denial is requested, but remote account logging and provider retention may still apply and the app does not promise zero retention. Saved plans leave the app only when the user deliberately selects decoded records, reviews the exact export summary and invokes the system share sheet; the export never includes credentials, raw prompts, provider exchanges or diagnostics.

The ephemeral transport has no URL cache, cookies or URL credential storage, and cancellation or backgrounding invalidates the request. Provider content is parsed into an untrusted proposal, mapped and validated locally, then discarded; PacePrompt keeps no prompt, response or provider-error history. A valid result still requires exact user review and a separate save confirmation.

Do not commit personal device captures or signing identifiers. Synthetic fixtures are clearly isolated in the test target.

## Build and test

Requirements used for this slice:

- Xcode 26.6 (build 17F113)
- iPhoneOS and iPhoneSimulator SDK 26.5
- iOS 17 minimum deployment target for the production app
- iOS 26 minimum deployment target for the developer-only Foundation Models evaluation app
- `uv` with Python 3.13 support for the offline host-evaluation tests

Before merging any change, run the complete local validation entry point:

```sh
scripts/validate_local.sh
```

It runs every checked-in offline Python test, all production unit and UI tests
with coverage, the unsigned Release simulator build, static analysis and all
developer-only evaluation tests. It makes no model-provider call. By default it
uses an available iPhone 17 Pro simulator on iOS 26.5 and retains isolated build,
result-bundle and coverage evidence under a new temporary directory. Set
`PACEPROMPT_SIMULATOR_DESTINATION` or `PACEPROMPT_VALIDATION_ROOT` to use another
listed simulator or an explicit evidence directory.

List the available simulator destinations:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePrompt -showdestinations
```

Build:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePrompt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Run all tests:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePrompt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Run static analysis:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePrompt \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO analyze
```

Validate the developer-only workout-import corpus and scorer:

```sh
python3 -B Evaluation/WorkoutImport/Scoring/scorer.py \
  --root Evaluation/WorkoutImport verify-corpus
python3 -B -m unittest discover -s Evaluation/WorkoutImport/Tests -v
```

Build and run the developer-only runner/adapter tests without a provider call:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePromptEvaluation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Use another listed iPhone simulator if that model is not installed.

## Continuous integration and coverage

Temporary issue #69 policy: ordinary pull requests and pushes to `main` run only
the fast repository checks. Complete validation is required locally through
`scripts/validate_local.sh`; the pull-request template records its exact evidence.
This avoids waiting for the slow hosted Xcode suite on every merge without skipping
or weakening any local test. Local evidence is not independent hosted evidence, so
this policy is explicit and reversible rather than a claim that the two environments
are equivalent.

The Actions **Run workflow** control retains the complete hosted production unit/UI
suite, Release simulator build, static analysis, deterministic corpus checks,
developer-only evaluation tests and informational Codecov upload on the standard
macOS 26 runner with Xcode 26.6. Use that manual path whenever hosted confirmation
is warranted and restore its pull-request/main triggers when the high-throughput
period ends. All Xcode builds are unsigned, and evaluation gates use only checked-in
synthetic fixtures; neither local nor hosted validation has a provider credential or
makes a model-provider call.

The coverage artifact is exported from the production `PacePrompt.app` binary only.
Test targets, evaluation and design/documentation files, and DEBUG-only UI-test
support are excluded. Codecov's project and patch reports are intentionally
informational while the repository establishes a baseline; no coverage percentage
is an acceptance threshold.

## Physical FR30z evidence

Physical characterisation is complete for the first product profile. Raw reports remain local because they contain a CoreBluetooth peripheral identifier. The checked-in sanitised records preserve capability, Request Control, target, telemetry and human-observation evidence without granting another physical session.

The candidate [physical-console execution profile](design/fr30z-physical-console-execution-profile.md) becomes the authority for subsequent product slices when issue #57 is accepted. It deliberately removes FTMS Start, Stop and Pause from the production surface: the operator starts/stops the belt physically while PacePrompt applies plan/manual speed and inclination targets, detects an accepted pause from fresh zero-speed telemetry or separate human confirmation, and restores the current effective targets after physical resume.

See the [11 September characterisation](docs/validation/fr30z-console-target-characterisation-2026-09-11.md), the accepted [Request Control proof](docs/validation/fr30z-request-control-success-2026-09-10.md), and the historical [freshness procedure](docs/validation/fr30z-treadmill-data-freshness-procedure.md). These records are evidence, not permission to connect or operate the treadmill.

## Simulator limitation

Simulator tests verify parsing, presentation and that the app builds. They cannot establish physical Bluetooth behaviour.

The first passive captures on 2 September 2026 established roughly two `0x2ACD` packets per second during console-controlled movement but did not capture a terminal zero. A later 11 September observation retained repeated stationary zero reports and an 8.010-second gap between the last pre-stop 0.50 km/h report and the first zero report. Silence remains unknown; the profile uses separate fresh, checking, paused and interrupted states.

The first separately authorised Request Control attempt on 9 September 2026 submitted exactly `00` once and received exactly `80 00 01`, but the then-reviewed transport failed closed because CoreBluetooth delivered the indication callback before its successful ATT write callback. The [sanitised first-attempt record](docs/validation/fr30z-request-control-2026-09-09.md) therefore remains failed/unknown evidence.

After issue #72 established callback-order-safe correlation and issue #76 added a protected diagnostic journal, a separately authorised proof on 10 September 2026 submitted exact `00` once. One well-formed `80 00 01` indication arrived for the same connection and procedure approximately 2.1 milliseconds before the successful ATT callback; the indication remained provisional until ATT acceptance, after which the procedure was acknowledged. The operator explicitly disconnected and separately reported no belt movement. The [sanitised accepted proof](docs/validation/fr30z-request-control-success-2026-09-10.md) establishes Request Control for that completed connection only.

On 11 September, low-value speed and inclination targets were separately submitted, acknowledged, later reported exactly by `0x2ACD`, and confirmed by the operator across physical-console Stop/Start cycles. FTMS Start and Stop acknowledgements did not provide reliable physical control, so they are excluded from production. The resulting policy is specific to the characterised equipment/profile and still requires a separately authorised end-to-end product proof in issue #62.

## Repository guidance

Product and design sources stay under `design/`. Project-wide safety and slice rules are in `AGENTS.md`; repository-local skills are maintained under `.agents/skills`. Per-commit Codex token measurements and API-equivalent estimates are recorded in `DEVELOPMENT_NOTES.md`.
