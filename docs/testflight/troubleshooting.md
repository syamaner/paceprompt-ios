# Recover an internal TestFlight release safely

Never blindly rerun an ambiguous release. A workflow failure and an upload
failure are different facts: the job can fail after Apple accepted the build.
Release tags are immutable and every new attempt needs a fresh build number,
reviewed merge and tag.

## First response to any failure

1. Do not rerun the workflow, move the tag or upload manually.
2. Record the run URL, tag, source SHA and failed step.
3. Read only the relevant stage markers; do not dump secrets or complete logs
   into an issue.
4. Query App Store Connect for the exact marketing version/build.
5. Classify the outcome before choosing recovery.

Inspect GitHub:

```sh
gh run view '<run-id>' --json status,conclusion,headSha,event,jobs,url
gh run view '<run-id>' --log-failed
```

The second command can contain build diagnostics. Review locally and quote only
non-sensitive lines.

With the local App Store Connect API environment configured, check the exact
build without changing it:

```sh
VERSION='<marketing-version>' BUILD='<build>' python3 -B - <<'PY'
import os
import scripts.testflight_api as api

app, group = api.app_and_group()
matches = api.matching_builds(app, os.environ['VERSION'], os.environ['BUILD'])
print('matching builds:', len(matches))
for build in matches:
    attrs = build['attributes']
    print({
        'id': build['id'],
        'processing_state': attrs.get('processingState'),
        'audience': attrs.get('buildAudienceType'),
    })
    detail = api.request(f"/builds/{build['id']}/buildBetaDetail")['data']['attributes']
    print({'internal_build_state': detail.get('internalBuildState')})
    listing = api.request(f'/betaGroups/{group}/builds?limit=200')
    print({'present_in_authorised_group': build['id'] in {item['id'] for item in listing['data']}})
PY
```

## Outcome A: failure before upload and Apple has no build

Examples include source-guard failure, missing approval, toolchain mismatch,
credential decoding, certificate/profile mismatch, archive/export failure or
signed-artifact guard failure.

- The tag remains consumed and immutable.
- Fix the root cause in a new reviewed commit.
- Increment the build number even though Apple has no binary for the failed
  number.
- Run the complete local gate again if executable, test, project, build,
  dependency, resource or validation input changed.
- Merge, wait for exact-main CI, reconfirm export compliance, set a new
  `EXPORT_COMPLIANCE_TAG`, and create a new tag.

Do not reuse the old tag to obtain a green run.

## Outcome B: upload output is ambiguous and Apple has no build yet

Apple processes builds asynchronously. A network timeout or failed uploader
process does not prove that Apple rejected the binary.

- Wait and repeat only the read-only exact-build query.
- Check App Store Connect **Apps → PacePrompt → TestFlight → iOS** and delivery
  status.
- Do not upload while the outcome is uncertain.
- If Apple eventually shows the build, use Outcome C.
- Only after sufficient read-only evidence shows no build and the failure is
  understood should a new reviewed build number be prepared.

Never retry the same version/build.

## Outcome C: Apple has the build but the workflow failed later

The uploader succeeded. Typical later failures include processing timeout,
export-compliance state, API permission on a readback, or group assignment
verification.

- Do not upload the same build again.
- Determine the Apple processing and internal-build states.
- Resolve a required export-compliance decision in App Store Connect only with
  the operator's judgement.
- If the build is valid but group assignment is missing, diagnose the existing
  group and API permissions before making a single deliberate assignment.
- Repair workflow verification in a reviewed PR for future releases.
- Record the historical run as failed-after-upload; do not rewrite it as green.

Build 1.0 (6) is the repository example: Apple accepted and processed it, but
the workflow failed on a forbidden reverse relationship read. PR #127 changed
future verification to the group's build list. The build was not uploaded
again.

## Outcome D: run is green but the tester cannot see the build

A green workflow proves API group assignment, not TestFlight UI visibility.

1. Confirm the tester is signed into TestFlight with the authorised App Store
   Connect account.
2. Confirm the existing group still contains exactly that tester.
3. Confirm the build is still present in the group and has not expired.
4. Check Apple processing and internal beta status.
5. Allow for TestFlight propagation, then refresh the TestFlight app.

Do not add testers, enable a public link, enable external testing or submit to
TestFlight App Review without separate authorisation.

## Common failures

### `Cloud signing permission error` or no profile found

This workflow intentionally uses manual signing. Confirm the current workflow
does not pass `-allowProvisioningUpdates`. Verify all three distribution secrets
are present and use the dedicated Apple Distribution identity and matching App
Store Connect profile described in [`setup.md`](setup.md).

### Certificate and profile do not match

Create a new App Store Connect profile selecting the same Apple Distribution
certificate whose private key is inside the `.p12`. Replace `DIST_P12_B64`,
`DIST_P12_PASSWORD` and `DIST_PROFILE_B64` as one set.

### Profile lacks HealthKit or allows debugging

Stop. Select the explicit `com.otherweather.PromptPace` App ID with HealthKit
enabled and regenerate the App Store Connect profile. `get-task-allow` must be
false. Do not alter app capabilities merely to make signing pass.

### `EXPORT_COMPLIANCE_TAG` mismatch

The workflow is correctly refusing a tag that has not received the exact
export-compliance decision. Confirm the candidate and encryption behaviour,
then update the variable to that exact tag. Do not weaken or remove the guard.

### Duplicate build

Choose a higher build number, prepare and review it as a new source change, and
use a new immutable tag. Apple build numbers are not reusable.

### Missing or changed group/tester

Stop. The workflow allows only the configured explicit-assignment internal
group with the configured sole tester. Restore the intended configuration or
obtain an explicit decision before changing tester access.

### Expired certificate or profile

Follow [`setup.md`](setup.md) to create a replacement Apple Distribution
certificate, `.p12` and matching App Store Connect profile. Validate locally,
replace the environment secrets together, and use a fresh release candidate.
Do not revoke the old certificate until the replacement release succeeds.

### API 401 or 403

Confirm the team key is active, the key ID and issuer ID match its `.p8`, and
the key has the approved App Manager role. A team key covers all apps and
cannot be scoped only to PacePrompt. If access must change, create a replacement
key rather than broadening the workflow or logging response bodies.

## Evidence boundaries

Report these as separate facts:

| Evidence | What it establishes |
| --- | --- |
| Local complete gate | Simulator tests/build/static checks for the source tree |
| Exact-head review | Independent review of the committed candidate |
| Main CI | Fast repository checks on the merge SHA |
| Signed-artifact guard | Exact signed bundle metadata, entitlements and identity before upload |
| Uploader success | Apple accepted the upload command |
| Apple processing | Apple produced a valid internal-only build |
| Group readback | The build appears in the configured internal group's API list |
| Tester observation | The tester can see the build in TestFlight |
| Installation/launch | The tester installed or launched that build |

None of these establishes HealthKit or physical FR30z behaviour unless those
are separately exercised and recorded under their own authorised procedures.
