# Console overrides and moving step time — policy revision 1

Authority: [issue #193](https://github.com/syamaner/paceprompt-ios/issues/193),
28 September 2026. This amends the
[FR30z execution profile](fr30z-physical-console-execution-profile.md) for the
user-authorised current-step override and ramp-countdown behaviour. It changes no
FTMS opcode, capability profile identity, persistence schema or Health interchange
schema. Physical behaviour still requires the acceptance procedure below.

## Architecture gate

The pure reducer owns a distinct movement-backed clock per planned step and a
bounded console-change candidate. Its monotonic event clock is injected; it has no
Bluetooth, HealthKit or UI dependencies. The orchestrator owns UTC interval
boundaries, persistence and command effects. Presentation projects those facts.
The shared pure interval-duration calculation is used by the producer, History
validator and Health payload projection. Transport and Watch adapters are unchanged.

Closed invariants remain exact capability increments, current connection epoch,
one unresolved command, ATT/FTMS/observation separation, no missed-step replay,
console Start/Stop authority, single Watch writer and iPhone-save suppression.
The new clock is transient execution state; recovery still interrupts, never
resumes a stored plan. No new provider or speculative policy abstraction is needed.

## Two different duration meanings

- The step clock begins on the first accepted complete positive-speed report after
  Begin workout. It includes initial, app-adjustment, planned-transition and resume
  ramps while accepted reports establish movement. Neither an override nor a
  target acknowledgement resets it.
- Freshness remains 2 seconds. At most that bounded interval after the last moving
  report is counted; excess gaps are excluded. Accepted stationary reports freeze
  the clock, including while Request Control is pending. Unavailable/malformed
  observations cannot bridge an unknown period. Wall-clock ticks alone never
  issue a planned transition.
- A due step advances once on fresh, settled joint evidence, after the current app
  target sequence has completed. While command/target confirmation or console
  settling is pending, show **Step time complete** and explain the wait. Preserve
  the normal procedure/observation timeout; do not cancel a procedure, replay
  overdue steps or carry excess time into the next step.
- A new planned step starts its own moving clock and clears both overrides. The
  original plan, step count and prescribed durations remain immutable.
- Settled interval time retains its old meaning. Local History `activeDuration`
  is the integer sum of closed settled intervals; ramps, candidate settling and
  pauses remain gaps. It can be shorter than the completed plan's moving time.
  The in-workout elapsed active field retains settled-time meaning; the countdown
  and plan progress use moving time. Shared summation floors with a 1-microsecond
  tolerance for Date representation near whole seconds, not missing evidence.

## App and console settings

App changes keep the existing acknowledged speed-then-inclination sequencing and
independent current-step axes. Rapid app changes update the pending choice without
competing with an unresolved procedure. A choice made while checking telemetry
remains pending until fresh movement allows its normal sequence to proceed.

Passive console inference is enabled only after the app's current sequence is
fully acknowledged and jointly observed, with no unresolved procedure. A candidate
must be an exact on-grid, in-range speed/incline pair reported at least three times
at distinct increasing timestamps spanning at least 1 second. Each gap is at most
2 seconds. A changed pair restarts the candidate, coalescing rapid button presses;
off-grid ramp values do not become targets. App input, lifecycle changes, pauses,
stale/unavailable evidence and step changes clear the candidate.

The confirming report installs only changed axes as `manualOverride` for the
current step and updates the observed target baseline. It sends no corrective
write and fabricates no protocol acknowledgement. An unchanged axis retains its
source. Returning to the old effective pair can reopen a settled interval without
creating an override. Return to plan remains an explicit app action.

The first divergent report closes the old settled interval at the bounded evidence
boundary. The confirming report opens another interval at its actual observation
time; never backdate through the ramp or debounce period. Adjacent identical
planned targets still get separate `planTransition` intervals with no command.

This is a deterministic settling policy, not proof of human intent from FTMS.
Overlapping console changes while an app command/ramp is unresolved cannot be
reliably distinguished from the app's ramp using current telemetry. They never
become an inferred console override or waive acknowledgement/timeout guards.
Physical acceptance must check settling reliability; do not claim this overlap
case has been solved by simulation.

## Health interchange and dependent work

Existing `segmentIndex` identifies the original planned step; `intervalIndex`
identifies its settled intervals. `manualOverride` includes accepted console and
app choices without claiming which input device produced a saved value. No new
metadata, raw telemetry or personal data is introduced. Watch manifests retain
immutable cumulative prefixes and the existing 64-interval bound; zero usable
intervals still discard. The Watch clock, HealthKit workout duration and local
settled duration remain distinct. Distance remains one accepted cumulative source
or unavailable, never integrated from the moving step clock.

[#115](https://github.com/syamaner/paceprompt-ios/issues/115) remains open for paired
device acceptance. [WeeklyHealthReport #80](https://github.com/syamaner/WeeklyHealthReport/issues/80)
must preserve repeated segment indices and the complete/incomplete interval rules,
without equating plan duration with HealthKit or local active duration. Its reader
is not implemented here. [#116](https://github.com/syamaner/paceprompt-ios/issues/116)
remains the cross-repository acceptance gate. Existing fixture bytes and revision
1.1 wire/metadata schema 1 are unchanged.

The user's build-15 report establishes user-observed HR/calorie display, a stalled
step and later workout presence in Health/Fitness. It does not establish the cause
of the separate Watch save-uncertain message, metadata integrity or distance-source
exclusion. This repair neither changes that save lifecycle nor uploads a release.

## Deterministic and physical acceptance

Reducer regressions cover independent axes, rapid changes, off-grid/duplicate
reports, acquisition pauses, stale gaps, app ramps, pending commands, due-but-unsettled
boundaries and clearing overrides. Orchestrator regressions cover three original
steps, interval splits, provenance, identical-target transitions and Health payload
eligibility. History tests cover fractional-duration agreement and rejection beyond
the rounding tolerance. Presentation tests distinguish countdown, settled elapsed
time and waiting status. Existing ownership/manifest tests remain mandatory.

For a separately authorised signed candidate and supervised physical session:

1. Record the exact build and use an operator-approved conservative three-step
   plan. Keep console Stop and safety key accessible; this document authorises no
   hardware operation or release.
2. After step two has settled, lower speed at the console. Observe the countdown
   continuing, actual readings changing and the stable override appearing without
   a corrective app write. Repeat a safe inclination-only change independently.
3. If safe, make several rapid console presses. Confirm one final settled interval
   rather than an interval per press. Repeat an app adjustment and observe moving
   ramp time count without resetting the countdown.
4. Observe step three begin once at its planned targets with both overrides cleared.
   A pending command or unsettled setting at zero must show the explicit waiting
   state; normal timeout/failure remains visible if confirmation never arrives.
5. Exercise a separately selected physical pause/resume. Countdown freezes while
   stationary and resumes with observed movement, including the restoration ramp.
   Never induce loss/stop/restart solely for a software test without operator scope.
6. End normally and privately inspect the original plan plus settled intervals.
   Run the [paired-device procedure](../docs/watch-health-interchange-runbook.md)
   to verify one Watch workout, metadata, single-source distance and the eventual
   WeeklyHealthReport readback. A Fitness entry alone is insufficient.

Record simulator, signed-device, physical and HealthKit-reader evidence separately.
Physical acceptance for this repair is unperformed until these observations exist.
