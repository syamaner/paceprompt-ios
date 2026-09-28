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
   v3 Daily fixtures and daily aggregates while introducing schema 4.
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
   was observed before the deadline. Watch ends collection and finishes once. Confirm the Watch shows the actual save result, while iPhone keeps “Watch-owned; save result unavailable on iPhone”; a final-manifest ack is not a save receipt.
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
replacement. Read the resulting schema-v4 JSON privately and assert:

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
state and schema-v4 round trip pass on the tested combination. Reconcile #7,
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
