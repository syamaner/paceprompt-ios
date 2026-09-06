# Issue 19 review handoff

## Issue 26 DEBUG-only redacted validation tracing — 6 September 2026

A separate DEBUG-only inspector now reports closed validation stages without becoming
part of the production parser. Its injectable sink receives only stable enums, request
count and coarse elapsed buckets. The default DEBUG sink writes stable public codes to
Apple unified logging; OS logging retention may apply. No prompt, request/response,
received identity, URL, ID, workout value, provider/native error, credential, header or
Keychain bytes can enter an event.

Synthetic tests drive every declared stage through the adapter and presentation path,
prove preview/save separation and a single request, and seed secret markers into user,
envelope, message and structured-content fields without disclosure. Separate fixtures
classify `native_finish_reason: "completed"` and rejected neighbours while preserving
the current production rule that only `"stop"` is accepted when the field is present.
Extra envelope/message fields and malformed structured content remain rejected.

The new implementation and all call sites are conditional on `DEBUG`; Release UI and
behaviour are unchanged. The inspector's output never changes routing, retries,
acceptance, deterministic mapping, local validation, preview or persistence. This
code-only milestone makes no provider request, reads no real credential, incurs no
OpenRouter spend and adds no physical-device, treadmill, FTMS, HealthKit or watchOS
authority.

Validation on Xcode 26.6 (`17F113`) and the iPhone 17 Pro Max iOS 26.5 simulator:

- focused import boundary tests: 25/25 passed;
- complete `PacePrompt` tests: 117/117 passed;
- complete developer-only evaluation tests: 14/14 passed;
- unsigned generic-simulator Release build and Release static analysis: succeeded;
- pinned-resource/source-privacy and built-bundle verification: passed;
- Release executable search: no diagnostic type, subsystem-code or log-category
  strings, and no evaluation artifact was bundled;
- phase-accounting helper tests: 20/20 passed; and
- `git diff --check`: passed.

## Provider-bound requested-alias amendment — 6 September 2026

The third authorised simulator observation made exactly one request and failed closed
as `identityModelAlias`. The separately viewed provider-side generation record reported
the selected canonical revision and OpenAI route. This establishes an OpenRouter
identity-representation mismatch: the API envelope can use the requested alias even
when the provider-side record attributes the generation to the selected revision.

The amended parser validates model and provider as one tuple. It accepts either the
canonical revision or the exact requested alias only when `provider` is exactly
`openai` or `OpenAI`. Missing, non-string, unqualified and unrelated model identities,
and missing or different providers, still fail closed. No received identity value,
response body, credential or provider record is logged or retained. Request routing,
privacy controls, schema validation, local mapping/validation and save authority are
unchanged. Development-mode redacted validation tracing is deferred to a separate
issue rather than added to this production fix.

## Second-stage redacted model classification — 6 September 2026

The authorised simulator observation against remote main `175b8279d5047b6e9ec1f19f94076f667560191d`
made exactly one provider request and failed closed as `identityModelMismatch` before provider,
envelope, proposal mapping or local validation could be established. This follow-up diagnostic
keeps the exact canonical-only acceptance rule while classifying a mismatched top-level model as
the requested alias, the canonical revision without its provider prefix, a non-string value, or
another mismatch. Only the stable category reaches UI feedback; the received value and response
body remain undisplayed and unretained.

This code-only follow-up makes no provider request, reads no credential and incurs no provider
spend. It does not authorise another live observation or relax any identity, envelope, retry,
local validation, physical-device, treadmill, FTMS, HealthKit or watchOS boundary.

## Post-live redacted identity diagnostics — 6 September 2026

After the first authorised simulator observation returned the existing aggregate
`providerFailure(identity)` code, a separate diagnostics slice was prepared from
remote main `272dc30db219e70d5db9cfae58ca2fcdd7ed8be0`. It does not alter the
request, accepted identities, response schema, retry policy or local authority.

Redirect and response-content-type failures are now distinct from transport and
structural failures. The response URL, missing or mismatched top-level model, missing
or mismatched provider, service tier and optional message model also produce distinct stable local
codes. Received values, response bodies and native errors remain undisplayed and
unretained. Synthetic tests cover every code and assert that the URL and test values
do not enter the normalized outcome. Current OpenRouter documentation still omits
the issue-required top-level `provider` field from its documented successful Chat
Completions response, so absence remains a deliberate fail-closed result rather than
being silently accepted.

