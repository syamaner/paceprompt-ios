# iPhone-only Apple Health workout export contract

Status: accepted product contract from GitHub issue [#63](https://github.com/syamaner/paceprompt-ios/issues/63). This document defines domain and export semantics only. It does not add a HealthKit entitlement, request permission, save or read Health data, expose History UI, operate a treadmill, or implement a JSON share flow.

## Scope and authority

This contract extends the accepted [local workout storage and history contract](local-workout-storage-and-history-contract.md) after the foreground physical-console execution accepted by issues [#57](https://github.com/syamaner/paceprompt-ios/issues/57), [#59](https://github.com/syamaner/paceprompt-ios/issues/59) and [#62](https://github.com/syamaner/paceprompt-ios/issues/62). It resolves the narrower duration-and-distance wording in parent issue [#48](https://github.com/syamaner/paceprompt-ios/issues/48): the Apple Health workout may also carry a bounded prescribed-versus-executed interval mirror, while the versioned local record remains the complete machine-readable authority.

The checked-in product specification and `TreadmillDesign.pdf` remain visual and eventual-product context. Their Watch, heart-rate, energy and rich trace concepts are not implementation authority.

The current Apple API references for this contract are:

- [`HKWorkoutBuilder`](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder), used to construct and save one workout and its associated data;
- [`HKWorkoutActivity`](https://developer.apple.com/documentation/healthkit/hkworkoutactivity), used for non-overlapping executed intervals;
- [`HKWorkoutActivity.metadata`](https://developer.apple.com/documentation/healthkit/hkworkoutactivity/metadata), which permits string, number and date values under predefined or app-specific keys;
- [`HKMetadataKeySyncIdentifier`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier) and [`HKMetadataKeySyncVersion`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion), used for stable replacement identity; and
- [`NSHealthUpdateUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nshealthupdateusagedescription), required by the later write implementation.

These documentation links inform the contract but do not replace signed-iPhone verification of the eventual implementation.

## Product decisions

1. Apple Health saving is a deliberate post-workout action. PacePrompt performs no automatic or background save.
2. PacePrompt requests write access only for the workout type and walking/running distance. It requests no HealthKit read access.
3. The local execution summary and its versioned prescribed-versus-executed timeline remain authoritative. HealthKit receives one useful workout plus a flattened interval mirror, not the complete local record.
4. `indoorWalking` maps to HealthKit walking with indoor location; `indoorRunning` maps to running with indoor location.
5. PacePrompt exports only a terminal, eligible local attempt. HealthKit success or failure never changes the local workout outcome.
6. A trustworthy session distance is optional. PacePrompt never derives distance from speed and time.
7. Planned, effective-target and observed speed and inclination remain separate. Absence in one layer is never filled from another.
8. PacePrompt writes no heart rate, active energy, calories, raw speed samples, raw inclination samples, high-frequency treadmill data, Control Point evidence, peripheral identity, plan prose or diagnostics to HealthKit.
9. The manual PacePrompt JSON export is the supported machine-readable interchange for an agent. HealthKit custom metadata is a bounded mirror and is not a promise about the contents of Apple's general Health-data archive.
10. Apple Watch and cross-device workout ownership remain post-MVP under issue [#7](https://github.com/syamaner/paceprompt-ios/issues/7).

## Execution-summary version 2

The implementation slice must introduce a new execution-summary schema version. It must not reinterpret or rewrite version-1 records.

Version 2 retains every version-1 field and adds:

| Field | Contract |
| --- | --- |
| `activityTimeline` | A tagged recorded or unavailable value. A recorded value contains workout start/end and ordered executed intervals. |
| `distance.provenance` | For a measured distance, a stable method and accepted aggregate boundary evidence. An unavailable distance retains a reason. |
| `healthExport` | Export state and an optional successful receipt, kept logically separate from the local workout facts. |

Updating `healthExport` never changes the attempt identity, plan snapshot, outcome, timeline, distance or stop evidence. Keeping it in the same versioned history record makes record deletion and atomic replacement follow the existing repository contract without a second store or orphaned sidecar.

### Activity timeline

A recorded timeline contains:

- `startedAt`: the UTC start of the first active interval under the accepted execution clock;
- `endedAt`: the UTC end of the final active interval under the accepted execution clock;
- `timingProvenance`: `executionClock`, identifying the accepted reducer/orchestrator timing boundary rather than claiming continuous belt-motion measurement; and
- ordered `executedIntervals`.

The existing summary `activeDuration` remains the single persisted duration field. When measured, it must equal the sum of the closed executed-interval durations.

`startedAt` is never copied from `attemptedAt`. `endedAt` is never copied from `lastUpdatedAt` or a later human stationary-confirmation time. Human confirmation establishes a safe terminal state; it does not invent an earlier physical stop instant.

The timeline is unavailable when any required boundary is absent or inconsistent. PacePrompt does not create `endedAt` by adding active duration to `startedAt`.

### Logical segments and executed intervals

The immutable `planSnapshot.steps` is the prescribed timeline. Each step's zero-based position is its stable `segmentIndex`; there is no inferred identity.

An executed interval is a closed period during which one effective target pair was active. It contains:

| Field | Contract |
| --- | --- |
| `segmentIndex` | Zero-based index into `planSnapshot.steps`. |
| `intervalIndex` | Zero-based index among executed intervals for that logical segment. |
| `startedAt` / `endedAt` | UTC execution-clock boundaries. Intervals are ordered, closed and non-overlapping. |
| `prescribed` | The indexed plan step's kind, speed in kilometres per hour and inclination percent, repeated here so consumers do not need a join or inference. |
| `effectiveSpeed` | Numeric kilometres per hour plus `planned` or `manualOverride` source. |
| `effectiveInclination` | Numeric percent plus `planned` or `manualOverride` source. |
| `settledObservation` | Required speed, inclination, UTC time and provenance from the later exact joint treadmill report; kept separate from the effective target. |
| `endReason` | Stable value such as `planTransition`, `targetChanged`, `paused`, `completed`, `endedByUser`, `interrupted` or `failed`. |

The interval starts only when issue #57's later current-epoch joint treadmill report has observed the effective speed and inclination after all required acknowledgements. That single settled observation is an aggregate boundary fact, not a persisted telemetry trace or average. Without it, no executed interval opens.

A speed or inclination change closes the current interval and can open another interval only after the new effective pair is separately observed. Because speed and inclination overrides are independent, each axis records its own `planned` or `manualOverride` source. Pause gaps are not active intervals. Resume opens a new interval after the restored effective pair is observed; restoration itself does not change the value source.

If an attempt fails or becomes interrupted before a target is observed, the pending target does not become an executed interval. Closed intervals may remain in local History, but failed and interrupted attempts are not Health-export eligible.

### Distance provenance

A measured session distance is valid only when all of these hold:

1. an accepted starting cumulative-distance value at the first executed-interval boundary and a later accepted final cumulative-distance value at or after the final executed-interval boundary came from well-formed current-epoch FR30z Treadmill Data during the same attempt;
2. the accepted cumulative values used by the aggregate did not regress or reset unexpectedly;
3. final value is greater than or equal to the start value; and
4. session metres equal the exact decimal final-minus-start difference.

Its provenance is `fr30zCumulativeDistanceDelta` and retains only the two accepted aggregate boundary values and their UTC observation times. It retains no raw packet, peripheral identifier or high-frequency series.

A missing boundary, regression, reset, malformed value, changed connection epoch or otherwise uncertain basis makes distance unavailable. A measured zero remains truthful locally but is omitted from the HealthKit distance sample. Speed multiplied by duration, plan distance and interpolation are prohibited.

## Machine-readable PacePrompt export

Issue [#96](https://github.com/syamaner/paceprompt-ios/issues/96), when separately authorised, must encode a selected supported version-2 summary into a JSON document with its own integer `formatVersion`. The document materialises the immutable prescribed plan beside the executed timeline so an agent does not need to infer or join semantic fields.

The stable top-level shape is:

```json
{
  "formatVersion": 1,
  "createdAt": "2026-09-13T12:00:00Z",
  "workouts": [
    {
      "summaryID": "00000000-0000-0000-0000-000000000001",
      "summarySchemaVersion": 2,
      "activity": "indoorWalking",
      "outcome": "completed",
      "timing": {
        "startedAt": "2026-09-13T11:50:00Z",
        "endedAt": "2026-09-13T11:55:00Z",
        "activeDurationSeconds": 300,
        "provenance": "executionClock"
      },
      "prescribedSegments": [
        {
          "segmentIndex": 0,
          "kind": "warmUp",
          "durationSeconds": 60,
          "speedKilometresPerHour": 0.5,
          "inclinationPercent": 0
        },
        {
          "segmentIndex": 1,
          "kind": "interval",
          "durationSeconds": 180,
          "speedKilometresPerHour": 0.6,
          "inclinationPercent": 0
        },
        {
          "segmentIndex": 2,
          "kind": "coolDown",
          "durationSeconds": 60,
          "speedKilometresPerHour": 0.5,
          "inclinationPercent": 0
        }
      ],
      "executedIntervals": [
        {
          "segmentIndex": 0,
          "intervalIndex": 0,
          "startedAt": "2026-09-13T11:50:00Z",
          "endedAt": "2026-09-13T11:51:00Z",
          "prescribed": {
            "kind": "warmUp",
            "speedKilometresPerHour": 0.5,
            "inclinationPercent": 0
          },
          "effectiveSpeed": {
            "kilometresPerHour": 0.5,
            "source": "planned"
          },
          "effectiveInclination": {
            "percent": 0,
            "source": "planned"
          },
          "settledObservation": {
            "state": "observed",
            "observedAt": "2026-09-13T11:50:00Z",
            "speedKilometresPerHour": 0.5,
            "inclinationPercent": 0,
            "provenance": "fr30zTreadmillDataCurrentEpoch"
          },
          "endReason": "planTransition"
        },
        {
          "segmentIndex": 1,
          "intervalIndex": 0,
          "startedAt": "2026-09-13T11:51:00Z",
          "endedAt": "2026-09-13T11:52:00Z",
          "prescribed": {
            "kind": "interval",
            "speedKilometresPerHour": 0.6,
            "inclinationPercent": 0
          },
          "effectiveSpeed": {
            "kilometresPerHour": 0.6,
            "source": "planned"
          },
          "effectiveInclination": {
            "percent": 0,
            "source": "planned"
          },
          "settledObservation": {
            "state": "observed",
            "observedAt": "2026-09-13T11:51:00Z",
            "speedKilometresPerHour": 0.6,
            "inclinationPercent": 0,
            "provenance": "fr30zTreadmillDataCurrentEpoch"
          },
          "endReason": "targetChanged"
        },
        {
          "segmentIndex": 1,
          "intervalIndex": 1,
          "startedAt": "2026-09-13T11:52:00Z",
          "endedAt": "2026-09-13T11:54:00Z",
          "prescribed": {
            "kind": "interval",
            "speedKilometresPerHour": 0.6,
            "inclinationPercent": 0
          },
          "effectiveSpeed": {
            "kilometresPerHour": 0.7,
            "source": "manualOverride"
          },
          "effectiveInclination": {
            "percent": 1,
            "source": "manualOverride"
          },
          "settledObservation": {
            "state": "observed",
            "observedAt": "2026-09-13T11:52:00Z",
            "speedKilometresPerHour": 0.7,
            "inclinationPercent": 1,
            "provenance": "fr30zTreadmillDataCurrentEpoch"
          },
          "endReason": "planTransition"
        },
        {
          "segmentIndex": 2,
          "intervalIndex": 0,
          "startedAt": "2026-09-13T11:54:00Z",
          "endedAt": "2026-09-13T11:55:00Z",
          "prescribed": {
            "kind": "coolDown",
            "speedKilometresPerHour": 0.5,
            "inclinationPercent": 0
          },
          "effectiveSpeed": {
            "kilometresPerHour": 0.5,
            "source": "planned"
          },
          "effectiveInclination": {
            "percent": 0,
            "source": "planned"
          },
          "settledObservation": {
            "state": "observed",
            "observedAt": "2026-09-13T11:54:00Z",
            "speedKilometresPerHour": 0.5,
            "inclinationPercent": 0,
            "provenance": "fr30zTreadmillDataCurrentEpoch"
          },
          "endReason": "completed"
        }
      ],
      "distance": {
        "state": "measured",
        "metres": 45,
        "provenance": "fr30zCumulativeDistanceDelta",
        "startCumulativeMetres": 10,
        "startObservedAt": "2026-09-13T11:50:00Z",
        "finalCumulativeMetres": 55,
        "finalObservedAt": "2026-09-13T11:55:00Z"
      }
    }
  ]
}
```

The normative schema will be frozen with the implementation issue. The example fixes the semantic field names and units but uses synthetic values only. JSON numbers remain numbers; display formatting and locale do not alter them.

The preview must disclose that the export contains prescribed and executed speed and inclination. The export still excludes raw prompts, provider exchanges, raw telemetry, command evidence, peripheral identity and diagnostics. It uses the protected temporary-file and cleanup rules in the local storage contract.

## Apple Health interval mirror

For an eligible version-2 summary, the later HealthKit implementation creates one non-overlapping `HKWorkoutActivity` for each closed executed interval. Every activity uses the containing workout's walking or running activity and indoor location.

The metadata namespace is the production bundle identifier prefix `com.otherweather.PromptPace`. Each activity uses only these flattened keys:

| Metadata key suffix | HealthKit value | Meaning |
| --- | --- | --- |
| `timelineSchemaVersion` | `NSNumber` integer | Version of this metadata mapping; initially `1`. |
| `segmentIndex` | `NSNumber` integer | Prescribed logical-segment index. |
| `intervalIndex` | `NSNumber` integer | Executed interval index within that segment. |
| `prescribedSegmentKind` | `NSString` | `warmUp`, `interval`, `recovery` or `coolDown`. |
| `prescribedSpeedKilometresPerHour` | `NSNumber` decimal | Plan snapshot speed for the logical segment. |
| `prescribedInclinationPercent` | `NSNumber` decimal | Plan snapshot inclination for the logical segment. |
| `effectiveTargetSpeedKilometresPerHour` | `NSNumber` decimal | Effective interval target. |
| `effectiveTargetInclinationPercent` | `NSNumber` decimal | Effective interval target. |
| `speedTargetSource` | `NSString` | `planned` or `manualOverride`. |
| `inclinationTargetSource` | `NSString` | `planned` or `manualOverride`. |
| `observedSpeedKilometresPerHour` | `NSNumber` decimal | Required settled treadmill observation. |
| `observedInclinationPercent` | `NSNumber` decimal | Required settled treadmill observation. |
| `observedAt` | `NSDate` | UTC instant of the settled joint observation. |
| `observationProvenance` | `NSString` | `fr30zTreadmillDataCurrentEpoch` when observed. |
| `intervalEndReason` | `NSString` | Stable reason that closed the interval. |

The full keys are the prefix, a full stop, and the suffix, for example `com.otherweather.PromptPace.segmentIndex`.

Every mirrored interval has its required observed-value, `observedAt` and provenance keys. Effective targets are never copied into observed fields. A record that cannot satisfy this invariant is not eligible for Health export rather than producing a partial interval mirror.

PacePrompt does not use `HKMetadataKeyAverageSpeed` for a target or one settled observation because neither is a measured time-weighted average. It does not use `HKMetadataKeyAlpineSlopeGrade` or derive elevation from treadmill inclination. It writes no speed or inclination `HKQuantitySample`, so these metadata fields add no new HealthKit share type.

The implementation converts canonical `Decimal` values to `NSDecimalNumber` metadata values. It does not round-trip through binary `Double` or expose floating-point representation tails in the metadata.

Apple documents custom metadata on HealthKit activities, but this contract makes no claim that arbitrary keys appear in Apple's **Export All Health Data** archive or native Fitness charts. The PacePrompt JSON document is the supported agent interchange. A third-party iOS reader requires its own user-granted HealthKit permissions and is outside this app's authority.

## Health export eligibility

An attempt is eligible only when:

- its summary schema version is 2;
- outcome is `completed` or `stoppedByUser` after an accepted terminal stationary state;
- physical stop is not unconfirmed;
- the activity timeline is recorded, internally consistent and contains at least one closed interval;
- active duration is greater than zero and equals the sum of executed-interval durations;
- every mirrored interval has recorded prescribed, effective and separately observed values; and
- activity maps exactly to indoor walking or indoor running.

Distance is not required. It is added only when the provenance rules above pass and metres are greater than zero.

Version-1, in-progress, failed, interrupted, physically uncertain, unconfirmed-stop and timing-unavailable attempts remain local only. There is no reconstruction from `attemptedAt`, `lastUpdatedAt`, plan duration, progress counters or human-confirmation time.

## HealthKit authorization and availability

The later implementation must:

1. check `HKHealthStore.isHealthDataAvailable()`;
2. request authorization only after the user invokes **Save to Apple Health** for the first time;
3. pass only workout and walking/running distance types to the share set and an empty read set;
4. evaluate write authorization separately for each type before saving; and
5. include a specific `NSHealthUpdateUsageDescription` explaining the deliberate workout and optional treadmill-distance save.

Workout write authorization is required. If workout is authorized and distance is denied, unavailable or absent, PacePrompt may save the workout without distance and records that exact result. A completed authorization request is not itself evidence that both types were granted.

`denied` means the current type is not share-authorized. `revoked` may be presented only when a locally retained earlier state recorded authorization and a later check reports denial; otherwise PacePrompt does not infer the user's history.

## Idempotency, save state and partial failure

The version-2 summary's `healthExport` value has these states:

- `notRequested`;
- `pending` with attempt time and candidate sync version;
- `saved` with save time, sync version, returned HealthKit workout UUID, mirrored-interval count and whether distance was included;
- `denied` with affected write type;
- `unavailable` with stable category;
- `failedRetryable` with stable error category; or
- `failedAmbiguous` when HealthKit may have committed but the app did not obtain conclusive completion.

The export value stores no raw HealthKit error, Health data, plan prose, treadmill identifier or diagnostics. A save-state mutation replaces only `healthExport`; it never rewrites the local workout outcome, timeline, distance or stop evidence.

The workout sync identifier is `com.otherweather.PromptPace.workout.<lowercase-summary-uuid>`. The optional distance sample uses `com.otherweather.PromptPace.distance.<lowercase-summary-uuid>`. Both carry the same positive integer sync version.

The payload for one sync version is immutable. A retry after a definite pre-save failure may reuse it. A changed payload, an attempt to add newly authorized distance, or a retry after ambiguous completion uses the next sync version so HealthKit can replace any lower-version objects with the same identifiers. Numeric sync version is never inferred from timestamps.

All activities, metadata and the optional distance sample are added to one builder before `finishWorkout`. Any definite failure before finish discards that builder. `saved` is recorded only after finish returns a workout. If the workout saves but recording the local receipt fails, the next attempt is ambiguous and uses a higher sync version rather than claiming either success or absence.

## Deletion and retention

- Deleting a local history record inherently removes its nested `healthExport` state in the same atomic local mutation. It does not delete or alter a workout already saved to HealthKit.
- **Clear history** and local-data reset do not delete HealthKit objects.
- PacePrompt performs no HealthKit delete in the iPhone MVP.
- Because PacePrompt has no read access, it cannot detect that a user or another app later deleted or changed a HealthKit workout. The UI says **Saved to Apple Health on...**, not **Currently in Apple Health**.
- A removed local record cannot be retried because PacePrompt retains no hidden sync tombstone, sidecar or workout payload.

## UI semantics

Preflight may show that Apple Health saving is available after the workout. It never prompts for permission or describes distance permission alone.

History detail presents local workout outcome independently from Health save state. It supports eligible-unsaved, permission-needed, saving, saved with distance, saved without distance, denied, unavailable, failed/retryable, ambiguous and ineligible states. Watch ownership and heart-rate wording are omitted.

Before saving, the confirmation preview names the activity, start/end, active duration, optional distance and number of interval metadata records. It states that each interval contains prescribed, effective-target and separately observed speed and inclination.

## Evidence and implementation boundaries

The domain implementation must use deterministic synthetic fixtures to prove:

- version-1 records remain readable and ineligible without reconstruction;
- version-2 round trips and rejects overlapping, unordered, open or inconsistent intervals;
- manual speed/inclination changes split intervals and preserve independent value sources;
- targets and observations never collapse, and a missing settled observation cannot open an executed interval;
- distance delta, zero, regression, reset, epoch change and missing-boundary cases;
- eligibility for every outcome and stop state;
- stable JSON field names, numeric units and exclusion of prohibited fields;
- stable Health metadata keys and flattened values;
- authorization, partial grant, save, retry, higher-version replacement, ambiguous completion and local-receipt failure using a fake store; and
- deletion semantics without a HealthKit delete.

Simulator tests can prove presentation and the fake-store boundary only. They are not evidence of HealthKit persistence, authorization presentation, metadata retention, duplicate prevention or Apple Health appearance.

Issue [#64](https://github.com/syamaner/paceprompt-ios/issues/64) must verify the real write path on a signed authorized iPhone. Issue [#96](https://github.com/syamaner/paceprompt-ios/issues/96) must verify the exact JSON document and agent parser fixture. Any claim about Apple's general Health-data archive retaining custom metadata requires separate direct evidence; it is not accepted by this contract.

## Exclusions

This issue adds no entitlement or executable code, permission prompt, HealthKit call, HealthKit read access, Apple Watch target, WatchConnectivity, heart-rate or energy data, speed or inclination quantity samples, raw telemetry persistence, command evidence, peripheral identity, diagnostic export, background delivery, physical treadmill operation, provider call, analytics or cloud storage.
