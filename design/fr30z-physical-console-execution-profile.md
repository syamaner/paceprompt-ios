# FR30z physical-console execution profile

Status: documentation-only MVP profile candidate for GitHub issue [#57](https://github.com/syamaner/paceprompt-ios/issues/57), prepared from the sanitised [11 September 2026 characterisation](../docs/validation/fr30z-console-target-characterisation-2026-09-11.md). On acceptance it becomes the immutable policy for later software slices; it does not itself authorise an executable Control Point write or physical treadmill session.

## Protocol authority

The protocol references were rechecked in the current Bluetooth SIG catalogue on 11 September 2026:

- [Fitness Machine Service 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/), Adopted;
- [Fitness Machine Profile 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-profile-1-0-1/), Adopted.

The normative FTMS procedure timeout remains 30 seconds from ATT acceptance, as defined in the accepted [Control Point handshake](fr30z-ftms-control-point-handshake.md). Product observation and telemetry windows below are separate policy values.

## Product ownership

The physical treadmill console owns belt motion:

- physical Start begins or resumes the belt;
- physical Stop pauses/stops the belt;
- the safety key remains authoritative;
- PacePrompt never exposes or sends FTMS Start, Stop or Pause in production.

PacePrompt owns the workout and targets:

- **Begin workout** creates the foreground app attempt, obtains control and waits for physical Start;
- validated plan segments supply speed and inclination targets;
- the user may override either target for the current segment;
- physical Stop freezes the workout after the telemetry policy detects uncertainty/zero;
- physical Start after an accepted pause permits PacePrompt to restore the paused segment's effective targets;
- **End workout** ends and saves the app attempt after an accepted stationary condition and sends no treadmill Stop.

## UI contract and design adaptation

The checked-in [HTML product specification](treadmill-controller-product-spec.html) and [visual design deck](TreadmillDesign.pdf) define the design system and product language for the later production screen. Layouts and states may change where the characterised workflow requires it, but they must remain recognisably part of that system. Preserve:

- the dark, high-contrast visual language, typography, spacing, card hierarchy and established status colours;
- segment label, remaining time, progress and next-segment preview stay prominent;
- requested/effective values remain visibly distinct from actual reported speed and inclination;
- acknowledgement/observation state and telemetry age remain glanceable;
- speed and inclination manual adjustments remain large, direct controls;
- portrait and landscape keep the same core information without turning Exercise into a tab or a diagnostic report;
- the complete plan remains available behind the established upward-swipe treatment.

The physical evidence supersedes only the command semantics depicted in those earlier concepts:

- the design's preflight **Start workout** label becomes **Begin workout**, which starts the app attempt and never starts the belt;
- while waiting, the Exercise screen replaces motion controls with **Press Start on the treadmill**;
- remove the iPhone and Apple Watch **Pause**, **Resume**, **Stop belt** and FTMS Start controls rather than leaving disabled or misleading versions;
- during checking or an accepted pause, use the same control region for clear physical-console status/instructions and the pending resume targets;
- show **End workout** only after accepted stationary evidence; it ends the app workout and never controls the belt.

These changes adapt the accepted design language to the characterised FR30z. Necessary layout, navigation and state-presentation changes are permitted when they serve the product flow, but they must reuse the design system rather than introduce a competing colour, typography, spacing, component or diagnostic language.

## Exact profile match

The production profile may arm only when every current-connection condition below is true:

1. The user selected the locally retained CoreBluetooth peripheral identity previously associated with the operator-confirmed FR30z. That identifier remains local and is never committed or exported.
2. Fitness Machine Service `0x1826` is present.
3. The required characteristic inventory and properties match:
   - `0x2ACC` Read;
   - `0x2ACD` Notify;
   - `0x2AD3` Read/Notify when advertised;
   - `0x2AD4` Read;
   - `0x2AD5` Read;
   - `0x2AD9` Write/Indicate;
   - `0x2ADA` Notify when advertised.
4. Current capability bytes match exactly:
   - `0x2ACC`: `0C 16 00 00 03 00 00 00`;
   - `0x2AD4`: `32 00 D0 07 0A 00` (0.50–20.00 km/h, 0.10 km/h increment);
   - `0x2AD5`: `00 00 96 00 0A 00` (0.0–15.0%, 1.0% increment).
5. The `0x2ACD` subscription and `0x2AD9` indication subscription are confirmed for this connection. Outcomes for `0x2AD3` and `0x2ADA` are recorded but their notifications are not required for progress.
6. The app is foreground-active, one connection epoch is current, and no failure or delivery uncertainty has invalidated it.

Any identity, characteristic, property, byte, range, increment, subscription, epoch or foreground mismatch blocks arming. The profile does not claim support for another FR30z, dongle or firmware revision.

## Allowed Control Point procedures

Production permits only the following procedures, using the issue #50 codec and one-procedure transport:

| Purpose | Opcode and parameters | Required FTMS success |
| --- | --- | --- |
| Request Control | `00` | `80 00 01` |
| Set Target Speed | `02 LL HH`, unsigned little-endian hundredths of km/h | `80 02 01` |
| Set Target Inclination | `03 LL HH`, signed little-endian tenths of one percent | `80 03 01` |

Production prohibits:

- Start or Resume `07`;
- Stop or Pause `08` with any parameter;
- Reset and every other Control Point opcode;
- more than one procedure in flight;
- automatic retry, reconnect, control reacquisition or guessed compensating commands.

Historical codec tests or sanitised diagnostic evidence may retain prohibited opcode representations, but no production adapter, reducer effect or enabled UI action may reach them.

## Session targets and ceilings

Before Begin workout, the user selects a session speed ceiling, inclination ceiling and maximum interval speed change. The app provides no advertised-range default.

- Speed targets must be 0.50–20.00 km/h, align exactly to 0.10 km/h and not exceed the selected session ceiling.
- Inclination targets must be 0.0–15.0%, align exactly to 1.0% and not exceed the selected session ceiling.
- The maximum interval speed change must be positive, align exactly to 0.10 km/h and be no greater than 19.50 km/h. It applies to the absolute speed difference between adjacent planned segments; there is no preselected value.
- The complete validated plan must fit both current capability ranges, both selected ceilings and the selected maximum interval speed change before arming.
- Manual adjustment uses the same increments and ceilings.
- Do not clamp, round or silently replace a value. An invalid value is rejected before any effect.

The interval-change limit validates planned segment boundaries. It does not reinterpret the console's physical start speed, pause/resume restoration or individual 0.10 km/h manual adjustments as new plan intervals.

The low-value physical characterisation covered speed 0.50–0.70 km/h and inclination 0.0–1.0%. Higher values are permitted only as explicit user-selected plan/session values inside the decoded machine range; the profile does not claim they were physically characterised.

## Telemetry policy

Only a well-formed current-epoch `0x2ACD` notification that includes instantaneous speed and inclination is execution telemetry. `0x2AD3`, `0x2ADA`, packet silence and cached values cannot establish current motion, stationary state, control or target achievement.

### Freshness and checking

- A sample is fresh for **2.0 seconds** from its monotonic receipt time.
- When a required sample becomes older than 2.0 seconds, freeze active workout and segment timing at `sample.receivedAt + 2.0 seconds`, suppress plan transitions and enter **Checking treadmill**.
- Checking may continue until **10.0 seconds** after the last well-formed required sample. This allows the observed 8.010-second console-stop gap without pretending the gap itself is stationary evidence.
- A fresh zero-speed sample received during checking establishes the telemetry-based pause condition.
- A fresh non-zero sample received during checking, before the 10.0-second boundary and with no other adverse evidence, returns to the preceding target-observation or running state. The uncertain gap is excluded from active duration.
- If no required sample arrives by 10.0 seconds, the workout becomes interrupted/physically uncertain. Invalidate control assumptions, emit no further procedure and direct the operator to the console/safety key. Later packets remain evidence but cannot restart that attempt automatically.

These windows are conservative product policy derived from normal observed delivery near 0.5 seconds and one 8.010-second post-stop gap. They are not Bluetooth guarantees.

### Physical Start and Resume

After Request Control success, PacePrompt displays **Press Start on the treadmill** and emits no target while the accepted current speed is zero.

One fresh, well-formed current-epoch sample reporting speed above zero while waiting establishes that the FR30z reported movement at that instant. It permits the initial or restore target sequence; it does not prove continuing motion between samples.

If the operator stops and restarts before a zero-speed sample or operator stationary confirmation establishes pause, PacePrompt cannot distinguish that cycle. It treats a returning non-zero stream as continuing the current segment and performs no resume restoration. The UI therefore instructs the operator to wait for **Paused** before pressing physical Start again.

### Physical Stop and pause

A fresh zero-speed sample after earlier accepted non-zero movement establishes **Paused — treadmill reports 0.00 km/h**. It does not prove emergency-stop safety or protocol Stop success. The operator and safety key remain authoritative.

If zero never arrives, the UI may accept a deliberate operator confirmation that the treadmill is physically stationary. That human observation is stored separately from telemetry and can establish paused/ending eligibility. It cannot invent a zero packet or protocol outcome.

## Target sequencing

Every sequence is deterministic and contains only procedures that change or reassert the effective target. One procedure must complete before the next starts.

1. Set Target Speed.
2. Require ATT acceptance and matching FTMS success.
3. Set Target Inclination.
4. Require ATT acceptance and matching FTMS success.
5. Wait for one later fresh `0x2ACD` sample, received after both acknowledgements, that reports the exact effective speed and inclination.

If only one axis changes during a running segment or manual override, send only that axis. Confirmation still requires a later sample reporting both effective values exactly. If neither axis changes, emit no target procedure and require current fresh exact telemetry before progressing.

The speed-then-inclination order is the only combined order accepted by the 11 September evidence. It applies to the first segment, planned transitions, manual changes that alter both axes and resume restoration.

### Observation deadline

The target-observation deadline is **30.0 seconds after the final required FTMS target acknowledgement**. The low-delta observations arrived within approximately 0.84 seconds, but larger user-selected changes were not characterised. The 30-second value is a fail-closed upper waiting limit, not a claim about expected ramp performance.

Before the deadline, different values may represent ramping and remain observable without confirming the target. At the deadline, lack of one exact joint sample means **target not confirmed**: freeze the attempt, emit no retry or compensating target and direct the operator to physical controls. It never means stopped.

## Planned targets and manual overrides

For each segment:

`effective target = current-segment manual override ?? planned segment target`

- Speed and inclination overrides are independent.
- A manual adjustment changes the effective target immediately and uses the target sequence above.
- **Return to plan** removes current-segment overrides and reapplies changed planned targets.
- Overrides survive physical pause/resume.
- Overrides clear when the next plan segment begins; that segment's planned targets become effective.
- A change entered while waiting for physical Start, checking telemetry or paused updates only the pending effective target and emits no Control Point procedure.
- A change entered while a target procedure is in flight updates the pending effective target without cancelling or competing with that procedure. After the current procedure settles successfully, recompute the remaining sequence from the latest effective values.
- The UI always shows planned, effective/requested and actual reported values separately.

## Resume restoration

The paused screen shows the exact pending effective speed and inclination. After the operator presses physical Start and a fresh non-zero sample is accepted:

1. preserve the same segment and remaining active duration;
2. set effective speed, even if the console began at 0.50 km/h;
3. after its matching FTMS success, set effective inclination;
4. after its matching success, wait for a later fresh joint exact report;
5. resume segment timing only from that joint report.

If control is no longer held, another procedure is in flight, the connection/identity/capabilities changed, or any procedure/evidence fails, do not restore or reacquire automatically. The attempt becomes interrupted and the console/safety key owns recovery.

## Completion and End workout

When the final segment duration completes, PacePrompt stops plan progression and displays **Workout complete — press Stop on the treadmill**. It sends no Stop procedure.

After fresh zero-speed telemetry or a separate operator stationary confirmation, PacePrompt presents **End workout**. This action finalises the local app attempt and may lead to the later deliberate Health save flow. It never controls the belt.

End workout is also available from an ordinary accepted pause. Ending while telemetry is moving, stale or physically uncertain is blocked; the app directs the operator to the physical console and retains the uncertainty.

## Failure and interruption rules

Any ATT error, negative/unknown/malformed/mismatched/duplicate/late FTMS response, procedure timeout, target-observation timeout, explicit control loss, capability/profile mismatch, app deactivation, disconnect or contradictory human/telemetry evidence:

- freezes timers and plan progression;
- invalidates control assumptions;
- emits no retry, reconnect, target continuation or compensating procedure;
- preserves intent, submission, ATT, FTMS, telemetry and human evidence separately;
- instructs the operator to use the physical console and safety key;
- requires a new user-created attempt and connection epoch for any later workout.

An ordinary in-foreground console Stop/Start cycle is not a failure when the same connection remains current, checking resolves within the telemetry policy and no adverse evidence appears.

## Evidence claims

The implementation must never collapse these levels:

1. current decoded capability/profile match;
2. reducer intent;
3. CoreBluetooth submission;
4. ATT acceptance;
5. correlated FTMS acknowledgement;
6. later `0x2ACD` observation;
7. operator observation.

Simulator and fake-transport tests prove software behaviour only. The separately authorised issue #62 session is required before the complete production path can be accepted against the physical FR30z.
