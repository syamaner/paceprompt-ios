# Internal TestFlight operator runbooks

These runbooks operate PacePrompt's protected, internal-only TestFlight release
path. They do not submit to App Review, enable external testing, publish an App
Store version or test HealthKit or treadmill behaviour.

Use them in this order:

1. [One-time setup and credential rotation](setup.md) — Apple certificate,
   provisioning profile, App Store Connect API key, internal tester group,
   GitHub environment, secrets, variables, trusted-tools pin, tag rules and
   main protection.
2. [Prepare and run a release](release.md) — choose a unique version/build,
   validate and review the source, merge it, create the protected tag, approve
   the environment job and verify each release stage.
3. [Failure recovery](troubleshooting.md) — determine whether an upload ran,
   avoid ambiguous retries, rotate expired credentials and recover with a new
   immutable tag when required.

The implementation and security rationale remain in
[`docs/internal-testflight-release.md`](../internal-testflight-release.md).
The workflow is [`.github/workflows/internal-testflight.yml`](../../.github/workflows/internal-testflight.yml).

## Fixed production identity

| Item | Expected value |
| --- | --- |
| App | Existing PacePrompt App Store Connect record |
| Bundle ID | `com.otherweather.PromptPace` |
| Tag | `testflight/<marketing-version>-b<build>` |
| GitHub environment | `internal-testflight` |
| Distribution | TestFlight internal testing only |
| Tester access | Existing explicit-assignment sole-tester group |
| Export method | `app-store-connect` with `testFlightInternalTestingOnly=true` |

Do not place a `.p8`, `.p12`, `.mobileprovision`, private key, certificate
password, decoded signing asset or signed IPA in Git, a pull request, an Actions
artifact, a terminal transcript or chat. Only the credential-free unsigned
archive is transferred as an Actions artifact, with one-day retention. Use
synthetic values in examples and tests.

## Runbook verification

On 26 September 2026, the setup instructions were checked against source commit
`cc8ec639705bec4e2b0edccadfb40cfebd67da4d` and live GitHub main/tag rules,
environment protections, token defaults and secret names. Shell examples were
syntax-checked with macOS zsh, embedded Python was compiled without execution,
and the workflow and release metadata checks passed. Apple certificate/profile
steps were cross-checked with the linked Apple guidance; they were not repeated
against the operator's account. Credential-entry commands and release/upload
commands were not executed during this documentation verification.

Recheck live configuration before using the runbooks. These instructions describe
the split workflow in this change. At implementation review the live pipeline
still used the combined workflow. Merging this change activates the split
workflow; it refuses signing until `RELEASE_TOOLS_SHA` is set to a reviewed
commit containing the new tools. Local unsigned archive/transfer validation is
separate from hosted Xcode 26.6 signing/export and Apple upload acceptance; no upload was performed
for this change.

The split implementation passed 33 focused release/security tests, workflow lint,
ShellCheck and shell syntax checks. All 28 documented shell blocks parsed under
zsh and their embedded Python compiled. A real unsigned device archive passed
handoff and device-platform checks; fixed entitlements were checked using an ad
hoc signature with synthetic team values, not an Apple distribution identity.
The complete local gate passed with Xcode 27.0 (27A266a), SDK 27.0 and iPhone 17
Pro/iOS 26.5: 339 production unit tests, 49 production UI tests, 16 evaluation
target tests, Release simulator build and static analysis. Offline HostEval
passed 247 tests with 36 skips for evidence absent from this checkout.

An initial iPhone 18 Pro/iOS 27.0 run found four landscape UI failures and was
stopped. All four passed in isolation on the default iPhone 17 Pro/iOS 26.5,
and the complete replacement gate on that destination passed. This does not
establish that the alternate simulator's layout issue is fixed; app/UI code
was not changed by this release-security slice.

On 26 September 2026, PR #165 merged the split workflow at
`2050f1dee6763297fc784f80aaf59c317b2d7e29`. Independent exact-head review found no
actionable findings, exact-main CI passed, and the protected environment's
`RELEASE_TOOLS_SHA` was set to that merge SHA and read back successfully. The
release tests and lint checks also passed from that exact merged checkout.
This activation did not create a release tag or exercise Apple signing/upload;
a fresh build is required because 1.0.1 (10) was already uploaded by the prior
workflow.

### Hosted split-pipeline validation: 1.0.1 (11)

