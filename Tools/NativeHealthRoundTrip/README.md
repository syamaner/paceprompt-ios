# Synthetic native Health round trip

This developer-only harness compiles seven **complete, unchanged producer files
from an exact Git commit** into a temporary Watch host. It exercises the actual
wire decoder, lifecycle, recording adapter, builder policy and Health metadata
writer, then saves and queries the native workout by its exact UUID. The only
substitution is companion mirroring: wire bytes are delivered in process. This
proves neither transport reliability nor physical treadmill behaviour.

The host has no Bluetooth or provider implementation. It creates a new iOS 27 /
watchOS 27 simulator pair, uses the released companion bundle relationship, and
embeds both a compile-time simulator restriction and the exact new device UUIDs.
It never selects an existing device, changes Health authorization, installs on
hardware, deletes a simulator, rewrites a saved workout, or adds samples after
save. The phone companion is an inert label with no Health writer. Native archives
and diagnostics remain under an absent `/private/tmp` directory, outside Git.

## Prepare and run

Requirements: the approved Xcode 27 SDK/runtime combination, `xcodegen`, Python 3,
and the iPhone 17 Pro / Apple Watch Series 11 (46 mm) simulator device types.
Use a reviewed, committed producer SHA; the generator deliberately refuses branch
names and uncommitted source substitution.

```sh
python3 Tools/NativeHealthRoundTrip/harness.py prepare \
  --repo /absolute/path/to/PacePrompt --ref <exact-40-character-commit> \
  --writer-api v3 --output /private/tmp/pp-native-proof
python3 Tools/NativeHealthRoundTrip/harness.py build-install \
  --output /private/tmp/pp-native-proof
python3 Tools/NativeHealthRoundTrip/harness.py run \
  --output /private/tmp/pp-native-proof --case v3-paused
```

`prepare` records each newly created simulator and pairs those exact IDs.
`build-install` uses simulator-only ad-hoc signing, without a development team or
provisioning credentials. The output contains complete source hashes, harness and
generated-input hashes, compiled artifact hashes, simulator identities and the
explicit case identity map. The app's Health source may be its phone companion
identifier; compare actual source revisions, not display names or metadata keys.

On the named synthetic Watch, approve its native workout/distance write prompt
only within the authorised synthetic scope. Authorization preflight happens
before the real lifecycle's startup deadline. After save, approve the exact
workout read prompt. The host bounds recording to 90 seconds after authorization
and its saved-UUID query to 15 seconds. The CLI waits at most 35 seconds and leaves
the app alive if a prompt is pending. Continue by collecting, not by restarting:

```sh
python3 Tools/NativeHealthRoundTrip/harness.py collect \
  --output /private/tmp/pp-native-proof
```

A completed case produces `outputs/<case>.manifest.json`, `.receipt.json`,
`.hkworkout` and `.log`. Existing bytes cannot be replaced by different bytes.
`probe.latest.log` is explicitly mutable; every observed log also has an immutable
SHA-addressed snapshot. Duplicate saves and unresolved attempts block `run`.
For a failed/ambiguous attempt, retain its evidence; use **Stop synthetic
recording** on that Watch if needed, then create a fresh proof workspace/pair.
Never overwrite the old identity or call a failure a successful native proof.

Run the remaining scenarios one at a time, collecting and retaining each before
starting another:

| Case | Declared accepted input | Native sample expectation |
| --- | --- | --- |
| `v3-paused` | 100 m; two interval deltas 30 + 70 m | Suppressed for unsafe coverage; accepted 100 remains separate |
| `v3-zero` | Observed counters 100 → 100, accepted 0 | Suppressed as `zeroAggregate`; zero remains available |
| `v3-incomplete` | No confirmed aggregate; one interval has 10 m | Suppressed as `notAccepted`; do not infer a whole total |
| `v3-rich` | 30.625 m; fractional targets, 0.625 s gap, partial 12.375 m first interval, unavailable second interval | Included only if exact native timing is safe |
| `v3-safe-0` … `v3-safe-7` | 10 m per uniquely identified attempt | Classify every natural boundary; never adjust timestamps |

The rich case uses prescribed speed/inclination 3.125/1.25 then 5.125/3.25,
effective and independently observed 3.5/2.75 then 4.875/3, and manual override
provenance. The first distance observation window is strictly inside its interval.
No heart-rate or energy values are invented or injected; retain native availability.

For safe candidates, stop once a genuine included sample is proved. To reproduce
the separate final-pause defect, use only the remaining candidates up to the
fixed total of eight: seek a final point pause strictly before the unchanged
sample end, with a valid strictly-later sample start and no earlier pause. Retain
all attempts and their native events. An invalid start is
`uncertainTemporalCoverage`, not isolated final-pause proof. If no qualifying
natural case occurs, report that native gap; do not shift dates, retry invisibly,
rescale a quantity, or fabricate an allocation.

For historical writer verification, create a **different fresh workspace/pair**
with `--writer-api legacy` and the released build-24 source commit
`7c4ae4f7cd94f2cf0168e603cc3830ed5929f5ca`. Run `v2-paused` for its accepted 100 m
sample. The old sample is persisted unchanged while native statistics can exclude
the pause proportionally. The current producer API can also execute the declared
legacy v1/v2 scenarios, but that is not a claim that it compiled build-24 source.

## Join the actual reader

Use WeeklyHealthReport's `Tools/WorkoutNativeInterop` from a separately reviewed
exact consumer commit. Its independently declared expectation generator must agree
with `case-identities.json`; never derive expected values from saved metadata or
change expectations to match a failed output. Retain both repository revisions and
all harness hashes in the combined evidence. The descriptor interface is
`scenarios.json` with `name`, `archive`, `nativeWorkoutUUID`,
`expectedAssociatedDistanceMetres`, and `expectedJSONPaths`.

First query each exact synthetic UUID on the paired phone through the real
HealthKit client and produce Daily schema 7 via the production projection,
serializer and strict identity validator. For legacy recovery, verify the exact
associated sample's source, sync identity/version, bounds and uniqueness. Assert
native statistics literally, separately from accepted distance. A secure archive
may independently verify the reader pipeline, but archive import alone is not
proof of Watch-to-phone Health synchronization. Metadata reboxing and post-save
sample injection are excluded from native acceptance.

New unsafe workouts may have no native distance in Apple Health or Fitness. The
accepted aggregate remains a separate value in the compatible reader. Historical
recovery does not rewrite Health. Native timestamps, activity statistics and
estimated energy remain literal; absent heart rate/zones remain unavailable, and
raw heart-rate series are not exported.

## Validate the reproducer

```sh
python3 -B -m unittest discover -s Tools/NativeHealthRoundTrip -p 'test_*.py' -v
```

These tests use mocked simulator operations and perform no Health access. Compile
both template API variants against their exact producer inputs before publishing
a harness change. The harness is outside every production and XCTest target; its
standalone tests supplement, rather than replace, the complete app gate. Preserve
all frozen app-input hashes when adding or reviewing this tool.
