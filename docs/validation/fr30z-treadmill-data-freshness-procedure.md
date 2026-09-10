# FR30z Treadmill Data freshness characterisation procedure

Status: software preparation only. No physical issue #52 session has been authorised or performed.

This procedure supports [issue #52](https://github.com/syamaner/paceprompt-ios/issues/52). It measures passive `0x2ACD` delivery so a later review can propose a conservative telemetry-freshness window, stream-interruption rule, and target-observation deadline. It does not adopt any of those values.

## Non-write build boundary

Every physical session must use a signed **Release** build from the reviewed issue #52 candidate. The app contains passive FTMS discovery, reads, subscriptions, packet capture, and operator markers, but no build configuration contains the completed issue #51 Control Point trigger, CoreBluetooth writer, or callback wiring. Debug retains read-only access to the #76 protected journal as historical evidence only.

The app must not write `0x2AD9`. Request Control, targets, Start, Stop/Pause, Reset, workout execution, retry, and automatic reconnect remain excluded. All treadmill operation is performed by the operator at the physical console.

## Evidence recorded by the app

- wall-clock receipt time plus monotonic time since the capture began;
- the interval between every pair of received `0x2ACD` notifications, including malformed packets;
- raw bytes, parser classification, decoded values, and an explicit list of included fields;
- initial-read versus notification provenance;
- application active, inactive, and background transitions;
- connection, disconnection, and value-error markers;
- operator-entered observation markers, explicitly labelled as human input rather than protocol evidence;
- the elapsed monotonic silence since the last `0x2ACD` notification when the report is generated;
- terminal passive-subscription outcomes retained after disconnect; and
- up to 10,000 complete in-memory packet records, separate from the newest 100 shown on screen. Any overflow is reported as incomplete evidence.

Nothing is persisted or transmitted automatically. Raw captures contain device-identifying diagnostics and must remain outside Git.

## Preconditions for each later session

Fresh written operator authorisation is required before connecting or operating the treadmill. For each session, separately confirm that:

- the operator is present at the identified FR30z and can control it exclusively from the console;
- the deck is clear and the belt is physically stationary;
- the console and safety key are immediately accessible;
- no other person or app is controlling the treadmill; and
- the exact reviewed Release build and source revision are recorded.

Abort on unexpected motion, loss of console or safety-key access, another person approaching the deck, a connection/subscription error, contradictory observation, capture overflow, or uncertainty about physical state. Use only the physical console or safety key in response; the app sends no compensating command.

## Measurement sequence

Run the complete sequence in at least two separately authorised sessions. The operator chooses safe console values and may abort any step.

1. Start a new scan explicitly, connect to the identified FR30z, and confirm the three passive subscription outcomes.
2. With the belt physically stationary, record **Belt observed stationary**. Observe stationary delivery without inferring state from packet silence.
3. Start from the physical console and immediately record **Start pressed on console**.
4. Once the operator observes a steady safe speed, record **Steady speed observed** and retain a steady-state packet interval sample.
5. Change speed only from the console and record **Speed changed on console**. Continue until the operator observes another steady state.
6. If safe, change inclination only from the console and record **Inclination changed on console**. Continue until the operator observes another steady state.
7. During a steady console-controlled state, take the app through one deliberate active-to-inactive/background-to-active interruption. The lifecycle markers are automatic. Do not infer what happened while the app could not receive callbacks.
8. Stop only from the physical console and immediately record **Stop pressed on console**.
9. When the operator directly confirms the belt is fully stationary, record **Belt observed fully stationary**. Continue passive observation for at least 30 seconds to measure final-packet and silence behaviour; this observation period is not a freshness policy.
10. Explicitly disconnect. Copy or share **Issue #52 capture** only after the disconnect is reported.

## Later analysis boundary

Compare the separate raw reports using monotonic intervals and lifecycle markers. Publish only sanitised aggregate timing distributions, field-presence counts, malformed/unavailable counts, gap observations, final-packet behaviour, and stated uncertainties.

Any proposed freshness window, stream-interruption rule, or target-observation deadline remains a review candidate. Packet silence, the last sample, Training Status, and an operator marker must never be converted into a protocol claim that the treadmill is stopped or currently at a target.
