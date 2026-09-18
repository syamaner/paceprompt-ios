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
  after the operator has made the export-compliance judgement. The operator
  confirmed on 18 September 2026 that this app uses no non-exempt encryption
  and that the judgement remains in force while its encryption behaviour is
  unchanged. Set the variable for each authorised fresh tag; change the
  declaration if the app's encryption behaviour changes.
  Both production configurations set
  `ITSAppUsesNonExemptEncryption=NO`; the release checks the signed app's
  `Info.plist` contains Boolean false. This records the operator's decision,
  not an independent legal determination.

Before creating the tag, retain the complete local gate and independent review
for the final executable/build-input tree; merge the reviewed PR; wait for fast
`main` CI to pass. Do not tag an unreviewed change or reuse a version/build.
Version 1.0 (1) already exists in App Store Connect. The immutable
`testflight/1.0-b2` run failed at cloud-signing export before upload. Read-only
Apple inspection confirmed no 1.0 (2) build. Do not rerun or move that tag.
The authorised replacement `testflight/1.0-b3` passed source and Apple
preflight, then failed while preparing manual signing assets, before archive
or upload. Read-only Apple inspection confirmed no 1.0 (3) build. Do not
rerun or move either tag. A further candidate needs a fresh build number,
reviewed merge, complete gate and environment approval.
The authorised `testflight/1.0-b4` reached a signed Release archive and
internal-only App Store export, then the artifact guard rejected its
entitlements output as an invalid plist before the upload command. Read-only
Apple inspection confirmed no 1.0 (4) build. Do not rerun or move that tag.
A new candidate requires a new build number and the same review, gate, merge
and per-release approval.
The authorised `testflight/1.0-b5` passed the signed-entitlements checks,
then failed while extracting the exported app's signing certificate before
upload. Read-only Apple inspection confirmed no 1.0 (5) build. Do not rerun
or move that tag. The authorised `testflight/1.0-b6` passed the certificate
guard and Apple's uploader reported no errors. Apple then reported one valid
internal-only 1.0 (6) build in internal testing, and the existing sole-tester
group's build list included it. The workflow nevertheless failed on a final
build-to-groups read that returned 403 for the approved API key. Do not rerun
or move the tag or upload the same build again. Repair the read-back path and
retain the Apple and tester evidence separately; the tester must confirm
TestFlight visibility.

## Apple access

The workflow uses the approved App Manager team API key for App Store Connect
preflight, upload and internal-group assignment. Apple applies a team key to
**all apps** at that role, so it cannot be limited to PacePrompt alone.
Store `ASC_KEY_ID`, `ASC_ISSUER_ID` and the base64-encoded `.p8` as
**environment secrets**; the latter is named `ASC_API_KEY_P8_B64`. Store
`ASC_TEAM_ID`, `ASC_INTERNAL_GROUP_ID` for the existing sole-tester group, and
`ASC_INTERNAL_TESTER_ID` for its authorised tester as environment
variables. Enter the
private key in GitHub's secret form, never in chat, a PR, a repository file or
an Actions log. The workflow
writes it to a restricted temporary file and removes it on exit. It creates
no IPA, archive, signing or credential artifact.

The first run proved Apple-managed cloud signing unavailable to this key:
`exportArchive Cloud signing permission error` and no distribution profile.
The operator approved a dedicated CI Apple Distribution certificate and an
App Store Connect provisioning profile for `com.otherweather.PromptPace`.
Create the certificate on the operator's Mac from a local Keychain Access CSR,
install it into Keychain Access, and export its certificate and private key as
a password-protected `.p12`. Create an iOS **App Store Connect** profile for
the explicit app ID with that certificate and HealthKit capability. The
Account Holder or Admin role is required for these Apple assets.

Store `DIST_P12_B64` (single-line base64 of the `.p12`),
`DIST_P12_PASSWORD`, and `DIST_PROFILE_B64` (single-line base64 of the
`.mobileprovision`) only as `internal-testflight` **environment secrets**.
Never paste private key or password material into chat, a PR, Git, or logs.
The job decodes them under `RUNNER_TEMP`, imports the identity into a temporary
keychain and installs the profile only after environment approval. Before the
archive it checks the imported Apple Distribution certificate against the
profile's sole certificate, exact team, app ID, iOS platform, HealthKit,
`get-task-allow=false`, expiry and lack of ad hoc/enterprise device lists.
The profile's embedded certificate fingerprint is matched directly to the
valid identity in the temporary keychain; no second PKCS#12 decoder is used.
It then archives and exports with manual signing and checks that the exported
app's actual signing certificate matches the approved CI identity. The signed
entitlements are requested from `codesign` as a property list and checked for
HealthKit, team, app ID and `get-task-allow=false` before upload. The keychain, profile and
temporary files are removed at job exit. If any match fails, there is no upload.
The signing certificate is extracted with a single `--extract-certificates=<prefix>`
argument; the guard fails if the leaf is missing or differs from the approved
profile identity.

## Workflow and evidence

The unprivileged job checks the tag and source without Apple secrets. After
environment approval, the macOS job rechecks them, pins Xcode 26.6
(`17F113`), checks the export-compliance tag and Apple account/group/build
identity, imports and verifies the approved manual signing assets, and archives Release. Export uses `app-store-connect`,
`manageAppVersionAndBuildNumber=false` and
`testFlightInternalTestingOnly=true`. Before the single upload attempt, the
workflow checks the IPA's version/build, bundle ID, purpose strings, privacy
manifest, HealthKit entitlement, team, Apple Distribution signature and
`get-task-allow=false`. It records the source SHA and IPA SHA-256 without
retaining the IPA.

After an accepted upload, the workflow waits for Apple processing and checks
that the resulting build is `INTERNAL_ONLY` and ready for internal testing.
It then adds only the existing sole-tester group and reads back the assignment
through that group's build list. This read-only check polls for up to two
minutes and rejects a missing build or paginated result; it does not repeat the
assignment request or upload.
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
