# FR30z workout proof operator-stop silence abort — 13 September 2026

Status: partial physical evidence for GitHub issue [#62](https://github.com/syamaner/paceprompt-ios/issues/62). The initial physical Start, planned transition and both manual overrides passed their bounded acceptance path. The operator-stop phase interrupted because no zero-speed telemetry arrived and the deliberate human-stationary fallback was not recorded before the then-current checking deadline. This attempt does not satisfy the complete issue acceptance criteria and does not authorise another physical session.

## Scope and authority

- The operator confirmed the deck clear, their presence, immediate console and safety-key access, an authorised iPhone, no other controlling client and exactly one supervised conservative walking proof.
- The freshly installed signed proof-only Release build used tree `69a11d0877f266cb4d2df0f2a117c09de0bfa869`, shared by merged `main` commit `1f7e312ac70a5768b0d6823674d313a4784d1df6` and source commit `844fcfccdc4cc0f036a2e53414a62e24cd08e4df`.
- One operator-confirmed Reebok FR30z connection matched the accepted profile. The peripheral identifier and raw packet data are deliberately excluded.
- The fixed plan was 60 seconds at 0.50 km/h and 0%, 180 seconds at 0.60 km/h and 0%, then 60 seconds at 0.50 km/h and 0%. Session ceilings were 0.70 km/h, 1% and a 0.10 km/h planned-step change.

## Result

- **Begin workout** emitted no procedure and waited for physical Start.
- A later 0.20 km/h ramp report permitted Request Control. Request Control, initial 0.50 km/h speed and initial 0% inclination were separately submitted, ATT-accepted and FTMS-acknowledged; later joint treadmill telemetry reported 0.50 km/h and 0%.
- The planned 0.60 km/h transition was separately submitted, ATT-accepted and FTMS-acknowledged; later treadmill telemetry reported 0.60 km/h and 0%.
- The manual 0.70 km/h speed override and 1% inclination override were separately submitted, ATT-accepted and FTMS-acknowledged; later joint treadmill telemetry reported 0.70 km/h and 1%.
- The operator recorded the physical Stop marker, physically stopped the treadmill and separately reported it stopped. That statement is human evidence, not treadmill telemetry.
- No later zero-speed treadmill report arrived. The app entered checking and then interrupted with sanitised reason `telemetry-stream-timed-out` under the then-current 10-second policy.
- The app explicitly disconnected once. There was no retry, reconnect, resume, control reacquisition or further procedure.
- No FTMS Start, Stop or Pause procedure was exposed or sent.

## Sanitised evidence timeline

```text
+0.000 s · Proof build opened; no treadmill procedure has been authorised in the app
+0.041 s · Application lifecycle: Inactive
+0.067 s · Application lifecycle: Active (foreground)
+0.318 s · Execution state: idle
+29.305 s · Supervised sequence 1 opened by an explicit connection
+29.305 s · Execution state: idle
+48.574 s · Supervised-session authority created for the selected, exact-profile connection
+55.823 s · Fixed plan and ceilings armed after current profile and telemetry checks
+55.823 s · Execution state: preflight
+64.607 s · Preflight confirmation activity: yes
+64.829 s · Preflight confirmation deckClear: yes
+81.258 s · Preflight confirmation consoleReachable: yes
+81.481 s · Preflight confirmation safetyKeyReachable: yes
+81.697 s · Preflight confirmation physicallyStationary: yes
+96.921 s · Begin workout accepted with no procedure sent; fresh physical-Start telemetry may submit Request Control
+96.922 s · Execution state: waiting for physical Start
+104.759 s · Operator marker: about to press initial physical Start
+129.134 s · Later treadmill report: 0 km/h, 0%
+131.920 s · Execution state: acquiring control
+131.921 s · Later treadmill report: 0.2 km/h, 0%
+132.179 s · Execution state: applying targets
+132.179 s · Procedure 1 Request Control: submitted at 133786.099, ATT accepted at 133786.163, FTMS acknowledged at 133786.163
+132.179 s · Procedure 2 Set Target Speed 0.5 km/h: submitted at 133786.175, ATT accepted at 133786.223, FTMS acknowledged at 133786.223
+132.179 s · Procedure 3 Set Target Inclination 0%: submitted at 133786.223, ATT accepted at 133786.283, FTMS acknowledged at 133786.283
+132.667 s · Execution state: running segment
+132.667 s · Later treadmill report: 0.5 km/h, 0%
+193.131 s · Execution state: applying targets
+193.132 s · Procedure 4 Set Target Speed 0.6 km/h: submitted at 133846.936, ATT accepted at 133846.973, FTMS acknowledged at 133846.973
+193.403 s · Execution state: running segment
+193.403 s · Later treadmill report: 0.6 km/h, 0%
+208.958 s · Manual speed adjustment accepted: 0.7 km/h
+208.958 s · Execution state: applying targets
+209.237 s · Procedure 5 Set Target Speed 0.7 km/h: submitted at 133863.167, ATT accepted at 133863.203, FTMS acknowledged at 133863.203
+210.153 s · Execution state: running segment
+210.153 s · Later treadmill report: 0.7 km/h, 0%
+218.808 s · Manual inclination adjustment accepted: 1%
+218.809 s · Execution state: applying targets
+219.203 s · Procedure 6 Set Target Inclination 1%: submitted at 133873.017, ATT accepted at 133873.073, FTMS acknowledged at 133873.073
+219.671 s · Execution state: running segment
+219.671 s · Later treadmill report: 0.7 km/h, 1%
+231.690 s · Operator marker: about to press physical Stop
+316.812 s · Execution state: checking treadmill
+324.730 s · Execution state: interrupted (telemetry-stream-timed-out)
+339.753 s · Explicit disconnect requested for the current supervised sequence
```

Human markers and the operator's stopped observation are operator statements, not protocol or treadmill telemetry evidence.

## Product correction

The operator owns physical Start and Stop. A missing treadmill report after Stop is therefore useful as a signal to freeze active timing and display **Checking treadmill**, but it is not proof that the belt stopped. The separate operator-stationary confirmation must remain available without an arbitrary expiry so the operator can establish pause or ending eligibility after directly observing the console and belt.

The repair removes only the silence-to-terminal deadline. Checking remains command-free and frozen until fresh zero, fresh moving telemetry or deliberate operator confirmation resolves it. Explicit telemetry unavailability, malformed or contradictory evidence, connection/control/profile loss, app deactivation, procedure deadlines and target-observation deadlines retain their fail-closed outcomes. The repair adds no FTMS Start, Stop or Pause, automatic retry, reconnect or control reacquisition and does not authorise another physical session.
