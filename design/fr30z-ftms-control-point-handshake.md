# Safe FR30z FTMS Control Point handshake

Status: protocol specification established by GitHub issue [#2](https://github.com/syamaner/paceprompt-ios/issues/2) and narrowed for callback-order handling by issue [#72](https://github.com/syamaner/paceprompt-ios/issues/72). It does not authorise a write to Fitness Machine Control Point `0x2AD9`, physical treadmill operation, or workout execution.

## Scope and safety boundary

This document specifies the smallest evidence model needed before a later, separately authorised FR30z control proof. It covers only:

- Request Control;
- Set Target Speed and Set Target Inclination because the FR30z advertised the corresponding target-setting feature bits;
- the Control Point response shared by those procedures;
- passive Treadmill Data, Training Status and Fitness Machine Status evidence relevant to control and loss of control.

It deliberately does not specify an executable workout state machine. Reset, Start or Resume, Stop or Pause, every other target procedure, automatic reconnection, automatic programme resumption, and workout execution are outside this slice. A future slice must not infer permission for any of them from this document.

The physical console and safety key remain authoritative at all times. An app command is never a safety stop. If app evidence is missing, late, malformed, contradictory or unknown, the app must fail closed, make no success claim and direct the human operator to the console and safety key.

## Protocol authority

This specification was checked on 3 September 2026 and rechecked for issue #72 on 10 September 2026 against these current, adopted Bluetooth SIG primary sources:

- [Fitness Machine Service 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/), revision date 1 October 2024: Sections 1.7, 4.1, 4.4, 4.11-4.12 and 4.16-4.18, especially Tables 4.14, 4.15, 4.23, 4.24, 4.25 and 4.26;
- [Fitness Machine Profile 1.0.1](https://www.bluetooth.com/specifications/specs/fitness-machine-profile-1-0-1/), especially Sections 4.4.14, 4.7 and 6.1 for configuring Control Point indications, the 30-second procedure timeout, error handling and Control Point security;
- the Bluetooth SIG [Fitness Machine Service test suite, publication 6](https://files.bluetooth.com/wp-content/uploads/dlm_uploads/2024/10/FTMS.TS_.p6.pdf) and [Fitness Machine Profile test suite, publication 7](https://files.bluetooth.com/wp-content/uploads/dlm_uploads/2024/10/FTMP.TS_.p7.pdf), used to cross-check request/response bytes and Collector failure behaviour;
- Bluetooth SIG [Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html) for service and characteristic UUIDs.

Issue #72 also rechecked Apple's current CoreBluetooth documentation for [`writeValue(_:for:type:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue%28_%3Afor%3Atype%3A%29), [`peripheral(_:didWriteValueFor:error:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/1518823-peripheral), [`setNotifyValue(_:for:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue%28_%3Afor%3A%29) and [`peripheral(_:didUpdateValueFor:error:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral%28_%3Adidupdatevaluefor%3Aerror%3A%29-1xyna). Apple documents the write result and subscribed value-update callbacks independently and does not specify a relative ordering between them. A peripheral chooses when to send subscribed updates. The client therefore cannot treat callback arrival order alone as protocol evidence ordering.

The product concept in [`treadmill-controller-product-spec.html`](treadmill-controller-product-spec.html) and [`TreadmillDesign.pdf`](TreadmillDesign.pdf) is eventual-product context only. Its controls and workout screens are not protocol authority or implementation permission.

## Evidence is a ladder, not one boolean

The future control layer must preserve these as distinct facts:

| Evidence level | What it establishes | What it does not establish |
| --- | --- | --- |
| Characteristic discovery | `0x2AD9` exists and exposes the discovered properties. Issue #1 found Write and Indicate. | That indications can be enabled, any opcode is accepted, or the treadmill will act. |
| Advertised capability | The second `UINT32` in `0x2ACC` has Speed Target Setting bit 0 and Inclination Target Setting bit 1 set. Issue #1 found both set. | That Request Control or either target procedure succeeds on this FR30z. |
| Validated range | `0x2AD4` or `0x2AD5` supplies a decodable range and minimum increment. | That a value within the range will be accepted or is safe to apply. |
| Command transmission | A GATT Write request with response was issued with the intended bytes. | That the ATT write or FTMS procedure succeeded. |
| ATT Write response | The Server accepted the write at the Attribute Protocol layer; the FTMS procedure has started. | That the FTMS procedure completed or the requested state changed. |
| Control Point indication | One well-formed response correlates to the one in-flight opcode. A `Success` result completes that FTMS procedure. | For a target procedure, that the belt or incline reached the requested value. |
| Reported treadmill state | A later well-formed `0x2ACD` packet explicitly includes and reports the relevant value. | Independent mechanical calibration, continuing state after that packet, or a stop when packets are silent. |
| Training Status snapshot | A well-formed `0x2AD3` read or notification reports the defined training-status value at receipt, with its source retained. | Belt motion, a physical stop, notification delivery, control permission or a Control Point result. |
| Human observation | The operator observes the console and machine and retains the safety key. | A substitute for protocol acknowledgement or permission for automation. |

No lower row may be inferred from a higher row or vice versa. In particular, the future UI must not collapse “sent”, “write accepted”, “protocol acknowledged” and “reported target observed” into “confirmed”.

## Relevant binary procedures

All multi-octet FTMS fields are least-significant octet first. As a PacePrompt safety policy, a future encoder must reject out-of-range, non-finite, overflowing or non-increment-aligned values; it must not silently clamp or round them.

| Procedure | Request value written to `0x2AD9` | Eligibility and meaning | Successful response indication |
| --- | --- | --- | --- |
| Request Control | `00` | Mandatory Control Point procedure. No parameter. A success grants this Client permission for supported procedures on the current connection only. | `80 00 01` |
| Set Target Speed | `02 LL HH` | Requires granted control and Speed Target Setting bit 0. `HHLL` is `UINT16`, resolution `0.01 km/h`, and must satisfy the decoded `0x2AD4` range and increment. | `80 02 01` |
| Set Target Inclination | `03 LL HH` | Requires granted control and Inclination Target Setting bit 1. `HHLL` is two's-complement `SINT16`, resolution `0.1%`, and must satisfy the decoded `0x2AD5` range and increment. | `80 03 01` |

The response indication for these procedures is exactly three octets:

```text
octet 0: 0x80 Response Code opcode
octet 1: request opcode being answered
octet 2: result code
```

These three procedures have no response parameter. Extra or missing octets are malformed for this scope.

### Result codes

| Result | Meaning | Required fail-closed handling |
| --- | --- | --- |
| `0x01` | Success | Complete only the correlated FTMS procedure. For a target, enter “acknowledged, observation pending”; do not claim the target was reached. |
| `0x02` | Op Code Not Supported | Fail the procedure, record the feature/procedure contradiction where applicable, invalidate control readiness and send nothing automatically. |
| `0x03` | Invalid Parameter | Fail the procedure, record the exact bytes and validated range/increment inputs, invalidate control readiness and send nothing automatically. |
| `0x04` | Operation Failed | Fail with the machine state unknown, invalidate control readiness and send nothing automatically. |
| `0x05` | Control Not Permitted | Fail and mark control not held. No target command may follow. |
| `0x00`, `0x06`-`0xFF` | Reserved for Future Use in Service 1.0.1 | Preserve the raw response as unknown, fail the procedure and invalidate control readiness. |

An indication whose response opcode is not `0x80`, whose request opcode does not match the single in-flight procedure, or whose layout is malformed must not complete that procedure. Preserve the raw bytes, report a protocol anomaly, invalidate control readiness and make no further write on that connection.

## Indications, correlation and timeouts

1. Discover `0x2AD9` with both Write and Indicate properties. Property presence is only a prerequisite.
2. Configure the `0x2AD9` Client Characteristic Configuration descriptor for indications and wait for CoreBluetooth to report that the subscription is active. A notification subscription is not equivalent. No Control Point write is allowed before this succeeds.
3. Permit exactly one Control Point procedure in flight. Correlate its locally generated procedure identifier, connection/bearer identifier, request opcode, exact request bytes and monotonic timestamps for write submission, ATT write result and indication receipt.
4. Use a GATT Write request with response. An explicit ATT Error response means the FTMS procedure did not start or queue. A local CoreBluetooth or transport error without a confirmed ATT Error response leaves delivery unknown and must fail closed. A successful ATT Write response starts the procedure but is not FTMS success. If one matching, well-formed response indication reaches the app after submission but before the ATT callback, retain it only as provisional response evidence for that same connection epoch and procedure identifier. It grants no success or control permission by itself.
5. After a successful ATT Write response, anchor the Profile-mandated 30-second ATT transaction deadline to that acceptance. If a provisional matching response already exists for the same in-flight procedure, the ATT acceptance supplies the missing evidence and the procedure may complete without waiting again. Otherwise, end the procedure only when the one matching, well-formed `0x80` indication arrives before the deadline. If none arrives within 30 seconds, or if the link is lost while the procedure is in progress, the procedure has timed out and failed. Do not substitute a shorter product timeout or extend this normative deadline.
6. After a Control Point procedure timeout, treat the procedure and machine state as unknown. Start no new Fitness Machine Control Point procedure until a new link is established. An explicit user action may disconnect; any later connection is a fresh session and must repeat discovery, reads and subscriptions. Never reconnect or retry automatically.
7. A disconnect at any stage ends control permission and invalidates every pending or remembered command outcome. Requested targets become historical intent only. On a later user-initiated connection, read and observe the machine afresh before considering any new request.

CoreBluetooth handles the ATT confirmation sent in response to an indication. Receipt by the app still has to be parsed and correlated as above; it must not be treated as a generic “latest command succeeded” event.

The 30-second deadline applies to receiving the Control Point response indication, not to reaching a target. There is no Bluetooth-defined deadline in the reviewed FTMS material for a treadmill to reach an acknowledged speed or inclination target. No post-acknowledgement observation timeout or tolerance is authorised here. Those are unresolved safety inputs for any later target proof. Until they are separately justified, expiry of any product-level waiting period can only mean “target not confirmed”, never “target failed safely” or “treadmill stopped”.

## Conceptual protocol transitions

This is a documentation model, not executable workout logic. Every transition is caused by an explicit user action or received evidence; none triggers a retry, reconnect, resume or follow-on command.

| From | Evidence/event | To | Claim allowed |
| --- | --- | --- | --- |
| Disconnected | User connects; required characteristics, features and ranges are read and passive subscriptions are resolved | Passive ready | Capability evidence only |
| Passive ready | `0x2AD9` indication subscription succeeds | Ready to request control | Ready for a separately authorised single write |
| Ready to request control | User explicitly initiates the authorised `00` Write request | Write pending | Request submitted |
| Write pending | Exactly `80 00 01` arrives on the same connection before the ATT callback | Write pending with provisional response | Response bytes and receipt time only; no ATT acceptance, protocol success or control permission claim |
| Write pending with provisional response | ATT Write response succeeds for the same in-flight procedure | Control granted | Both ATT acceptance and the correlated protocol response are now established; no motion or target claim |
| Write pending with provisional response | ATT rejection, delivery uncertainty, disconnect, duplicate or any contradictory evidence | Failed/unknown | No control permission or success claim; no automatic retry or follow-on write |
| Write pending | ATT Write response succeeds | Awaiting indication | Procedure started |
| Awaiting indication | Exactly `80 00 01` arrives on the same connection | Control granted | Protocol permission held on this connection; no motion or target claim |
| Control granted | User explicitly initiates one separately authorised, prevalidated target write | Target write pending | Target request submitted |
| Target write pending | ATT Write response then matching `80 02 01` or `80 03 01` arrives | Target acknowledged, observation pending | Target procedure succeeded at FTMS protocol level |
| Target acknowledged, observation pending | A later well-formed `0x2ACD` packet explicitly reports the requested field at the exact encoded target value | Target observed at one instant | FR30z reported that value in that packet only |
| Any connected state | Disconnect, ATT or transport error, procedure timeout, negative/unknown/malformed response, correlation failure, explicit `0x2ADA FF`, or contradictory observation | Failed/unknown | No success or stop claim; no further writes |

A reported value that does not equal the exact encoded target remains an observation, not confirmation. Reaching a nearby value must not be accepted using an invented tolerance. A subsequent packet, the console or the physical machine may change independently, so “observed” is not a durable guarantee.

## Control loss and machine-status evidence

Under FTMS 1.0.1, control permission remains valid until the connection ends, the Client initiates Reset, or Fitness Machine Status reports Control Permission Lost. Reset is outside this scope.

`0x2ADA FF` with no parameter is explicit control-loss evidence and must immediately invalidate control. Missing `0x2ADA` notifications are not evidence that control is retained. No `0x2ADA` notification was observed in the passive physical capture, so the future client must not depend on receiving either control loss or target-change status from this FR30z.

Fitness Machine Status target-change values are `05 LL HH` for speed (`UINT16`, `0.01 km/h`) and `06 LL HH` for inclination (`SINT16`, `0.1%`). FTMS specifies that a Client-originated status update is notified to other connected Clients, if any; it is therefore not a required acknowledgement to the originating Client. `0x2ADA` cannot replace the matching `0x2AD9` indication or the later `0x2ACD` reported-state check.

Console input and safety-key removal override app intent. If either changes the machine, all outstanding assumptions must be discarded. The absence of a status notification must not suppress that human authority.

## What passive FR30z evidence established

The completed passive slice is recorded in [issue #1](https://github.com/syamaner/paceprompt-ios/issues/1), with the initial Training Status read added on `main` in commit [`e41bbae`](https://github.com/syamaner/paceprompt-ios/commit/e41bbaea39aa3145e00cf3bced9e8bbd635fa6e8):

- all three passive subscriptions to `0x2ACD`, `0x2AD3` and `0x2ADA` enabled successfully;
- while motion was initiated and controlled exclusively from the physical console, `0x2ACD` emitted well-formed packets with flags `0x058C` at roughly two per second;
- decoded reported speed, inclination and elapsed time tracked the observed console changes;
- after the physical-console stop, no further packet arrived during the reported 30-second observation;
- no terminal zero-speed `0x2ACD` packet was sent;
- an initial read of `0x2AD3` returned `00 00`; and
- no `0x2AD3` notification or `0x2ADA` notification was observed during the captured runs.

For `0x2AD3`, `00 00` decodes as flags `0x00` followed by Training Status `0x00` (`Other`), with no status string present. It proves that the characteristic returned that read snapshot at that moment. It does not establish that the treadmill was moving or stopped, that Training Status notifications will arrive, or that any control procedure is supported or completed. The source of a future `0x2AD3` value must therefore remain explicit: an initial read is not notification evidence.

In an `0x058C` packet, instantaneous speed is present because the More Data bit is clear; the flags also include total distance, inclination/ramp angle, energy, heart rate and elapsed time. For this protocol, only fields actually present and successfully decoded in an individual packet count as reported-state evidence.

A well-formed `0x2ACD` packet can establish that the FR30z reported a particular instantaneous speed, inclination and elapsed time at receipt, and issue #1 shows those values tracked console changes in the captured runs. It cannot establish:

- control permission, command transmission, acknowledgement or target acceptance;
- physical calibration or the machine state between or after packets;
- that a requested value has been reached when the field is absent or packets are silent;
- that the treadmill stopped, remains stopped or is safe merely because packets ceased;
- a safety-key event, stop reason or loss of control;
- that future firmware or sessions will emit the same fields or cadence.

Consequently, target confirmation may use a positive, well-formed `0x2ACD` observation but must never require a terminal zero-speed packet or infer anything from silence. Stopping must be confirmed by the human operator at the physical machine unless a later, separately evidenced signal is authorised.

## Smallest separately authorised physical proof

The next proof should test Request Control only. It must not test target speed, target inclination, Start or Resume, Stop or Pause, Reset, workout execution, or any automatic behaviour. A successful result would prove only that the tested FR30z/firmware accepted one Request Control procedure on one connection.

### Prerequisites

- Fresh written authorisation explicitly permitting one physical `0x2AD9` Request Control write and use of the FR30z. Issue #2 and this document do not provide it.
- A separately reviewed diagnostic build whose Control Point encoder is hard-allow-listed to the single byte `00`; target, start, stop, pause and reset opcodes are absent or unreachable. No automatic retry or reconnection.
- A connection satisfying the Profile's Control Point requirement of LE Security Mode 1, Security Level 2 or higher. Honour any OS-mediated security or pairing failure; do not bypass it or assume that characteristic discovery proves the requirement is met.
- Raw, timestamped capture of discovery, `0x2ACC`, `0x2AD4`, `0x2AD5`, all subscription outcomes, the exact write, its CoreBluetooth completion, every `0x2AD9` indication, concurrent passive packets and disconnect.
- The treadmill deck is clear. The human operator is at the console, can observe the belt and incline directly, and has immediate authority over the physical stop and safety key.
- The operator has confirmed physically that the belt is stationary before the write. Packet silence is not acceptable proof of this prerequisite.

### Procedure and evidence

1. Connect only after an explicit user action. Record the FR30z identity/firmware information available without storing personal identifiers in Git.
2. Record `0x2AD9` discovery with Write and Indicate and the raw feature/range reads. Treat these as prerequisites, not results.
3. Enable passive `0x2ACD`, `0x2AD3` and `0x2ADA` notifications, then enable `0x2AD9` indications. Record each CoreBluetooth subscription result. Abort if the Control Point indication subscription is not confirmed.
4. Reconfirm visually and at the console that the belt is stationary and no other person or app is controlling the treadmill.
5. On one explicit user action, submit exactly one with-response write containing `00`. Record the request bytes and write-completion result. Send nothing else.
6. If the write succeeds, start the 30-second timer and wait for the single correlated Control Point indication. Record its raw bytes and classification. Accept only exactly `80 00 01` as protocol success. Any defined negative result, reserved result, wrong opcode, malformed layout, duplicate, disconnect or expiry before the indication is a failed/unknown proof.
7. The operator confirms that the belt and incline did not move unexpectedly. Record any concurrent `0x2ACD`, `0x2AD3` or `0x2ADA` packet, retaining read-versus-notification provenance, but do not infer stationary state or retained control from silence.
8. End the proof with one explicit disconnect. Confirm the disconnect and that no automatic reconnection occurs. Do not send Reset or Stop.

### Abort conditions

Abort immediately on unexpected belt or incline motion; loss of direct access to the console or safety key; another person approaching the deck; a subscription or write error; a negative, unknown, malformed, mismatched or duplicate response; `0x2ADA FF`; contradictory telemetry; disconnect; timeout; or any inability to determine the machine's physical state.

On abort, send no compensating FTMS command. The operator uses the physical console or safety key as necessary, and the app records the outcome as failed/unknown. Disconnect only when doing so does not interfere with the operator's physical response.

### Exact evidence boundary

This proof can establish whether one Request Control write received a valid FTMS response and whether unexpected motion was humanly observed during that attempt. It cannot establish target-setting support, start/stop semantics, continuing ownership, loss-of-control notification, response timing guarantees, telemetry availability, safe command values, actuation behaviour, disconnect behaviour during motion, or workout execution. Each remains a later, separately authorised slice.

## Unresolved FR30z safety blockers

- Whether Request Control is accepted, rejected or requires bonding, a console mode or another vendor-specific precondition beyond the Profile's authenticated LE security requirement.
- Whether the FR30z returns exactly one correlated indication within the mandated 30-second response window.
- Whether control can be revoked by the console or another Client and whether this FR30z then emits `0x2ADA FF`.
- Whether Training Status notifications are emitted in control-related states; the observed `0x2AD3` initial read `00 00` is not notification evidence.
- Whether app-originated target changes cause any `0x2ADA` notification to the originating Client; FTMS does not require that path and passive physical evidence contained no such notification.
- Whether speed and inclination requests within the advertised ranges and increments are accepted, and whether values must meet undocumented FR30z constraints.
- Whether either target command can cause motion or incline actuation while nominally stopped, or whether Start or Resume is required. No target write is safe to classify as inert.
- The delay, ramp behaviour and reported `0x2ACD` sequence after an acknowledged target; no observation deadline or tolerance has been evidenced.
- Whether `0x2ACD` continues during app-controlled operation or after any particular transition. Issue #1 proves neither a terminal zero-speed packet nor post-stop telemetry.
- How physical-console Stop, Pause and speed/incline changes interact with app control and pending procedures.
- How safety-key removal affects control permission, pending procedures, indications and later reconnection.
- What happens to motion and target settings if Bluetooth disconnects. The protocol ends permission; it does not provide FR30z physical-behaviour evidence.
- How multiple connected Clients contend for control on the FR30z.
- Whether behaviour varies by FR30z firmware, Bluetooth dongle revision, iPhone model or OS version.

Until the relevant blocker is resolved under a separately authorised proof, the associated control transition must remain unavailable rather than guessed.
