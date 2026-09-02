Build the first bounded slice of a new local-first iPhone app called PacePrompt.

Product vision

The eventual product will:

- Connect to a Reebok FR30z Floatride treadmill over Bluetooth FTMS.
- Import interval workouts from free text using OpenRouter structured outputs.
- Convert the result into a strict local workout-plan schema.
- Display and save plans only after deterministic validation and user confirmation.
- Execute interval plans by controlling treadmill speed and inclination.
- Provide large manual speed, inclination, pause and stop controls in portrait and landscape.
- Maintain detailed local workout history.
- Use an Apple Watch companion for real-time heart rate.
- Save one meaningful indoor walking or running workout to Apple Health.

This is a separate app. Do not modify or depend on the existing WeeklyHealthReport project.

Current authorised slice

Deliver only the greenfield iOS app shell and a safe, non-motion Bluetooth FTMS capability explorer.

Do not implement treadmill control, OpenRouter, HealthKit writing, the Watch app, workout execution or persistent workout history in this slice.

Confirmed device evidence

A generic BLE explorer can see the following standard Bluetooth Fitness Machine Service characteristics on the physical FR30z:

- 0x2ACC: Fitness Machine Feature, Read
- 0x2AD4: Supported Speed Range, Read
- 0x2AD5: Supported Inclination Range, Read
- 0x2AD6: Supported Resistance Level Range, Read
- 0x2AD7: Supported Heart Rate Range, Read
- 0x2AD8: Supported Power Range, Read
- 0x2ACD: Treadmill Data, Notify
- 0x2AD3: Training Status, Notify and Read
- 0x2AD9: Fitness Machine Control Point, Indicate and Write
- 0x2ADA: Fitness Machine Status

The expected parent service is FTMS 0x1826. Verify UUID assignments and binary layouts against the current Bluetooth SIG Fitness Machine Service specification before implementing parsers.

Deliverables

1. Create a native SwiftUI iPhone application named PacePrompt with a test target.

2. Use a provisional iOS 17 minimum deployment target if supported by the installed Xcode SDK. Report the actual Xcode and SDK versions used.

3. Create the eventual navigation shell:

   - Home
   - Plans
   - History
   - Settings

   Plans and History may contain restrained placeholder states. Do not build speculative feature implementations.

4. Home should show:

   - Bluetooth availability
   - Treadmill connection state
   - A route to treadmill setup
   - Clear unavailable, scanning, connecting, connected and failed states

5. Settings should contain a functional Treadmill section that:

   - Starts scanning only in response to an explicit user action
   - Filters or prioritises FTMS service 0x1826
   - Shows discovered device names and identifiers
   - Lets the user explicitly select and connect to the FR30z
   - Discovers services and characteristics
   - Reads 0x2ACC, 0x2AD4 and 0x2AD5
   - Subscribes to safe notifications from 0x2ACD, 0x2AD3 and 0x2ADA where available
   - Shows raw hexadecimal values alongside decoded values
   - Shows the declared speed and inclination ranges and increments
   - Shows whether speed and inclination target-setting feature bits are enabled
   - Handles Bluetooth-off, permission, disconnect and malformed-packet states explicitly

6. Keep the Bluetooth layer separate from SwiftUI:

   - A CoreBluetooth client owns scanning, connection and subscriptions.
   - Pure parser types decode FTMS payloads.
   - Observable presentation state adapts the client for the UI.
   - Views do not parse bytes or issue CoreBluetooth operations directly.

7. Add focused tests using synthetic byte fixtures for:

   - Fitness Machine Feature parsing
   - Supported Speed Range parsing
   - Supported Inclination Range parsing
   - Little-endian signed and unsigned values
   - Short, malformed and unsupported payloads
   - Presentation of unavailable values

8. Add a concise README covering:

   - Product purpose
   - Current slice and exclusions
   - Privacy model
   - How to build and test
   - How to perform the physical-device capability check
   - Which raw values should be captured for the next control slice
   - The simulator limitation for Bluetooth validation

9. Add a concise repository-level AGENTS.md that records the safety, privacy, validation and slice-boundary rules for future work.

Safety contract

- Do not write anything to FTMS Control Point 0x2AD9.
- Do not send Request Control, Start, Stop, Pause, target-speed or target-inclination commands.
- Do not cause treadmill motion.
- Notification subscriptions and characteristic reads are permitted.
- Treat the physical console and safety key as authoritative.
- Do not add automatic reconnection that could later resume a programme.
- Do not infer capability solely from characteristic presence; decode 0x2ACC and retain explicit unknown states.
- Never report a command or state transition as successful without machine acknowledgement and observed state. This becomes relevant in later slices.

Privacy and dependency boundaries

- No accounts, analytics, advertising, telemetry, cloud storage or background delivery.
- No OpenRouter or other network API calls.
- No API-key field yet.
- Do not request HealthKit permissions.
- Do not add a watchOS target yet.
- Do not store personal workout or health values.
- Keep signing team identifiers and personal configuration out of Git.
- Prefer Apple frameworks and avoid third-party dependencies unless strictly necessary and justified.
- Do not create a remote repository, commit, push or publish anything.

Validation

- Inspect the repository state before editing.
- Keep the implementation CLI-buildable.
- Run the narrow parser tests while iterating.
- Run the complete simulator test suite once the implementation stabilises.
- Run an iOS simulator build.
- Run Xcode static analysis if it works reliably in the installed environment.
- Review git diff --check, the final diff and repository status.
- Do not claim simulator success proves physical Bluetooth behaviour.
- Do not claim the FR30z’s capabilities are confirmed until values have been read on the actual treadmill.

Physical-device handoff

Provide a short, exact checklist for me to:

1. Build and install on my iPhone.
2. Turn on the FR30z and insert its fitness Bluetooth dongle.
3. Scan and connect.
4. Capture raw values for 0x2ACC, 0x2AD4 and 0x2AD5.
5. Observe 0x2ACD and 0x2ADA notifications without starting the belt through the app.
6. Return the diagnostics needed to design the separately authorised control slice.

Final report

Report:

- What was created
- The important architectural decisions
- Files changed
- Tests and build commands with results
- Static-analysis result
- Repository status
- The exact remaining physical-device validation
- Any assumptions or unresolved FTMS behaviour

Stop after this slice. Do not proceed into motion control, plan execution, OpenRouter, Watch or HealthKit implementation.