On 26 September 2026, the operator authorised internal build 1.0.1 (11).
[PR #166](https://github.com/syamaner/paceprompt-ios/pull/166) merged the reviewed
candidate at `4a59bf38e1176309049d2881e5d5ba8cf30b90d3`. The lightweight immutable
tag `testflight/1.0.1-b11` points to that merge; the trusted-tools pin remains
`2050f1dee6763297fc784f80aaf59c317b2d7e29`.

[Release run 36272300449](https://github.com/syamaner/paceprompt-ios/actions/runs/36272300449)
completed successfully on attempt 1. It verified protected source and exact-main
CI, built the unsigned archive on the credential-free runner, verified the
same-run archive handoff with pinned tools, passed Apple app/group/tester and
fresh-build preflight, validated the certificate/profile, signed without
rebuilding candidate code, exported internal-only, and verified the signed
artifact. Apple accepted the one upload, processed the build, and the API check
confirmed internal-only status and assignment to the unchanged sole-tester
group. Only the unsigned archive was retained as an Actions artifact; no signed
IPA or signing asset was retained there. Environment approval was submitted on
the operator's behalf using their explicit authorisation for this exact internal
version/build and unchanged encryption declaration.

The candidate's full local gate passed on a fresh iPhone 17 Pro/iOS 26.5
simulator: 388 production tests, 16 evaluation tests, Release build and static
analysis. Two earlier runs stopped on CoreSimulator Mach `-308` launch-service
errors; the affected tests passed in isolation and the final full gate. One
initial isolated plan test failed tab navigation before explicit boot; no
app/test repairs were made. Evidence remains under the build11 paths in
`/private/tmp`, with the final gate at
`/private/tmp/paceprompt-build11-fresh-full-gate`.

This run validates hosted signing/export, Apple acceptance and internal-group
assignment. It does not prove that the tester installed or opened the build,
or establish physical Bluetooth, treadmill or HealthKit acceptance. Follow
release.md's separate tester checks for those claims. Future candidates still
require source/workflow review and explicit release authorisation.

### Internal profile-flow release: 1.0.1 (12)

On 27 September 2026, the operator authorised a new internal release for device
testing. [PR #174](https://github.com/syamaner/paceprompt-ios/pull/174) merged the
reviewed candidate at `913d67248c59c966893dbd374738c07315ed2b1b`.
The lightweight immutable tag `testflight/1.0.1-b12` points to that merge.
The trusted-tools pin remains `2050f1dee6763297fc784f80aaf59c317b2d7e29`.
The build includes saved treadmill profile work merged through issue #144.

[Release run 36326381304](https://github.com/syamaner/paceprompt-ios/actions/runs/36326381304)
completed successfully on attempt 1. Masked logs confirm protected source and
exact-main CI, the credential-free unsigned device archive, same-run handoff
verification, Apple fresh-build/app/sole-tester-group preflight, validated signing
identity/profile, signing without executing candidate build code, internal-only
export and signed-artifact verification. Apple accepted the single upload at
14:38 UTC. At 14:40 UTC, the API confirmed the processed build was internal-only
and assigned to the unchanged sole-tester group. The environment approval was
submitted on the operator's behalf under their explicit internal release
authorisation, with the unchanged non-exempt-encryption declaration. No signed
IPA or signing asset was retained as an Actions artifact.

The complete local gate passed 435 production tests (372 unit, 63 UI), 16
evaluation tests, unsigned Release simulator build, static analysis, coverage
and offline checks with Xcode 27.0 on a fresh, unshared iPhone 17 Pro/iOS 26.5
simulator. Final evidence is `/private/tmp/paceprompt-build12-isolated-ios26-full-gate`.
Two earlier shared-simulator runs ended with Mach `-308` launch-service errors.
An iOS 27 complete run and isolated repeat reproduced four landscape action-button
hittability failures; all four passed unchanged on iOS 26.5 in isolation and the
complete gate. [Issue #173](https://github.com/syamaner/paceprompt-ios/issues/173)
tracks that unresolved forward-compatibility limitation. App code and test
assertions were not changed to obtain the release result.

This receipt confirms upload, Apple processing and internal tester assignment.
Tester installation/visibility, physical Bluetooth, treadmill behaviour and
signed-device protection remain unverified; they require separate device checks.


### Combined iPhone improvements candidate: 1.0.1 (13)

The operator authorised an internal release after Walking label PR #179, profile
selection PR #181 and live-capability ceiling PR #180 merged. The candidate
starts from `e3e5a2b82a8990e4f1d2346f1f4efd2d7e61ab3e`; production Debug and
Release build numbers and matching guard fixtures advance to 13. Marketing
version, privacy/HealthKit declarations, encryption behaviour, workflow and
trusted signing-tools pin remain unchanged. The existing sole-tester internal
group is the destination. Build freshness is checked by hosted Apple preflight
before importing signing assets or uploading; no Apple credentials are copied
locally.

The first complete gate had one iOS text-edit menu test fail to expose Select All;
all other 70 UI tests passed. The same test passed unchanged in isolation. A
complete replacement gate on the unchanged candidate then passed 449 production
tests (378 unit, 71 UI), 16 evaluation tests, unsigned Release simulator build,
static analysis, coverage and offline checks. Evidence is
`/private/tmp/pp-build13-replacement-full`; the initial failed gate is retained
at `/private/tmp/pp-build13-full`. Of 456 frozen tracked regular-file inputs
excluding the accounting ledger, 455 stayed byte-identical. This later
non-executable runbook receipt is the sole difference; executable, test, build
and validation inputs did not change. This is simulator evidence, not
signed-device, Bluetooth or physical treadmill acceptance.

[PR #182](https://github.com/syamaner/paceprompt-ios/pull/182) merged reviewed
head `da950d1294ce562ce02a4abfd82d149db8fa61fa` at
`2cacab9b18801ab34b518c4fee1c8dc5b477d3e3`. Exact-main CI passed; the
merge tree equals the reviewed head. The lightweight immutable tag
`testflight/1.0.1-b13` points to that merge. The trusted signing-tools pin
remained `2050f1dee6763297fc784f80aaf59c317b2d7e29`.

[Release run 36355270842](https://github.com/syamaner/paceprompt-ios/actions/runs/36355270842)
passed on attempt 1. The protected source/unsigned archive jobs passed before
environment approval, which was submitted on the operator's behalf under this
release instruction. The protected job verified the same-run transfer, existing
app/group/tester, fresh build, manual signing identity and internal-only signed
artifact. Apple accepted the one upload; at 22:33 UTC on 27 September 2026,
its processed build was confirmed internal-only and assigned to the unchanged
sole-tester group. The unchanged non-exempt-encryption declaration applied.
No signed IPA or signing asset was retained as an Actions artifact.

Tester visibility, installation and launch have not been observed. Signed-device
protection, HealthKit and physical treadmill acceptance are separate checks.

## Deferred Watch-primary acceptance

Issue #114 freezes the [Watch/Health interchange contract](../../design/watch-primary-health-interchange-contract.md) and [paired-device runbook](../watch-health-interchange-runbook.md). It adds no Watch target or release. #115 now has a merged software implementation; its signed-device acceptance, WeeklyHealthReport #80 and #116 remain separate work; existing release receipts above do not establish Watch or cross-repository interoperability.


### Watch release preparation (#186)

The [two-bundle architecture and validation receipt](../../design/watch-release-preparation.md)
records strict archive transfer, separate profiles, inside-out signing and both-app
verification. This is preparation only: the environment tools pin and credentials
are unchanged, no new build/tag is issued, and no signed export or upload is claimed.
Follow [setup](setup.md#watch-companion-release-boundary-115) before a separately
authorised fresh release. Earlier phone-only receipts do not validate Watch delivery.


### Watch companion candidate: 1.0.1 (14), issue #188

The operator authorised Watch signing setup and an internal-only TestFlight
upload, excluding hardware operation. The candidate advances all four phone/Watch
Debug/Release build settings to 14; marketing version remains 1.0.1. App behaviour,
privacy and encryption declarations, release workflow and signing policy are
unchanged. Existing signing settings, credentials and the sole-tester group are
preserved.

On 28 September 2026, the operator completed registration of the explicit
`com.otherweather.PromptPace.watchkitapp` App ID with HealthKit. The protected
environment's `RELEASE_TOOLS_SHA` was activated and read back as
`ab0ec096af74b79a498b7686fc87476781e612cc`, the independently reviewed PR #187
merge. All 55 release-tool tests, workflow lint, ShellCheck and shell syntax
passed from a separate clean checkout of that exact commit. Watch provisioning
profile generation and validation remain pending at this checkpoint.

Independent review of the candidate build/fixture diff found no actionable
findings. Focused release tests and metadata/boundary checks passed. The complete
local gate passed: 437 production unit tests, 72 simulator UI tests, 16 evaluation
tests, unsigned Release simulator build including Watch, static analysis and
coverage. Offline HostEval passed 247 tests with 36 explicit private-evidence
skips; all 55 script and 24 accounting tests passed. Evidence is
`/private/tmp/pp188-complete-gate` and `/private/tmp/pp188-complete-gate.log`; all
417 frozen non-Markdown inputs remained byte-identical. Documentation checks
passed 42 local links, 34 shell snippets and two embedded Python snippets
(syntax/compile only). Exact-head review and required CI are recorded on the
delivery PR before protected merge. The fresh tag, hosted signing/export, upload,
Apple processing and internal-group assignment remain pending.
Neither setup nor simulator evidence establishes tester visibility, installation,
real mirrored sessions, HealthKit writes or physical treadmill acceptance.
