# Set up internal TestFlight release credentials and controls

This runbook creates or rotates the credentials used by the
`internal-testflight` GitHub environment. Perform certificate and profile work
as the Apple Developer Account Holder or an Admin. Create the App Store Connect
team key as the Account Holder or an Admin and give it the **App Manager** role.
Apple team keys apply to every app on the team; they cannot be restricted to
PacePrompt alone.

Before starting, install Xcode, Python 3.10 or newer, GitHub CLI, `actionlint`,
`shellcheck`, `ripgrep` and `uv`. Authenticate
`gh` to `syamaner/paceprompt-ios` with repository-admin access, and confirm that
the existing Apple Developer and App Store Connect agreements are active.
Run repository commands from a current checkout of this repository's root.
The credential-entry examples use macOS **zsh**; `read -s 'NAME?prompt'` is
zsh syntax, not portable bash syntax. Keep shell tracing disabled (`set +x`).

Check the local prerequisites without changing Apple or GitHub:

```sh
git rev-parse --show-toplevel
git remote get-url origin
gh auth status
python3 --version
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"'
rg --version
uv --version
actionlint -version
shellcheck --version
xcodebuild -version
gh api repos/syamaner/paceprompt-ios --jq '.permissions.admin'
```

The remote must be `syamaner/paceprompt-ios`, and the final command must print
`true`. The workflow currently requires hosted Xcode **26.6 (17F113)** at
`/Applications/Xcode_26.6.app/Contents/Developer`, with iOS Simulator SDK 26.5.
A different local Xcode version does not validate that hosted toolchain.
Read the checked-in workflows before changing any toolchain pin. The complete
local gate also supports Xcode 27.0 (27A266a) with Simulator SDK 27.0, and uses
`uv` to run the locked HostEval tests with Python 3.13. Complete Xcode's first
launch, required component installation and licence prompts before validation.

Use existing valid credentials and the existing environment when already set
up; do not create a second certificate, API key or tester group unnecessarily.
Verify their configuration using the checks below. GitHub cannot return stored
secret values; listing a secret name does not establish that its value is valid.

Primary references:

