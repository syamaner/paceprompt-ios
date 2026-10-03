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


### Actual Watch profile compatibility (#188)

After explicit operator confirmation on 28 September 2026, Apple generated
`PacePrompt Watch CI App Store` for the fixed Watch companion ID using the existing
distribution certificate. Private local inspection confirmed both profiles have
the same team/certificate, distinct UUIDs, exact role identities, no device or
enterprise distribution and the fixed required entitlements. Only the new
`DIST_WATCH_PROFILE_B64` environment secret was added; the six existing secrets
and tester audience were preserved. Secret-name readback is configuration evidence,
not proof that the hosted signer can use its private key.

Both actual profiles declare the ordered family `iOS, xrOS, visionOS`. The
prepared guard rejected it before any tag/upload. The bounded correction accepts
that exact profile family for phone and Watch while preserving role identity,
certificate and fixed-entitlement validation. Separate device Mach-O checks still
reject visionOS and simulator code. Synthetic profile fixtures exercise this
family through the real shell orchestration with fake Apple tools; additional
negative tests retain unknown/malformed-family and visionOS-binary rejection.

Independent working-diff review found no actionable findings; all 57 script tests
and release lint checks pass. The replacement complete gate passed on all 417 frozen non-Markdown inputs:
437 unit, 72 UI and 16 evaluation tests; unsigned Release simulator build
including Watch, analysis, coverage and offline checks. HostEval passed 247 tests
with 36 explicit private-evidence skips; 57 script and 24 accounting tests passed.
Evidence: `/private/tmp/pp188-profile-gate-v2.log` and
`/private/tmp/pp188-profile-gate-v2`. Documentation checks passed 42 links, 34 shell
snippets and two embedded Python snippets (syntax/compile only). The corrected tools must be reviewed, merged and activated
before release. Build 14 remains unused: no tag, signed export or upload has yet
been attempted. Actual hosted signing/export and Apple acceptance remain pending.

The first profile-repair full gate was stopped after the existing simulator
refused app launches with `Busy / Application failed preflight checks`. All three
affected Health export UI tests passed unchanged on a fresh dedicated simulator
(`/private/tmp/pp188-profile-focused.log`). The replacement gate uses that fresh
simulator and unchanged executable inputs. The failed run is retained at
`/private/tmp/pp188-profile-gate.log` and is not acceptance evidence.


### Build 14 stopped before upload; build 15 recovery (#188)

