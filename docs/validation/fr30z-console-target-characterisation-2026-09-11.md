# FR30z console and target-control characterisation — 11 September 2026

Status: sanitised physical evidence used by GitHub issue [#57](https://github.com/syamaner/paceprompt-ios/issues/57). The raw operator-provided reports remain local and are not committed because they include a CoreBluetooth peripheral identifier. This record does not authorise another physical session.

## Evidence scope

- Equipment: one operator-identified Reebok FR30z with its removable fitness Bluetooth dongle. The treadmill firmware and dongle revision were not exposed by the diagnostic and remain unknown.
- Client: PacePrompt DEBUG diagnostics on the operator's iPhone, foreground-active, connected once per captured report.
- Operator: present at the treadmill with the physical console and safety key authoritative.
- Adopted protocol references rechecked on 11 September 2026: Bluetooth SIG Fitness Machine Service 1.0.1 and Fitness Machine Profile 1.0.1, both still listed as Adopted.
- This is evidence for the identified equipment/profile only. It is not a compatibility claim for another FR30z, firmware, dongle, treadmill or FTMS implementation.

## Identity and capability evidence

The captured connection exposed Fitness Machine Service `0x1826` and the expected characteristics, including:

- Fitness Machine Feature `0x2ACC`: exact bytes `0C 16 00 00 03 00 00 00`; speed-target and inclination-target feature bits decoded as supported.
- Supported Speed Range `0x2AD4`: exact bytes `32 00 D0 07 0A 00`; 0.50–20.00 km/h in 0.10 km/h increments.
- Supported Inclination Range `0x2AD5`: exact bytes `00 00 96 00 0A 00`; 0.0–15.0% in 1.0% increments.
- Fitness Machine Control Point `0x2AD9`: Write and Indicate.
- Treadmill Data `0x2ACD`, Training Status `0x2AD3` and Fitness Machine Status `0x2ADA` subscriptions were confirmed.

`0x2AD3` repeatedly read exact bytes `00 00`, decoded as Training Status `Other` with no detail. No useful `0x2ADA` notification was captured. The production workflow therefore cannot depend on either status characteristic.

The peripheral UUID is deliberately omitted from this sanitised record. A production installation may retain the user-selected CoreBluetooth identity locally, but must not put it in Git, logs, analytics or export.

## Control Point evidence

### Request Control

One Request Control procedure submitted exact bytes `00`. CoreBluetooth separately recorded ATT acceptance and the matching FTMS success response `80 00 01`. This repeats the accepted issue #51 result for a later connection; it establishes protocol control only for that connection.

### Speed targets

While the belt was started and stopped by the operator from the physical console, the same controlled connection submitted these target procedures one at a time:

| Target | Request | FTMS response | Later `0x2ACD` report | Operator observation |
| --- | --- | --- | --- | --- |
| 0.60 km/h | `02 3C 00` | `80 02 01` | exact 0.60 km/h | confirmed |
| 0.70 km/h | `02 46 00` | `80 02 01` | exact 0.70 km/h | confirmed |
| 0.60 km/h | `02 3C 00` | `80 02 01` | exact 0.60 km/h | confirmed |
| 0.50 km/h | `02 32 00` | `80 02 01` | exact 0.50 km/h | confirmed |

In the captured low-delta samples, the first exact reported value followed the matching protocol acknowledgement by approximately 0.70–0.81 seconds. These measurements do not establish the ramp time for larger target changes.

### Inclination targets

The same connection submitted:

| Target | Request | FTMS response | Later `0x2ACD` report | Operator observation |
| --- | --- | --- | --- | --- |
| 1.0% | `03 0A 00` | `80 03 01` | exact 1.0% | confirmed |
| 0.0% | `03 00 00` | `80 03 01` | exact 0.0% | confirmed |

In the captured 1.0-percentage-point samples, the first exact reported value followed the matching protocol acknowledgement by approximately 0.78–0.84 seconds. This does not establish mechanical calibration or the ramp time for larger target changes.

### Combined ordering and console cycles

A combined sequence successfully used speed before inclination, then speed before inclination again: 0.60 km/h, 1.0%, 0.50 km/h, 0.0%. Each procedure had separate ATT acceptance, matching FTMS success, a later exact `0x2ACD` report and operator confirmation.

Physical console Stop/Start cycles occurred without reconnecting or issuing another Request Control procedure. Later speed and inclination targets were acknowledged and observed on the same connection. This supports retaining control across an ordinary console Stop/Start cycle only while the same connection remains current and no explicit control-loss, error, malformed evidence or contradiction appears.

### FTMS Start and Stop are excluded

Separate diagnostic interactions produced protocol responses to FTMS Start and Stop, but their physical effects were not reliable:

- FTMS Start could receive success `80 07 01` without causing the console countdown or belt motion observed from physical Start.
- FTMS Stop produced inconsistent protocol results across interactions, including success `80 08 01` and Operation Failed `80 08 04`; the operator did not accept it as a reliable belt-stop control.

Protocol acknowledgement did not establish the expected physical action. The product therefore exposes no FTMS Start, Stop or Pause route. The operator uses the physical console and safety key.

## Treadmill Data timing

During steady stationary and moving periods, well-formed `0x2ACD` notifications normally arrived about every 0.48–0.57 seconds and included instantaneous speed and inclination.

One later, deliberately slower console Stop/Start observation captured:

- last pre-stop non-zero report: 0.50 km/h at `20:03:16.918Z`;
- first post-stop zero report: 0.00 km/h at `20:03:24.928Z`;
- observed gap: 8.010 seconds;
- repeated zero reports continued at roughly 0.5-second intervals;
- physical restart then reported 0.30 km/h followed by 0.50 km/h.

Earlier console Stop/Start cycles restarted within roughly three to five seconds and did not expose an intervening zero packet. The product must tell the operator to wait until PacePrompt displays **Paused** before restarting if a distinct pause is wanted.

This evidence supports a **Checking treadmill** state during delayed delivery. It does not make packet silence a zero-speed report, and it does not prove physical safety between samples.

## Human observation boundary

The operator separately confirmed physical console starts, stops and target changes. Those observations do not replace protocol acknowledgements. Conversely, acknowledgements and `0x2ACD` reports do not replace the physical console or safety key.

The product-policy candidate derived from this record is in [`design/fr30z-physical-console-execution-profile.md`](../../design/fr30z-physical-console-execution-profile.md).