This diagnostic preparation made no provider request, read no credential and spent
$0.00. The retained simulator credential was not inspected or changed. Focused
tests passed 28/28; the complete production suite passed 113/113; the evaluation
suite passed 14/14. Release simulator build, static analysis, resource verification,
all three skill validators, the accounting helper's 20 tests and diff checks passed.
Exact Codex phase accounting is unmeasured because the unmodified helper rejected a
cumulative counter decrease between events 77 and 78 before implementation.

Implementation was prepared uncommitted on `codex/issue-19-production-import` in
`/private/tmp/paceprompt-issue19`, based on verified remote main
`5fea298b07eedd19b816fd5eb70a8e6ae750ac2e`.

## Review entry points

1. Read the complete current issue 19 and [production contract](production-contract.md).
   [outbound-request.json](outbound-request.json) makes all request fields and fixed
   messages reviewable. The response allowlist was written before the adapter.
2. Inspect `PacePrompt/Import/`: credential storage, request/resource ownership,
   independent URLSession transport, strict JSON parsing, untrusted proposal mapping,
   consent/lifecycle state and SwiftUI disclosure are separate components.
3. Inspect the small `PlansViewModel.reviewImportedPlan` bridge and reuse of
   `PlanPreviewView`. Import never writes to the repository directly. The existing
   separate confirmation performs the save; changed capability/input invalidates
   import preview. Save failure clears the import and retains safe local feedback.
4. Inspect `PacePromptTests/WorkoutImportTests.swift` and the two import cases in
   `PacePromptUITests/PlansFlowUITests.swift`. Unit tests use synthetic keychain,
   repository, generator and transport doubles; URLSession tests install a local
   URLProtocol that handles every URL. UI tests select an in-memory generator and
   credential backend under the existing DEBUG-only UI-test launch flag.
5. Run `python3 scripts/verify_import_resources.py --app-bundle <built PacePrompt.app>`.
   It independently reprojects the eleven development examples without importing
   evaluation code, checks pinned hashes and confirms bundle independence.

## Validation commands

All Xcode commands use `CODE_SIGNING_ALLOWED=NO`, the iPhone 17 Pro Max simulator,
and `/private/tmp/paceprompt-issue19-derived`. No physical installation is included.
Focused suites: WorkoutImportTests, WorkoutImportBoundaryTests and
ImportSessionTransportTests, plus the two import UI tests. Complete suite follows,
then simulator build, Xcode static analysis, repository skills and full-diff review.

Results are recorded below after each gate completes. Logs and xcresult bundles
remain local under `/private/tmp/paceprompt-issue19-*`.

## Privacy and preservation

Zero provider calls and zero spend. Public documentation/catalogue GETs only;
no repository .env, real key, authenticated provider request, physical installation,
treadmill connection/operation, FTMS write, HealthKit or watchOS work.
The primary checkout's two modified shared schemes are unchanged. No evaluation
source, sealed prompt/dataset/policy/scorer or original run evidence was modified.
`/private/tmp/paceprompt-issue17-research` and its ignored .runs remain untouched.
At the original review boundary, no commit, push, publication or issue-state change
had been performed. A local commit was subsequently authorised; push, publication
and issue-state changes remain unauthorised.

## Remaining acceptance boundaries

- Mocked success does not establish complete live route/envelope compatibility, live
  response metadata, account guardrail compatibility, network timing or remote retention.
  The provider-bound requested-alias amendment is narrower than historical evaluation,
  which did not require the production provider field. OpenRouter's OpenAPI omits the issue-required top-level
  provider field; production requires it anyway and fails closed if absent.
- Keychain accessibility, device-only/no-sync behaviour and lifecycle ordering are
  implemented using the specified Apple attributes and mocked failure tests. Physical
  iPhone Data Protection behaviour remains unvalidated. App buffer clearing is not
  a remote-retention or secure-memory-erasure guarantee.
- On-device inference is deferred under 14. No open-weight candidate qualified;
  Sol remains the human selection. The consolidated evaluation used deterministic
  scoring, not an LLM judge.
- The complete tracked and untracked slice was subsequently reviewed against the
  ratified contract. One test-only gap was found and corrected: the unit suite now
  captures the complete production request and compares its decoded JSON body with
  `outbound-request.json`, while also asserting method, URL, cache policy, timeout
  and the exact three-header envelope. No production behaviour or resource byte changed.