- Apple: [create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request),
  [certificate types](https://developer.apple.com/help/account/create-certificates/certificates-overview),
  [create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile),
  and [create an App Store Connect API key](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).
- GitHub: [deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments),
  [Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
  and [repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository).

## 1. Confirm the Apple app and App ID

In App Store Connect, open **Apps → PacePrompt → App Information** and confirm
that the app uses bundle ID `com.otherweather.PromptPace`. Do not create a
second app record.

In the Apple Developer account, open **Certificates, Identifiers & Profiles →
Identifiers**, select the explicit App ID for `com.otherweather.PromptPace`, and
confirm that **HealthKit** is enabled. Stop if Apple asks to create a different
App ID or change its HealthKit capability.

For the companion, separately authorise setup of the explicit
`com.otherweather.PromptPace.watchkitapp` App ID with HealthKit under the same
team. This is a companion identifier; do not create another App Store Connect
app record. Stop on any unexpected capability or identity change.

## 2. Create the App Store Connect API key

If API access is not already enabled, the Account Holder opens **App Store
Connect → Users and Access → Integrations → App Store Connect API**, requests
access and accepts the terms.

Then:

1. Open **Users and Access → Integrations → App Store Connect API → Team Keys**.
2. Click **Generate API Key** or **+**.
3. Name it, for example, `PacePrompt CI`.
4. Select **App Manager** access.
5. Generate it and record the **Issuer ID** and **Key ID**.
6. Download `AuthKey_<KEY_ID>.p8` once and move it to encrypted local storage.

Never paste the `.p8` content into chat. Apple permits downloading it only once.
Revoke it immediately if it is lost or exposed.

For local, read-only validation, export only paths and identifiers in the
current shell:

```sh
export ASC_KEY_ID='<10-character-key-id>'
export ASC_ISSUER_ID='<issuer-uuid>'
export ASC_KEY_PATH="$HOME/path/to/AuthKey_<KEY_ID>.p8"
```

Do not add these exports to a shell profile or repository file.

## 3. Create an Apple Distribution certificate

On the Mac that will create the signing identity:

1. Open **Keychain Access** using Spotlight.
2. Choose **Keychain Access → Certificate Assistant → Request a Certificate
   from a Certificate Authority**.
3. Enter the Apple Developer account email and a clear common name such as
   `PacePrompt CI Distribution`.
4. Leave **CA Email Address** empty, select **Saved to disk**, and save the
   `.certSigningRequest`.
5. Open the Apple Developer site → **Certificates, Identifiers & Profiles →
   Certificates → +**.
6. Select **Apple Distribution**, continue, upload the CSR, generate the
   certificate and download the `.cer`.
7. Double-click the `.cer` to install it in the login keychain.
8. In Keychain Access → **My Certificates**, expand the Apple Distribution
   certificate and confirm that a private key appears below it.

Confirm that macOS sees a signing identity:

```sh
security find-identity -v -p codesigning
```

The output must include an unexpired `Apple Distribution` identity for the
expected Apple team.

### Export the CI identity

In **Keychain Access → My Certificates**, select the Apple Distribution
certificate together with its private key, choose **File → Export Items**, save
it as a Personal Information Exchange (`.p12`) file, and assign a strong,
unique export password. Keep the `.p12` and password in separate protected
locations. Never export only the certificate: the workflow needs the associated
private key.

## 4. Create the two App Store Connect provisioning profiles

1. Open Apple Developer → **Certificates, Identifiers & Profiles → Profiles → +**.
2. Under **Distribution**, select **App Store Connect**.
3. Select the explicit App ID for `com.otherweather.PromptPace`.
4. Select the Apple Distribution certificate created above.
5. Name the profile `PacePrompt CI App Store`.
6. Generate and download the `.mobileprovision`.

An App Store Connect profile contains one distribution certificate. Stop if
Apple asks to change the App ID or HealthKit capability.

Repeat the profile procedure for `com.otherweather.PromptPace.watchkitapp`,
selecting the **same** distribution certificate and naming the separate profile
`PacePrompt Watch CI App Store`. The two profiles must have distinct UUIDs.

Inspect each profile locally without committing its decoded content:

```sh
umask 077
PROFILE_PATH="$HOME/path/to/PacePrompt_CI_App_Store.mobileprovision"
PROFILE_INSPECTION_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/paceprompt-profile.XXXXXX")"
security cms -D -i "$PROFILE_PATH" > "$PROFILE_INSPECTION_DIR/profile.plist"
plutil -p "$PROFILE_INSPECTION_DIR/profile.plist" | less
```

Confirm:

- `TeamIdentifier` is the expected team;
- `application-identifier` exactly matches the team prefix and the selected
  phone or Watch bundle ID;
- `com.apple.developer.healthkit` is true;
- `get-task-allow` is false;
- `beta-reports-active` is true;
- `keychain-access-groups` grants the app ID or the expected team wildcard;
- there is no `ProvisionedDevices` or `ProvisionsAllDevices` entry;
- the profile is not expired.

Remove the decoded inspection file when finished:

```sh
rm -rf "$PROFILE_INSPECTION_DIR"
unset PROFILE_INSPECTION_DIR
```

The repository guard performs these checks for both roles during release.
The phone and Watch profile platform-family policy accepts `iOS` or the exact
ordered family `iOS, xrOS, visionOS`; the Watch also accepts `watchOS` and the
ordered pair `iOS, watchOS`. The shared three-entry family was observed in both
Apple-issued App Store profiles during authorised setup on 28 September 2026.
Exact App ID, team and certificate still bind each profile to its role. This
profile declaration does not permit visionOS executables: the separate Mach-O
policy still requires iPhone IOS and Watch WATCHOS device slices. Synthetic tests
cover accepted families, malformed/unknown families, role swaps and visionOS
binary rejection. Actual profile inspection does not prove possession of the CI
private key, signed export or Apple upload acceptance. Unexpected platform output
requires a reviewed policy change, not an ad hoc bypass.

## 5. Confirm the internal group and discover IDs

In App Store Connect:

1. Open **Apps → PacePrompt → TestFlight**.
2. Under **Internal Testing**, open the existing group.
3. Confirm **automatic distribution is disabled**.
4. Confirm the group contains only the authorised tester.
5. Do not invite another tester or enable a public link as part of release setup.

With the local API-key environment from step 2, the following read-only command
lists group and tester IDs without printing emails or credentials:

```sh
python3 -B - <<'PY'
import scripts.testflight_api as api

apps = api.request('/apps?filter[bundleId]=com.otherweather.PromptPace&limit=2')['data']
app = api.one(apps, 'matching app')
groups = api.request(f"/apps/{app['id']}/betaGroups?limit=200")
if groups.get('links', {}).get('next'):
    raise SystemExit('Group result is paginated; inspect before selecting an ID')
for group in groups['data']:
    detail = api.request(f"/betaGroups/{group['id']}")['data']['attributes']
    testers = api.request(f"/betaGroups/{group['id']}/betaTesters?limit=200")
    if testers.get('links', {}).get('next'):
        raise SystemExit('Tester result is paginated; cannot prove sole membership')
    tester_ids = [tester['id'] for tester in testers['data']]
    print({
        'group_id': group['id'],
        'name': detail.get('name'),
        'is_internal': detail.get('isInternalGroup'),
        'access_to_all_builds': detail.get('hasAccessToAllBuilds'),
        'public_link_enabled': detail.get('publicLinkEnabled'),
        'tester_ids': tester_ids,
    })
PY
```

Choose only the existing group whose output is internal, explicit assignment
and exactly the authorised tester. App Store Connect can omit
`publicLinkEnabled` for an internal group; confirm in the UI that no public link
is enabled. Record the group ID and tester ID as non-secret configuration
values.

## 6. Create and protect the GitHub environment

In GitHub, open **Repository → Settings → Environments → New environment** and
name it `internal-testflight`. If it exists, open and verify it instead.

Configure:

- **Required reviewers:** the release operator (`syamaner`);
- **Prevent self-review:** off for this single-operator repository;
- **Allow administrators to bypass configured protection rules:** off;
- **Deployment branches and tags:** selected tags only, pattern `testflight/*`.

Jobs cannot read environment secrets until the reviewer approves the protected
environment job.

### Environment secrets

Store these under **Settings → Environments → internal-testflight → Environment
secrets**:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect team key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_API_KEY_P8_B64` | Single-line base64 of the downloaded `.p8` |
| `DIST_P12_B64` | Single-line base64 of the `.p12` identity |
| `DIST_P12_PASSWORD` | `.p12` export password |
| `DIST_PROFILE_B64` | Single-line base64 of the phone App Store profile |
| `DIST_WATCH_PROFILE_B64` | Single-line base64 of the separate Watch App Store profile |

To enter a value in the GitHub UI, click **Add environment secret**, type the
exact name from the table, paste the value, and select **Add secret**. GitHub
will show the saved name but will not reveal the value again. Use the CLI
method below when practical because it reads credential values from protected
files or stdin instead of placing them on a command line.

Use protected temporary files and stdin so credential values do not appear in
shell history. Substitute real paths locally:

```sh
set +x
umask 077
SECRET_SETUP_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/paceprompt-secrets.XXXXXX")"
P8_PATH="$HOME/path/to/AuthKey_<KEY_ID>.p8"
P12_PATH="$HOME/path/to/PacePrompt-CI.p12"
PROFILE_PATH="$HOME/path/to/PacePrompt_CI_App_Store.mobileprovision"
WATCH_PROFILE_PATH="$HOME/path/to/PacePrompt_Watch_CI_App_Store.mobileprovision"

base64 -i "$P8_PATH" -o "$SECRET_SETUP_DIR/p8.b64"
gh secret set ASC_API_KEY_P8_B64 --env internal-testflight \
  < "$SECRET_SETUP_DIR/p8.b64"

base64 -i "$P12_PATH" -o "$SECRET_SETUP_DIR/p12.b64"
gh secret set DIST_P12_B64 --env internal-testflight \
  < "$SECRET_SETUP_DIR/p12.b64"

base64 -i "$PROFILE_PATH" -o "$SECRET_SETUP_DIR/profile.b64"
gh secret set DIST_PROFILE_B64 --env internal-testflight \
  < "$SECRET_SETUP_DIR/profile.b64"

base64 -i "$WATCH_PROFILE_PATH" -o "$SECRET_SETUP_DIR/watch-profile.b64"
gh secret set DIST_WATCH_PROFILE_B64 --env internal-testflight \
  < "$SECRET_SETUP_DIR/watch-profile.b64"

printf '%s' '<key-id>' | gh secret set ASC_KEY_ID --env internal-testflight
printf '%s' '<issuer-uuid>' | gh secret set ASC_ISSUER_ID --env internal-testflight
read -s 'P12_PASSWORD?P12 export password: '
printf '\n'
printf '%s' "$P12_PASSWORD" | \
  gh secret set DIST_P12_PASSWORD --env internal-testflight
unset P12_PASSWORD
rm -rf "$SECRET_SETUP_DIR"
unset SECRET_SETUP_DIR
```

Run each `gh secret set` successfully before continuing. If any command fails,
stop, remove the temporary directory and unset the password before diagnosing;
do not echo or paste the failed secret. To clean up an interrupted setup shell:

```sh
unset P12_PASSWORD
if [ -n "${SECRET_SETUP_DIR:-}" ] && [ -d "$SECRET_SETUP_DIR" ]; then
  rm -rf "$SECRET_SETUP_DIR"
fi
unset SECRET_SETUP_DIR
```

Do not use literal placeholders as real values. Confirm secret names without
reading their values:

```sh
gh secret list --env internal-testflight
```

### Environment variables

Store these under **Environment variables**:

| Variable | Value |
| --- | --- |
| `ASC_TEAM_ID` | Ten-character Apple team ID |
| `ASC_INTERNAL_GROUP_ID` | Existing explicit-assignment internal group ID |
| `ASC_INTERNAL_TESTER_ID` | Sole authorised tester ID |
| `EXPORT_COMPLIANCE_TAG` | Exact authorised release tag; update per release |
| `RELEASE_TOOLS_SHA` | Reviewed full 40-character commit SHA containing the trusted release tools; update only when those tools are deliberately upgraded |

In the GitHub UI, click **Add environment variable** for each name and value.
These identifiers and the release tag are configuration, not credentials;
keep the private key, signing identity, profile and password in the secret
section above.

```sh
gh variable set ASC_TEAM_ID --env internal-testflight --body '<team-id>'
gh variable set ASC_INTERNAL_GROUP_ID --env internal-testflight --body '<group-id>'
gh variable set ASC_INTERNAL_TESTER_ID --env internal-testflight --body '<tester-id>'
```

Set `EXPORT_COMPLIANCE_TAG` only during a release after the operator has
confirmed the export-compliance decision for that exact candidate. See
[`release.md`](release.md).

### Bootstrap and upgrade the trusted signing tools

The split pipeline requires a tools pin before its first release. After this
change has been independently reviewed, validated and merged to protected
`main`, choose that full merge SHA. Older commits that lack
`scripts/testflight_handoff.py` or `scripts/testflight_release.sh` cannot serve
as the bootstrap pin. Do not set `main`, a branch name, a tag, an abbreviated
SHA or a placeholder as the pin. Do not update it automatically for every app
release: it identifies the trusted signing implementation, separately from
the candidate app source.

From a current, clean checkout, verify the selected tools commit locally:

```sh
TOOLS_SHA='<reviewed-40-character-tools-commit-sha>'
(
  set -e
  [[ "$TOOLS_SHA" =~ ^[0-9a-f]{40}$ ]]
  git fetch origin main
  git cat-file -e "$TOOLS_SHA^{commit}"
  git merge-base --is-ancestor "$TOOLS_SHA" origin/main
  for file in scripts/testflight_release.sh scripts/testflight_handoff.py \
    scripts/testflight_guard.py scripts/testflight_signing.py scripts/testflight_policy.py \
    scripts/testflight_api.py PacePrompt/PrivacyInfo.xcprivacy PacePromptWatch/PrivacyInfo.xcprivacy; do
    git cat-file -e "$TOOLS_SHA:$file"
  done
)
```

Every check must succeed. Independently review the exact tools code and the
candidate workflow before changing the pin. File existence and ancestry are
not proof of review. Use a separate checkout of the selected SHA to run the
release-tool tests and lint checks described in `release.md`; running tests
from a different checkout would not validate this pin.

Then set the protected environment variable and verify the stored value:

```sh
gh variable set RELEASE_TOOLS_SHA --repo syamaner/paceprompt-ios \
  --env internal-testflight --body "$TOOLS_SHA"
test "$(gh variable get RELEASE_TOOLS_SHA --repo syamaner/paceprompt-ios \
  --env internal-testflight --json value --jq '.value')" = "$TOOLS_SHA"
```

A missing or malformed pin fails before the trusted-tools checkout. The signer
checks that checkout's HEAD equals the pin, then executes only its tools. The
candidate checkout is used for Git/source metadata; privacy manifests are checked
against the trusted checkout. Candidate scripts, project and scheme are not executed in the signing job. Builds
run on a separate runner with no Apple environment or credentials.

The version-2 artifact handoff permits exactly the phone app and
`Watch/PacePromptWatch.app`, plus their two dSYMs as inert data. The phone requires
device arm64; Watch accepts device arm64_32 with optional arm64, checking every
Mach-O slice. Both executable permissions are restored after bounded extraction.
Unknown nested code, disguised Mach-O resources, unsigned inputs containing
signature load commands/profiles, symlinks, unsafe or duplicate paths and oversized
archives fail closed. Identity, capability or topology changes require a deliberate
reviewed tools update. The pinned privacy manifests and purpose strings must match.

The signer validates both profiles against one approved certificate, generates
fixed role-specific entitlements, signs Watch first and phone last, and exports
with an explicit two-profile map. Both exported bundles must pass identity,
privacy, device code, complete profile, exact entitlement, certificate-leaf and
strict signature checks before the single upload command is reachable.

The tag's workflow still defines secret access and can be edited in a candidate.
A tools pin is not protection against an approved malicious workflow that
removes these checks. Review workflow changes and the exact candidate SHA before
every environment approval. SHA-256 binds a transfer to its build output; it
does not prove that the app's behaviour is benign.

## 7. Protect release tags

In GitHub, open **Repository → Settings → Rules → Rulesets → New ruleset → New
tag ruleset**. Create two active rulesets targeting `testflight/*`:

1. `Internal TestFlight tags: admins create`
   - enable **Restrict creations**;
   - add repository role **Admin** to the bypass list with **Always allow**.
2. `Internal TestFlight tags: immutable`
   - enable **Restrict updates** and **Restrict deletions**;
   - configure no bypass actor.

The first permits only repository admins to create release tags. The second
prevents everyone, including admins, from moving or deleting them.

Verify the live controls without reading secrets:

```sh
gh api repos/syamaner/paceprompt-ios/rulesets \
  --jq '.[] | {id,name,enforcement,target}'
gh api repos/syamaner/paceprompt-ios/environments/internal-testflight \
  --jq '{deployment_branch_policy,protection_rules,can_admins_bypass}'
gh api repos/syamaner/paceprompt-ios/environments/internal-testflight/deployment-branch-policies \
  --jq '.branch_policies[] | {name,type}'
```

## 8. Protect main and verify the complete GitHub setup

In **Settings → Rules → Rulesets**, verify or create the active branch ruleset
`Main: PRs and required CI`, targeting `refs/heads/main`:

- no bypass actors, including administrators;
- restrict deletions and block force pushes;
- require a pull request and resolve review conversations;
- allow merge commits only, because the release guard requires a two-parent
  merge commit;
- require **Fast repository checks**, with **GitHub Actions** as the expected
  source, and require the branch to be up to date before merging;
- required approving reviews: **0** for the current single-maintainer setup.
  Independent review remains a manual release requirement. The commit-message
  review marker is an operator attestation, not authenticated review evidence.

Do not require the manual full-validation or Codecov jobs for each PR: the
current CI deliberately skips those jobs on PR events.

Read back effective protection rather than relying on the ruleset's name:

```sh
gh api repos/syamaner/paceprompt-ios/branches/main --jq '.protected'
gh api repos/syamaner/paceprompt-ios/rules/branches/main \
  --jq '.[] | {type,parameters,ruleset_id}'
gh api repos/syamaner/paceprompt-ios/actions/permissions/workflow
gh secret list --repo syamaner/paceprompt-ios
gh secret list --repo syamaner/paceprompt-ios --env internal-testflight
```

Expect `true`, active deletion/force-push/PR/status-check rules, a fast-check
context bound to GitHub Actions (integration ID `15368`), default token
permissions `read`, and `can_approve_pull_request_reviews=false`. Expect no
repository Actions secrets and all seven named Apple/signing secrets in the
environment. Read each ruleset's detail (`gh api
repos/syamaner/paceprompt-ios/rulesets/<id>`) to confirm conditions and bypass
actors; the ruleset list alone does not establish tag immutability or admin-only
creation. Environment readback must show required reviewer `syamaner`,
`can_admins_bypass=false`, and the tag-only `testflight/*` deployment policy.

These checks establish GitHub configuration only. Credential values, Apple
permissions, certificate validity and actual upload compatibility require the
separate local/Apple checks and an explicitly authorised fresh release. The
build runner has no Apple secrets. The signing runner uses the independently
pinned tools; it never rebuilds the candidate project. Apple tools still parse
and sign candidate binaries/data, so this does not claim isolation from defects
in Xcode, codesign or archive parsers.

## 9. Rotate or revoke credentials

For suspected exposure, revoke the affected Apple API key or certificate
**immediately** and stop releases. Do not wait for a replacement release to
succeed. Replace the affected secrets and investigate before authorising a new
release. Apple documents immediate API-key revocation in its
[API-key guidance](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api).

For planned rotation before expiry, with no suspected exposure:

1. Create and validate the replacement API key or certificate/profile locally.
2. Replace all related environment secrets together.
3. Run a fresh, uniquely numbered internal release through the normal review
   and approval path.
4. After that release is verified, revoke the superseded Apple API key or
   certificate and securely delete obsolete local copies.

A new distribution certificate requires a new `.p12` and replacement phone and
Watch profiles embedding that certificate. Replace the related secrets together.

## Watch companion release boundary (#115)

Issue #186 delivered strict two-bundle tooling and synthetic failure coverage for
the #115 companion. Its architecture and evidence are recorded in
[Watch release preparation](../../design/watch-release-preparation.md). That
preparation did not activate signing or upload a release. Authorised setup under
#188 subsequently activated the reviewed tools merge
`ab0ec096af74b79a498b7686fc87476781e612cc`; see the
[current setup and candidate receipt](README.md#watch-companion-candidate-101-14-issue-188).
Keep local signing configuration and team identifiers out of Git.

A release still requires a validated real Watch profile, a fresh build number and
an exact-head-attested candidate merge; 1.0.1 (13) is already used. Do not infer hosted Xcode 26.6 compatibility, Apple
acceptance, TestFlight visibility or paired-device behaviour from local unsigned
Xcode 27.0 and mocked-tool tests. #115 device acceptance, WeeklyHealthReport #80
and physical/cross-repository #116 remain open dependent work.

Exported IPA inspection is also bounded: only `Payload/PacePrompt.app` and its
exact Watch child are accepted. Unknown top-level support directories or sibling
apps fail closed before extraction/signature inspection. Any required Apple export
layout extension needs its own reviewed policy update. Certificate, identity and
exact-entitlement display checks explicitly select every Mach-O architecture;
strict verification also covers all architectures.


## Optional symbol-package export (#188)

The trusted export options set `uploadSymbols = false`. Xcode's `-help` documents
that App Store packages include optional symbols by default; a local reproduction
of the first Watch release export contained a `Symbols/` root outside `Payload/`.
Disabling that optional package produced an IPA that passed the unchanged strict
whole-IPA and both-app signature guards. This preserves the closed application
graph rather than admitting an unvalidated support-file format.

Trade-off: Apple does not receive the optional symbol package, which may limit
Apple-side crash symbolication. Matching phone/Watch dSYMs remain in the verified
unsigned archive, whose hosted artifact has one-day retention; retain that archive
locally if later crash analysis is needed. `stripSwiftSymbols` is not changed.
Local export/verification proves local Xcode compatibility only; hosted Xcode
26.6 and Apple acceptance require the fresh build-15 release. The failed build-14
tag/run remains immutable and is never rerun or moved.
