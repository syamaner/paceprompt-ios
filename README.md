# PacePrompt

PacePrompt is a local-first iPhone app for turning plain-English interval workouts into validated treadmill plans and, in later authorised slices, running them on a Reebok FR30z over Bluetooth FTMS.

The core product rule is: AI may propose a plan; deterministic local code validates it and controls the treadmill.

## Current slice

This version contains:

- a native SwiftUI iPhone shell with Home, Plans, History and Settings;
- explicit Bluetooth availability and treadmill connection states;
- a user-initiated scan restricted to devices advertising Fitness Machine Service `0x1826`;
- explicit device selection, connection, service and characteristic discovery;
- reads of Fitness Machine Feature `0x2ACC`, Supported Speed Range `0x2AD4` and Supported Inclination Range `0x2AD5`;
- passive subscriptions to Treadmill Data `0x2ACD`, Training Status `0x2AD3` and Fitness Machine Status `0x2ADA`, when notified by the treadmill;
- raw hexadecimal diagnostics alongside bounded decoded values;
- pure FTMS parsers tested with synthetic payloads.

It does **not** contain treadmill commands, FTMS Control Point writes, workout execution, OpenRouter, API keys, HealthKit access, a watchOS app or persistent workout history.

The FTMS mappings and field layouts were checked against the Bluetooth SIG [Fitness Machine Service 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/) and its current [Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf) document on 2 September 2026.

## Architecture

- `FTMSClient` owns CoreBluetooth scanning, connection, discovery, reads and passive subscriptions.
- `FTMSParser` and its value types decode data without CoreBluetooth or SwiftUI.
- `TreadmillSetupViewModel` adapts client events into explicit observable presentation state.
- SwiftUI views render state and forward deliberate user actions; they do not parse bytes or call CoreBluetooth.

The client protocol intentionally has no characteristic-write operation.

## Privacy

PacePrompt has no account, analytics, advertising, telemetry, cloud storage or background delivery. It makes no network API calls and requests no HealthKit permission. Capability diagnostics stay in memory and are not persisted.

Do not commit personal device captures or signing identifiers. Synthetic fixtures are clearly isolated in the test target.

## Build and test

Requirements used for this slice:

- Xcode 26.6 (build 17F113)
- iPhoneOS and iPhoneSimulator SDK 26.5
- iOS 17 minimum deployment target

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

Use another listed iPhone simulator if that model is not installed.

## Physical FR30z capability check

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`, replace the placeholder with your Apple development-team identifier, and keep that ignored file local.
2. Open `PacePrompt.xcodeproj`, select your connected iPhone and run PacePrompt.
3. Turn on the FR30z and insert its fitness Bluetooth dongle. Keep the physical console and safety key authoritative.
4. In PacePrompt, open **Settings → Treadmill**, press **Scan for FTMS treadmills**, select the FR30z and connect.
5. Capture the displayed raw and decoded values for `0x2ACC`, `0x2AD4` and `0x2AD5`.
6. Without starting the belt through the app, observe and capture any `0x2ACD`, `0x2AD3` and `0x2ADA` notifications.
7. Disconnect in PacePrompt when finished.

Return:

- the discovered device name and identifier;
- the full discovered-characteristic list and properties;
- raw values for `0x2ACC`, `0x2AD4` and `0x2AD5`;
- several stationary `0x2ACD` and `0x2ADA` packets, plus `0x2AD3` if present;
- any malformed-packet, permission, connection or disconnect message.

These captures are inputs to a separately authorised control slice. They are not permission to send a command.

## Simulator limitation

Simulator tests verify parsing, presentation and that the app builds. They cannot establish physical Bluetooth behaviour.

A user-run iPhone/FR30z check on 2 September 2026 confirmed that PacePrompt can discover and connect to the treadmill, enumerate the expected FTMS characteristics, and read and decode the three capabilities in this slice. No passive notification values were visible in the returned evidence, so stationary notification behaviour remains unresolved. This check did not exercise or establish any Control Point behaviour.

## Repository guidance

Product and design sources stay under `design/`. Project-wide safety and slice rules are in `AGENTS.md`; repository-local skills are maintained under `.agents/skills`. Per-commit Codex token measurements and API-equivalent estimates are recorded in `DEVELOPMENT_NOTES.md`.
