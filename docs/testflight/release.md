# Prepare and run an internal TestFlight release

Use this runbook for every release. A merge to `main` does not invoke this
workflow. Only pushing a new tag matching `testflight/*` starts
`.github/workflows/internal-testflight.yml`, and its signing job still waits
for approval of the `internal-testflight` environment.

## 1. Choose a unique version and build

Apple associates the upload with the existing app using its bundle ID and
marketing version. The build number uniquely identifies a build and can never
be reused after Apple receives it.

Read the checked-in production values:

```sh
python3 -B scripts/verify_release_configuration.py
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' \
  PacePrompt.xcodeproj/project.pbxproj
```

Use semantic marketing versions such as `1.0` and monotonically increasing
integer build numbers such as `8`. Form the tag as:

```text
testflight/<marketing-version>-b<build>
```

Before editing, confirm that the tag and Apple build are unused. With the local
API-key environment and existing group/tester IDs set:

```sh
export ASC_INTERNAL_GROUP_ID='<existing-group-id>'
export ASC_INTERNAL_TESTER_ID='<authorised-tester-id>'
python3 -B scripts/testflight_api.py preflight \
  --version '<marketing-version>' --build '<build>'
git ls-remote origin 'refs/tags/testflight/<marketing-version>-b<build>'
```

`preflight` must report the existing app, sole-tester group and a fresh
version/build. `git ls-remote` must print nothing. Stop if either is already in
use.

Create a fresh branch from current remote `main`; do not reuse an earlier
release branch:

```sh
git fetch origin main
git switch -c '<release-branch>' origin/main
```

## 2. Update version and release metadata

In Xcode, select the **PacePrompt** project and production **PacePrompt** target,
then **Build Settings**. Update:

- **Marketing Version** (`MARKETING_VERSION`) only when the user-facing version
  changes;
- **Current Project Version** (`CURRENT_PROJECT_VERSION`) for both production
  Debug and Release configurations on every upload.

Do not change the separate test/evaluation target versions unless their own
work requires it. Update the release-guard synthetic fixtures in
`scripts/tests/test_testflight_release.py` to the same candidate.

Review production metadata whenever it changes:

- bundle ID `com.otherweather.PromptPace`;
- display name;
- Bluetooth and HealthKit purpose strings;
- `PacePrompt/PrivacyInfo.xcprivacy`;
- `PacePrompt/PacePrompt.entitlements` with HealthKit;
- `ITSAppUsesNonExemptEncryption` as a Boolean declaration;
- app icon and Release archive scheme.

These values come from different sources and should not be conflated:

| Release value | Source of truth | Workflow check |
| --- | --- | --- |
| Marketing version | Production `MARKETING_VERSION` | Tag and signed `Info.plist` |
| Build number | Production `CURRENT_PROJECT_VERSION` | Tag, preflight and signed `Info.plist` |
| Bundle ID | Production build settings | Existing Apple app and signed bundle |
| Purpose strings and encryption declaration | Generated `Info.plist` settings | Source verifier and signed bundle |
| Privacy declarations | `PacePrompt/PrivacyInfo.xcprivacy` | Bundled manifest equals source |
| HealthKit capability | Entitlements, App ID and profile | Signed entitlements and embedded profile |
| Team/signing identity | GitHub variables and protected signing secrets | Archive, profile and signed certificate |

The workflow does not change the public App Store listing or submit it for
review. TestFlight **What to Test** text is separate beta metadata and is not
currently written by the workflow. If it is needed, add non-sensitive text to
the processed build in **App Store Connect → Apps → PacePrompt → TestFlight**;
do not treat that optional text as version, build or source provenance.

Run the focused checks:

```sh
python3 -B -m unittest scripts.tests.test_testflight_release -v
python3 -B scripts/verify_release_configuration.py
actionlint .github/workflows/ci.yml .github/workflows/internal-testflight.yml
git diff --check
```

## 3. Validate, review and commit

Inspect the complete diff and run the required complete local gate on the final
executable, test, build and validation-script tree:

```sh
git diff --check
git diff --stat
git diff
scripts/validate_local.sh
```

Retain the gate path and counts. Follow `AGENTS.md` development accounting for
every Codex-assisted commit, add the `DEVELOPMENT_NOTES.md` row, and use the
matching trailer:

```text
PacePrompt-Change: PP-YYYYMMDD-NN
```

Commit, push and open a pull request. Obtain independent review of the exact PR
head SHA. The pull request must identify the exact candidate version/build,
complete local gate evidence, exact-head review and release boundaries. If a
review repair changes the head, repeat the affected checks and obtain a new
review of the replacement SHA. Wait for **Fast repository checks**; do not add
the full simulator suite to hosted PR CI.

## 4. Merge with the exact-head attestation

Immediately before merge, refresh `origin/main`, confirm the PR head still
matches the reviewed SHA, and confirm hosted checks pass. Merge with a merge
commit whose body contains:

```text
Exact-head-review: <reviewed-pr-head-sha>
PacePrompt-Change: <matching-change-id>
```

Example:

```sh
REVIEWED_HEAD='<40-character-pr-head-sha>'
CHANGE_ID='<matching-change-id>'
MERGE_BODY='/private/tmp/paceprompt-testflight-merge-body.md'
printf 'Exact-head-review: %s\nPacePrompt-Change: %s\n' \
  "$REVIEWED_HEAD" "$CHANGE_ID" > "$MERGE_BODY"
gh pr merge '<pr-number>' --merge --match-head-commit "$REVIEWED_HEAD" \
  --subject 'Merge internal TestFlight <version> (<build>) candidate' \
  --body-file "$MERGE_BODY"
rm -f "$MERGE_BODY"
```

After merge, verify:

```sh
git fetch origin main
MERGE_SHA="$(git rev-parse origin/main)"
git show -s --format='%H%n%P%n%B' "$MERGE_SHA"
test "$(git rev-parse "$MERGE_SHA^{tree}")" = \
  "$(git rev-parse "$REVIEWED_HEAD^{tree}")"
gh run list --branch main --limit 3 \
  --json databaseId,headSha,status,conclusion,workflowName,url
```

The merge must have exactly two parents; the second parent must be the reviewed
PR head, the merge tree must equal that head's tree, and fast `main` CI must be
green on the exact merge SHA.

## 5. Confirm export compliance and authorise the upload

Before every upload, the operator must confirm the exact marketing version,
build, reviewed merge SHA, internal-only destination and export-compliance
decision. PacePrompt currently declares no non-exempt encryption. That standing
decision applies only while encryption behaviour is unchanged; stop for a new
judgement if cryptography, networking security behaviour or the declaration
changes.

Set the non-secret environment gate to the exact authorised tag:

```sh
TAG='testflight/<marketing-version>-b<build>'
gh variable set EXPORT_COMPLIANCE_TAG \
  --env internal-testflight --body "$TAG"
test "$(gh variable get EXPORT_COMPLIANCE_TAG --env internal-testflight)" = "$TAG"
```

This variable is an allowlist for one tag, not a substitute for the GitHub
environment approval.

## 6. Create the protected tag

Recheck Apple, remote main, main CI, the local project metadata and absence of
the remote tag. Then create a **lightweight** tag on the validated merge commit:

```sh
TAG='testflight/<marketing-version>-b<build>'
MERGE_SHA='<validated-main-merge-sha>'

test "$(git rev-parse origin/main)" = "$MERGE_SHA"
git tag "$TAG" "$MERGE_SHA"
test "$(git cat-file -t "refs/tags/$TAG")" = commit
test "$(git rev-parse "refs/tags/$TAG")" = "$MERGE_SHA"
git push origin "refs/tags/$TAG"
git ls-remote origin "refs/tags/$TAG"
```

The remote SHA must equal `MERGE_SHA`. Never use an annotated tag: the source
guard accepts only a lightweight commit tag. Never move or delete a release
tag.

## 7. Approve the protected environment job

The tag starts **Actions → Internal TestFlight**. The credential-free **Verify
protected release source** job must pass first. The signing job then waits for
`internal-testflight` approval.

In GitHub:

1. Open the new **Internal TestFlight** workflow run.
2. Select **Review deployments**.
3. Select `internal-testflight`.
4. Recheck the tag, source SHA, version/build and internal-only purpose.
5. Approve and deploy.

Do not approve an unexpected tag or SHA. The environment secrets become
available only after this approval.

## 8. Monitor the single attempt

```sh
gh run list --workflow internal-testflight.yml --limit 5
gh run view '<run-id>' --json status,conclusion,jobs,url
gh run watch '<run-id>' --exit-status
```

A green run proves these ordered stages passed:

1. protected lightweight tag and reviewed `main` merge;
2. exact-SHA fast CI and version/build match;
3. explicit environment approval and pinned Xcode toolchain;
4. App Store Connect app/group/tester preflight and unused build;
5. certificate, profile, team, app ID, HealthKit and distribution checks;
6. Release archive and internal-only export;
7. signed IPA metadata, privacy manifest, purpose strings, Apple Distribution
   signature, HealthKit entitlement and `get-task-allow=false`;
8. one accepted upload;
9. Apple processing to a valid internal-only beta build;
10. assignment visible in the unchanged sole-tester group's build list.

The workflow summary records source SHA, tag, bundle ID, version/build and IPA
SHA-256. It retains no IPA or signing asset.

## 9. Verify Apple and tester evidence separately

In App Store Connect, open **Apps → PacePrompt → TestFlight → iOS** and verify
that the exact version/build is processed and marked internal. Open the existing
internal group and confirm the build is present and membership has not changed.
Apple documents that processing occurs after upload and that internal-only
builds can be added only to internal groups.

Then ask the authorised tester to check the TestFlight app. Record these claims
separately:

- GitHub workflow green;
- upload accepted;
- Apple processing valid;
- internal group assigned;
- tester sees the build;
- tester installed or launched it.

Do not infer iPhone installation, HealthKit behaviour or physical treadmill
behaviour from CI, App Store Connect or TestFlight availability.

## 10. Record the outcome

Record the run URL, tag, exact source SHA, version/build, non-sensitive signing
result, upload result, Apple processing state and group result. State explicitly
whether tester visibility or installation was observed. Preserve the immutable
tag even if the run fails; follow [`troubleshooting.md`](troubleshooting.md).