- The local commit was separately authorised with a fresh pre-commit accounting
  boundary; push remains unauthorised. Any live check still needs a separately sealed
  run-specific credential/call/spend gate. Any further identity change requires new
  evidence and an explicit contract amendment.

## Repository state for review

At the original review boundary, the delivery worktree had seven modified tracked
files and sixteen new files; nothing was staged, committed or pushed. Tracked changes
were the Xcode project, Plans UI-test
support, PlansViewModel, RootTabView, PlansView, SettingsView and PlansFlowUITests.
New files are seven import Swift components, three fixed resource files, one unit
test file, four contract/fixture/handoff documents and one offline verifier.

Primary checkout: still on main at the verified base, with only these original
modifications, whose hashes match the start of this task:

- PacePrompt.xcodeproj/xcshareddata/xcschemes/PacePrompt.xcscheme:
  `e56435804b205a7156aae4d8d99335b04955ca76ee994fce3bdeb99c66a81f75`
- PacePrompt.xcodeproj/xcshareddata/xcschemes/PacePromptEvaluation.xcscheme:
  `fc812c98e219e7b3cc30837ad34542c01476902a0d2068a5a310a140c8c0d5e2`

Other existing worktrees were not changed or removed. In particular, the issue 17
research worktree remains registered at c2e7df1 and its ignored evidence directory
is present. Before the separately authorised local commit, the delivery branch added
no commits relative to the verified base.

## Completed validation

- Focused: 26 tests passed, zero failed/skipped (24 unit tests plus two import UI tests).
  Result: `/private/tmp/paceprompt-issue19-derived/Logs/Test/Test-PacePrompt-2026.09.06_14-15-42-+0100.xcresult`.
- Phase-accounting helper: 20 tests passed. All three repository skill validators
  passed using the existing isolated validator environment with PyYAML 6.0.3.
- Resource provenance/equivalence and built-bundle independence checks passed.
- Tracked and new-file whitespace checks passed; complete diff reviewed.
- Additional staged results follow below.

- Complete production simulator suite: 107 passed, zero failed/skipped.
  Result: `/private/tmp/paceprompt-issue19-derived/Logs/Test/Test-PacePrompt-2026.09.06_14-18-14-+0100.xcresult`.
- Existing evaluation simulator suite: 14 passed, zero failed/skipped.
  Result: `/private/tmp/paceprompt-issue19-derived/Logs/Test/Test-PacePromptEvaluation-2026.09.06_14-23-20-+0100.xcresult`.
- Release simulator build: passed for generic iOS Simulator, with test doubles
  excluded. Non-fatal toolchain warnings: AppIntents metadata extraction skipped
  (no framework dependency), and dsymutil could not locate a cached SwiftShims PCM.
  This is not a warning-free debug-symbol validation claim.
- Release Xcode static analysis: passed, no analyzer findings reported.
- Final Release bundle: pinned resource hashes and evaluation-independence checks passed.

After the test-only correction, the fresh focused unit suite passed 24 tests and the
two import UI tests passed. The complete production suite again passed 107 tests,
the evaluation suite again passed 14 tests, and the Release simulator build, Release
static analysis, resource verifier, bundle-independence check, accounting-helper tests,
all three repository skill validators and final whitespace checks passed. The new
result bundles are under `/private/tmp/paceprompt-issue19-derived/Logs/Test/`, dated
15:14, 15:16 and 15:20 on 2026-09-06. This remains mocked/simulator evidence, not
live-provider or physical-device acceptance.

Logs: `/private/tmp/paceprompt-issue19-focused-final.log`,
`/private/tmp/paceprompt-issue19-complete-final.log`,
`/private/tmp/paceprompt-issue19-evaluation-tests.log`,
`/private/tmp/paceprompt-issue19-build.log`,
`/private/tmp/paceprompt-issue19-analysis.log`, and
`/private/tmp/paceprompt-issue19-accounting-tests.log`.

## Development accounting boundary

