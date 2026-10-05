# Watch-primary interchange implementation and acceptance runbook

Authority: [contract v1](../design/watch-primary-health-interchange-contract.md),
PacePrompt #114 → #115 and WeeklyHealthReport #80 → PacePrompt #116. Merging
#114 accepts a specification only. No Watch feature, HealthKit readback,
release, paired-device or physical treadmill acceptance is completed by it.

## Implementation handoff and local validation

1. Select #115 or #80 separately; read the accepted contract and record its merge
   SHA. Copy the [synthetic fixtures](fixtures/watch-health-v1/README.md) at that
   immutable SHA and record their digests. Keep schema versions independent.
2. Implement consumer-owned domain/adapter seams and every applicable state-table
   and fake-store case. Preserve iPhone-only saves and v1/v2 records. #80 preserves
   v3 Daily fixtures and daily aggregates while introducing schema 6 (v4 remains the food projection).
3. Review the complete diff, privacy boundaries and all failure paths. Run the
   fixture tests and the applicable complete local gate. Review the exact final
   head independently, run required hosted checks and merge through protection.
4. Leave #116 unperformed until both implementations merge. Simulator success is
   UI/domain evidence only. Use the existing [release runbooks](testflight/README.md)
   only with separate release authority; this procedure authorizes no upload.

## Preconditions for separately authorised #116

Record exact PacePrompt and WeeklyHealthReport commits/builds, contract version,
OS versions and synthetic fixture digests. Install compatible signed Release
candidates on the paired Watch/iPhone through an authorised procedure. Keep local
signing settings ignored. Inspect entitlements and purpose strings; no signing,
Health identifiers or device identifiers enter public evidence.

Operator reviews Health permissions, recording ownership, the enriched export
preview, destination and privacy/App Store compliance checkpoint. Use one reviewed
conservative walking plan. For the bounded FR30z session, operator is present,
deck is clear and console/safety key accessible. The accepted existing execution
profile applies; no new opcode or Watch treadmill control is permitted. Stop
for unexpected motion, lost supervision, uncertainty or changed scope. Further
physical disconnect scenarios require fresh operator authority.

## No-motion paired-device rehearsal

Before treadmill work, exercise independent Watch recording and a bounded
synthetic interval feed in an explicitly identified test build, never the
production execution route. Keep these observations separate from production
acceptance. Observe ownership reservation/suppression after relaunch; primary
recovery restores an existing builder rather than creating another one.

Exercise missing workout permission, missing distance permission, missing sensor
visibility and a mirror disconnected before final ack/confirmation. Confirm no
automatic remirror, phone save, command or target restoration. End recording on
Watch; save a nonempty valid prefix as incomplete, distance omitted. If no usable
interval remains, discard without finishing and verify no workout was saved. Read
back saved status directly with an authorised HealthKit reader. Ambiguous finish, journal
failure, partial builder mutation and unknown protocol inputs belong in deterministic
fake-store tests; do not deliberately corrupt real Health data to manufacture them.

## Production happy-path observations

1. Start a fresh Watch-assisted attempt through normal UI. Observe one Watch
   primary/builder and matching phone mirror. Confirm the phone Save to Apple
   Health action is suppressed in History and service paths, including relaunch.
2. Start and stop belt motion only at the physical console. Exercise one planned
   target transition and, only if selected safely, a manual override. Record
   pass/fail that prescribed, independently effective and observed values remain
   distinct; do not publish the operator's metric values. For a candidate containing
   #193, use its [console/ramp checklist](../design/console-overrides-and-step-clock.md#deterministic-and-physical-acceptance):
   keep three planned steps, split only settled intervals, count moving ramps and
   confirm the following step clears overrides. App-command overlap remains an
   explicit limitation; never waive the normal acknowledgement/timeout guards.
3. At an accepted physical pause, observe recording pause; after accepted execution
   resume, observe recording resume. Distinguish API request, callback and physical
   observation. Separately observe that Watch recording pause/end never moves or
   changes treadmill targets. Never resume a belt to test a HealthKit callback.
4. End execution and perform the accepted end-preparation, final-manifest, ack,
   confirmation sequence while mirroring remains valid. Record whether each leg
   was observed before the deadline. Watch ends collection and finishes once. Confirm the Watch shows the actual save result, while iPhone reports end sent and directs save-result checking to Watch; a final-manifest ack is not a save receipt.
5. Using direct HealthKit readback (not just Fitness UI), assert exactly one workout
   for this summary, matching explicit identity, `watchPrimary`, complete status,
   final revision and stable sync keys/version. Assert exact interval count,
   chronological nonoverlap, same activity/indoor configuration, recognized keys
   and no auto-generated extra activity. Settling and physical pause remain gaps.
