# Watch release preparation architecture gate

This separately authorised slice prepares the merged #115 companion for the existing internal-only release pipeline. It changes release tooling, its synthetic tests and runbooks; it does not authorise Apple credential/account changes, signing a release, tag creation, upload, device installation, HealthKit access, treadmill operation or WeeklyHealthReport implementation.

## Closed signing boundary

Keep source verification and unsigned building on runners without Apple secrets. The credential-bearing runner executes only the independently pinned trusted tools. Candidate source is metadata, never imported or executed there. The source/tag/run/digest identity, first-attempt policy, protected merge/exact-head attestation, internal-only export and one-upload rules stay intact.

The only accepted application graph is `PacePrompt.app` and `Watch/PacePromptWatch.app`, with bundle IDs `com.otherweather.PromptPace` and `com.otherweather.PromptPace.watchkitapp`. A shared fixed policy validates both versions, executable names, device platforms, narrow permissions/privacy declarations, Watch companion linkage and background modes. Unknown apps, extensions, frameworks, dylibs, executable resources, symlinks and unexpected provisioning/signature content fail closed. Both dSYMs may travel as inert data. Payload paths, collisions and size limits remain bounded and are validated before extraction.

The unsigned archive inspected with Xcode 27.0 contains iPhone arm64 and Watch arm64 plus arm64_32; both Watch slices have WATCHOS load commands. Platform validation checks Mach-O load commands rather than trusting Info.plist. This is build evidence only. The pinned hosted toolchain remains Xcode 26.6; its actual distribution output still requires a separately authorised run.

Each app requires its own explicit App Store profile, with the exact fixed app identity, the same team and approved distribution certificate, HealthKit and no debugging/device/enterprise grant. The profile platform-family compatibility policy accepts iOS and the exact ordered family iOS/xrOS/visionOS for both roles, plus watchOS or the ordered iOS/watchOS pair for Watch. The three-entry family was observed in both Apple-issued profiles during authorised #188 setup. This shared profile family does not broaden the separate device Mach-O policy. Exact role identity is mandatory. Entitlements come from trusted policy, not the candidate or profile's broader grants. Sign the Watch first and the enclosing phone last, then map both profiles explicitly for internal-only export. Validate both exported bundles' metadata, device code, profile, exact entitlements, certificate leaf and strict signatures before upload is reachable. Never use `codesign --deep` as the signing strategy.

Profile decoding, file operations, Apple-tool invocation and orchestration remain separate from pure policy checks. Synthetic profile/archive fixtures and mocked subprocess tests cover both successful and hostile traces, including failure of the inner bundle blocking export/upload. Ordinary app versions need no policy rewrite; introducing any new bundle/capability or layout does.

## Evidence and rollout

Run focused release tests, an unsigned device archive pack/unpack/validation, workflow/shell checks, independent security review and the complete local gate on final inputs. Capture exact development accounting, exact-head review and required CI before protected merge. Keep synthetic, unsigned-build, mocked-signing, actual signed-export, Apple-processing and paired-device evidence distinct.

After merge, a later authorised setup must supply the companion profile and deliberately update the independently reviewed tools pin; preparation does not mutate that environment. A fresh build number and an attested candidate merge are required for a later release. Existing build 13 is not a new upload candidate.

Apple grounding: [nested signing order](https://developer.apple.com/documentation/xcode/using-the-latest-code-signature-format), [App Store profile creation](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile), and [manual distribution signing](https://help.apple.com/xcode/mac/current/en.lproj/devcac6ab5b3.html).

Exported IPA inspection is also bounded: only `Payload/PacePrompt.app` and its
exact Watch child are accepted. Unknown top-level support directories or sibling
apps fail closed before extraction/signature inspection. Any required Apple export
layout extension needs its own reviewed policy update. Certificate, identity and
exact-entitlement display checks explicitly select every Mach-O architecture;
strict verification also covers all architectures.


## Preparation evidence (28 September 2026)

The local unsigned device archive confirmation completed with exit 0 and
`ARCHIVE SUCCEEDED` under Xcode 27.0 (27A266a); both bundles pass the trusted
unsigned guard. The earlier quiet invocation also returned exit 0 but emitted
an ambiguous SwiftCompile diagnostic, so the explicit confirmation is the build
receipt. No source change was needed. The two-app/two-dSYM archive completed a
bounded pack/unpack round trip and guard validation. The test handoff uses a
synthetic run identity, not an actual release tag or GitHub signing run.

Evidence paths: `/private/tmp/pp186-unsigned-confirm.log`,
`/private/tmp/pp186-unsigned-confirm.xcarchive`,
`/private/tmp/pp186-unsigned-guard.log` and
`/private/tmp/pp186-handoff-receipt.txt`. These are local development receipts;
no real signing profile or private health data was used. Mocked shell tests use
synthetic certificates/profiles and fake Apple tools, including the upload tool.
They prove ordering and refusal behaviour, not real signatures or Apple acceptance.


Independent working-diff review found no remaining P1/P2 after repairing
per-architecture signature display checks and whole-IPA topology validation.
All 55 repository script tests and 24 accounting-helper tests pass. Documentation
checks covered 41 local links, 34 shell snippets (syntax only) and two embedded
Python snippets (compile only); workflow lint and shell syntax pass.

The complete local gate passed on the 417 frozen non-Markdown inputs: 437
production unit tests, 72 iPhone simulator UI tests, 16 developer-only evaluation
tests, unsigned Release simulator build including Watch, static analysis and
coverage. Offline HostEval completed 247 tests with 36 explicit skips for absent
ignored private evidence; the remaining offline checks passed. Full receipt:
`/private/tmp/pp186-complete-gate.log`, with results in
`/private/tmp/pp186-complete-gate`. Exact committed-head review and required hosted
CI are recorded on the delivery PR. This gate establishes software evidence only.
