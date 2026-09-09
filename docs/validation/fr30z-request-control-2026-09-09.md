# FR30z Request Control attempt — 9 September 2026

Status: failed/unknown proof under GitHub issue [#51](https://github.com/syamaner/paceprompt-ios/issues/51). This record is not evidence that control was granted and does not authorise another attempt or any other FTMS Control Point procedure.

## Authority and candidate

- The operator explicitly authorised exactly one Request Control procedure while present at the identified Reebok FR30z, with the deck clear, belt stationary, and console and safety key immediately accessible.
- Bluetooth SIG Fitness Machine Service 1.0.1 and Fitness Machine Profile 1.0.1, revision 1 October 2024, were reverified from the adopted specification catalogue before the candidate was built.
- The candidate started from `origin/main` at `979187d9121fd16eb1f405998c5f6f555d42ab11` and was an uncommitted Debug-only diagnostic build. Its final relevant source hashes were:

  | File | SHA-256 |
  | --- | --- |
  | `PacePrompt.xcodeproj/project.pbxproj` | `f637dc11dd89a4c20defbbc4a7512d55ce81e94eb71045efe78ba4d8cf0eecd3` |
  | `PacePrompt/Bluetooth/FTMSClient.swift` | `d663efc3107379f3c16f797b2dbdb0a3c04e5cfe1f0e0ccde628939e27f3a37f` |
  | `PacePrompt/Bluetooth/FTMSModels.swift` | `f4ab18dcb3a9a01d0f70f8d51028e331d279e77bcbe91441d7bcf81cd0f8c999` |
  | `PacePrompt/Bluetooth/RequestControlDiagnostic.swift` | `ed729f537352b8f4cd24312ed1e198b6f9279590e7ee43f14536d317cd25ffa7` |
  | `PacePrompt/Presentation/HomeUITestSupport.swift` | `c0ec0708d7e3800a8181b405bf7d7b7d24320091a50560a5222d633457f2276b` |
  | `PacePrompt/Presentation/TreadmillSetupViewModel.swift` | `463222ae45133751e404636f7440a94b907874d53acc7de9f7387ef4265e7af4` |
  | `PacePrompt/Views/TreadmillSetupView.swift` | `b19fa1b2b219dfc3c35781c924382fea06b4bc497ba8cab9e0c24318421d1aed` |

- The Debug path persisted a one-write allowance before forwarding and hard-allowed only the exact byte `00`. It exposed no target, Start, Stop/Pause, Reset, workout, retry, or reconnect action. The Release build compiled this diagnostic path out.
- Focused deterministic tests passed all 53 codec, single-procedure transport, one-shot diagnostic, and presentation tests.
- `scripts/validate_local.sh` passed before installation using Xcode 26.6 build 17F113 and an iPhone 17 Pro simulator on iOS 26.5: 233 unit tests, 23 UI tests, Release build, static analysis, coverage export without a threshold, 14 evaluation tests, and 23 accounting-helper tests all succeeded.

## Sanitised physical evidence

- Equipment: operator-identified Reebok FR30z. The treadmill Bluetooth dongle revision and treadmill firmware were unavailable through this FTMS-only diagnostic.
- Central: iPhone on iOS 26.6.1 using built-in Bluetooth. Raw device and peripheral identifiers are deliberately excluded from Git.
- CoreBluetooth enabled the security-restricted Control Point indication subscription without reporting an OS-mediated security or pairing error. Negotiated LE security details were not exposed.
- Control Point `0x2AD9` exposed Write and Indicate.
- Current feature bytes were `0C 16 00 00 03 00 00 00`; the decoded target-setting flags advertised speed and inclination target support.
- Current supported speed range bytes were `32 00 D0 07 0A 00`, decoded as 0.50–20.00 km/h in 0.10 km/h increments.
- Current supported inclination range bytes were `00 00 96 00 0A 00`, decoded as 0.0–15.0% in 1.0% increments.
- Passive subscriptions to `0x2ACD`, `0x2AD3`, and `0x2ADA` were all confirmed. The only passive value received was the initial `0x2AD3` read `00 00`, decoded as Training Status `Other`; no passive notification arrived during the procedure.
- After the operator's explicit two-stage confirmation, the app submitted exactly one with-response write containing `00`. Its local procedure identifier was connection epoch 1, sequence 1.
- CoreBluetooth delivered one well-formed Control Point indication containing exactly `80 00 01`, followed immediately in the app callback stream by a successful ATT write callback. Both callbacks shared the same timestamp to millisecond precision; the indication callback was observed first.
- The reviewed transport requires confirmed ATT write acceptance before it will accept a response indication or start the 30-second deadline. It therefore classified the callback order as `Control Point indication arrived before ATT write acceptance`, invalidated the procedure, and did not record control permission.
- The operator observed no unexpected belt or incline movement.
- The operator explicitly disconnected. CoreBluetooth confirmed disconnection, and no automatic reconnect occurred.
- No second write, compensating command, Reset, Stop, target, Start, Pause, retry, reconnect, workout operation, provider call, HealthKit operation, or Watch operation occurred.

## Conclusion

The attempt established that this connection returned the exact bytes `80 00 01` after the sole `00` submission and that CoreBluetooth later reported the write accepted. It did **not** satisfy the reviewed evidence ordering, so issue #51 cannot accept it as proof that control was granted. Request Control remains unresolved under the repository contract, and all target, Start, Stop/Pause, Reset, motion, and workout behaviour remains entirely unresolved.

The one authorised physical attempt is consumed. Resolving the CoreBluetooth callback-order mismatch requires a separately reviewed software-policy decision; it does not create retry or reconnect authority.
