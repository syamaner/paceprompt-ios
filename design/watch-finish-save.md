# Watch finish/save and ordinary ending — revision 3

Changes: PP-20261002-01, PP-20261002-04 and PP-20261003-04. Authorised maintenance after the
build 19/20 operator reports in #212 and the request to remove repetitive
ordinary-end confirmations in #211.

## Evidence and scope

The operator reports startup, pairing and live Watch values working. After console
stop, stationary confirmation and exercise-end confirmation, Watch reported an
uncertain result; the operator then used Watch Stop. PacePrompt History retained
the workout; no Health workout was observed, and Watch offered Prepare next workout.
This is operator evidence, without independently inspected native diagnostics or
Health readback. It fails successful automatic completion/nonempty Health-save
acceptance. It does not identify the native failure stage or prove a zero-prefix
result. That report preceded #217 and the internal build 20 release.

## Build 20 collection-closure follow-up

After a new completed build 20 attempt, the operator supplied a private Watch photo
reporting “Workout was not saved. Stop recording, then prepare your next workout.”
The phone screenshot shows all programme steps completed, local ending and a Watch
end message sent. Live Watch values were reported, but no native diagnostic stage
or Health database was inspected. This fails successful save acceptance; the
exact physical-device cause remains unconfirmed. Personal values and images stay private.

An isolated, previously authorised watchOS 26.5 simulator used the native primary,
collection, pause and verified stopped state. The old order produced HealthKit
error 3, “Activity cannot start or end, builder is not active”, at first interval
insertion after collection closure. Activity counts were zero before and after
closure: automatic extra activity was not the reproduced cause. Moving interval
assembly before collection closure passed the same discard-only probe. A separate
synthetic three-interval probe then returned one native finish receipt with exactly
three closed indoor-walking activities. It used existing simulator permissions,
no new authorisation request and no Health queries. The native probe used distance
unavailable; accepted-distance insertion and reader associations remain unverified.
This is native simulator save evidence, not real-device Health readback or a
complete native paired round trip.

A separate native paired startup test used both companion apps with native
HealthKit adapters and the existing synthetic treadmill fixture on the connected
isolated iPhone/watchOS simulator pair. It failed before binding with
Rapport -6727 (paired companion not found) and HealthKit 300 (remote unreachable).
The empty Watch attempt ended/discarded. This repeats the previous simulator
transport failure; it is not a passed paired test or the cause of the user's
successful-start/failed-save report. The standalone native save probe above
excluded mirroring deliberately and cannot substitute for paired acceptance.

Revision 2 keeps the verified stopped boundary, inserts and verifies intervals
while collection is active, then closes collection and rechecks the exact activity
list, source exclusion and absence of automatic distance. Existing accepted
cumulative-distance and metadata handling follow closure. Writer, identity,
metadata/wire/journal versions, receipt ordering and single-finish semantics do
not change. Build 20 lacks this amendment; a later reviewed release and device
acceptance remain separate requirements. An older failed/uncertain attempt is
never retried or replaced by this repair.

## Architecture gate

The Foundation lifecycle owns identity, durable finish intent/receipt, deadlines
and generation fencing. The recording adapter owns normal stop/assembly/save order;
consumer-owned operations separate stopped activity from emergency session end.
The SDK adapter translates exact native session callbacks, while the assembly
writer retains closed activity/distance invariants. Presentation sends an explicit
stationary-and-end intent; the coordinator applies existing reducer actions in
order and ends only after accepted stationary evidence. Neither view calls HealthKit
or Bluetooth, and no new treadmill command or automatic reconnect is introduced.

Stable invariants: one Watch writer, permanent phone-save suppression, one finish
attempt, no replacement after uncertainty, zero-usable-interval discard, exact
activity mapping and one accepted distance source. Native timing, errors and
callbacks are volatile; injected fake ports/clocks supply deterministic tests.
Local optional failure-stage diagnostics do not change wire v1, Health metadata
schema v1 or journal v2 compatibility. Old records omit the new optional field.

## Normal saving versus recovery

