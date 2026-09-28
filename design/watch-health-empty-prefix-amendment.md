# Accepted decision: ending with no usable execution intervals

Status: operator selected zero-prefix discard on 28 September 2026; incorporated in contract revision 1.1, subject to reviewed PR merge. Issue #115 architecture gate, 28 September 2026. This decision preceded the #115 implementation in this change. It is documentary API evidence, not device observation.

## Conflict and evidence

The accepted v1 contract allows an incomplete Watch save with available metrics when no manifest was received, and after all intervals are rejected as outside the actual workout bounds. It also requires an exact interval/activity mapping with no extra activities and permits `intervalCount = 0`.

Apple's [Dividing a HealthKit workout into activities](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities) states that every saved workout has at least one associated activity, and HealthKit supplies one matching the workout type when the app adds none. Therefore a saved zero-interval workout cannot satisfy the current no-extra-activity rule. This is a documented cardinality conflict, not evidence that nonempty late-added activities fail.

The Xcode 27.0 Watch SDK exposes `addWorkoutActivity` before finish, a read-only activity list and activity end/metadata updates, but no activity-removal operation. `shouldCollectWorkoutEvents` controls session events; its documentation does not promise to suppress automatically supplied activities. Neither API inspection nor fixtures establish signed-device behaviour.

## Selected resolution: discard a zero-prefix workout

Normative text:

> During terminal assembly, if the materializable PacePrompt interval prefix is empty, end the existing session and discard its builder without calling finishWorkout. Persist a definite no-workout-saved result when discard is certain; otherwise retain save ambiguity. Only after definite discard, show “Workout not saved: no execution intervals were received or usable.” For uncertain discard, show an ambiguous save result, never definite absence. Do not synthesize an interval, recreate the builder or save on iPhone. A nonempty valid prefix may still save as incomplete under all existing rules. Local execution History and irreversible phone-save suppression remain unchanged.

This preserves the exact activity mapping, gaps, metadata interpretation and WeeklyHealthReport decoder boundary. It changes one product outcome: available Watch metrics alone do not produce a saved workout if no usable execution interval arrived. HealthKit may already have persisted sensor samples; discarding the workout does not promise deletion of those samples.

Required coordinated changes:

- Record a reviewed contract revision and update all zero-prefix/startup/Watch-End/timeout/out-of-bounds clauses consistently.
- Add a synthetic no-usable-interval trace with expected create <= 1, finish = 0, discard <= 1, iPhone save = 0 and no treadmill effects. Cover absent manifest, wholly invalid bounds and recovered empty prefix.
- Keep the accepted nonempty complete/incomplete fixture bytes unchanged; add the new fixture separately, recording the amendment commit for both producers and readers.
- Update #115, #116, parent #7 and WeeklyHealthReport #80 to distinguish no saved workout from an incomplete saved workout. No consumer implementation is authorised by this amendment.
- Check definite discard versus uncertain mutation/recovery results through fake ports; actual Apple behaviour remains a later signed-device acceptance item.

## Rejected alternative: preserve metrics-only incomplete workouts

Allow exactly one HealthKit-generated, unannotated same-type activity when the recognised PacePrompt interval prefix is empty. Define `intervalCount` as the count of recognised PacePrompt activities rather than all activities, require status incomplete and distance unavailable, and forbid interpreting the generated whole-workout activity as executed treadmill time. Add a reader rule and synthetic readback fixture for this exception, plus an explicit contract revision coordinated with WeeklyHealthReport #80.

This retains the original metrics-only save outcome but broadens the interchange/reader semantics and requires independent review of the generated activity's actual saved shape on signed devices. It must never permit arbitrary extra activities in a nonempty interval workout or claim a complete mirror.

## Decision boundary

Current AGENTS.md requires conflicting safety/product/slice boundaries to be surfaced before affected implementation. The frozen contract requires an explicit reviewed semantic revision. The operator selected discard; no fabricated zero-length activity or undocumented suppression switch is acceptable.
