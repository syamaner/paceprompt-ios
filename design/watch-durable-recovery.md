# Watch durability and lifecycle amendment — revision 1

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
