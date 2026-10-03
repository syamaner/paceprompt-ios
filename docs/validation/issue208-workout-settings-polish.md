# Workout captions and grouped privacy — #208

Authorised on 3 October 2026 as a small addition before the next release.
Baseline main: `183075468c4be7466b48d20b7d24e8c4e2f4ffad`.

## Scope and architecture

Remove Animation off / Gentle status animation captions from the portrait and
landscape workout actions. Keep console guidance, override status, workout state
and controls. The checking icon's pulse still requires `!shouldReduceMotion`;
the existing environment/override resolution is unchanged. Removing explanatory
copy does not disable support for Reduce Motion.

Settings → Privacy now groups the existing disclosure into On this device,
AI processing and Apple Health. All nine original sentences are retained verbatim,
with no new permission, provider request, Health action or privacy claim. The
Apple Health group separates iPhone saving, Watch ownership and empty-workout
behaviour into readable paragraphs. Headings expose the accessibility header
trait; paragraphs wrap vertically without a line limit.

Views continue to own presentation. Domain, adapters, storage, consent, execution,
Bluetooth and Health ownership are untouched. No new architecture seam is needed
for this fixed presentation change. No hardware operation or release upload.

## Disclosure inventory

| Group | Retained meaning |
| --- | --- |
| On this device | Saved plans stay on this device; the key is in its Keychain; no analytics. |
| AI processing | Workout text goes to OpenRouter and OpenAI only after disclosure and agreement for each request; no zero-retention guarantee. |
| Apple Health — iPhone | No iPhone Health reading; iPhone-only saves require Save to Apple Health. |
| Apple Health — Watch | Separate available heart-rate/active-energy reads; workout, execution intervals and available treadmill distance saved by Watch; phone saving disabled for that attempt. |
| Apple Health — empty workout | No workout without usable step details; heart-rate/calorie samples may still remain. |

## Validation

Four focused UI tests passed on iPhone 17 Pro / iOS 26.5; grouped privacy at
accessibility XXXL and workout landscape also passed on iPhone SE 3 / iOS 26.5.
Automated sufficient-description/trait audits passed. The inspected small-screen
capture confirms enlarged wrapped text in the scrollable disclosure. Private
results: `/private/tmp/pp208polish-focused.xcresult`,
`/private/tmp/pp208polish-small.xcresult` and `/private/tmp/pp208polish-small-images/`.

Complete local gate passed on the frozen candidate: 517 unit tests, 78 UI tests,
16 evaluation-target tests, Release simulator build and static analysis. Supporting
checks passed: 57 release-script tests, 41 scorer tests, 13 summary tests,
247 HostEval tests (36 expected private-evidence skips) and 24 accounting tests.
All 417 frozen executable/test/build inputs were unchanged. Private gate evidence:
`/private/tmp/pp208polish-complete-gate` and its adjacent `.log` file.
`git diff --check` passed. Source comparison confirms all nine
original privacy sentences remain, along with the actual Reduce Motion predicate.
Synthetic UI coverage checks portrait reduced-motion status and landscape console
guidance without the captions, plus grouped disclosure content, large text,
scrolling and automated accessibility description/trait audits.

These checks do not establish a VoiceOver listening session, installation,
physical treadmill/Watch behaviour or acceptance of a new TestFlight build.
#208 remains open for broader runtime/device audit reconciliation. This change
and #210 are ready to be included in a separately recorded release after merge.
