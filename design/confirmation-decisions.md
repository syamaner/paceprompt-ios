# Confirmation decisions — #211

Accepted scope: the operator's 3 October 2026 instruction to proceed with #211,
after reviewing remaining iPhone/Watch double confirmations. Baseline main
`5af321691c3a158a0e5ceb39308e0570d4df9cfd`; parent audit #208. This supersedes only
the recovery-tap rows of `watch-finish-save.md`. Ordinary finish stays automatic
from phone to Watch. No new release, hardware operation or Health readback belongs
to this implementation.

## Architecture and closed invariants

Views own the placement of explanations and dispatch existing intents. The phone
coordinator/reducer still owns stationary eligibility and records an observation
without converting an interrupted/failed workout into successful completion. The
Watch lifecycle still owns stop verification, durable archival/retirement,
generation fences and idempotency. No lifecycle, SDK, writer, wire, journal,
permissions, provider, persistence or treadmill-control change is needed.

Keep one Watch Health writer, permanent phone-save suppression, no save retry or
replacement after uncertainty, zero-usable-interval discard, native stop proof
before retirement and physical console authority. A labelled observation is
explicit human evidence; silence, elapsed time and disconnection never supply it.
No Undo is claimed. Removing an extra dialog does not make these actions reversible.

## Decisions

Tap counts exclude opening the relevant screen, physical console use and OS UI.
Frequency is qualitative product context, not measured analytics.

| Flow/context | Before → after | Decision and information/consequence | Preserved invariant / route |
| --- | --- | --- | --- |
| Phone ordinary end; every workout | 1 → 1 | Retain direct End workout or combined Treadmill stopped — end workout. Ending is not undoable; existing inline console guidance remains. | Exercise view → coordinator; accepted stationary evidence precedes end. |
| Phone interrupted/failed belt observation; recovery | 2 → 1 | Remove repeated attestation. The button itself says I can see the belt has stopped. A mistaken tap records false human evidence, so the explicit wording and console warning remain. There is no separate cancel step once tapped. | Existing confirmOperatorStationary intent; failure/interruption outcome preserved, no automatic resume/end. |
| Watch emergency recording stop; recovery or deliberate interruption | 2 → 1 | Remove modal; show Recording recovery and consequences directly above Stop recording. Normal End recording & save stays separately labelled. A mistaken stop can lose unsaved recording; it is not reversible. A submitted save can still complete. | Existing forceStop, immediate Stopping state, native stop verification and fenced late callbacks. Never stops belt or promises Health save. |
| Watch prepare next after verified stop; recovery | 2 → 1 | Remove modal; place known-not-saved or uncertain-outcome explanation immediately above Prepare next workout. This retires the attempt locally, not a Health deletion or save retry. | Existing archival, releaseStopped and durable retirement; uncertainty and phone suppression retained. |
| History iPhone-only Health save/retry; occasional external write | 2 → 2 | Retain exact-data/versioned-retry consent. It conveys a distinct write/replacement consequence; no reliable Undo. | Eligibility, consent and idempotency unchanged; absent for Watch/invalid ownership. |
| Delete saved plan; occasional irreversible action | 2 → 2 | Retain named-plan confirmation; no implemented restore. | Exact selected record and cancellation semantics unchanged. |
| Delete treadmill profile; occasional irreversible action | 2 → 2 | Retain named-profile confirmation; selection can clear, unrelated plans/History/connection unchanged. | Existing profile repository transaction. |
| Delete OpenRouter key; occasional irreversible action | 2 → 2 | Retain explicit credential-removal confirmation; no recoverable key copy or Undo. | Cancel/failure/confirmed removal remain distinct. |
| Save despite historical limit mismatch; occasional exception | 2 → 2 | Retain for this design: the dialog restates exact affected targets immediately before acknowledging the exception. Existing plan preview remains. Removing it needs a separate snapshot-bound inline acknowledgement design; defer that implementation. | Exact compatibility acknowledgement, no silent clamp, no live execution clearance. |
| Plan create/edit/imported proposal → review → save; routine authoring | 2 → 2 | Retain review then commit: the review reveals exact ordered targets/times. Save/Update commits; Back/Cancel preserves/discards the draft as already specified. | Deterministic validation and explicit canonical-plan acceptance. |
| Select planning profile → Done; routine authoring | 2 → 2 | Retain staged selection and Cancel. Immediate commit would change Cancel semantics. | No partly committed selection after cancellation. |
| Changed profile → compare → Update or Keep; occasional | unchanged | Retain the replacement decision; old/new evidence adds material information. | Explicit historical evidence replacement, not live readiness. |
| Prepare workout → checks → Begin; every workout | unchanged | Retain deliberate Begin and Watch ownership selection after current checks. | Background refresh/reconnect cannot begin execution automatically. |
| AI input → send disclosure → proposal review/save; optional | unchanged | Retain remote-recipient/spend consent separately from acceptance of an untrusted plan. | No request without new consent; no automatic save. |
| JSON export → selection → preview → Share; occasional | unchanged | Retain sensitive-data preview and OS destination choice. Combining pages is deferred beyond recovery. | Exact snapshot, temporary-copy protection and recipient disclosure. |
| Replace key → enter → Replace; occasional | unchanged | Retain editor commit/cancel; this is not a duplicate dialog. | Prior key retained on failure. |
| History View plan / Full plan → Done | unchanged | Retain dismissal; no workout or plan mutation. | No invented Repeat feature. |
| OS Bluetooth/Health permissions | unchanged | Outside app-owned duplication; keep required permission purposes and choices. | No new permission or suppressed consent. |

