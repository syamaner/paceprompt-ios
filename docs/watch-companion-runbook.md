# Watch companion operation and evidence (#115)

Authority: [contract v1, revision 1.3](../design/watch-primary-health-interchange-contract.md), [architecture gate](../design/watch-companion-implementation-gate.md), and the operator's zero-interval discard decision. Minimum versions are iOS 17 and watchOS 10. This document describes the implemented path; software checks do not establish signed-device acceptance.

## Start and ownership

On iPhone, select a saved plan, prepare the treadmill and opt into **Record workout on Apple Watch**. Begin reserves a new identity in protected local storage before asking HealthKit to launch the Watch. Execution waits for a matching Watch binding response and then rechecks the existing treadmill readiness. The physical console and safety key remain authoritative; Watch recording never controls them.

The Watch owns one primary session and its associated builder. The phone owns execution and sends only closed intervals and accepted cumulative distance. HealthKit's mirrored-session channel is the sole transport. There is no app-driven automatic remirroring or treadmill reconnection. HealthKit OS redelivery may restore the same identity after activity/start/bind validation; it never restarts execution. Once reserved, that attempt can never use iPhone Health saving, even after timeout, disconnection, relaunch or an uncertain Watch result. Start a new deliberate attempt after ending an unavailable attempt; do not retry its identity.

The Watch displays recording status, elapsed recording time, available heart rate and estimated active energy with HealthKit provenance. Missing quantities remain unavailable. **End recording & save** ends Health recording only: it does not stop the treadmill. On iPhone, **Watch-owned; save result unavailable on iPhone** is intentional. Final acknowledgement confirms interchange, not a saved Health workout. The Watch retains the actual result locally.

## End, discard and recovery

The phone sends a cumulative final manifest only after the Watch establishes its recording end boundary. Confirmation within the bounded deadline permits complete status. Without confirmation, a valid nonempty prefix can be saved as incomplete, with distance omitted. Conflicts, malformed data, recovery and disconnection cannot manufacture completeness.

If there are no usable intervals, the Watch ends and discards the builder without calling finish. A definite discard displays **Workout not saved: no execution intervals were received or usable.** This is not a promise to delete sensor samples HealthKit may already have stored. Any uncertain mutation, finish result or receipt-persistence failure remains uncertain and never triggers a replacement workout or iPhone fallback.

Active-workout recovery attaches only to the existing primary session and builder, validates identity/start/activity/source provenance, and restores delegates. It does not recreate an ended or ambiguous builder. End a recovered recording on Watch. An uncertain journal is not cleared automatically. Use **Stop recording**, then **Prepare next workout** only after the app verifies that the existing HealthKit primary has ended or none is active. The old outcome is archived and remains uncertain; no Health workout is deleted or replaced, and its iPhone suppression stays permanent. A storage/probe failure keeps recovery blocked and offers another explicit stop/check. Do not reinstall or delete ownership files as a recovery step.

## Privacy and retention

The iPhone does not request Health reads. Its existing manual Health save remains available only for eligible iPhone-only records. The Watch requests heart-rate and active-energy reads, and workout/active-energy/optional walking-running-distance writes. HealthKit determines which samples are available; absence does not prove denial. Automatic distance is disabled before attaching the data source. Only a positive accepted final FR30z delta with write permission and proven source exclusion is eligible; unexpected automatic distance prevents saving that builder.

Both apps remain local-first. No account, analytics, telemetry, cloud transport, second connectivity channel or raw sensor log is added. HealthKit itself may sync Health data according to the user's Apple settings. Interval metadata includes prescribed/effective/observed treadmill values and provenance, not device identity, raw FTMS packets, command evidence, plan prose or raw heart-rate/energy samples. Other authorised Health readers can access saved workout metadata; review their permissions before export.

The Watch keeps one bounded, versioned active journal under Application Support, containing ownership, interval manifests and save receipt. Local journal v2 reads legacy v1 and adds explicit retirement, with up to 64 immutable uncertain-attempt archives and no automatic eviction. This is separate from the unchanged wire/Health metadata v1. A subsequent legitimate attempt replaces a saved/discarded or explicitly retired active journal. Retirement requires verified stop and a durable archive; it never retries the old summary. The phone retains one immutable reservation per Watch attempt, plus its version-3 local History record. Reservations have no deletion API and survive failed starts; do not remove them as troubleshooting. Both stores use atomic replacement, complete file protection and backup exclusion. Leftover staging files or unavailable protected data fail closed. Simulator tests exercise atomic contents and backup exclusion but cannot verify device file encryption; device builds require protection-attribute readback.

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

