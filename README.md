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
- passive subscriptions to Treadmill Data `0x2ACD`, Training Status `0x2AD3` and Fitness Machine Status `0x2ADA`, with explicit inactive, subscribing, subscribed, not-subscribable and failed states;
- full flag-driven decoding of supported Treadmill Data fields, Training Status values and Fitness Machine Status opcodes, while preserving unavailable sentinels, unknown values and malformed packets;
- a 100-packet, timestamped, in-memory log with raw hexadecimal bytes and decoded values;
- deliberate copy and system-share actions, with no automatic persistence or transmission;
- pure FTMS parsers tested with synthetic payloads.

It does **not** contain treadmill commands, FTMS Control Point writes, workout execution, OpenRouter, API keys, HealthKit access, a watchOS app or persistent workout history.

The FTMS mappings, behaviours and field layouts were checked on 2 September 2026 against Bluetooth SIG [Fitness Machine Service 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/), the 5 February 2026 [GATT Specification Supplement](https://www.bluetooth.com/specifications/gss/) and current [Assigned Numbers](https://www.bluetooth.com/specifications/assigned-numbers/).

## Architecture

- `FTMSClient` owns CoreBluetooth scanning, connection, discovery, reads and passive subscriptions.
- `FTMSParser` and its value types decode little-endian fields, optional flags, unavailable sentinels and unknown protocol values without CoreBluetooth or SwiftUI.
- `TreadmillSetupViewModel` adapts client events into explicit observable presentation state.
- `TreadmillSetupViewModel` also bounds packet capture to the newest 100 entries and builds the user-requested diagnostic report in memory.
- SwiftUI views render state and forward deliberate scan, connection, copy, share and clear actions; they do not parse bytes or call CoreBluetooth.

The client protocol intentionally has no characteristic-write operation.

## Privacy

PacePrompt has no account, analytics, advertising, telemetry, cloud storage or background delivery. It makes no network API calls and requests no HealthKit permission. Capability and packet diagnostics stay in memory and are not persisted. Data leaves that memory-only view only after the user deliberately copies it or opens the system share sheet.

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

## User-run physical FR30z validation

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`, replace the placeholder with your Apple development-team identifier, and keep that ignored file local.
2. Open `PacePrompt.xcodeproj`, select your connected iPhone, build and run PacePrompt. Confirm the app offers no speed, incline, start, stop, pause or Control Point action.
3. Insert the FR30z fitness Bluetooth dongle, insert the safety key and turn on the treadmill. Keep the physical console and safety key authoritative throughout.
4. In PacePrompt, open **Settings → Treadmill**, press **Scan for FTMS treadmills**, select the FR30z and connect. Do not use another app to control the treadmill during this check.
5. Record the subscription state shown for `0x2ACD`, `0x2AD3` and `0x2ADA`. A subscribed state with no packet is distinct from an unsupported or failed subscription.
6. With the belt stationary, wait at least 30 seconds. Capture the raw and decoded values for `0x2ACC`, `0x2AD4` and `0x2AD5`, then use **Copy diagnostics** or **Share diagnostics** to capture the stationary packet log. Do not put the resulting device diagnostics in Git.
7. If and only if you choose to validate moving-belt telemetry, stand clear first, retain access to the safety key, and start and adjust the belt exclusively from the physical FR30z console. The app must remain untouched and read-only. Observe at least one console-initiated start, one speed change, one inclination change if safe, and one console-initiated stop.
8. After the belt is fully stationary, copy or share the final diagnostic report, press **Disconnect**, and turn off the treadmill.

Return:

- the discovered device name and identifier;
- the full discovered-characteristic list and properties;
- raw values for `0x2ACC`, `0x2AD4` and `0x2AD5`;
- the subscription state for `0x2ACD`, `0x2AD3` and `0x2ADA`;
- the stationary 30-second packet log, including an explicit report when no packet arrived;
- if the optional console-only moving check was performed, packets surrounding the physical start, speed change, inclination change and stop;
- any unknown opcode/status, unavailable value, malformed packet, permission error, subscription failure, connection error or disconnect message.

These captures are inputs to a separately authorised control slice. They are not permission to send a command.

## Simulator limitation

Simulator tests verify parsing, presentation and that the app builds. They cannot establish physical Bluetooth behaviour.

User-run iPhone/FR30z validation on 2 September 2026 confirmed discovery, connection, the expected characteristic list, the three capability reads and successful CoreBluetooth notification subscriptions to `0x2ACD`, `0x2AD3` and `0x2ADA`. During motion initiated from the physical console, `0x2ACD` emitted well-formed `0x058C` packets at roughly two per second; decoded speed, inclination and elapsed-time values tracked the observed console changes.

The user reported that, after a physical-console stop, no further packets arrived during the instructed 30-second observation. The treadmill did not send a terminal zero-speed `0x2ACD` packet, and no `0x2AD3` or `0x2ADA` packet was observed during the captured runs. This validates passive moving-belt `0x2ACD` telemetry and subscription enablement on the tested FR30z, but does not establish continuous stationary telemetry, Training Status delivery, Fitness Machine Status delivery, multi-notification behaviour or any Control Point behaviour. The last received value remains timestamped historical evidence, not proof of current treadmill state.

## Repository guidance

Product and design sources stay under `design/`. Project-wide safety and slice rules are in `AGENTS.md`; repository-local skills are maintained under `.agents/skills`. Per-commit Codex token measurements and API-equivalent estimates are recorded in `DEVELOPMENT_NOTES.md`.