6. Inspect workout/activity pause-adjusted duration separately from local active
   duration; record agreement with each source's semantics, not equality between
   them. Heart-rate and energy statistics are optional; label energy calculated.
   Missing visibility stays `noDataOrAccess`. Activity interpolation is explicit.
7. Inspect collection configuration and associated distance samples with a private
   authorised diagnostic reader. Confirm automatic Watch distance was disabled
   before collection and exactly one accepted treadmill delta contributes, or
   confirm distance absent. A plausible total alone cannot prove single-source
   distance. Unexpected extra-source distance fails acceptance; do not relabel it.
8. Reopen/relaunch after save and confirm no second workout or save action. Real
   sync replacement is not exercised by v1 (no replacement path); fake-store and
   single-writer checks do not prove HealthKit replacement semantics.

## WeeklyHealthReport round trip

Run the ordinary user-controlled Daily Export for the same workout. Before export,
confirm preview explicitly names workout HR summaries, calculated energy and
PacePrompt intervals, missing visibility, reviewed Drive destination and canonical
replacement. Read the resulting schema-v6 JSON privately and assert:

- workout min/average/max HR and energy carry `healthKitWorkoutStatistics`, and
  each available activity statistic carries `healthKitActivityStatistics`;
- daily active energy is structurally separate and unchanged in meaning;
- activity IDs, boundaries, durations and all recognized metadata match direct
  readback; the supported complete/incomplete state is accurate;
- missing visibility is `noDataOrAccess`, with no inferred zero/denial, raw series,
  per-activity distance interpolation or unknown metadata dump;
- repeating the deliberate export replaces the canonical JSON safely and creates
  no HealthKit workout; cancellation/error publishes no partial enriched document.

Repeat for the incomplete rehearsal and an ordinary non-PacePrompt Watch workout.
Incomplete intervals cannot be filled from the local PacePrompt record. Missing
metrics alone do not fail truthful absence handling, but sensor-production claims
require actual observations and remain unverified when absent.

## Evidence record and closure

Use a private evidence worksheet with these columns; publish only its sanitised
assertions and source/build identities:

| Case | Exact source/build | Contract/static | Deterministic | Simulator | Signed paired-device | HealthKit readback | Physical FR30z | WHR extraction | Result/limitation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Complete / incomplete / missing access / ordinary Watch | pending | pending | pending | pending | unperformed | unperformed | unperformed | unperformed | pending |

Do not publish personal heart rate, calories, Health UUIDs, screenshots of Health,
signing identity, device identity or raw diagnostic packets. Actual sensor output,
calorimetry, metadata survival, recovery and distance source exclusion require
separate observations; lower-level evidence cannot establish them.

#116 closes only after complete and incomplete interchange, single-writer/no
fallback, single-source distance (or truthful omission), directional recording
state and schema-v6 round trip pass on the tested combination. Reconcile #7,
#115 and #80; #7 closes only after all accepted children finish. An executable
repair invalidates affected device evidence and requires new focused/full gates
and exact-head review before repeating it. Record every unperformed case.

## Revision 1.1: no usable intervals

The operator selected zero-prefix discard on 28 September 2026. For no manifest,
all intervals outside recording bounds, and recovered empty prefix, verify that
Watch ends the existing session, discards its builder and never calls finish.
After definite discard, the Watch displays “Workout not saved: no execution intervals were received or
usable.” No workout/readback projection is expected. iPhone suppression and local
History remain unchanged. Do not claim that discarding a workout deletes sensor
samples HealthKit may already have persisted. An uncertain discard remains
ambiguous and cannot trigger creation, finish retry or a phone fallback.

The new synthetic zero-interval fixture proves the terminal contract only. Actual
builder discard and any previously persisted sensor samples remain signed-device
observations; this amendment grants no device or treadmill-operation authority.

## #115 implementation handoff

The [companion operating runbook](watch-companion-runbook.md) describes the
implemented ownership, protected retention, failure and recovery paths. The
source/test/CI evidence recorded in the #115 PR is distinct from every signed
paired-device and physical row above, which remains unperformed until observed.
The schema/fixture amendment for zero intervals does not implement WHR #80 or
complete #116. Resolve the nested Watch signing handoff before installing a
later signed candidate; do not relax release checks to obtain one.

## Durability acceptance (#198; unperformed on devices)

Use a freshly installed candidate containing #198 on both devices, with a
comfortable short plan. Record each observation separately; do not infer it from
simulator tests or release availability. Keep all real diagnostics private.

1. Connect with each app initially foreground, then background/foreground the
   phone and Watch independently during startup and during a step. Confirm one
   recording identity, no repeated execution start and responsive controls.