## Console adjustments and countdown (#193)

Use the [console and moving-clock policy](../design/console-overrides-and-step-clock.md)
for app/console overrides and the physical acceptance checklist. A settled console
change applies independently per axis for the current planned step; the next step
clears overrides. Countdown includes moving ramps without resetting. History and
Watch activities continue to contain settled intervals only. At zero, an unresolved
command or unsettled setting displays **Step time complete** with an explanation.

The build-15 operator subsequently reported Watch HR/calorie visibility and found
the workout in Health/Fitness. That is user-reported evidence only and supersedes
the earlier availability checkpoint for those narrow observations. The reported
step stall is tracked by #193; the Watch save-uncertain state remains a separate
unresolved observation. No raw values or diagnostics are published. Full signed
paired-device, metadata, distance-source and WHR acceptance remain outstanding.
Build 15 does not contain this repair. The subsequent #195 release makes it
available in internal TestFlight **1.0.1 (16)**: source
`f416d485a05128204a7788affc951934a042e381`, tag `testflight/1.0.1-b16`.
[The release receipt](testflight/README.md#console-override-internal-release-101-16-issue-195)
records accepted upload, Apple API processing and assignment to the unchanged
sole-tester group. Build-16 installation and physical acceptance remain unobserved.

For a later operator test, confirm build 16 on iPhone and the updated companion on
Watch, use a comfortable three-step plan, change speed or inclination during step 2,
and observe countdown during the ramp and progression into step 3. Confirm overrides
clear at the next planned step. End recording on Watch and inspect Health/Fitness
for the single workout; record any save-uncertain state separately. This is a test
procedure, not evidence that the behaviour has passed on real equipment.

## Recording controls and app lifecycle (#198)

Controls are above the metrics so recovery does not depend on scrolling beneath
calories. **End recording & save** uses the ordinary single save/discard path.
**Stop recording** is available while connecting, recording, saving or uncertain;
it stops Health recording, prevents subsequent save operations and checks native
termination. A finish already submitted may still complete. The confirmation
explicitly says the treadmill keeps moving until stopped at its console.
**Prepare next workout** preserves the uncertain result before allowing a new
iPhone attempt. None of these controls pauses or stops the treadmill.

Recovery, saving and verified stop have a 15-second operation watchdog. A timeout
exposes Stop recording again; it does not imply a saved/discarded result or stopped
HealthKit session. Background/foreground transitions preserve the live lifecycle;
foreground refreshes deadlines and resends current state. The phone registers
mirroring at launch and can accept OS redelivery for the same activity/start and
summary, within a 30-second reconnect window. The initial execution-start callback
is never repeated. Cumulative manifests retry unchanged revisions until acknowledged
within the existing rate/byte bounds. Real disconnect/recovery remains incomplete.
Cold phone relaunch never reconstructs or resumes treadmill execution.

If recovery says previous state is unavailable, an archive cannot be written or
retention is full, preserve it and report the status. Do not erase local files.
These software guarantees require paired-device acceptance for actual scheduling,
locked-device protected storage, OS reconnection and Health result visibility.

## Build 17 availability (#200)

Internal TestFlight **1.0.1 (17)** includes the #198 recording controls and app
lifecycle repair; build 16 does not. [Release run 36542470238](https://github.com/syamaner/paceprompt-ios/actions/runs/36542470238)
passed one upload, valid internal-only Apple processing and existing-group API
readback. Update both apps before following the [durability procedure](watch-health-interchange-runbook.md#durability-acceptance-198-unperformed-on-devices).
Tester installation, real background delivery/recovery and Health result readback
remain unobserved for build 17. The [release receipt](testflight/README.md#watch-durability-internal-release-101-17-issue-200)
records source, review, CI and archive evidence. No hardware was operated.

## Startup and shutdown repair (#203)

Normal use should need only the phone workflow: Begin, exercise, then end on phone
and stop belt motion at the console. Watch displays Connecting, Recording, Ending,
Saving, then its actual saved/discarded result. No separate Watch confirmation is
needed for a successful handoff. Stop recording remains an emergency recording-only
control; uncertain results still need verified stop and explicit retirement.

The phone now keeps a progress screen during startup checks, prevents duplicate
Begin work and rereads stale preflight evidence after foreground restoration without
starting execution. A timeout gives cancellation/recovery guidance. End messages
retry unchanged within their original five-second deadline/budget. The phone waits
for this handoff before enabling terminal dismissal and labels end-sent separately
from save success. Native Watch end proof precedes builder assembly. Late native
failure callbacks cannot cancel an in-progress Stop verification or overwrite a
completed result. A native stop timeout remains visibly unresolved.

The operator reported fiddly startup and a Stop confirmation loop after earlier
release availability. This is device feedback, not successful acceptance or proof
that all devices had the same installed build. The repair's tests, review and merge
are separate from a future signed release and the paired-device procedure below.

Repair validation: the final #203 complete local gate passed 490 production unit,
72 UI and 16 evaluation tests, unsigned Release including Watch, static analysis,
coverage and offline checks. Independent working-diff review cleared the repaired
edge cases before executable freeze. The PR records exact-head review and required
CI. These results do not establish repaired-device acceptance or release availability.

## Simulator investigation and bounded repairs (#212)

Build 18 was reported installed on both devices, but the operator's phone remained
in blocked Preflight while Watch reported an uncertain save. Issue #212 and signed
acceptance #115 remain open; do not treat the following simulator evidence as a
successful device retest or a Health save receipt.

Two deterministic failures were reproduced before repair: recovery could publish
`bound`/ACK before verifying the native primary and overwrite concurrent state;
starting again immediately after discard could reset before native end was proved.
The recovery/adapter ordering changes and regression tests are described in the
[durability amendment](../design/watch-durable-recovery.md#recovery-and-next-attempt-ordering-repair-212).

For native simulator work, create a dedicated iPhone/Watch pair and install both
apps. The usual unsigned full validation gate checks software but cannot exercise
HealthKit: the native service rejects missing HealthKit entitlements. Use a
separate simulator-only build with `CODE_SIGNING_ALLOWED=YES` and
`CODE_SIGN_IDENTITY=-`; preserve the repository's signing configuration and inspect
Xcode's simulated entitlement output rather than interpreting an empty ad-hoc
signature entitlement dictionary as the effective simulator entitlement. No Apple
Developer account change or distribution signing is required.

An isolated iOS/watchOS 26.5 pair with an ad-hoc signed Debug build reached the
native Watch Health permission sheet through the phone's normal Watch selection
and Begin path, using the existing synthetic treadmill UI fixture. Leaving that
sheet unanswered exceeded the startup deadline and reproduced Watch's uncertain
state and phone's blocked Preflight. A temporary Watch XCTest UI probe then
exercised **Stop recording → confirmation → Prepare next workout → confirmation**
and observed Ready. This establishes that recovery path only in that synthetic
experiment. No sensor, real treadmill, nonempty Health save or background delivery
acceptance follows. A first phone probe that did not successfully toggle Watch
selection is excluded from connection evidence.

When testing manually, confirm the Watch toggle is actually on and the preflight
shows **Apple Watch owns this recording** before Begin. Complete Health permissions
on Watch promptly. After an uncertain attempt, updating the app alone does not
retire its retained journal. Follow Stop recording on Watch, wait for verified stop,
then Prepare next workout if offered, and cancel the old phone preflight before
preparing again. Preserve uncertain outcomes; never uninstall or delete ownership
files to clear them. The phone now names that missing preparation step explicitly.


The #212 bounded repair's full local gate passed 494 production unit tests, 72 UI
tests, 16 evaluation tests, Release build including Watch, static analysis and
coverage. Offline checks passed 57 script, 41 corpus, 13 summary and 247 HostEval
tests, with 36 explicit HostEval skips for absent private evidence; all 24 accounting
helper tests passed. Independent pre-gate review found no remaining P1/P2 issues.
Permission-granted native startup and a nonempty Health save remain unverified;
the exact-head review/hosted CI and later device acceptance are separate gates.

## Ordinary finish and failure recovery

The [finish/save amendment](../design/watch-finish-save.md) keeps the normal Watch
session active until its workout receipt is saved locally, then ends the session.
Phone ending has one action: **Treadmill stopped — end workout** when direct
stationary observation is needed, or **End workout** when current stationary
evidence is already accepted. Stop the treadmill using its console first. Healthy
normal completion needs no Watch tap. Watch **Stop recording** is recovery, not a
save retry, and **Prepare next workout** preserves the previous outcome.

The new optional protected-journal failure stage distinguishes stopped-activity,
collection, assembly, finish and receipt errors. It contains no raw SDK errors or
sensor logging. Legacy journals remain readable; known pre-finish failure says
not saved, while uncertain finish/receipt outcomes remain uncertain. Full device
acceptance is still required; the current build 19 report failed saving.