[PR #190](https://github.com/syamaner/paceprompt-ios/pull/190) merged the real
profile-family correction as `7da0f8e0369bebb605a78a4185423ea361526942`, from
independently approved head `6fd0bb0edff1a72b0072fc81466bf43824fed17d`. Required PR
and exact-main CI passed; the exact merged tools passed their focused tests and
were activated with readback.

Immutable tag `testflight/1.0.1-b14` started
[run 36427295439](https://github.com/syamaner/paceprompt-ios/actions/runs/36427295439).
Source verification, credential-free hosted Xcode 26.6 archive, normal protected
environment approval, Apple fresh-build/sole-tester preflight, both real profile
and CI certificate checks, inside-out signing and internal-only export passed.
The whole-IPA path guard then failed before the single upload command was reached.
No Apple build processing or tester delivery is claimed. Preserve the failed
tag/run; do not rerun or move it.

Local diagnosis reproduced export from the exact hosted unsigned archive, using
an existing matching distribution identity without exporting keys or changing
keychain settings. Temporary profile installations were removed and pre-existing
profiles preserved. Xcode 27.0 added optional `Symbols/` files outside `Payload/`.
Its documented `uploadSymbols=false` option removed those files; the resulting
actual signed phone/Watch IPA passed the unchanged whole-IPA, profile, privacy,
per-architecture certificate/entitlement and strict-signature guard. This is local
signed-export evidence, not hosted 26.6 or Apple upload acceptance. Local evidence:
`/private/tmp/pp188-local-export-v3/export.log`; the signed IPA and private
inspection files remain outside Git and public artifacts.

Build 15 applies that explicit export option, keeping the strict archive policy
unchanged and retaining symbol-package refusal tests. Apple-side symbolication
may be limited because optional symbol submission is disabled; both matching
dSYMs remain in the verified unsigned archive with one-day hosted retention.
The fresh build requires complete validation, independent exact-head review,
protected merge and deliberate tools-pin activation before its new tag.

Build-15 complete local gate passed on the frozen inputs: 437 unit, 72 UI and
16 evaluation tests; unsigned Release simulator build including Watch, static
analysis and coverage; 57 release-script and 24 accounting tests; HostEval 247
tests with 36 explicit private-evidence skips. Evidence is retained at
`/private/tmp/pp188-build15-gate.log` and `/private/tmp/pp188-build15-gate`.
All 417 non-documentation inputs match
`/private/tmp/pp188-build15-frozen-inputs.json`. Documentation checks passed
42 local links, 34 shell snippets (syntax only) and two embedded Python snippets
(compilation only). Independent complete-diff review found no actionable findings.
Exact committed-head review and hosted CI will be recorded on the delivery PR.

### Watch internal release: 1.0.1 (15), issue #188

[PR #191](https://github.com/syamaner/paceprompt-ios/pull/191) merged as
`796819b21382ac7dd038fb989e79e1352aaf06ca`. Its independently reviewed second parent
is `06ebf19eb0a6bc7701486360a47fb9ca61d4cfb0`; the merge tree is identical.
Required [PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36433451866)
and [exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36433605646)
passed. Main protection was not bypassed. The exact clean merged signing tools
passed 57 focused tests and lint before `RELEASE_TOOLS_SHA` activation/readback.

Immutable tag `testflight/1.0.1-b15` and the trusted-tools pin both identify that
merge. The unchanged encryption declaration was bound to this tag.
[Release run 36433756311](https://github.com/syamaner/paceprompt-ios/actions/runs/36433756311),
attempt 1, passed protected-source verification and the credential-free hosted
Xcode 26.6 archive, then received the normal protected-environment approval under
the operator's internal-upload authorisation. Existing main/environment/tag
protections and the sole-tester audience were preserved.

Hosted evidence now establishes both real App Store profiles against the CI
certificate, explicit Watch-then-phone signing, internal-only export and the
unchanged whole-IPA/per-architecture signature, entitlement and privacy guards.
The single upload returned `UPLOAD SUCCEEDED with no errors`. Apple processing
reached `VALID`, the build audience was `INTERNAL_ONLY`, and the processed build
was assigned to and read back from the unchanged sole-tester internal group.
The complete run concluded successfully. Tester-side visibility, installation,
launch and paired-device HealthKit behaviour were not observed.

The retained credential-free unsigned archive has SHA-256
`583a71a68c27586bbba21425975bf6bc02ad6f5757f3647b0ccf78aa84f6613e`.
Its bounded handoff was revalidated against the hosted digest, exact source, tag,
run and attempt. Both `PacePrompt.app.dSYM` and `PacePromptWatch.app.dSYM` are
retained with it at `/private/tmp/pp188-build15-retained/PromptPace.xcarchive`;
the original transfer is `/private/tmp/pp188-build15-hosted-archive/unsigned-release.zip`.
A digest-verified copy of the unsigned transfer is also retained in durable
private local storage at `~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-15/unsigned-release.zip`,
outside Git and the worktree. Temporary extraction paths above may be cleaned
without losing that archive. Optional symbol submission remains disabled, so Apple-side symbolication
may be limited. The hosted archive expires after one day. No signed IPA or signing
asset was uploaded as an Actions artifact.

Watch App ID/profile setup and internal TestFlight delivery under #188 are now
complete. #115 signed paired-device acceptance, WeeklyHealthReport #80 reader
implementation and #116 interoperability acceptance remain outstanding. No
hardware was operated, Health data accessed, tester added or public/external
release submitted. Contract revision 1.1, zero-interval discard, single Watch
writer and permanent iPhone-save suppression remain unchanged.

### Console-override release candidate: 1.0.1 (16), issue #195

Build 16 includes the console-override and moving-step countdown repair from
[PR #194](https://github.com/syamaner/paceprompt-ios/pull/194), merged as
`ab08da04cbd8ec62712e3e7da1800e16e77d0fa1`. The release candidate changes only the
four production phone/Watch build settings, matching synthetic release fixtures
and release documentation/accounting. Marketing version remains `1.0.1`.
Signing settings, release workflow, entitlements, privacy declarations and
cryptography are unchanged. The reviewed signing-tools pin remains
`796819b21382ac7dd038fb989e79e1352aaf06ca`.

The operator authorised the next internal TestFlight upload. Candidate validation,
exact-head review, protected merge and exact-main CI precede creation of the
immutable `testflight/1.0.1-b16` tag. The protected hosted preflight must confirm
the unused Apple build before signing/upload; no API key is copied locally.
Upload, Apple processing and existing-group assignment are separate later gates.
No tester is added and no external/public distribution or hardware operation is
included. The separate Watch save-uncertain observation remains unresolved;
#115 paired-device acceptance, #116 interoperability and WeeklyHealthReport #80
reader work remain outstanding.

The final candidate complete gate passed: 449 unit tests, 72 UI tests, 16
evaluation tests, unsigned iPhone/Watch Release build, static analysis and
coverage; 57 script, 41 scorer, 13 summary, 247 HostEval tests (36 explicit
private-evidence skips), and 24 accounting tests. Evidence is retained at
`/private/tmp/pp-build16-complete-gate` and its sibling `.log`. All 417 frozen
non-Markdown inputs match `/private/tmp/pp-build16-frozen-inputs.json`.
Documentation validation passed 10 local links and 11 shell snippets (syntax
only). Independent working-diff and documentation reviews found no actionable
findings; exact-head review and hosted CI are recorded on the candidate PR.

### Console-override internal release: 1.0.1 (16), issue #195

[PR #196](https://github.com/syamaner/paceprompt-ios/pull/196) protected-merged as
`f416d485a05128204a7788affc951934a042e381`. Its independently reviewed second parent
is `8ec006f0a0051a508aa40ad06f83a40937faed8a`; the merge tree is identical.
Required [PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36488334600)
and [exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36488472363)
passed. Main protection was not bypassed. The release tag was created under the
existing admin-only creation rule; the separate no-bypass update/deletion rules
remain active. No protection settings changed.

Immutable tag `testflight/1.0.1-b16` identifies that source. The reviewed tools pin
remained `796819b21382ac7dd038fb989e79e1352aaf06ca`, and the unchanged encryption
declaration was bound to this tag. The candidate workflow matches the reviewed
workflow byte-for-byte. [Release run 36488598314](https://github.com/syamaner/paceprompt-ios/actions/runs/36488598314),
attempt 1, passed source verification and the credential-free hosted Xcode 26.6
archive. Normal protected-environment approval followed under the operator's
explicit internal-upload authorisation.

The trusted hosted preflight confirmed fresh build 16 and the existing app and
sole-tester group. Both apps passed profile/certificate validation, inside-out
signing, internal-only export, and whole-IPA/per-architecture signature,
entitlement and privacy checks. The single upload returned
`UPLOAD SUCCEEDED with no errors`. Apple API processing reached `VALID` with
`INTERNAL_ONLY` audience; the existing group's build-list readback confirmed
assignment. All release jobs succeeded. No tester was added.

This is hosted App Store Connect API evidence. The separate browser visual check
could not be completed because the existing App Store Connect session had expired;
no credentials were extracted or copied. Tester-side visibility, installation,
launch and build-16 paired-device behaviour remain unobserved. These boundaries
are not changed by the green workflow.

Unsigned archive SHA-256:
`0abea11b54f595f488847cba9fd3fb23d48cb2a408b233fc495ddfa1a540f504`.
It matches the hosted handoff digest and was revalidated against exact source,
tag, run and attempt. The transfer and both phone/Watch dSYMs are retained in
private local storage at
`~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-16/unsigned-release.zip`
(file mode 600, containing directory 700), outside Git and the worktree.
Temporary extraction is `/private/tmp/pp-build16-retained/PromptPace.xcarchive`.
No signed IPA or signing asset was downloaded or published as an Actions artifact.
Optional symbol submission remains disabled; Apple-side symbolication may be
limited. The hosted unsigned artifact expires after one day.

Build 16 contains the #193 repair; build 15 does not. Use the
[console override acceptance procedure](../../design/console-overrides-and-step-clock.md)
and [paired-device HealthKit procedure](../watch-health-interchange-runbook.md)
for later testing. The separate Watch save-uncertain observation remains unresolved.
#115 signed-device acceptance, #116 interoperability and WeeklyHealthReport #80
reader implementation remain open. No hardware was operated in this release.

### Watch durability release candidate: 1.0.1 (17), issue #200

The operator authorised the next internal TestFlight release containing #198,
merged in [PR #199](https://github.com/syamaner/paceprompt-ios/pull/199) as
`a497c78b5816f8a67673fcec86d356efc7cd23e2`. Build 17 includes visible recording
controls, verified-stop recovery and background/foreground reconciliation.
Build 16 does not contain this repair. Marketing version remains `1.0.1`; all
four phone/Watch build settings and matching synthetic fixtures advance to 17.
App behaviour, signing settings, profiles, workflow, privacy and encryption
declarations are unchanged in the release candidate. The reviewed tools pin
remains `796819b21382ac7dd038fb989e79e1352aaf06ca`.

Candidate validation, independent exact-head review, protected merge and exact-
main CI precede the immutable `testflight/1.0.1-b17` tag. The hosted protected
preflight checks Apple build freshness and the existing sole-tester group before
signing or upload; no API key is copied locally. Upload, valid Apple processing
and group assignment are separate release gates. No new tester, public/external
distribution, hardware operation or dependent reader implementation is included.
Use the [durability acceptance procedure](../watch-health-interchange-runbook.md#durability-acceptance-198-unperformed-on-devices)
on both updated devices; #115/#116 acceptance and WeeklyHealthReport #80 remain
separate work. Availability never proves installation or physical behaviour.

The complete candidate gate passed on Xcode 27.0 (27A266a), iOS 26.5 simulator:
475 unit, 72 UI and 16 evaluation tests; unsigned Release including Watch; static
analysis and coverage; 57 script, 41 scorer, 13 summary, 247 offline HostEval tests
(36 explicit private-evidence skips), and 24 accounting tests. Evidence is
`/private/tmp/pp-build17-complete-gate` and its sibling `.log`. All 418 frozen
non-Markdown inputs, including the tracked skill symlink, match
`/private/tmp/pp-build17-frozen-inputs.json`. Documentation validation passed
13 local links and 11 shell snippets (syntax only). Exact-head review and
required hosted CI are recorded on the delivery PR. These results do not claim
signed export, upload, Apple processing, tester installation or device acceptance.

### Watch durability internal release: 1.0.1 (17), issue #200

[PR #201](https://github.com/syamaner/paceprompt-ios/pull/201) merged through normal
main protection as `5114c65b1a3fd5441ca8e5e0a835f5c77845d33b`. Its independently
reviewed second parent is `983752c6f9f81ef547ee9f3019e0329aa830cff7`; the trees
are identical and the merge records the exact-head attestation. Required
[PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36542275631) and
[exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36542368498)
passed. Main protection was not bypassed. The lightweight immutable tag
`testflight/1.0.1-b17` was created using the existing admin-only tag-creation
exception; separate no-bypass tag update/deletion rules remain unchanged.

[Release run 36542470238](https://github.com/syamaner/paceprompt-ios/actions/runs/36542470238),
attempt 1, succeeded from that source. The reviewed tools pin remained
`796819b21382ac7dd038fb989e79e1352aaf06ca`; candidate workflow/tools, signing
policy, profiles, privacy and encryption declarations were unchanged. Source and
credential-free unsigned archive verification passed before normal protected
environment approval under the operator's internal-upload authorisation.

Hosted preflight confirmed fresh build 17 and the existing app/sole-tester group.
Both bundles passed profile/certificate, inside-out signing, internal-only export,
whole-IPA/per-architecture signature, entitlement and privacy checks. Exactly one
upload-success marker was recorded: `UPLOAD SUCCEEDED with no errors`. Trusted
Apple API checks established processing `VALID`, audience `INTERNAL_ONLY`, and
existing-group build-list readback. No tester was added or external/public
release submitted. The browser session expired, so no separate visual Apple
verification was completed. Tester visibility, installation/launch and build-17
paired-device observations remain unverified.

Unsigned archive SHA-256:
`497563e4078f7679d634a23c43aa23e5d52af40438d05d0fdc82f59582f384c1`.
The retained transfer matches the hosted digest and passes source/tag/run/attempt
identity, bounded unpacking and both unsigned-device bundle checks. The archive
and both phone/Watch dSYMs are retained privately at
`~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-17/unsigned-release.zip`
(file mode 600, directory 700). Temporary extraction is
`/private/tmp/pp-build17-retained/PromptPace.xcarchive`. Optional symbol submission
remains disabled. No signed IPA, signing material or Health data was retained
as an Actions artifact.

Build 17 contains #198; build 16 does not. Update both phone and Watch before
following the [durability acceptance procedure](../watch-health-interchange-runbook.md#durability-acceptance-198-unperformed-on-devices).
Check foreground/background transitions and the recording controls separately
from normal single-workout Health saving. Stop recording affects recording only;
the treadmill must still be stopped at its console. #115 paired-device acceptance,
#116 interoperability and WeeklyHealthReport #80 reader/privacy work remain open.
No hardware was operated during this release.


### Watch startup/shutdown release candidate: 1.0.1 (18), issue #205

The operator authorised an internal release containing #203, merged in
[PR #204](https://github.com/syamaner/paceprompt-ios/pull/204) as
`c8cd1866aa95d38b7f3ecd79eafab4c92cdb328d`. Build 18 contains stable startup
progress, foreground/unlock capability refresh, verified native end before Watch
saving, late-callback isolation and bounded terminal-message retries. Build 17
does not contain this repair. Both phone and Watch must be updated for testing.

The candidate changes only the four phone/Watch build settings to 18 and matching
synthetic release fixtures, plus documentation/accounting. Marketing version stays
`1.0.1`. Signing configuration, profiles, workflow, privacy/encryption declarations
and trusted tools pin `796819b21382ac7dd038fb989e79e1352aaf06ca` are unchanged.
The existing sole-tester internal group is the only destination. No new tester,
external/public distribution, hardware operation or reader implementation is included.

Complete candidate validation, independent exact-head review, protected merge with
attestation, exact-main CI and tree equality precede the immutable
`testflight/1.0.1-b18` tag. Hosted preflight checks Apple build freshness before
importing signing assets or uploading; no Apple key is copied locally. The standing
no-non-exempt-encryption decision applies because encryption behaviour is unchanged.
Normal protected-environment approval is submitted under this explicit release
instruction only after source and unsigned archive checks pass.

Upload, Apple processing, existing-group assignment, tester installation and paired-
device acceptance remain distinct. Use the [startup/shutdown acceptance procedure](../watch-health-interchange-runbook.md#startupshutdown-acceptance-203-unperformed-on-repaired-devices)
after both devices update. Contract revision 1.3, unchanged wire/metadata v1 and
fixture bytes do not establish device acceptance. #115/#116 and WeeklyHealthReport
#80 remain open dependent work. Release outcome will be recorded separately.

Candidate local validation passed at `/private/tmp/pp-build18-complete-gate`
(log `/private/tmp/pp-build18-complete-gate.log`): 490 unit, 72 UI and 16 evaluation
tests; Release simulator build including Watch; static analysis and coverage;
57 script, 41 corpus, 13 summary, 247 offline host tests (36 explicitly skipped
private-evidence cases), and 24 accounting tests. No application test was skipped.
All 418 frozen non-Markdown inputs, including the skill symlink, remained identical.
Independent pre-commit diff/documentation review found no actionable issues;
exact-head review and protected hosted gates remain required before release.


### Watch startup/shutdown internal release: 1.0.1 (18), issue #205

Candidate [PR #206](https://github.com/syamaner/paceprompt-ios/pull/206) merged
through normal protected main as `acc547420aa6b3703951ca8195cd03c374849927`,
with exact-head attestation for independently approved
`afb8364b718cfec9fab5c098765d93868a1dcf64` and equal Git trees. Required
[PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36777295499) and
[exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36777420767)
passed. The complete local gate is recorded above.

Immutable lightweight tag `testflight/1.0.1-b18` identifies that merge.
[Release run 36777559090](https://github.com/syamaner/paceprompt-ios/actions/runs/36777559090)
is attempt 1. The existing administrator exception admitted tag creation; main
protection and immutable-tag update/delete rules were not bypassed or changed.
Normal required environment review approved only this internal release after
source verification and unsigned archive success. The reviewed workflow and
trusted tools pin `796819b21382ac7dd038fb989e79e1352aaf06ca` remain unchanged.

Hosted preflight confirmed the fresh build and existing sole-tester group. Both
phone and Watch passed profile/certificate checks, inside-out signing, internal-only
export, whole-IPA/per-architecture signature, entitlement and privacy verification.
Exactly one upload-success marker was recorded: `UPLOAD SUCCEEDED with no errors`.
Trusted Apple API checks confirmed processing `VALID`, audience `INTERNAL_ONLY`
and existing-group build-list readback. No tester was added or external/public
release submitted. No separate Apple browser visual check was performed; tester
visibility, installation/launch and build-18 paired-device observations remain
unverified.

Unsigned archive SHA-256:
`5c4d8c60cfcfda8955faafd904b3e13f8298bdc560a7a1f75e0218ca58e31f03`.
The retained transfer matches the hosted digest and passes source/tag/run/attempt
identity, bounded extraction and both unsigned-device bundle checks. The archive
and both phone/Watch dSYMs are retained privately at
`~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-18/unsigned-release.zip`
(file mode 600, directory 700). Temporary extraction is
`/private/tmp/pp-build18-retained/PromptPace.xcarchive`. Optional symbol submission
remains disabled; no signed IPA or signing asset was retained as an Actions artifact.

Build 18 includes #203; build 17 does not. Update both phone and Watch before the
[startup/shutdown acceptance procedure](../watch-health-interchange-runbook.md#startupshutdown-acceptance-203-unperformed-on-repaired-devices).
Check a single Begin action, background/foreground recovery, automatic Watch
completion after phone end, and one saved Health workout or explicit zero-interval
discard. Emergency Stop recording affects recording only; stop treadmill motion
at its console. Contract revision 1.3, wire/metadata v1, journal v2 and shared
fixture bytes are unchanged. #115 signed paired-device acceptance, #116
interoperability and WeeklyHealthReport #80 reader/schema-v4/privacy work remain
open. No hardware was operated during this release.

## Internal build 19 candidate (#214)

The operator requested a new internal release on 1 October 2026 to test the Watch
recovery/startup ordering repair from #212 / protected PR #213. Candidate
**1.0.1 (19)** keeps phone and Watch versions equal and updates the matching
release-guard fixtures. App code, workflow, signing tools, privacy declarations,
entitlements and the standing no-non-exempt-encryption decision are unchanged.
The protected candidate merge, tag and hosted receipt are recorded separately
after their gates pass; this candidate entry does not claim upload or processing.

Build 18 does not contain #213. That repair addresses two deterministic races,
but the real-device failure remains open. With explicit approval, the isolated
iOS/watchOS 26.5 pair completed its exact Health permissions and recovered an old
timeout through Stop recording and Prepare next workout. Two fresh native starts
(including one pair restart) failed because the simulator HealthKit transport
could not find its companion. Empty attempts were discarded. This does not
establish the cause on the user's Watch or a successful native save.

After build 19 is actually available, install both companions and repeat the
[startup/shutdown acceptance procedure](../watch-health-interchange-runbook.md#startupshutdown-acceptance-203-unperformed-on-repaired-devices).
Record installed builds, startup, normal phone end, single-workout save or explicit
empty discard, and background/foreground recovery separately. #212/#115 remain
open; #116 and WeeklyHealthReport #80 retain their independent acceptance/reader
work. No physical operation or new tester is included in this release.

## Internal build 19 release receipt (#214)

On 1 October 2026, candidate [PR #215](https://github.com/syamaner/paceprompt-ios/pull/215)
merged through normal protected main as
`ec6f2bd7b2300755abf60b0da760da06d4b7ee90`, from independently approved head
`937f117c3f5028787ad74c92b3837f3cb594a245`. The merge includes its exact-head
attestation, has the reviewed head as second parent and has an identical tree.
Required [PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36832075767)
and [exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/36832194527)
passed. Immutable lightweight tag: `testflight/1.0.1-b19`. Main protection was
not bypassed; tag creation used its existing admin-only creation exception,
with tag update/deletion protection unchanged.

[Release run 36832307430](https://github.com/syamaner/paceprompt-ios/actions/runs/36832307430),
attempt 1, succeeded through the normal protected environment approval. The
unchanged tools pin is `796819b21382ac7dd038fb989e79e1352aaf06ca`. Source and
unsigned archive verification, fresh Apple build/group preflight, both profiles,
both signed apps, privacy, exact entitlements and internal-only export passed.
The log records exactly one accepted upload, then Apple API processing
`VALID` / `INTERNAL_ONLY` and assignment visible in the unchanged sole-tester
group. The standing no-non-exempt-encryption declaration is unchanged. No
external/public release, new tester or physical operation occurred.

Unsigned archive SHA-256:
`96d9fbdc3e435c1d6140dad4696b4e444188aab5b7f440bbaf1b6caf244af124`.
The retained package matches the hosted archive digest and passed bounded
extraction plus source/tag/run/attempt identity and device-bundle checks. Both
phone and Watch dSYMs are present. Private retention:
`~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-19/unsigned-release.zip`
(file mode 600, directory 700). No signed IPA or signing material was retained
as an Actions artifact. Optional symbol upload remains disabled.

These are hosted release and Apple API observations. Browser visual verification
was unavailable because the Apple session expired. Tester visibility, installation,
launch and signed-device acceptance were not observed. Update both companions
to **1.0.1 (19)** before testing. This release contains #213; build 18 does not.
An older uncertain attempt remains preserved and may still require verified
Stop recording then Prepare next workout before a fresh phone start. Updating
does not silently retire it. #212/#115 remain open; #116 and WeeklyHealthReport
#80 remain separate interoperability/reader work.

## Internal build 20 candidate (#218)

The user authorised internal TestFlight **1.0.1 (20)** on 2 October 2026 to test
[PR #217](https://github.com/syamaner/paceprompt-ios/pull/217)'s Watch finish/save
repair and one-tap ordinary phone ending. The candidate starts from protected main
`f79c1429cda8372ad16a3cf19353dc5e0a49f13b`, keeps phone/Watch Debug and Release
versions equal and updates the release-guard fixtures. Production code, workflow,
trusted tools pin, signing configuration, permissions, privacy declarations,
entitlements and the standing no-non-exempt-encryption decision are unchanged.
The tag is unused; hosted trusted preflight must establish Apple build freshness
and the unchanged app/group/tester before signing/upload. This candidate entry
does not claim an upload, processing, installation or Health save.

Build 19 does not contain #217. After build 20 is actually processed and available,
update both companions and follow the [finish/save acceptance procedure](../watch-health-interchange-runbook.md).
Use one explicit ordinary phone end and leave Watch untouched; require exactly
one nonempty Health workout and check local History separately. Repeat background/
foreground and manual overrides only after basic foreground completion passes.
Retained uncertain attempts are not silently retired or replaced by an update.
#212/#115 remain open, #211 remains the wider UX audit, and #116/WeeklyHealthReport
#80 remain separate reader/interchange work. No hardware, real Health readback,
new tester or external/public release is included in this candidate delivery.

## Internal build 20 release receipt (#218)

On 2 October 2026, [candidate PR #219](https://github.com/syamaner/paceprompt-ios/pull/219)
merged normally through protected main as
`575a86e3842b94e02ba648d015a4684f3e0c7a33`, from independently approved exact head
`742677dd0e210485fc35e4c0b63488b707ba6bd5`. The merge has that head as its second
parent, an identical reviewed tree and the exact-head attestation. Required
[PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/37066613998) and
[exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/37066754913)
passed. All 417 frozen candidate inputs match the merged blobs. Immutable
lightweight tag: `testflight/1.0.1-b20`. Main protection was not bypassed; tag
creation used its existing admin-only creation exception, with update/deletion
protection unchanged.

[Release run 37066974021](https://github.com/syamaner/paceprompt-ios/actions/runs/37066974021),
attempt 1, succeeded through normal protected environment approval. Exact tag,
source, unchanged trusted tools pin `796819b21382ac7dd038fb989e79e1352aaf06ca`
and export allowlist readback were checked before approval. The standing
no-non-exempt-encryption declaration remains unchanged. Source verification,
unsigned archive verification, fresh Apple build/app/group/tester preflight,
both profiles, both signed apps, privacy, exact entitlements and whole-IPA
verification passed. One `UPLOAD SUCCEEDED` marker was observed. The trusted
Apple API guard permits its processed-build success only after `VALID` and
`INTERNAL_ONLY`, then confirms membership in the unchanged sole-tester group's
build list. Its final processed/internal-group success was observed; no second
upload or workflow rerun occurred.

Unsigned archive SHA-256:
`94d90ecf1d7971d6690b5ed98f8a479d58f1d4b551c885b54ac32aedf53a338c`.
The privately retained package matches the hosted digest and passed bounded
extraction with exact source/tag/run/attempt identity and both unsigned device
bundle checks. Both `PacePrompt.app.dSYM` and `PacePromptWatch.app.dSYM` are present.
Private retention: `~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-20/unsigned-release.zip`
(package mode 600, directory mode 700). No signed IPA/signing asset was retained
as an Actions artifact; optional symbol upload remains disabled.

These are hosted release and Apple API guard observations. Browser visual
verification, tester-side visibility, installation, launch and signed-device
Health saving were not observed. No hardware, real Health readback, added tester
or external/public release occurred. Update both companions to **1.0.1 (20)**
and follow the [finish/save acceptance procedure](../watch-health-interchange-runbook.md).
Build 20 contains #217; build 19 does not. Normal phone ending should require one
explicit eligible action and no Watch tap; require exactly one nonempty Health
workout and check PacePrompt History separately. An update does not silently
retire or replace an older uncertain attempt. #212/#115 remain open, #211 remains
the wider UX audit, and #116/WeeklyHealthReport #80 remain separate reader and
interoperability acceptance work.

## Build 20 device follow-up: save failure (#212)

After a newly completed build 20 workout, the operator's private Watch photo
reports a known pre-finish save failure; the phone reports local ending and
Watch end sent. This fails save acceptance and does not invalidate the separate
upload/processing/group evidence above. No personal metrics or images are stored
here and no Health database readback was inspected.

The [revision 2 save amendment](../../design/watch-finish-save.md#build-20-collection-closure-follow-up)
repairs a native simulator-reproduced interval-insertion order defect. Build 20
does not contain that repair. A later reviewed internal candidate is required
before repeating the existing foreground acceptance procedure. Retain old failed/
uncertain outcomes; no finish retry, phone replacement export or Health deletion.
Native paired simulator binding still failed separately; successful standalone
native saving is not full paired-device acceptance. Keep #212/#115 open.

## Internal build 21 candidate (#222)

The operator authorised the next internal release on 3 October 2026 to test
#221's Watch interval-save repair, merged as
`5ed7abf3073e42c4fb2c3f3a6319834730c4b00f`. Candidate **1.0.1 (21)**
advances both companions together and updates matching synthetic release
fixtures. Marketing version, production logic, workflow, signing tools, privacy
and encryption declarations remain unchanged. The destination is the existing
sole-tester internal group; the trusted tools pin remains
`796819b21382ac7dd038fb989e79e1352aaf06ca`. Hosted preflight checks the unused
Apple build and unchanged app/group/tester before signing or upload.

Build 20 lacks #221. A standalone native simulator save succeeded with three
closed intervals after the repair; native paired startup still failed separately.
This candidate does not establish installation, automatic device saving,
background recovery, accepted-distance readback or cross-repository acceptance.
After both companions are updated, repeat the foreground phone-end procedure
and leave Watch untouched while checking one nonempty Health workout separately
from PacePrompt History. Retain older failed/uncertain outcomes without retry
or replacement. #212/#115 remain open; #116 and WeeklyHealthReport #80 remain
separate reader/interchange work.

Candidate validation, independent exact-head review, protected merge/CI and the
immutable release receipt are recorded at their respective gates. No physical
operation, new tester or external/public release is included.

The complete candidate gate passed on the dedicated iPhone 17 Pro/iOS 26.5
simulator using Xcode 27.0: 512 unit, 72 UI and 16 evaluation tests; unsigned
Release builds including Watch, static analysis, coverage and repository checks.
Offline HostEval passed 247 tests with 36 unavailable-evidence skips. The
evidence root is `/private/tmp/pp-b21-full-gate`; all 417 frozen executable/test/
build inputs remain identical. Independent working-diff review approved before
the gate. Exact-head review and required hosted PR/main CI precede release.

## Internal build 21 release receipt (#222)

On 3 October 2026, [candidate PR #223](https://github.com/syamaner/paceprompt-ios/pull/223)
merged through protected main as `1e34be1a9ae3fa87b7016788c13403ac6a296abf`,
from independently approved head `1c779a6b02ad62e83aa66e392e95a8d23e97e12a`.
Required [PR CI](https://github.com/syamaner/paceprompt-ios/actions/runs/37099087496)
and [exact-main CI](https://github.com/syamaner/paceprompt-ios/actions/runs/37099117490)
passed. The merge tree and all 417 frozen candidate inputs match the reviewed
head. The candidate's full local gate is recorded above. Immutable lightweight
tag `testflight/1.0.1-b21` points to that merge. Its creation used the existing
admin-only tag-creation exception; tag update/deletion and main protection were
unchanged, and main was not bypassed.

[Release run 37099154214](https://github.com/syamaner/paceprompt-ios/actions/runs/37099154214),
attempt 1, succeeded. The credential-free Xcode 26.6 archive passed before normal
protected-environment approval under the operator's internal-release instruction.
Exact tag/source, unchanged workflow and trusted tools
`796819b21382ac7dd038fb989e79e1352aaf06ca`, export-compliance allowlist and
same-run archive identity were verified. The standing no-non-exempt-encryption
declaration applied unchanged to build 21.

Trusted preflight verified the existing app, fresh build and sole-tester group.
Both profiles, inside-out signing, internal-only export and both signed apps'
metadata, privacy and fixed entitlements passed. The log records exactly one
`UPLOAD SUCCEEDED with no errors` marker. The trusted Apple guard confirmed
processed `VALID` / `INTERNAL_ONLY` and assignment in the unchanged sole-tester
group's build list. No workflow rerun or second upload occurred.

The Actions wrapper artifact digest was
`232239c29cbd50aa36551bdee8f5c75685aa72d8e9cebafc039e17431c442944`.
The inner unsigned archive digest was
`5e22fb02a6386dd77bc8cd3d9ccb5cf811fbde59dbecbc6e0fd467197d374451`.
The download matched the hosted digest, bounded extraction verified the exact
source/tag/run/attempt, and both unsigned device apps passed validation. Matching
archive and both dSYMs are retained privately under
`~/Library/Application Support/PacePrompt/ReleaseArchives/1.0.1-21/` with
directory mode 700 and file mode 600. Only the unsigned package was transferred
as an Actions artifact. Optional symbol upload remains disabled.

These are hosted-release and Apple API observations. Browser visual verification,
tester installation and physical Health acceptance were not observed. Update
both companions to **1.0.1 (21)** before the foreground phone-end test. This
build contains #221; build 20 does not. Physically stop the treadmill, use the
eligible phone end action and leave Watch untouched while checking its saved
result and exactly one nonempty Health workout; check local History separately.
Preserve older failed/uncertain attempts without finish retry or replacement.
#212/#115 remain open for save/recovery acceptance, #211 for the wider confirmation
audit, and #116/WeeklyHealthReport #80 for reader/interchange work. No hardware,
new tester or external/public distribution was included in this release.


## Internal build 22 candidate (#227)

The operator authorised internal **1.0.1 (22)** on 3 October 2026 after #209/#211.
Baseline main `ce97934d100e01af3dd8d31c5217b52ece231a84` includes clearer product
copy (#225) and direct recovery actions (#226). Watch recovery uses Stop recording,
then Prepare next workout without duplicate dialogs; interrupted/failed iPhone
recovery records one explicit belt-stopped observation. Normal phone ending still
finishes Watch recording automatically. Incomplete/uncertain save distinctions,
no replacement, zero-interval discard and physical console authority are unchanged.

This candidate changes only the four phone/Watch build numbers to 22 and matching
synthetic release fixtures. Version 1.0.1, bundle identities, workflow, trusted
signing tools, profiles, privacy, permissions and encryption behaviour are unchanged.
Use the standing no-non-exempt-encryption decision only for this unchanged behaviour.
The existing internal-only, explicit-assignment sole-tester group remains the sole
destination. No new testers or external/public release.

The build-22 tag was absent and build 21 was the latest successful release when
preparing this candidate. Apple freshness is checked by trusted hosted preflight
before signing/upload; protected Apple credentials are not copied locally.
The complete local gate passed on 3 October 2026 with Xcode 27.0 (27A266a),
SDK 27.0 and the dedicated iPhone 17 Pro / iOS 26.5 simulator: 517 unit tests,
72 UI tests and 16 evaluation-target tests, zero failures. Release simulator build,
static analysis, coverage, built-bundle safety/metadata checks and 24 accounting
helper tests passed. Offline checks passed 57 release tests, 41 scorer tests,
13 summary tests and 247 HostEval tests (36 private-evidence skips). Focused
metadata, actionlint, shell syntax and shellcheck passed. All 417 frozen
executable/test/build inputs remain unchanged. Private evidence:
`/private/tmp/pp22-complete-gate.log` and `/private/tmp/pp22-complete-gate/`.
Local document links and `git diff --check` passed. Candidate preparation is not
an upload or installation receipt.

After delivery, update both companions to build 22. Test normal phone ending
without Watch taps and exactly one nonempty Health workout; separately check the
two direct Watch recovery actions and one-tap phone recovery when needed. See
[confirmation decisions](../../design/confirmation-decisions.md) for the procedure
and limits. Interactive Watch scrolling/VoiceOver, tester installation and physical
Health/treadmill acceptance remain unobserved until tested. Preserve older uncertain
attempts without save retry or replacement. #210 remains separate diagnostics work.
