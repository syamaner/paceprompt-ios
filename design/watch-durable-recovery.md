# Watch durability and lifecycle amendment — revision 2

Authorised by the operator after build 16 startup timeout/disconnection and a stuck
Watch screen: durable recovery, explicit recording controls and reliable
background/foreground transitions. Source findings do not establish the complete
physical-device failure cause. This amendment extends the v1 interchange contract
without changing its wire vocabulary or Health metadata schema.

## Architecture gate

The Foundation-only lifecycle owns stop intent, bounded operation deadlines,
generation checks, stable identity and readiness. A narrow recording port proves
that the existing HealthKit primary has ended (or no active primary exists),
without creating or finishing a builder. Infrastructure owns SDK callbacks and
protected storage. Views render actions; they cannot access HealthKit or treadmill
controls. Time and new attempt identifiers are injected.

A force stop invalidates outstanding lifecycle work, ends the current primary and
preserves an uncertain save result. It never retries finish, deletes Health data,
saves on iPhone or controls the treadmill. A late finish may have saved the old
workout; no absence is claimed. Every awaited completion must be fenced before
changing the journal or issuing another builder operation.

After positively verified stop, the explicit **Prepare next workout** action
archives the old journal immutably, then persists a retired marker. Archive failure
or an unverified stop blocks readiness. Local journal version 2 accepts legacy v1
for recovery, retains at most 64 uncertain-attempt archives without automatic
eviction, and preserves file protection/backup exclusion. The next phone start
must reserve a new identity; the retired attempt is never replayed. Legacy orphaned
unbound state is archived under a fixed legacy key; conflicts fail closed.

**End recording** performs the normal single save/discard path. **Stop recording**
is the explicit escape action during connecting, recording, saving and recovery.
It requests Health recording termination and reports whether that was verified.
It does not terminate the watchOS process. Save/stop timeouts expose recovery
controls rather than a permanent busy screen; absence of a callback never proves
success. Confirmations explain possible incomplete/uncertain results and that the
treadmill must be stopped at its console. No Watch pause/resume button is added.

## Connection and application lifecycle

Install the phone mirroring handler at app construction, retaining it for the app
lifetime. Background/foreground changes do not destroy a live session, re-reserve
identity or restart execution. Apple HealthKit can redeliver the mirrored session
when the connection returns. Accept redelivery for the current bound attempt only
when activity/start provenance and the repeated `bound` identity match; never
create a primary to reconnect. A genuine disconnection remains incomplete on Watch.
No app-driven automatic remirroring or treadmill reconnect is introduced.

Retain cumulative closed intervals through a bounded reconnect window. Retry the
same unacknowledged manifest revision/content; acknowledge only the exact current
revision. Foreground entry refreshes deadlines and republishes state over the
existing mirror. A rebind must not invoke the initial execution-start callback.
Initial connection and reconnect are bounded separately; deadline expiry leaves
Health saving suppressed and directs the user to Watch controls. Phone cold restart
does not recreate or resume treadmill execution from mirroring callbacks.

## Required validation and exclusions

Contract tests cover delayed authorization/recovery/start/assembly/finish/stop,
force-stop double taps, failed archive/write, crash between archive and retirement,
legacy journal recovery, fresh-identity next attempt, late old callbacks after a new
attempt, connection loss/redelivery, duplicate bound/ack, missing manifest ack,
foreground after deadline, and unchanged single-writer/zero-prefix behaviour.
Native compilation and static dependency checks supplement tests; paired-device
background, lock, transport loss, force quit/relaunch and Health readback remain
explicit manual acceptance. Operating-system scheduling/delivery is not guaranteed.
No new permissions, provider calls, raw sensor logging, hardware operation, release
upload or WeeklyHealthReport implementation is included.

## Apple API basis

