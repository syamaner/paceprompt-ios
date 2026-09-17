# Internal TestFlight release

Issue #120 adds a separate tag-triggered release route for the existing
`com.otherweather.PromptPace` app. It does not submit to App Review, create an
external tester group, publish the app or run the complete simulator suite in
GitHub Actions.

## Repository controls

- `testflight/<marketing-version>-b<build>` is a lightweight tag on a reviewed
  pull request merge commit in the first-parent history of `main`. The tag's
  version and build must match both production project configurations.
- The merge commit message records `Exact-head-review: <reviewed head SHA>`
  after an independent review of that SHA. The guard checks that marker, the
  PR head as the merge commit's second parent, identical merge/PR-head trees
  and fast `main` CI on the merge SHA. The marker binds the reviewed content;
  the operator is responsible for retaining the actual independent review
  evidence, as this single-collaborator repository has no separate GitHub
  reviewer account.
- Repository tag rulesets restrict creation to repository admins and prohibit
  tag updates and deletion. The release guard also checks the current remote
  tag, merged PR and successful fast `main` CI on the exact SHA.
- The `internal-testflight` environment permits only `testflight/*` tags,
  requires approval by `syamaner` for **every** run and disables admin bypass.
  Self-review is permitted because the repository's release operator is the
  sole required reviewer. Changing this policy needs a deliberate repository
  settings update.
- The environment variable `EXPORT_COMPLIANCE_TAG` must equal the exact tag
  after the operator has made that build's export-compliance judgement. It is
  empty until then. For 1.0 (2), the operator judged the app's encryption exempt
  on 17 September 2026. Both production configurations now set
  `ITSAppUsesNonExemptEncryption=NO`; the release checks the signed app's
  `Info.plist` contains Boolean false. This records the operator's decision,
  not an independent legal determination.

Before creating the tag, retain the complete local gate and independent review
for the final executable/build-input tree; merge the reviewed PR; wait for fast
`main` CI to pass. Do not tag an unreviewed change or reuse a version/build.
The first candidate is `testflight/1.0-b2`; 1.0 (1) already exists in App Store
Connect.

## Apple access

Xcode's command-line automatic signing requires a key issuer ID; Apple's
individual keys have none and cannot use provisioning API endpoints. This
workflow therefore requires the operator's separate security approval for a
dedicated App Manager team API key. Apple lists this role for uploading builds
and assigning a group to a build. Apple applies a team
key to **all apps** at that role, so it cannot be limited to PacePrompt alone.
Store `ASC_KEY_ID`, `ASC_ISSUER_ID` and the base64-encoded `.p8` as
**environment secrets**; the latter is named `ASC_API_KEY_P8_B64`. Store
`ASC_TEAM_ID`, `ASC_INTERNAL_GROUP_ID` for the existing sole-tester group, and
`ASC_INTERNAL_TESTER_ID` for its authorised tester as environment
variables. Enter the
private key in GitHub's secret form, never in chat, a PR, a repository file or
an Actions log. The workflow
writes it to a restricted temporary file and removes it on exit. It creates
no IPA, archive, signing or credential artifact.

The workflow attempts Apple-managed automatic signing. If Xcode requires a
distribution certificate/profile or a role broader than approved, stop and agree
that arrangement with the operator before provisioning it. Do not silently
switch signing methods.

## Workflow and evidence

The unprivileged job checks the tag and source without Apple secrets. After
environment approval, the macOS job rechecks them, pins Xcode 26.6
(`17F113`), checks the export-compliance tag and Apple account/group/build
identity, and archives Release. Export uses `app-store-connect`,
`manageAppVersionAndBuildNumber=false` and
`testFlightInternalTestingOnly=true`. Before the single upload attempt, the
workflow checks the IPA's version/build, bundle ID, purpose strings, privacy
manifest, HealthKit entitlement, team, Apple Distribution signature and
`get-task-allow=false`. It records the source SHA and IPA SHA-256 without
retaining the IPA.

After an accepted upload, the workflow waits for Apple processing and checks
that the resulting build is `INTERNAL_ONLY` and ready for internal testing.
It then adds only the existing sole-tester group and reads back the assignment.
An upload failure or processing timeout is ambiguous: inspect App Store
Connect before any manual retry or new tag. A missing-compliance state requires
the operator's decision in App Store Connect; no API retry is automatic.

The workflow's claims are separate: signed/exported, upload accepted, Apple
processed, group assigned, tester-visible and installed on an iPhone. The
tester must verify visibility in TestFlight; installation, HealthKit and
physical FR30z behaviour require their own evidence.

Run the dry checks without Apple access:

```sh
python3 -B -m unittest discover -s scripts/tests -v
actionlint .github/workflows/ci.yml .github/workflows/internal-testflight.yml
python3 -B scripts/verify_release_configuration.py
```

The release job has no public App Review, external testing or treadmill path.
