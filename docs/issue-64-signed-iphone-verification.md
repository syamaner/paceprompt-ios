# Issue #64 signed-iPhone verification

This checklist prepares the separately observed physical-iPhone acceptance evidence for the deliberate Apple Health write. Simulator tests and an unsigned build do not prove HealthKit authorization, persistence, metadata retention, replacement behaviour or appearance in Apple Health.

## Preconditions

- Use a personal signing team only through ignored `Config/Signing.local.xcconfig`; do not commit team IDs, profiles or certificates.
- Use a physical iPhone running a supported iOS version, signed into the operator's intended Apple Health environment.
- Record a newly eligible version-2 PacePrompt workout. Do not reuse or reconstruct a version-1 record.
- Use synthetic/non-sensitive workout values when practical. Do not capture Health data, device diagnostics or personal values in GitHub evidence.

## Build preparation

1. Confirm the app target has the HealthKit capability and the built entitlements contain `com.apple.developer.healthkit`.
2. Confirm the generated Info.plist contains `NSHealthUpdateUsageDescription` with the deliberate workout and optional-distance explanation.
3. Build the Release app for `generic/platform=iOS` with the ignored local signing configuration.
4. Keep CI unsigned; no signing material belongs in Git or hosted logs.

## Physical acceptance observations

For one newly recorded eligible version-2 summary:

1. Open History and confirm that no Health permission prompt appears before tapping **Save to Apple Health**.
2. Inspect the confirmation preview: activity, execution-clock start/end, active duration, optional accepted distance and interval count must match the local summary. Confirm the disclosure distinguishes prescribed, effective-target and observed speed/inclination.
3. Tap **Save** and verify the authorization sheet requests write access only for Workouts and Walking + Running Distance, with no read request.
4. With both write types allowed, verify exactly one indoor walking/running workout appears in Apple Health with the expected source, start, end, active duration and accepted non-zero distance.
5. Retry the same saved record and confirm the UI offers no duplicate-producing action and Apple Health still contains one workout.
6. Repeat with workout access allowed and distance access denied. Verify the workout saves once, has no distance sample, and PacePrompt says **Saved to Apple Health without distance**.
7. Repeat with workout write access denied. Verify no workout is saved, local workout facts are unchanged, and the denial state is shown.
8. Exercise a deliberately injected ambiguous fake-store result only in the deterministic test boundary; do not manufacture an ambiguous real HealthKit write. Verify the next payload uses a higher sync version in tests.

Record only the iOS version, app commit, pass/fail for each observation and whether distance was included. Do not claim that custom activity metadata survives Apple's general Health-data archive without separate direct evidence.
