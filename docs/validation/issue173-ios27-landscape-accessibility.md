# Issue 173: iOS 27 landscape accessibility

## Diagnosis and bounded repair

Baseline: main `c40c267ec2c286c28a0acf16c2d965eacd4aedbd`, Xcode 27.0
(27A266a), fresh iPhone 17 Pro / iOS 27.0 simulator. The unchanged End,
operator-stationary and reference-geometry tests failed their original
`isHittable` assertions. Evidence: `/private/tmp/pp173-baseline.xcresult`.
The live issue also records the alternate-size failure and unchanged iOS 26.5
passes; build 12 release acceptance remains the previously completed iOS 26.5 gate.

A temporary diagnostic against unchanged app code recorded all three buttons as
unhittable, then coordinate-tapped their centres. Full plan opened its sheet;
End and stationary observation opened their separate confirmation panels.
Evidence: `/private/tmp/pp173-coordinate.xcresult`, synthetic accessibility trees
in `/private/tmp/pp173-coordinate-attachments`. These results establish simulator
touch interaction, not physical-device or assistive-technology acceptance.

The accessibility trees exposed the geometry markers as independent accessible
sibling leaves, with screen/column/action-region frames overlapping controls.
Replacing them with containing accessibility groups made the original standard
taps and hittability assertions pass. Removing only `contentShape` or adding
`accessibilityRespondsToUserInteraction(false)` did not fix the failures.
A single-child wrapper collapsed nested region identifiers; a hidden zero-sized,
noninteractive child preserves distinct group identity without contributing size.
The group also explicitly uses `contentShape(.accessibility, Rectangle())`:
without it, accessibility bounds follow the union of child content and vary
slightly between workout states. The original exact cross-state geometry test
caught that regression; the explicit accessibility shape makes all ten states
pass without changing touch geometry or weakening any assertion.

The repair changes only the presentation helper. Domain rules, execution,
Bluetooth, action handlers, confirmation wording, layout proportions, dimensions
and minimum button sizes remain unchanged. Existing assertions are retained.
The new regressions require region/button ancestry, standard Full plan tapping,
confirmation cancellation, and rejection of an underlying Full plan coordinate
tap while confirmation is visible. Tapping the opener again would not prove
interception because it could merely reopen the same panel; independent review
identified and corrected that diagnostic weakness.

A newly introduced diagnostic expecting an underlying button to become
`isHittable == false` during confirmation failed on iOS 27. The boundary is
therefore verified through the distinct observable plan-sheet side effect,
rather than that unsupported XCTest assumption. No original assertion changed.

This is evidence of an accessibility-tree modelling defect exposed by iOS 27
XCTest hit testing, not evidence that ordinary touch actions were broken.
VoiceOver/Switch Control and physical-device interaction remain unperformed in
this investigation. No treadmill operation or release upload occurred.

The synthetic reference screenshots before and after the repair are byte-identical:
SHA-256 `938e64d97b65c22ddaa5fcd3aefac79cf15cdffa86a0e4e430bd21f055113bf4`.
They were visually inspected as well as hashed. The original geometry assertions
also pass, including the fixed 57/43 columns, 72/28 right-side regions and minimum
control sizes. This evidence covers the tested reference fixture, not every device.

## Validation

The initial full iOS 27 run (`/private/tmp/pp173-ios27-full-gate`) is superseded:
it caught the container-bounds regression above and a separate unchanged
PlansFlow text-editing failure finding the Select All menu item. Its passing
unit/offline cases do not certify the final candidate. The unchanged plan-editing test passed on its isolated iOS 27 rerun. This supports
a transient test failure; no cause or unchanged-main reproduction is claimed.

Final iOS 27 suite: 19/19 exercise UI tests, plus the unchanged isolated
plan-editing test (20/20 total), `/private/tmp/pp173-ios27-final-exercise.xcresult`.
This includes all four original failures, all ten landscape state snapshots,
portrait flows, Dynamic Type, reduced motion and the three new regressions.
Independent read-only review found no actionable defects at view SHA-256
`732c898921ccd240dbf47364dbd24c37c48fa7eaea3a9778a239dea015b5e4c9`
and UI-test SHA-256
`922a6bc305b0aea2a7cfd0f531c7e8197acc439a1d122ae948ac8b5d6d09e56f`.
The final reference screenshot has the same SHA-256 as the baseline above.

Complete final iOS 26.5 gate passed with Xcode 27.0 (27A266a): 438 production
tests (372 unit, 66 UI), 16 evaluation tests, unsigned Release simulator build,
static analysis, production coverage, corpus/resource/release/boundary checks,
247 host-evaluation tests and accounting-helper tests. Evidence:
`/private/tmp/pp173-ios26-final-full-gate`.
The 450 tracked regular-file inputs (ledger excluded) in
`/private/tmp/pp173-final-gate-inputs.json` still match the tested candidate.
All evidence is simulator/static; physical-device and assistive-technology
acceptance remains separate. Independent final committed-head review and
required GitHub checks precede the protected PR merge.