2. During a recording, briefly interrupt the phone/Watch connection and restore it
   within the reconnect window. Confirm same-workout reconnection, cumulative
   interval recovery, sticky incomplete status and no treadmill command caused
   by the Watch transition. Leave it disconnected past the window separately;
   the phone must show unavailable, with iPhone saving still suppressed.
3. Exercise **End recording & save** normally; confirm a single Health workout or
   zero-interval discard as appropriate. Verify the Watch final result separately.
4. Exercise **Stop recording** during connection and during a recording. Confirm
   the treadmill is unaffected and the UI does not claim stopped until verified.
   The old save remains uncertain if any mutation may have occurred.
5. After verified stop, use **Prepare next workout**. Confirm the next deliberate
   iPhone attempt connects under a new identity and the old workout is never
   retried or duplicated. Existing ambiguous build-16 state must follow this path.
6. Force quit/relaunch each app separately. Watch recovery may attach only to its
   existing primary. A cold phone launch must never resume treadmill execution.
   Verify the recovery/stop controls remain usable and late results cannot change
   a new attempt. Check Health for a late old finish before drawing conclusions.
7. Test device lock/protected-data availability, permission delays and storage
   errors separately. An unavailable protected store must remain fail-closed with
   a clear status; it must not erase uncertainty or claim a successful save.

<a id="startupshutdown-acceptance-203-unperformed-on-repaired-devices"></a>

## Startup/shutdown acceptance (#203; blocked by #212)

