# FR30z workout proof app-continuity abort — 13 September 2026

Status: partial physical evidence for GitHub issue [#62](https://github.com/syamaner/paceprompt-ios/issues/62). The initial physical Start, planned transition, manual overrides and repaired non-expiring Checking-treadmill state passed their bounded paths. The attempt then interrupted when direct iPhone use moved PacePrompt out of the foreground. This attempt does not satisfy the complete issue acceptance criteria and does not authorise another physical session.

## Scope and authority

- The operator confirmed that the treadmill was stationary and the deck clear, that they were present with the console and safety key immediately reachable, that no other controlling client was connected, and that exactly one supervised conservative issue #62 proof was authorised.
- A fresh signed proof-only Release build used tree `38aecad9d2516262c0199fc625bf629a0b81be61`, shared by merged `main` commit `0403f279ad0ffea51eeebc418e8875dc6d372fa5` and the reviewed proof branch at installation time.
- One operator-confirmed Reebok FR30z connection matched the accepted profile. The peripheral identifier and raw packet data are deliberately excluded.
- The fixed plan was 60 seconds at 0.50 km/h and 0%, 180 seconds at 0.60 km/h and 0%, then 60 seconds at 0.50 km/h and 0%. Session ceilings were 0.70 km/h, 1% and a 0.10 km/h planned-step change.

## Result

- **Begin workout** emitted no procedure and waited for physical Start.
- A later 0.20 km/h ramp report permitted Request Control. Request Control, initial 0.50 km/h speed and initial 0% inclination were separately submitted, ATT-accepted and FTMS-acknowledged; later joint treadmill telemetry reported 0.50 km/h and 0%.
- The planned 0.60 km/h transition was separately submitted, ATT-accepted and FTMS-acknowledged; later treadmill telemetry reported 0.60 km/h and 0%.
- The manual 0.70 km/h speed override and 1% inclination override were separately submitted, ATT-accepted and FTMS-acknowledged; later joint treadmill telemetry reported 0.70 km/h and 1%.
- The operator recorded the physical Stop marker, physically stopped the treadmill and separately reported it stopped. That statement is human evidence, not treadmill telemetry.
- No later zero-speed treadmill report arrived. The app entered **Checking treadmill** and remained there for approximately 243 seconds with active timing frozen and no silence-to-terminal transition. This is physical evidence that merged repair #93 removed the former arbitrary checking deadline for this tested session.
- The separate operator-stationary confirmation was not recorded. The operator used the physical iPhone to capture the portrait screen; iPhone Mirroring reported that direct iPhone use ended the mirrored session, and the retained app timeline recorded `Background` followed by `interrupted (app-continuity-lost)`. The operator action is contextual human evidence; the app lifecycle and terminal code are retained app evidence.
- PacePrompt explicitly disconnected once after returning to the foreground. There was no retry, treadmill reconnection, resume, control reacquisition or further procedure.
- No FTMS Start, Stop or Pause procedure was exposed or sent.

## Sanitised evidence timeline

```text
+0.000 s · Proof build opened; no treadmill procedure has been authorised in the app
+0.027 s · Application lifecycle: Inactive
+0.307 s · Application lifecycle: Active (foreground)
+0.314 s · Execution state: idle
+317.431 s · Supervised sequence 1 opened by an explicit connection
+317.431 s · Execution state: idle
+366.281 s · Supervised-session authority created for the selected, exact-profile connection
+376.019 s · Fixed plan and ceilings armed after current profile and telemetry checks
+376.019 s · Execution state: preflight
+387.370 s · Preflight confirmation activity: yes
+387.592 s · Preflight confirmation deckClear: yes
+404.438 s · Preflight confirmation consoleReachable: yes
+404.659 s · Preflight confirmation safetyKeyReachable: yes
+404.876 s · Preflight confirmation physicallyStationary: yes
+426.082 s · Begin workout accepted with no procedure sent; fresh physical-Start telemetry may submit Request Control
+426.083 s · Execution state: waiting for physical Start
+437.940 s · Operator marker: about to press initial physical Start
+575.829 s · Later treadmill report: 0 km/h, 0%
+578.839 s · Execution state: acquiring control
+578.839 s · Later treadmill report: 0.2 km/h, 0%
+579.104 s · Execution state: applying targets
+579.104 s · Procedure 1 Request Control: submitted at 137364.364, ATT accepted at 137364.428, FTMS acknowledged at 137364.428
+579.104 s · Procedure 2 Set Target Speed 0.5 km/h: submitted at 137364.439, ATT accepted at 137364.488, FTMS acknowledged at 137364.488
+579.104 s · Procedure 3 Set Target Inclination 0%: submitted at 137364.488, ATT accepted at 137364.548, FTMS acknowledged at 137364.548
+579.556 s · Execution state: running segment
+579.556 s · Later treadmill report: 0.5 km/h, 0%
+639.561 s · Execution state: applying targets
+639.561 s · Procedure 4 Set Target Speed 0.6 km/h: submitted at 137424.964, ATT accepted at 137424.999, FTMS acknowledged at 137424.999
+640.321 s · Execution state: running segment
+640.321 s · Later treadmill report: 0.6 km/h, 0%
+664.249 s · Manual speed adjustment accepted: 0.7 km/h
+664.249 s · Execution state: applying targets
+664.596 s · Procedure 5 Set Target Speed 0.7 km/h: submitted at 137449.806, ATT accepted at 137449.870, FTMS acknowledged at 137449.870
+665.303 s · Execution state: running segment
+665.303 s · Later treadmill report: 0.7 km/h, 0%
+682.075 s · Manual inclination adjustment accepted: 1%
+682.076 s · Execution state: applying targets
+682.564 s · Procedure 6 Set Target Inclination 1%: submitted at 137467.632, ATT accepted at 137467.689, FTMS acknowledged at 137467.689
+683.047 s · Execution state: running segment
+683.048 s · Later treadmill report: 0.7 km/h, 1%
+695.080 s · Operator marker: about to press physical Stop
+711.451 s · Execution state: checking treadmill
+954.589 s · Application lifecycle: Background
+954.960 s · Execution state: interrupted (app-continuity-lost)
+955.634 s · Application lifecycle: Active (foreground)
+984.116 s · Application lifecycle: Background
+987.450 s · Application lifecycle: Inactive
+988.211 s · Application lifecycle: Active (foreground)
+995.429 s · Application lifecycle: Inactive
+1006.196 s · Application lifecycle: Active (foreground)
+1071.628 s · Application lifecycle: Background
+1072.396 s · Application lifecycle: Active (foreground)
+1177.407 s · Explicit disconnect requested for the current supervised sequence
```

Human markers and the operator's stopped observation are operator statements, not protocol or treadmill telemetry evidence.

## Acceptance boundary

This attempt adds accepted physical evidence for the initial physical-Start path, the first planned transition, both bounded manual overrides and the repaired non-expiring telemetry-silence presentation. It does not establish the separate operator-stationary transition, preserved-target presentation after accepted pause, physical-resume restoration, next-segment override reset, final physical Stop or local End-workout flow.

A later proof must stay inside iPhone Mirroring while the app attempt is active. Screenshots should be taken from the Mac-side mirrored window; direct iPhone use is reserved for after the workout is ended or interrupted and explicitly disconnected. Any later proof still requires fresh safety checks and separate exact-session authority.
