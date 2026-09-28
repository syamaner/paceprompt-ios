# Watch companion operation and evidence (#115)

Authority: [contract v1, revision 1.1](../design/watch-primary-health-interchange-contract.md), [architecture gate](../design/watch-companion-implementation-gate.md), and the operator's zero-interval discard decision. Minimum versions are iOS 17 and watchOS 10. This document describes the implemented path; software checks do not establish signed-device acceptance.

## Start and ownership

On iPhone, select a saved plan, prepare the treadmill and opt into **Record workout on Apple Watch**. Begin reserves a new identity in protected local storage before asking HealthKit to launch the Watch. Execution waits for a matching Watch binding response and then rechecks the existing treadmill readiness. The physical console and safety key remain authoritative; Watch recording never controls them.

The Watch owns one primary session and its associated builder. The phone owns execution and sends only closed intervals and accepted cumulative distance. HealthKit's mirrored-session channel is the sole transport. There is no automatic remirroring or treadmill reconnection. Once reserved, that attempt can never use iPhone Health saving, even after timeout, disconnection, relaunch or an uncertain Watch result. Start a new deliberate attempt after ending an unavailable attempt; do not retry its identity.

The Watch displays recording status, elapsed recording time, available heart rate and estimated active energy with HealthKit provenance. Missing quantities remain unavailable. **End recording** ends Health recording only: it does not stop the treadmill. On iPhone, **Watch-owned; save result unavailable on iPhone** is intentional. Final acknowledgement confirms interchange, not a saved Health workout. The Watch retains the actual result locally.

## End, discard and recovery

The phone sends a cumulative final manifest only after the Watch establishes its recording end boundary. Confirmation within the bounded deadline permits complete status. Without confirmation, a valid nonempty prefix can be saved as incomplete, with distance omitted. Conflicts, malformed data, recovery and disconnection cannot manufacture completeness.

If there are no usable intervals, the Watch ends and discards the builder without calling finish. A definite discard displays **Workout not saved: no execution intervals were received or usable.** This is not a promise to delete sensor samples HealthKit may already have stored. Any uncertain mutation, finish result or receipt-persistence failure remains uncertain and never triggers a replacement workout or iPhone fallback.

Active-workout recovery attaches only to the existing primary session and builder, validates identity/start/activity/source provenance, and restores delegates. It does not recreate an ended or ambiguous builder. End a recovered recording on Watch. A quarantined journal is deliberately not cleared automatically; there is no user recovery/reset UI in this slice. Preserve the state for a separately authorised investigation rather than deleting ownership markers or assuming no Health workout exists.

## Privacy and retention

The iPhone does not request Health reads. Its existing manual Health save remains available only for eligible iPhone-only records. The Watch requests heart-rate and active-energy reads, and workout/active-energy/optional walking-running-distance writes. HealthKit determines which samples are available; absence does not prove denial. Automatic distance is disabled before attaching the data source. Only a positive accepted final FR30z delta with write permission and proven source exclusion is eligible; unexpected automatic distance prevents saving that builder.

Both apps remain local-first. No account, analytics, telemetry, cloud transport, second connectivity channel or raw sensor log is added. HealthKit itself may sync Health data according to the user's Apple settings. Interval metadata includes prescribed/effective/observed treadmill values and provenance, not device identity, raw FTMS packets, command evidence, plan prose or raw heart-rate/energy samples. Other authorised Health readers can access saved workout metadata; review their permissions before export.

The Watch keeps one bounded, versioned journal under Application Support, containing ownership, interval manifests and save receipt. A subsequent legitimate attempt replaces a terminal saved/discarded journal; uncertain state blocks replacement. The phone retains one immutable reservation per Watch attempt, plus its version-3 local History record. Reservations have no deletion API and survive failed starts; do not remove them as troubleshooting. Both stores use atomic replacement, complete file protection and backup exclusion. Leftover staging files or unavailable protected data fail closed. Simulator tests exercise atomic contents and backup exclusion but cannot verify device file encryption; device builds require protection-attribute readback.

Watch-owned History is schema 3 with an explicit ownership envelope. Missing/invalid new ownership is rejected, never treated as a legacy phone record. Version-1/2 records retain their prior interpretation. The existing JSON export accepts schema 2 only; schema 3 is unavailable rather than downgraded. No Watch sensor samples are copied into local History.

## Validation and remaining acceptance

Run `python3 scripts/verify_watch_boundaries.py`, `python3 -B -m unittest discover -s scripts/tests -v`, the focused `WatchInterchangeTests`, ownership/History/execution regressions, and then the complete `scripts/validate_local.sh` gate on final executable inputs. Shared synthetic complete/incomplete fixtures are bundled only into the test target. Tests exercise production lifecycle/assembly adapters through fake SDK-operation ports, including delayed callbacks, storage failure, zero-prefix discard and single-writer suppression. Native SDK compilation and an idle Watch simulator render are separate evidence levels.

Use the [paired-device acceptance procedure](watch-health-interchange-runbook.md) for later signed-device permission, real mirroring, sensors, builder activity readback, metadata, distance-source and recovery checks. Physical FR30z operation remains #116. WeeklyHealthReport extraction remains #80. No simulator or fake test substitutes for those observations. The [release setup runbook](testflight/setup.md#watch-companion-release-boundary-115) records the strict two-bundle signing policy. Separately authorised #188 completed Watch App ID/profile setup and internal TestFlight 1.0.1 (15); see the [release receipt](testflight/README.md#watch-internal-release-101-15-issue-188). Apple processing and internal-group assignment do not establish installation or any paired-device acceptance row.

## Recorded software evidence

The #115 final local gate on Xcode 27.0 (27A266a), iOS 26.5 simulator, passed 437 production unit tests, 72 UI tests, 16 developer-only evaluation tests, unsigned Release build (including Watch), static analysis and coverage. Offline HostEval ran 247 tests with 36 explicit skips for absent ignored private evidence; all 46 repository script tests and 24 accounting-helper tests passed. The independent working-diff review found no remaining P1/P2 findings after repairs. The PR records the exact committed-head review and required hosted CI. Earlier failed focused runs and the deliberately superseded full run are not acceptance evidence.

An isolated watchOS 26.5 simulator installed and displayed the compiled idle Watch UI. This did not exercise a real mirrored HealthKit session, permission prompt, sensor data or save. All signed-device, HealthKit readback, physical FR30z and WeeklyHealthReport rows in the acceptance runbook remain unperformed. No signing or release acceptance is implied.


## Internal release availability (#188)

Internal TestFlight 1.0.1 (15) uses reviewed source
`796819b21382ac7dd038fb989e79e1352aaf06ca` and immutable tag
`testflight/1.0.1-b15`. Its protected hosted run verified both signed apps, uploaded
once, confirmed Apple processing `VALID` and observed assignment to the existing
sole-tester internal group. Tester visibility/install/launch and all signed-device
HealthKit, physical FR30z and WeeklyHealthReport acceptance remain unperformed.
The earlier software-only evidence above remains scoped to its original slice.
