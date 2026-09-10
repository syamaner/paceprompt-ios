# FR30z Request Control accepted proof — 10 September 2026

Status: accepted Request Control proof under GitHub issue [#51](https://github.com/syamaner/paceprompt-ios/issues/51). This record establishes control permission only for the completed connection. The explicit disconnect ended that permission. It does not authorise another attempt or any other FTMS Control Point procedure.

## Authority and candidate

- The operator explicitly authorised exactly one Request Control procedure while present at the identified Reebok FR30z, with the deck clear, belt stationary, and console and safety key immediately accessible.
- The candidate started from exact `origin/main` `494c431affdae0c19881949d4993312de33cfe8a`, which contains the issue #72 callback-order policy and the issue #76 crash-resilient diagnostic journal.
- The adopted Bluetooth SIG Fitness Machine Service 1.0.1 and Fitness Machine Profile 1.0.1 revisions, both dated 1 October 2024, remained the checked protocol authority.
- The uncommitted diagnostic candidate changed only the DEBUG one-shot gate from its consumed first-attempt key to the fresh persistent v3 key and added a test fixing that exact key. The issue #76 protected journal remained schema v1 at its existing path. No gate reset or second fresh gate version was used.
- The DEBUG path persisted its one-write allowance before forwarding and hard-allowed only exact Request Control byte `00`. It exposed no target, Start, Stop/Pause, Reset, workout, retry, or reconnect action. The Release build compiled the diagnostic path out.
- The candidate's relevant source hashes were:

  | File | SHA-256 |
  | --- | --- |
  | `PacePrompt.xcodeproj/project.pbxproj` | `f637dc11dd89a4c20defbbc4a7512d55ce81e94eb71045efe78ba4d8cf0eecd3` |
  | `PacePrompt/Bluetooth/FTMSClient.swift` | `f144e31edfddb2afbf9f211c0d590fbcf39babdafc27362d21adb99224fc3d2b` |
  | `PacePrompt/Bluetooth/FTMSModels.swift` | `f4ab18dcb3a9a01d0f70f8d51028e331d279e77bcbe91441d7bcf81cd0f8c999` |
  | `PacePrompt/Bluetooth/RequestControlDiagnostic.swift` | `a9d66da61a5205e310249dd7b288b97d95f26921a1255dd5cfbc7add9837c779` |
  | `PacePrompt/Presentation/HomeUITestSupport.swift` | `c0ec0708d7e3800a8181b405bf7d7b7d24320091a50560a5222d633457f2276b` |
  | `PacePrompt/Presentation/TreadmillSetupViewModel.swift` | `dc079e7505f7e008b62477ab6922d3dc2e021b3c8dadcec1635e16a81bf9d326` |
  | `PacePrompt/Views/TreadmillSetupView.swift` | `b19fa1b2b219dfc3c35781c924382fea06b4bc497ba8cab9e0c24318421d1aed` |

- All 17 focused `RequestControlDiagnosticTests` passed. The complete `scripts/validate_local.sh` policy then passed the sealed corpus, scorer and summary checks, 82 host-evaluation tests with two expected optional sibling-worktree skips, all 250 production unit tests, all 23 UI tests, production coverage export without a threshold, the Release simulator build, static analysis, all 14 developer-only evaluation tests, all 24 accounting-helper tests, and `git diff --check`.
- A signed Debug iPhone build succeeded and was installed in place without deleting app data. The locally retained signing identity is deliberately excluded from Git. These software and installation checks are not physical Request Control evidence; the separate observation below is.

## Sanitised physical evidence

- Equipment: operator-identified Reebok FR30z. The treadmill Bluetooth dongle revision and treadmill firmware were unavailable through this FTMS-only diagnostic.
- Central: iPhone on iOS 26.6.2 using built-in Bluetooth. The raw peripheral identifier and RSSI are deliberately excluded from Git.
- CoreBluetooth enabled the security-restricted Control Point indication subscription without reporting an OS-mediated security or pairing error. Negotiated LE security details were not exposed.
- Control Point `0x2AD9` exposed Write and Indicate.
- Current feature bytes were `0C 16 00 00 03 00 00 00`; the decoded target-setting flags advertised speed and inclination target support.
- Current supported speed range bytes were `32 00 D0 07 0A 00`, decoded as 0.50–20.00 km/h in 0.10 km/h increments.
- Current supported inclination range bytes were `00 00 96 00 0A 00`, decoded as 0.0–15.0% in 1.0% increments.
- Passive subscriptions to `0x2ACD`, `0x2AD3`, and `0x2ADA` were all confirmed. The only passive value received was the initial `0x2AD3` read `00 00`, decoded as Training Status `Other`; no passive notification arrived during the procedure.
- Once every read and subscription outcome was recorded, the diagnostic reported **Ready for one request**. The operator completed both confirmation stages and explicitly triggered the procedure once.
- The protected journal records one request-path entry, one consumed gate, one forwarding intent, and exactly one Write With Response submission containing exact bytes `00`. Its local procedure identifier was connection epoch 1, sequence 1.
- One well-formed Control Point indication containing exactly `80 00 01` arrived for that same procedure approximately 2.1 milliseconds before CoreBluetooth delivered the successful ATT write callback. Under the reviewed issue #72 policy, the early matching indication remained provisional and did not grant control by itself. The later matching ATT acceptance supplied the missing evidence, after which the diagnostic recorded one acknowledged outcome for opcode `0x00`.
- No malformed, mismatched, duplicate, negative, late, error, timeout, uncertainty, or unexpected-disconnect evidence was recorded.
- The operator explicitly requested disconnection. CoreBluetooth confirmed the disconnect about 34 milliseconds later, and no automatic reconnect occurred.
- After disconnection, the operator separately reported that there had been no belt movement.
- No second write, compensating command, target-speed or target-inclination request, Start, Stop/Pause, Reset, retry, reconnect, treadmill operation, workout execution, provider call, HealthKit operation, or Watch operation occurred.

## Conclusion and proof limit

The single correlated evidence chain—exact request `00`, successful ATT acceptance, and exact response `80 00 01` on the same connection epoch and procedure—satisfies the issue #51 acceptance rule. It establishes that the FR30z granted this client control permission for that connection at the FTMS protocol level.

The explicit disconnect ended that connection and its control permission. This result does not establish that control is currently held, that the belt or incline changed, that any target would be accepted or reached, or that Start, Stop/Pause, Reset, motion, safety-stop, automatic, or workout behaviour works. Every such procedure remains unresolved and requires its own separately reviewed slice and fresh operator authority.
