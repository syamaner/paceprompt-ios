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
