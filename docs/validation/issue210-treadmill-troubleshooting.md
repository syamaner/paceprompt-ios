# Treadmill setup and troubleshooting — #210

Authorised on 3 October 2026, from main
`654fbc34b0e71cc0a442b586d156ef2596ae65b2`. Parent audit: #208.

## Information hierarchy and architecture

Home → Set up treadmill retains Bluetooth/connection status, errors, deliberate
scan/select/disconnect, saved treadmills, supported speed/incline limits and
reading availability. Raw identifiers, bytes, subscription detail and capture
controls move behind Treadmill → Troubleshooting. Standard navigation provides
a labelled back button; there is no additional confirmation or automatic action.

Both views observe the same existing `TreadmillSetupViewModel`. Views format
presentation and dispatch its existing intents. Capture buffers, parsers,
connection lifetime, clocks, domain rules and execution binding are unchanged.
No new abstraction, persistence or platform dependency is needed for this split.
The DEBUG-only synthetic client remains behind the existing test launch switch.
The actual troubleshooting route is present in Release too.

## Closed contracts

- A notification subscription means updates are enabled, not that a fresh value
  has arrived. The primary screen says Ready to receive updates and explains this
  limit. Inactive, connecting, failed and unavailable streams remain distinct.
- Unreadable limits remain unavailable as limits, with reconnect guidance; exact
  parser reasons and raw bytes remain in Troubleshooting. No stale values become
  current evidence and no data is clamped or invented.
- Treadmill console/safety key authority, existing commands, no automatic
  reconnection and workout checks are unchanged. Navigation invokes no client
  or capture action. Diagnostic human observations never become stationary proof
  or permission to start/end execution.
- Existing in-memory bounds remain 100 recent displayed packets and 10,000
  capture records, with explicit dropped-record warnings. Copy/share remain
  deliberate; no automatic persistence, export or transmission is introduced.
- Troubleshooting discloses names, device identifiers, timestamps and readings
  before copy/share. Choose recipients deliberately. Clear retains its existing
  scope. Timing capture and recent-packet capture remain separate reports.
- Product buttons say Share/Copy reading capture. Historical issue numbers in
  report headers and protocol fields remain intact for existing analysis tooling.

## Current support procedure

1. Open Home → Set up treadmill. Check Bluetooth/connection and the supported
   limits. For a read failure, follow the displayed connection guidance.
2. Open Troubleshooting deliberately. Read the capture disclosure first.
3. Reading capture contains application state, capacity/overflow and explicit
   human-observation markers. These markers cannot verify physical belt state.
4. Copy or share the reading capture only when intended. Device details,
   capability bytes, subscription outcomes and discovered characteristics remain
   below it; the recent packet log retains its own copy/share/clear controls.
5. Use Back to return to setup; the shared connection and capture are preserved.
   Opening/closing this screen never scans, reconnects or starts a workout.

The [historical freshness procedure](fr30z-treadmill-data-freshness-procedure.md)
remains a record of issue #52's then-current build and authority. Its historical
Issue #52 capture action is now Reading capture under Troubleshooting; this does
not renew physical-session authority or alter the report format.

## Validation and remaining acceptance

Focused validation passed all 10 Home UI tests on a task-owned iPhone SE
(3rd generation), iOS 26.5 simulator. The final tests include automated sufficient
accessible-description and trait audits on setup/troubleshooting, back navigation
and accessibility XXXL text. Inspected synthetic screenshots confirm large text
wraps and scrolls on the small screen; copy remains reachable. An earlier expanded
launch-setting name did not actually enlarge text and is not counted as large-text
evidence. The corrected value is `UICTContentSizeCategoryAccessibilityXXXL`.
Private evidence: `/private/tmp/pp210-small.xcresult`, `/private/tmp/pp210-small.log`
and `/private/tmp/pp210-small-images/`.

The complete local gate passed on 3 October 2026 with Xcode 27.0 (27A266a),
SDK 27.0 and the dedicated iPhone 17 Pro / iOS 26.5 simulator: 517 unit tests,
76 UI tests and 16 evaluation-target tests, zero failures. Release simulator build,
static analysis, coverage, built-bundle safety/metadata and 24 accounting tests
passed. Offline checks passed 57 release, 41 scorer, 13 summary and 247 HostEval
tests (36 private-evidence skips). All 417 frozen executable/test/build inputs
remain identical. The Release binary contains the troubleshooting view/actions
and excludes the new DEBUG fixture routes. Private complete gate:
`/private/tmp/pp210-complete-gate.log` and `/private/tmp/pp210-complete-gate/`.
Changed-document local links and `git diff --check` passed. Synthetic UI checks cover
primary/secondary separation, supported/unreadable limits, stream availability,
explicit copy and back navigation, large text and disabled observation while
not connected. No hardware operation or release upload belongs to this slice.
Interactive VoiceOver and signed-device ergonomics remain separate acceptance;
automated labels/navigation and screenshots are not a VoiceOver listening test.
