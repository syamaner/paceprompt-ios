# FR30z workout proof target-observation abort — 13 September 2026

Status: failed-closed physical evidence for GitHub issue [#62](https://github.com/syamaner/paceprompt-ios/issues/62). This attempt does not satisfy the issue acceptance criteria and does not authorise another physical session.

## Scope and authority

- The operator confirmed the deck clear, immediate console and safety-key access, an authorised iPhone, no other controlling client and one supervised conservative walking proof.
- The signed proof-only Release build used source tree `0592268ecb5b4fc9212a8a2bbb3aba557125421b`, shared by reviewed source commit `f0abd10be97cf3bf53bd8786e7ec5b6b049a41b2` and merged `main` commit `a91a470c44033790a61de4f0421bcfd445f03543`.
- One operator-confirmed Reebok FR30z connection matched the accepted profile. The peripheral identifier and raw packet data are deliberately excluded.
- The fixed plan was 60 seconds at 0.50 km/h and 0%, 180 seconds at 0.60 km/h and 0%, then 60 seconds at 0.50 km/h and 0%. Session ceilings were 0.70 km/h, 1% and a 0.10 km/h planned-step change.

## Result

- **Begin workout** emitted no procedure and waited for physical Start.
- Fresh non-zero treadmill data then permitted Request Control. Separate ATT acceptance and matching FTMS success were recorded for Request Control, initial 0.50 km/h and 0% targets, the planned 0.60 km/h transition and the manual 0.70 km/h speed override.
- Later treadmill reports confirmed 0.50 km/h and 0%, then 0.60 km/h and 0%.
- After the 0.70 km/h acknowledgement, a later report was decoded as `0.7000000000000001` km/h and 0%. The operator separately observed 0.70 km/h on the treadmill.
- The execution layer compared that non-canonical `Decimal` with the exact 0.70 km/h target. It did not accept the report, allowed the 30-second observation deadline to expire and failed closed.
- No inclination override, pause/resume cycle, final segment, local End workout, retry, reconnect, control reacquisition or compensating target occurred.
- The operator physically stopped the treadmill and separately confirmed it stopped. The app then explicitly disconnected once.

## Sanitised evidence timeline

```text
+0.000 s · Proof build opened; no treadmill procedure has been authorised in the app
+0.046 s · Application lifecycle: Inactive
+0.282 s · Application lifecycle: Active (foreground)
+0.541 s · Execution state: idle
+271.299 s · Supervised sequence 1 opened by an explicit connection
+271.299 s · Execution state: idle
+329.337 s · Supervised-session authority created for the selected, exact-profile connection
+339.655 s · Fixed plan and ceilings armed after current profile and telemetry checks
+339.655 s · Execution state: preflight
+353.689 s · Preflight confirmation activity: yes
+358.561 s · Preflight confirmation deckClear: yes
+371.223 s · Preflight confirmation consoleReachable: yes
+371.446 s · Preflight confirmation safetyKeyReachable: yes
+375.908 s · Preflight confirmation physicallyStationary: yes
+401.210 s · Begin workout accepted with no procedure sent; fresh physical-Start telemetry may submit Request Control
+401.211 s · Execution state: waiting for physical Start
+410.771 s · Operator marker: about to press initial physical Start
+424.740 s · Later treadmill report: 0 km/h, 0%
+428.036 s · Execution state: acquiring control
+428.036 s · Later treadmill report: 0.5 km/h, 0%
+428.300 s · Execution state: applying targets
+428.300 s · Procedure 1 Request Control: submitted at 127551.612, ATT accepted at 127551.647, FTMS acknowledged at 127551.647
+428.300 s · Procedure 2 Set Target Speed 0.5 km/h: submitted at 127551.654, ATT accepted at 127551.737, FTMS acknowledged at 127551.737
+428.300 s · Procedure 3 Set Target Inclination 0%: submitted at 127551.737, ATT accepted at 127551.827, FTMS acknowledged at 127551.827
+428.756 s · Execution state: running segment
+488.768 s · Execution state: applying targets
+488.769 s · Procedure 4 Set Target Speed 0.6 km/h: submitted at 127612.106, ATT accepted at 127612.157, FTMS acknowledged at 127612.157
+489.521 s · Execution state: running segment
+489.521 s · Later treadmill report: 0.6 km/h, 0%
+501.938 s · Manual speed adjustment accepted: 0.7 km/h
+501.938 s · Execution state: applying targets
+502.218 s · Procedure 5 Set Target Speed 0.7 km/h: submitted at 127625.543, ATT accepted at 127625.597, FTMS acknowledged at 127625.597
+503.246 s · Later treadmill report: 0.7000000000000001 km/h, 0%
+532.288 s · Execution state: failed
+591.007 s · Explicit disconnect requested for the current supervised sequence
+799.542 s · Application lifecycle: Background
+800.512 s · Application lifecycle: Active (foreground)
+800.624 s · Application lifecycle: Inactive
+801.309 s · Application lifecycle: Background
+801.997 s · Application lifecycle: Inactive
+802.305 s · Application lifecycle: Active (foreground)
```

Human markers and the operator's 0.70 km/h and stopped observations are operator statements, not protocol or treadmill telemetry evidence.

## Repair boundary

The repair canonicalises only integer-scaled FTMS values at the protocol-to-domain boundary: speed to two decimal places and inclination to one. Capability ranges and live workout telemetry share that conversion. The reducer retains exact equality, and the existing Control Point encoder retains its bounded representation-tolerance and off-grid rejection. Safety deadlines, freshness rules, command ordering, per-write guards and fail-closed behaviour are unchanged.