## Interaction contract

- Watch normal completion needs no Watch acknowledgement. End recording & save
  remains a one-tap manual normal finish. Emergency Stop is visually grouped under
  Recording recovery with its irreversible consequence shown before activation.
- Stop enters Stopping immediately; duplicate taps are rejected by the existing
  guard. While stopping, Prepare next is unavailable. Failure/timeout presents
  the actual unverified result and allows an explicit retry of stopping only.
- Prepare next is an explicit, separate action only after verified stop. It archives
  the old result before retirement. A second tap after retirement has no effect.
  Archive/release/write failure preserves a blocked state; never creates a new save.
- Background/foreground never supplies an implicit tap or confirmation. Existing
  deadlines, generation fences and foreground recovery remain unchanged. A late
  callback cannot affect a later attempt. No automatic retirement is introduced.
- The phone recovery button records only the observation. It disappears after
  acceptance; interrupted/failed outcome and unavailable ordinary end stay intact.
  Current moving evidence continues to reject stationary/end actions in the domain.
- All actions use standard accessible buttons, not long-press-only gestures.
  Existing identifiers remain. Text precedes each Watch recovery button in the
  scroll view; no custom confirmation overlay remains on phone.

## Validation and paired-device procedure

Complete `scripts/validate_local.sh` passed on 3 October 2026 with Xcode 27.0
(27A266a), SDK 27.0 and the dedicated iPhone 17 Pro / iOS 26.5 simulator: 517 app
unit tests, 72 UI tests and 16 evaluation-target tests, zero failures. Debug and
Release simulator builds including Watch, static analysis, coverage export,
built-bundle safety/metadata checks, offline repository tests and 24 accounting
helper tests passed. HostEval reported 247 tests with 36 private-evidence skips.
All 417 frozen executable/test/build inputs remained unchanged after validation.
Changed-document local links and `git diff --check` passed. Private evidence:
`/private/tmp/pp211-complete-gate.log` and `/private/tmp/pp211-complete-gate/`.
These checks do not establish interactive Watch/VoiceOver or device acceptance.

Focused validation passed 114 Watch contract tests and all 20 exercise UI tests.
A synthetic retained-uncertainty journal rendered the new Recovery heading on a
Watch SE 3 40 mm / watchOS 26.5 simulator. Status text wraps; the recovery controls
are below the first viewport in the existing scroll view. This partial capture
(`/private/tmp/pp211-watch-recovery.png`) is not proof of button visibility after
scrolling or an interactive Watch/VoiceOver pass. No workout or Health save was
started. The task-owned Watch simulator was shut down afterward.

Synthetic checks cover normal end and recovery in portrait/landscape, unchanged
outcomes, repeated Watch stop/retirement, premature retirement, delayed native
callbacks, stop timeouts, storage failures and foreground recovery. These are
software evidence; native Watch VoiceOver/scroll and paired-device ergonomics
remain separate acceptance.

For a later released candidate, confirm both companions use that build, then:

1. Complete a short nonempty workout; stop the belt physically and end on phone.
   Leave Watch untouched. Require its actual saved result and exactly one Health
   workout; check local History separately.
2. In a separately selected recovery scenario with the belt physically stopped,
   read the Watch inline consequence and tap Stop recording once. Require visible
   progress followed by verified stop or truthful failure. No second dialog.
3. Once offered, tap Prepare next workout once. Require Ready for your next workout,
   with the old outcome retained; no replacement Health workout. Do not manufacture
   an uncertain device save solely to exercise this path.
4. For a naturally interrupted phone workout, observe the stopped belt and tap
   I can see the belt has stopped once. Require the interrupted/failed outcome to
   remain; no second panel or automatic resumption.
5. Check small-Watch scrolling and VoiceOver labels/order, and foreground/background
   during recovery. Report build, coarse state and tap sequence without committing
   personal metrics or identifiers. Do not infer Health absence from uncertain UI.

#115/#212, #116 and WeeklyHealthReport #80 remain device/interchange acceptance;
#210 retains diagnostics placement. This decision resolves the source audit's
flow dispositions; it does not claim all device acceptance or deferred redesigns.