Normal nonempty finalisation uses `stopActivity(with:)` at the agreed end boundary,
waits for the attached primary's exact `.stopped` state/callback, assembles and
verifies intervals while collection is active, ends collection and rechecks
activity/source/distance invariants, adds accepted distance/metadata, persists
finish intent, and calls `finishWorkout` once. It persists the returned workout receipt before calling
native `end()`. Session mode remains available while saving. A subsequent attempt
waits for verified native end before resetting the saved primary. Cold recovery of
a saved journal first probes the prior primary: start/activity/indoor provenance
must match before terminating it. Cleanup failure or timeout preserves the saved
receipt and blocks new primary creation; foreground may retry cleanup without
finishing again. A mismatched session is never ended by saved cleanup. Cleanup cannot
reclassify a durable saved receipt; unknown cleanup timing cannot become proof of
Health absence or authorise another write.

Emergency Stop retains its separate `.ended`/no-active-primary proof, invalidates
pending work and preserves the previous result. Every native await and builder
mutation is generation-fenced. The existing bounded deadline exposes recovery if
stop, assembly or finish stalls. Old callbacks cannot finish or overwrite a later
attempt. No write retry, replacement builder or Health deletion is added.

On failure/timeout the protected local journal records only a closed operation
stage: stopActivity, assemblyValidation, endCollection, activities, distance, metadata, finish or
receiptPersistence. It stores no raw SDK error text, sensor values or transport
payloads for diagnostics. A known failure before finish is presented as not saved;
finish/receipt uncertainty and legacy unknown outcomes remain uncertain. These
coarse stages are local troubleshooting evidence, not a Health-save receipt.

Apple's current [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
guidance specifies stopped activity, collection/save, then session end. Older
examples used end before finishing; the mismatch is a concrete source finding,
not proof of this device cause. Native activity-list behaviour on physical devices
remains unverified:
extra activities still fail closed, and `shouldCollectWorkoutEvents` is not used as
an undocumented activity-suppression mechanism.

## Ordinary ending decision

| Flow | Previous phone taps | New phone taps | Preserved condition |
| --- | ---: | ---: | --- |
| Stationary fallback then end | 4 | 1 | Explicit **Treadmill stopped — end workout** attests observed belt stop; accepted stationary evidence must precede end |
| End with current stationary evidence | 2 | 1 | Existing reducer end eligibility; inline console authority |
| Interrupted/failed stationary recovery | 2 | 1 | Explicit observation remains distinct from successful ending; warning inline |
| Watch emergency Stop / Prepare next | 4 | 2 | Separate direct actions with inline consequences; verified stop and retained uncertain outcome |

Counts exclude physical console operation. Fresh moving telemetry hides the
combined action and still prevents end. Stale or missing telemetry does not prove
stationary: the labelled action is the operator's explicit observation. Repeated
end taps after transition are rejected; no extra local finalisation or Watch save
is created. Portrait and landscape retain accessible controls. Normal end has no
second app confirmation; other permission, deletion, privacy and recovery flows
remain in the wider #211 audit.

## Validation and remaining acceptance

Two ordering regressions first failed on the previous implementation. Deterministic
contracts cover verified stopped activity before builder operations, receipt before
cleanup, following-attempt native end, failures by stage, missing/late callbacks,
cancellation, saved-journal crash recovery/mismatch/timeout, unchanged zero-prefix/idempotency and optional journal decoding.
UI tests cover one-tap ordinary ending in both orientations and unchanged recovery
direct observation. Required local/CI and independent exact-head review evidence is
recorded in the PR and development ledger.

A later installed candidate must repeat normal completion with no Watch tap and
exactly one nonempty Health workout, plus foreground/background and recovery.
#212 and #115 remain open for device acceptance; #116 and WeeklyHealthReport #80
remain separate interchange/reader work. No hardware, real Health-data inspection,
release upload or implementation of those dependent issues occurs in this slice.

Revision 3 adopts [the #211 confirmation decisions](confirmation-decisions.md):
recovery explanations move inline and duplicate dialogs are removed. Native stop,
archival and save policies are unchanged; normal phone ending remains automatic.
