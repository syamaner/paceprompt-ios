# FR30z workout proof physical-start abort — 13 September 2026

Status: failed-closed physical evidence for GitHub issue [#62](https://github.com/syamaner/paceprompt-ios/issues/62). This attempt does not satisfy the issue acceptance criteria and does not authorise another physical session.

## Scope and authority

- The operator confirmed the treadmill stopped and deck clear, immediate console and safety-key access, an authorised iPhone, no other controlling client and one supervised conservative walking proof.
- The signed proof-only Release build used the source tree shared by merged `main` commit `dd9560bf4ec5ddaf6a862615dee6c6cb6a472fff` and source commit `7113f4aca5324888c980fed7b4056f9d3afde94a`.
- One operator-confirmed Reebok FR30z connection matched the accepted profile. The peripheral identifier and raw packet data are deliberately excluded.
- The fixed plan was 60 seconds at 0.50 km/h and 0%, 180 seconds at 0.60 km/h and 0%, then 60 seconds at 0.50 km/h and 0%. Session ceilings were 0.70 km/h, 1% and a 0.10 km/h planned-step change.

## Result

- **Begin workout** emitted no procedure and waited for physical Start.
- The operator recorded the marker and physically started the treadmill.
- PacePrompt recorded one later complete stationary report at 0 km/h and 0%, then entered failed state about 3.3 seconds later.
- No Request Control, target-speed or target-inclination procedure was recorded or submitted.
- The operator physically stopped the treadmill and separately confirmed it stopped. That is human evidence, not treadmill telemetry.
- The app explicitly disconnected once. There was no retry, reconnect or control acquisition.

The proof build recorded only `failed`, not the reducer's sanitised terminal category, so this retained report cannot prove which adverse telemetry event caused the terminal transition. Code review nevertheless found a deterministic physical-start defect on this exact path: the reducer treated the advertised 0.50 km/h minimum target-setting speed as the minimum valid reported motion speed. A complete transitional report above zero but below 0.50 km/h therefore became contradictory instead of valid physical-start ramp evidence. The physical-start timing makes that defect consistent with this abort, but the omitted terminal category prevents claiming it as observed packet evidence.

## Sanitised evidence timeline

```text
+0.000 s · Proof build opened; no treadmill procedure has been authorised in the app
+0.061 s · Application lifecycle: Inactive
+0.254 s · Application lifecycle: Active (foreground)
+0.515 s · Execution state: idle
+31.387 s · Supervised sequence 1 opened by an explicit connection
+31.387 s · Execution state: idle
+142.315 s · Supervised-session authority created for the selected, exact-profile connection
+149.199 s · Fixed plan and ceilings armed after current profile and telemetry checks
+149.199 s · Execution state: preflight
+161.554 s · Preflight confirmation activity: yes
+161.768 s · Preflight confirmation deckClear: yes
+172.720 s · Preflight confirmation consoleReachable: yes
+172.952 s · Preflight confirmation safetyKeyReachable: yes
+173.152 s · Preflight confirmation physicallyStationary: yes
+190.658 s · Begin workout accepted with no procedure sent; fresh physical-Start telemetry may submit Request Control
+190.659 s · Execution state: waiting for physical Start
+202.082 s · Operator marker: about to press initial physical Start
+221.654 s · Later treadmill report: 0 km/h, 0%
+224.945 s · Execution state: failed
+368.158 s · Explicit disconnect requested for the current supervised sequence
```

Human markers and the operator's stopped observation are operator statements, not protocol or treadmill telemetry evidence.

## Repair boundary

The repair separates the target-setting minimum from reported-state validity. Complete current-epoch speeds from zero through the accepted maximum are valid reported state; any positive value is physical-start motion evidence, while submitted targets still require the validated advertised range, increments, plan and session ceilings. Negative speed and speed above the accepted maximum remain contradictory. The proof report also records a stable sanitised terminal code for future failures without retaining raw packets, identifiers or associated diagnostic strings.

The repair does not add FTMS Start, Stop or Pause, automatic retry, reconnect, control reacquisition, approximate target matching or a further physical session.