Apple documents early handler registration and OS reconnection with a redelivered
mirrored session in [workoutSessionMirroringStartHandler](https://developer.apple.com/documentation/healthkit/hkhealthstore/workoutsessionmirroringstarthandler).
This is distinct from the app creating or starting another primary or calling an
app-driven remirroring loop. The adapter uses Apple's active-session recovery to
probe the existing primary and observes its ended callback for verified stop.
Native compilation and fake-port tests cannot establish physical delivery timing.

## Startup and automatic shutdown repair (#203)

On 30 September 2026 the operator reported flickering startup/recovery screens and
Watch Stop returning to the same action after phone completion. A prior remote
phone observation showed stale capability evidence and an interchange timeout;
these observations do not identify the full device failure cause or confirm
installed build parity. This repair extends contract revision 1.3, retaining wire,
Health metadata and local journal versions and the original synthetic fixture bytes.

The architecture remains the same: the phone coordinator owns explicit Begin and
fresh capability validation, the pure interchange lifecycle owns identity and
bounded retries, the recording adapter sequences native stop proof before builder
assembly, and the SDK adapter owns session identity/callbacks. Presentation commits
one coherent Watch status/action snapshot and publishes metrics only when changed.
No new transport, permission, treadmill command or persistence schema is added.

Startup displays progress while reading capabilities or awaiting the Watch. Repeated
Begin taps cannot launch additional tasks. A Watch timeout displays an actionable
failure requiring cancellation of the old attempt. Foreground first restores the
binding's activity state, then refreshes unavailable preflight capabilities. This
refresh cannot arm, start or resume execution; a binding received while inactive
requires a subsequent deliberate Begin. If active arrives before protected data
becomes available, the later unlock event also triggers validation while active. A deferred launch is cancelled when its
coordinator attempt has been dismissed or replaced.

Phone end preparation, final manifest and final confirmation may be retransmitted
at most once per second within the original five-second deadline, always subject
to the unchanged send budget. Repeats keep the exact sequence/revision/content;
no retry extends a deadline or manufactures an acknowledgement. Large manifests
may exhaust the final-message budget and fall back to the existing incomplete
policy. A foreground app-lifetime timer services pending handoff after the workout
screen is dismissed; this is not durable background delivery or a new transport.
The terminal screen waits for the bounded interchange handoff before dismissal.
The phone's end-sent status remains explicitly separate from the Watch save result.

Normal Watch finalisation waits for the already-attached primary's exact ended
callback or ended state before builder assembly. Only an unattached adapter uses
active-session recovery probing. A request to end is not stop proof. Operation
deadlines and generation fences still reject missing and late completions. Late
native errors during requested end do not cancel the verifier; lifecycle errors
during stop, save or after a terminal outcome do not re-enter end or overwrite it.
A failed proof still times out and exposes explicit recovery, never fake success.

Once phone end preparation arrives, Watch shows Ending workout and removes the
normal End action, retaining emergency Stop. A successful save/discard removes both
recording controls and allows the next explicitly launched phone workout without
Watch recovery steps. Uncertain outcomes still require verified Stop and explicit
Prepare next workout; archival and permanent suppression remain unchanged.

Regression tests exercise native-end suspension/cancellation, callbacks during and
after verified stop/save, attached-primary proof without a recovery probe, terminal
message loss/retry/deadline, stable ending state, duplicate Begin, foreground refresh
and inactive binding without execution. Full local validation and independent review
are software evidence only. The paired-device checklist remains required.

Apple's [Watch workout example](https://developer.apple.com/videos/play/wwdc2021/10009/)
waits for session end before ending collection and finishing the builder.
[Active workout recovery](https://developer.apple.com/documentation/watchkit/wkapplicationdelegate/handleactiveworkoutrecovery())
addresses reattachment after a crash; an attached session already supplies the
identity needed to observe termination. Neither document proves this device report's
root cause.

## Recovery and next-attempt ordering repair (#212)

The build 18 operator report remains a failed paired-device attempt with an
unconfirmed cause. Synthetic regressions identified two independent ordering
failures, now repaired without changing wire, metadata or journal versions:

- While reattaching a retained recording, ingress and foreground publication wait
  for native recovery verification. No `bound` or manifest acknowledgement is sent
  during that wait. Retries after verification use the existing protocol budgets.
  Recovery reads the current same-generation journal after the await, preserving
  pause and disconnection state recorded by native callbacks. Stop/timeout cancels
  the gate; an older completion cannot clear a newer recovery gate.
- Discard requests native end asynchronously. Before a subsequent attempt resets
  the adapter, a previously created and discarded primary must pass the existing
  native stop verifier. The existing startup deadline remains in force. A failed
  proof or cancellation prevents reset, authorisation and new primary creation;
  late proof cannot revive a cancelled attempt. Saved workouts already pass native
  end verification in their assembly path.

The architecture remains the pure lifecycle for durable state and ingress, the
recording adapter for native-operation ordering, and the HealthKit adapter for
identity-specific termination proof. Regression tests suspend both boundaries and
exercise successful retry, callback state preservation, cancellation and failed
stop proof. Phone failure instructions now include the existing **Prepare next
workout** step after verified Stop when the previous result is uncertain. This does
not remove confirmations, automatically retire uncertain results, or permit a
replacement save. Unreadable retained state and native startup errors remain
separate investigation cases; these repairs do not establish the device root cause.

## Normal finish/save amendment (#212, revision 3)

[Watch finish/save and ordinary ending](watch-finish-save.md) supersedes the earlier
normal-save requirement to end the primary before assembly. Normal saving now
verifies stopped activity and persists its single save receipt before native end.
Emergency verified termination, archival, late-callback fences and uncertainty
rules remain unchanged. Saved next-attempt reset also verifies native end first.
The same amendment removes only redundant ordinary phone-end confirmations;
Watch emergency/recovery confirmations remain independently assessed.
