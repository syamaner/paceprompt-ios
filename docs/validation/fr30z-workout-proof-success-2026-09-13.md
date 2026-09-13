# FR30z supervised workout proof — 13 September 2026

Status: accepted physical evidence for GitHub issue [#62](https://github.com/syamaner/paceprompt-ios/issues/62). This supervised session completed the fixed five-minute physical-console workout through pause, physical resume, next-segment reset, final physical Stop, operator-confirmed stationary state, local End workout and explicit disconnect. Together with the already-retained manual-override evidence, it satisfies the issue's bounded physical acceptance criteria. It does not authorise another physical session or broaden the result beyond the tested operator-confirmed FR30z profile.

## Scope and authority

- The operator freshly confirmed that the treadmill was stationary and the deck clear, that they were present with the console and safety key immediately reachable, that no other controlling client was connected, and that exactly one new supervised conservative issue #62 proof was authorised.
- A preceding attempt was interrupted when the operator inadvertently closed the app during the warm-up. The treadmill was physically stopped and that interrupted sequence was explicitly disconnected before this proof. The same already-installed signed proof build was then terminated and relaunched without a code or build change. Merged `main` was `b63510914763a5775e0f5c5a957902f72e8d688e`; its changes since the installed build's validated executable tree were limited to `DEVELOPMENT_NOTES.md` and the fifth-attempt evidence document, so app, test, project, build and validation-script inputs remained byte-identical.
- One operator-confirmed Reebok FR30z connection matched the accepted profile. The peripheral identifier and raw packet data are deliberately excluded.
- The fixed plan was 60 seconds at 0.50 km/h and 0%, 180 seconds at 0.60 km/h and 0%, then 60 seconds at 0.50 km/h and 0%. Session ceilings were 0.70 km/h, 1% and a 0.10 km/h planned-step change.
- The only allowed Control Point procedures were Request Control, Set Target Speed and Set Target Inclination. Physical-console Start and Stop remained authoritative throughout.

## Session result

- **Begin workout** emitted no procedure and waited for physical Start.
- A fresh 0.40 km/h movement report permitted Request Control. Request Control, initial 0.50 km/h speed and initial 0% inclination were separately submitted, ATT-accepted and FTMS-acknowledged; later joint treadmill telemetry reported 0.50 km/h and 0%.
- The planned 0.60 km/h transition was separately submitted, ATT-accepted and FTMS-acknowledged; later treadmill telemetry reported 0.60 km/h and 0%.
- After the operator's physical Stop, the app entered **Checking treadmill** when telemetry became stale. Active timing froze with 11 seconds left in the proof interval. Silence and stale data did not establish stationary state.
- The operator separately confirmed that the treadmill was physically stationary. The app then entered the accepted paused state and displayed the preserved effective targets of 0.60 km/h and 0%.
- After the operator's physical resume, fresh reports progressed from 0 to 0.30 km/h. PacePrompt restored 0.60 km/h then 0% sequentially; both procedures were ATT-accepted and FTMS-acknowledged, and later telemetry reported the restored 0.60 km/h and 0% targets.
- When the remaining 11 seconds elapsed, the next segment reset the effective speed to its planned 0.50 km/h. That target was separately submitted, ATT-accepted and FTMS-acknowledged; later telemetry reported 0.50 km/h and 0%.
- At five minutes of active time, PacePrompt entered **awaiting final physical Stop** and sent no Stop procedure. The operator physically stopped the treadmill and separately confirmed it stationary after the app entered **Checking treadmill**.
- **End workout** requested local finalisation only. Execution finished, the local attempt was saved, and no FTMS Stop procedure was sent.
- PacePrompt explicitly disconnected once. There was no retry, automatic reconnect, control reacquisition or further procedure.

## Acceptance accounting

The successful restarted session is the complete pause/resume/end proof. It deliberately did not repeat the manual 0.70 km/h and 1% overrides already established by the earlier accepted target-observation session. Issue #62 acceptance is therefore supported by distinct, sanitised evidence rather than by claiming that every accepted observation occurred in one timeline:

- this session establishes explicit connection, plan review, Preflight, physical Start, Request Control, initial targets, a planned transition, operator-confirmed pause, preserved targets, physical resume restoration, next-segment reset, final physical Stop, operator-confirmed stationary state, local End workout and explicit disconnect;
- the accepted fourth and fifth attempt evidence establishes separate in-range 0.70 km/h speed and 1% inclination overrides, including intent, submission, ATT acceptance, FTMS acknowledgement and later exact treadmill reports; and
- the unsuccessful attempts remain retained as abort evidence for the fail-closed paths and subsequent repairs. They are not recast as successful complete workouts.

## Sanitised evidence timeline

```text
+0.000 s · Proof build opened; no treadmill procedure has been authorised in the app
+0.035 s · Application lifecycle: Inactive
+0.274 s · Application lifecycle: Active (foreground)
+0.535 s · Execution state: idle
+22.221 s · Supervised sequence 1 opened by an explicit connection
+22.221 s · Execution state: idle
+39.122 s · Supervised-session authority created for the selected, exact-profile connection
+45.239 s · Fixed plan and ceilings armed after current profile and telemetry checks
+45.239 s · Execution state: preflight
+61.108 s · Preflight confirmation activity: yes
+66.342 s · Preflight confirmation deckClear: yes
+77.676 s · Preflight confirmation consoleReachable: yes
+81.664 s · Preflight confirmation safetyKeyReachable: yes
+87.664 s · Preflight confirmation physicallyStationary: yes
+102.343 s · Begin workout accepted with no procedure sent; fresh physical-Start telemetry may submit Request Control
+102.344 s · Execution state: waiting for physical Start
+107.247 s · Operator marker: about to press initial physical Start
+157.968 s · Later treadmill report: 0 km/h, 0%
+160.745 s · Execution state: acquiring control
+160.745 s · Later treadmill report: 0.4 km/h, 0%
+161.000 s · Execution state: applying targets
+161.000 s · Procedure 1 Request Control: submitted at 139815.740, ATT accepted at 139815.804, FTMS acknowledged at 139815.804
+161.000 s · Procedure 2 Set Target Speed 0.5 km/h: submitted at 139815.812, ATT accepted at 139815.863, FTMS acknowledged at 139815.863
+161.000 s · Procedure 3 Set Target Inclination 0%: submitted at 139815.864, ATT accepted at 139815.924, FTMS acknowledged at 139815.924
+161.490 s · Execution state: running segment
+161.490 s · Later treadmill report: 0.5 km/h, 0%
+221.489 s · Execution state: applying targets
+221.489 s · Procedure 4 Set Target Speed 0.6 km/h: submitted at 139876.284, ATT accepted at 139876.344, FTMS acknowledged at 139876.344
+222.477 s · Execution state: running segment
+222.477 s · Later treadmill report: 0.6 km/h, 0%
+239.928 s · Operator marker: about to press physical Stop
+392.406 s · Execution state: checking treadmill
+459.730 s · Operator separately confirmed the treadmill stationary
+459.750 s · Execution state: paused
+465.380 s · Operator marker: about to press physical Start for resume
+478.477 s · Later treadmill report: 0 km/h, 0%
+481.256 s · Execution state: restoring targets
+481.256 s · Later treadmill report: 0.3 km/h, 0%
+481.513 s · Procedure 5 Set Target Speed 0.6 km/h: submitted at 140136.260, ATT accepted at 140136.295, FTMS acknowledged at 140136.295
+481.513 s · Procedure 6 Set Target Inclination 0%: submitted at 140136.295, ATT accepted at 140136.355, FTMS acknowledged at 140136.355
+481.954 s · Later treadmill report: 0.5 km/h, 0%
+482.237 s · Execution state: running segment
+482.237 s · Later treadmill report: 0.6 km/h, 0%
+493.467 s · Execution state: applying targets
+493.467 s · Procedure 7 Set Target Speed 0.5 km/h: submitted at 140148.296, ATT accepted at 140148.356, FTMS acknowledged at 140148.356
+494.240 s · Execution state: running segment
+494.240 s · Later treadmill report: 0.5 km/h, 0%
+554.486 s · Execution state: awaiting final physical Stop
+566.574 s · Operator marker: about to press final physical Stop
+575.356 s · Execution state: checking treadmill
+618.479 s · Operator separately confirmed the treadmill stationary
+618.500 s · Execution state: ready to End workout
+632.781 s · End workout tapped; local finalisation requested with no FTMS Stop procedure
+632.782 s · Execution state: finished
+640.433 s · Explicit disconnect requested for the current supervised sequence
```

Human markers and the operator's stationary confirmations are operator statements, not protocol or treadmill telemetry evidence.

## Evidence boundary

This record supports only one operator-confirmed FR30z profile with the signed, byte-identical issue #62 executable inputs. It separates user intent, procedure submission, ATT acceptance, FTMS acknowledgement, later treadmill reports, app state and human observations. It does not establish unattended operation, automatic recovery, running-speed or endurance behaviour, a broad FR30z/device claim, HealthKit saving, Watch behaviour, or FTMS Start, Stop or Pause support.

No further physical session is authorised by this record.