The selected root session is
`01a076c2-21c1-78a0-9d40-caa524fc0178`, model `gpt-6-astra`. No subagents,
separate tasks, external reviewers or provider inference channels were used.
The unmodified accounting helper captured the pre-implementation baseline at event 4,
2026-09-06T12:47:56.329Z, in `/private/tmp/paceprompt-issue19-baseline.json`.
Final helper results follow below. Historical transcripts, helper logic and ledger
rows remained unchanged at this implementation boundary. The later authorised commit
uses a separate pre-commit boundary and commit-measurement row.
The user authorised an official OpenAI Astra cost calculation and comparison with
Sol. The earlier statement that a pricing basis was not authorised was incorrect;
the verified pricing calculation below supersedes it without changing the phase.

The helper validated this task's phase delta successfully (this does not resolve
historical counter-reset failures). Exact phase: event 4 through event 71,
2026-09-06T12:47:56.329Z through 2026-09-06T13:25:08.976Z.

| Counter | Tokens |
| --- | ---: |
| Total input | 10,920,072 |
| Cached input, included in total input | 10,751,872 |
| Cache-write input | 0 |
| Output | 56,126 |
| Reasoning output, included in output | 15,006 |
| Total | 10,976,198 |

67 measured requests; largest input 209,321 tokens. Both official model pages
specify a 272,000-input-token long-context threshold; zero measured requests cross
it, so no long-context surcharge applies.

Official OpenAI standard text-token prices checked 2026-09-06, in USD per million:

| Pricing basis | Uncached input | Cached input | Cache writes | Output | Phase estimate |
| --- | ---: | ---: | ---: | ---: | ---: |
| [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) | $10.00 | $1.00 | $12.50 | $50.00 | **$15.24** |
| [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol), same usage | $4.00 | $0.40 | $5.00 | $20.00 | **$6.10** |

Sol's published promotional rates are available at least through 2026-11-21.
Both models apply 2x input and 1.5x output rates above the threshold; Astra
explicitly includes cache rates in that input multiplier. Cache writes are zero.

The unmodified accounting helper's `parse_counter` and `request_cost` functions
price the preserved validated phase totals. Aggregation is valid here because
every request is below the threshold and uses the same rates. No transcript,
original helper report or historical ledger was rewritten.

- Astra: (168,200 × 10 + 10,751,872 × 1 + 56,126 × 50) / 1,000,000 = $15.240172.
- Sol: (168,200 × 4 + 10,751,872 × 0.40 + 56,126 × 20) / 1,000,000 = $6.0960688.
- Difference before rounding: $9.1441032, or **$9.14**. Astra is **2.5x** the cost;
  Sol is **60% cheaper** for this identical token mix.

These are token-only standard API-equivalent estimates, not a subscription bill
or a claim about the actual service tier. Sol is a counterfactual pricing comparison
on observed Astra tokens; a real Sol implementation could use different tokens.
Reasoning is already included in output and is not charged twice. Tool charges and
this pricing follow-up are excluded. OpenRouter provider calls and spend remain zero.
Calculation evidence: `/private/tmp/paceprompt-issue19-cost-comparison.json`.

Exact helper output: `/private/tmp/paceprompt-issue19-usage.json`.
Final insertion of these figures and subsequent handoff/check messages are outside
that measured boundary. A later authorised commit must capture its final boundary and
add the required stable change-ID ledger row/trailer at that time; that separate
authorisation was subsequently given and is recorded in `DEVELOPMENT_NOTES.md` as
`PP-20260906-04`.

## Historical new-session continuation

These were the continuation instructions used for the subsequent review: resume the
existing worktree `/private/tmp/paceprompt-issue19` on
`codex/issue-19-production-import`; its implementation was uncommitted and must not
be discarded or replaced with a fresh worktree. Read current AGENTS.md,
bounded-slice-delivery and codex-phase-accounting, then this handoff and the
production contract. Reverify remote main and issue 19 plus accepted dependencies
6, 10, 11, 15 and 17 before relying on recorded authority. Review the complete
tracked and untracked diff against the ratified contract; preserve both modified
primary-checkout schemes and issue 17 research/.runs evidence.

The recorded simulator gates passed; live-provider and physical-device acceptance
remain outstanding. Review or further local fixes do not authorise commit, push,
publication, issue closure, real credential access, provider calls/spend or hardware
operation. Start a separate accounting boundary for new-session work and retain
the measured implementation phase and Astra/Sol comparison above without merging
or inventing missing usage. The historical counter-reset problem remains unresolved.