The operator confirmed both devices had finished updating to build 18 before a
failed attempt: iPhone showed blocked Preflight with a Watch interchange timeout,
and Watch remained at an uncertain save result. This is failure evidence, not
acceptance or proof that Health did or did not save an earlier workout. The
[simulator investigation and bounded ordering repairs](watch-companion-runbook.md#simulator-investigation-and-bounded-repairs-212)
do not resolve the device report by themselves. Repeat this procedure on a later
installed candidate containing the #212 repair, recording its actual build numbers.
The remaining rows below are not marked passed by that report or by simulator tests.

Internal TestFlight **1.0.1 (18)** contains this repair in both apps. The
[release receipt](testflight/README.md#watch-startupshutdown-internal-release-101-18-issue-205)
records source, protected delivery and Apple API availability. Update both devices
before this procedure; release availability does not establish installation or
acceptance. Build 17 does not contain #203.


Record both installed build numbers before this check. The operator's earlier report
of flickering and Stop returning after confirmation is a failure observation; it
does not establish complete device cause or repair acceptance.

1. Prepare a Watch-assisted attempt and tap Begin once. Expect stable Connecting
   progress, then exercise readiness. Repeated taps must not create extra attempts.
2. Independently background/foreground phone and Watch during preparation. The phone
   must refresh stale checks without issuing a treadmill command or automatically
   starting execution. Include lock/unlock with active state preceding protected-data
   availability; stale checks must clear once both return. A Watch binding received while phone is inactive requires a
   deliberate Begin when foreground checks pass. Normal active binding may complete
   the already-requested Begin once.
3. During a separately authorised conservative exercise, end on phone and stop the
   belt at the console. Leave both apps open. Expect Watch Ending, Saving, then saved
   or discarded (zero usable intervals). No Watch tap should be needed; the normal
   End action must disappear during handoff and both recording actions disappear
   after successful completion. Phone end-sent is not a Health save receipt.
4. If the Watch requires emergency Stop, read its inline consequence and tap
   Stop recording once. Expect Stopping, then a
   verified stopped state with Prepare next workout, or a bounded explicit failure.
   A late callback must not silently return to the same Stop prompt. Do not relaunch
   or delete data to mask a failed stop; retain the exact visible status privately.
5. Exercise app foreground changes after a terminal result. The result must remain
   stable. Check Health for at most one workout and direct metadata/statistics using
   the authorised reader procedure. An uncertain result stays uncertain.

Lost-message/callback ordering and storage corruption are synthetic regression cases,
not instructions to inject faults into real Health data. #115 remains paired-device
acceptance, WeeklyHealthReport #80 reader implementation, and #116 the cross-repository
physical acceptance boundary. This software repair authorises no release or hardware
operation.

## Build 19 finish/save follow-up — 2 October 2026

Operator reports successful startup/pairing and live Watch values, followed by an
uncertain Watch save after ordinary phone ending. Watch Stop was pressed after
uncertainty appeared. PacePrompt History retained the workout; no Health workout
was observed; Watch then offered Prepare next workout. Native errors, installed
build metadata and Health readback were not independently inspected. This is failed
finish/save acceptance, not a confirmed root cause or successful zero-prefix discard.

The [finish/save amendment](../design/watch-finish-save.md) defines the bounded
source repair. It is not part of released build 19. On a later installed candidate:

1. Record both installed builds and start one conservative Watch-assisted attempt.
2. Keep apps open for the first run and verify interval progression.
3. Stop the belt physically. If stationary fallback is needed, tap **Treadmill
   stopped — end workout** only after observing belt stop. Otherwise use **End
   workout** with current stationary evidence. No second ordinary-end confirm.
4. Leave Watch untouched: expect Ending/Saving then Saved for a nonempty workout,
   or the explicit no-usable-interval discard only for an empty attempt.
5. Check local History separately from Health/Fitness. Confirm exactly one Health
   workout for the nonempty attempt. An interchange acknowledgement is not save proof.
6. If failure recurs, record exact phone/Watch wording and the protected local
   failed-save stage through separately authorised private diagnostics. Do not
   retry finish, export a replacement on phone, or delete retained uncertain state.
7. Repeat background/foreground and manual-override cases separately after the
   basic foreground completion passes. Simulator/native compile evidence cannot
   establish signed paired-device acceptance.

#212/#115 remain open. #211 remains the wider confirmation audit; this slice only
simplifies ordinary ending. #116 and WeeklyHealthReport #80 retain their independent
reader/round-trip acceptance requirements. Do not publish device diagnostics or
personal health/workout values in issue records.

## Active collection during interval assembly (#212; build 20 follow-up)

The [revision 2 finish/save amendment](../design/watch-finish-save.md#build-20-collection-closure-follow-up)
repairs a native simulator-reproduced ordering defect. Verify stopped activity,
add and exactly verify execution intervals while the builder remains active,
then end collection and recheck the activity list/distance-source invariants
before the existing distance/metadata and single finish. Ending collection
before adding intervals produced HealthKit error 3 in the isolated simulator.
The repaired native three-interval probe returned a finish receipt with three
closed indoor-walking activities; no Health queries or physical devices were used.

This does not establish the user's exact device failure stage or paired-device
acceptance. Build 20 still lacks the repair. Keep #212/#115 open; after a later
installed candidate repeat the existing foreground phone-end procedure, leave
Watch untouched and verify one nonempty Health workout separately from History.
Retain failed/uncertain attempts; no finish retry, phone replacement export or
Health deletion. Keep personal diagnostics and images out of Git/tracker records.

## Executed-interval enrichment acceptance (#233 / WeeklyHealthReport #80)

Use compatible signed builds containing the [interval contract](../design/workout-interval-enrichment-contract.md).
Software validation does not close this device gate. In a separately supervised
session, include a normal planned step, console speed change, inclination change
and pause/resume. Preserve planned segment indices and verify each executed
sub-interval without resetting the programme clock. Compare readback start/end,
HR minimum/average/maximum, HealthKit-estimated energy and independent workout totals.
Verify v2 distance metadata includes actual cumulative readings and observation
times. A partial observation window stays partial; reset/missing values stay
unavailable. No per-activity HealthKit distance interpolation is permitted.

On OS 27+ check available native zone durations, BPM boundaries and source; on
older OS verify unsupported rather than invented zones. Verify exactly one saved
workout and permanent phone-save suppression. Export only after explicit review
of the enriched preview and destination; inspect Daily v6 privately and verify
historical replacement ordering. Partial coverage need not sum to workout totals.
Exercise the retained manifest byte/count ceiling synthetically; do not operate
hardware to force a protocol resource failure. #116 remains open until the
cross-repository signed-device/HealthKit/reader evidence is complete.

## Starting again while the previous saved recording closes (#212)

Watch foreground recovery can still be verifying termination of a previously
saved primary when iPhone delivers a new explicit Start. The Watch retains one
supported Start during that saved cleanup and shows "Preparing next workout.
Closing previous recording…". Once matching cleanup succeeds, it creates the
new attempt once and follows the ordinary mirror/bind/collection path. The
existing saved receipt stays intact until cleanup has been verified. Duplicate
launch callbacks do not create additional sessions.

A failed cleanup or its existing 15-second timeout clears the waiting Start.
Foreground retry or a late callback cannot resurrect it; a subsequent new Start
is required. An unrelated native primary still fails identity verification.
This queue applies only to an explicit launch during saved cleanup, never an
uncertain save, a recovered active recording or an automatic programme restart.

Regression coverage holds native-operation ports at the cleanup stop and recovery
probe boundaries. It checks new recording/binding and controls, cold recovery,
duplicate starts, failures, timeout and late completion. The new foreground-race
test failed on the released source with zero creates, a saved journal and hidden
recording controls; all 137 Watch lifecycle tests pass with the repair.
These are deterministic simulator tests through the production lifecycle and
recording adapter, not proof of the operator's native device failure stage.
After an installed repair, verify the existing phone-start procedure reaches a
new Watch recording with advancing elapsed time and its recording end/recovery
controls. Device acceptance and any physical workout remain supervised.
