# Set up internal TestFlight release credentials and controls

This runbook creates or rotates the credentials used by the
`internal-testflight` GitHub environment. Perform certificate and profile work
as the Apple Developer Account Holder or an Admin. Create the App Store Connect
team key as the Account Holder or an Admin and give it the **App Manager** role.
Apple team keys apply to every app on the team; they cannot be restricted to
PacePrompt alone.

Before starting, install Xcode and GitHub CLI, authenticate `gh` to
`syamaner/paceprompt-ios` with repository-admin access, and confirm that the
existing Apple Developer and App Store Connect agreements are active.

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

1. Open **Keychain Access** from `/Applications/Utilities`.
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

## 4. Create the App Store Connect provisioning profile

1. Open Apple Developer → **Certificates, Identifiers & Profiles → Profiles → +**.
2. Under **Distribution**, select **App Store Connect**.
3. Select the explicit App ID for `com.otherweather.PromptPace`.
4. Select the Apple Distribution certificate created above.
5. Name the profile `PacePrompt CI App Store`.
6. Generate and download the `.mobileprovision`.

An App Store Connect profile contains one distribution certificate. Stop if
Apple asks to change the App ID or HealthKit capability.

Inspect the profile locally without committing its decoded content:

```sh
PROFILE_PATH="$HOME/path/to/PacePrompt_CI_App_Store.mobileprovision"
security cms -D -i "$PROFILE_PATH" > /private/tmp/paceprompt-profile.plist
plutil -p /private/tmp/paceprompt-profile.plist | less
```

Confirm:

- `TeamIdentifier` is the expected team;
- `application-identifier` ends with `.com.otherweather.PromptPace`;
- `com.apple.developer.healthkit` is true;
- `get-task-allow` is false;
- there is no `ProvisionedDevices` or `ProvisionsAllDevices` entry;
- the profile is not expired.

Remove the decoded inspection file when finished:

```sh
rm -f /private/tmp/paceprompt-profile.plist
```

The repository guard performs the same fail-closed checks during release.

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
name it `internal-testflight`.

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
| `DIST_PROFILE_B64` | Single-line base64 of the `.mobileprovision` |

To enter a value in the GitHub UI, click **Add environment secret**, type the
exact name from the table, paste the value, and select **Add secret**. GitHub
will show the saved name but will not reveal the value again. Use the CLI
method below when practical because it reads credential values from protected
files or stdin instead of placing them on a command line.

Use protected temporary files and stdin so credential values do not appear in
shell history. Substitute real paths locally:

```sh
umask 077
P8_PATH="$HOME/path/to/AuthKey_<KEY_ID>.p8"
P12_PATH="$HOME/path/to/PacePrompt-CI.p12"
PROFILE_PATH="$HOME/path/to/PacePrompt_CI_App_Store.mobileprovision"

base64 -i "$P8_PATH" -o /private/tmp/paceprompt-p8.b64
gh secret set ASC_API_KEY_P8_B64 --env internal-testflight \
  < /private/tmp/paceprompt-p8.b64

base64 -i "$P12_PATH" -o /private/tmp/paceprompt-p12.b64
gh secret set DIST_P12_B64 --env internal-testflight \
  < /private/tmp/paceprompt-p12.b64

base64 -i "$PROFILE_PATH" -o /private/tmp/paceprompt-profile.b64
gh secret set DIST_PROFILE_B64 --env internal-testflight \
  < /private/tmp/paceprompt-profile.b64

printf '%s' '<key-id>' | gh secret set ASC_KEY_ID --env internal-testflight
printf '%s' '<issuer-uuid>' | gh secret set ASC_ISSUER_ID --env internal-testflight
read -s 'P12_PASSWORD?P12 export password: '
printf '\n'
printf '%s' "$P12_PASSWORD" | \
  gh secret set DIST_P12_PASSWORD --env internal-testflight
unset P12_PASSWORD
rm -f /private/tmp/paceprompt-p8.b64 \
  /private/tmp/paceprompt-p12.b64 /private/tmp/paceprompt-profile.b64
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

## 8. Rotate or revoke credentials

Rotate before certificate/profile expiry or immediately after suspected
exposure:

1. Create and validate the replacement API key or certificate/profile locally.
2. Replace all related environment secrets together.
3. Run a fresh, uniquely numbered internal release through the normal review
   and approval path.
4. After that release is verified, revoke the superseded Apple API key or
   certificate and securely delete obsolete local copies.

A new distribution certificate requires a new `.p12` and a new provisioning
profile that embeds that certificate. Never update only one of those two
secrets.
