# Workout-import evaluation contracts and corpus

This developer-only boundary implements GitHub issues #12 and #13 under the accepted
[provider-neutral workout proposal, privacy and evaluation contract](../../design/workout-proposal-privacy-and-evaluation-contract.md).
The accepted #12 corpus, schemas and scorer remain unchanged. The separate
`PacePromptEvaluation` iPhone target now supplies a provider-neutral runner,
Apple Foundation Models and OpenRouter adapters, and an explicit readiness
screen. Nothing in this boundary chooses a provider or model, performs a real
provider run, enters production code, persists a workout or controls a treadmill.

## Tracked and local areas

| Area | Source-control boundary |
| --- | --- |
| `Contracts/` | Tracked versioned provider-neutral proposal and normalized result JSON Schemas. |
| `Corpus/v1/` | Tracked reviewed synthetic prompts, semantic expectations, manifest metadata and corpus hash. |
| `Scoring/` | Tracked standard-library-only schema validation, canonical mapping, local validation and scoring. |
| `Tests/` | Tracked synthetic results, deliberately failing fixtures and deterministic tests. |
| `Summaries/` | Tracked only after an aggregate has been explicitly reviewed under the rules in its README. |
| `.runs/` | Ignored local raw run inputs and complete outputs. Never commit this directory or treat it as workout storage. |
| `Sources/` | Developer-only #13 app, provider adapters and runner. These files are members of `PacePromptEvaluation`, never `PacePrompt`. |

No raw provider transcript is eligible for `Summaries/`. There is no automatic
upload, export, deletion or retention job. An operator deliberately removes a
local raw run after review.

## Versioned contracts

- `workout-proposal/v1` represents only a structurally complete untrusted
  proposal. Its supported v1 source vocabulary is seconds or minutes,
  kilometres per hour or miles per hour, percent inclination, indoor walking or
  indoor running, and the four accepted step kinds. It cannot carry a local
  validation, persistence, execution or treadmill-control claim.
- `workout-import-result/v1` records normalized case outcomes and non-sensitive
  provenance. The result contains no prompt or complete provider transcript.
  Operational measurements remain separate from semantic assertions and must
  be explicitly `unmeasured` when unavailable.

Unknown versions, outcomes, activities, step kinds, units and additional
properties fail structurally. The checked-in validator deliberately supports
only the JSON Schema keywords used by these contracts and rejects a schema that
introduces an unimplemented keyword.

## Corpus v1

The corpus contains 20 reviewed synthetic cases across `en-GB` and `en-US`.
It covers exact walking and running requests, source-unit conversion, exact
step order and repeated interval/recovery multiplicity, missing and ambiguous
fields, contradictions, unsupported activities/units/capabilities,
out-of-domain text, prompt injection, unsafe and medically framed requests,
excessive complexity, explicit provider unavailability/failure, and capability
unknown.

Expected results are semantic assertions. Proposal cases state exact canonical
activity, ordered kinds, duration in integer seconds, speed in kilometres per
hour and inclination in percent. Non-proposal cases state the normalized
outcome, reason category and affected paths. Suggested names, labels and prose
are not compared exactly.

`manifest.json` binds stable case IDs and categories to the corpus and records
its hash. `workout-import-corpus-hash/v1` is SHA-256 over:

```text
"workout-import-corpus-hash/v1\n" + canonical-json({
  "caseContractVersion": manifest.caseContractVersion,
  "cases": cases sorted by id,
  "corpusVersion": manifest.corpusVersion
})
```

Canonical JSON sorts object keys, preserves array order, emits UTF-8 without
insignificant whitespace and normalizes finite decimal spelling. The hash does
not depend on file-system order or pretty-printing, but any semantic case
change produces a different hash.

## Deterministic scoring

Run the focused validation and fixture score from the repository root:

```sh
python3 -B Evaluation/WorkoutImport/Scoring/scorer.py \
  --root Evaluation/WorkoutImport verify-corpus

python3 -B Evaluation/WorkoutImport/Scoring/scorer.py \
  --root Evaluation/WorkoutImport score \
  Evaluation/WorkoutImport/Tests/Fixtures/normalized-results-v1.json

python3 -B -m unittest discover \
  -s Evaluation/WorkoutImport/Tests -v
```

The scorer uses exact decimal conversion. Minutes must map to an integer number
of seconds and miles per hour is multiplied by the exact decimal `1.609344`.
It never clamps, rounds, inserts, removes, merges or reorders a step. The local
validator mirrors the accepted #3 structural and capability outcomes needed by
this corpus; it does not create a production `ValidatedPlan`.

Every applicable rule is reported as passed or failed, with non-applicable
rules labelled explicitly:

- structural outcome;
- stated-value fidelity;
- step-order and multiplicity fidelity;
- clarification, unsupported, refusal, unavailable or failure behaviour;
- deterministic local-validator outcome;
- unsupported/unknown capability handling; and
- preservation of the model's lack of validation, persistence, execution and
  treadmill-control authority.

There is no weighting, percentage, pass threshold, hard safety gate or provider
decision rule. Aggregates are exact counts by result, rule, pipeline class and
case category. Invalid generator structure, failed canonical mapping, an
invalid local plan, a blocked local validation and scorer failure stay distinct.
Malformed schemas, corpus data, provenance, incomplete evidence, duplicate
identities or missing case evidence produce `scorerFailure` rather than partial
credit.

## Later provider-runner boundary

A separately authorised provider runner may read `Corpus/v1/manifest.json` and
`cases.json`, pass each exact prompt plus declared locale/capabilities to its
adapter, and emit `workout-import-result/v1`. It must not rewrite cases,
expectations or scoring logic per provider. Raw requests, complete responses and
native provider errors remain under ignored `.runs/`; only the normalized
result document is an input to this scorer.

The later run configuration must supply its ratified model set, repetition
count, spending limit, comparison rubric, hard safety gates and provider
decision rule. This slice intentionally defines none of them. It also performs
no Apple Foundation Models or OpenRouter integration, provider SDK or network
call, API-key handling, evaluation UI, physical-iPhone run, model comparison,
production inference, persistence change, FTMS write, workout execution,
HealthKit, watchOS or treadmill operation.

All current evidence is static/fixture evidence. It establishes only contract,
corpus, schema and deterministic scorer behaviour.

## Developer-only targets and execution boundary

`PacePromptEvaluation` requires iOS 26 because its Apple adapter imports the
Foundation Models framework. `PacePromptEvaluationTests` is hosted only by that
developer app. The evaluation target compiles the canonical production
`WorkoutPlan` and `WorkoutPlanValidator` source files directly; it neither
duplicates them nor links the production app target. The production scheme,
archive and tab navigation have no dependency on either evaluation target.

The runner loads only the bundled accepted v1 corpus and verifies its fixed
version, stable case index and hash
`be6355a1afdd9d56a14c759e3da0ef836280091218a6f282d7a826029cade79c`.
It requires an explicit run identity, exact app commit, repetition count,
evidence level, device/OS/locale, network condition, provider/model identity,
routing inputs, inference parameters and measurement-tool list. Adapter inputs
must exactly match the provenance recorded by the runner.

The Apple adapter uses Foundation Models guided generation with no tools. It
reports runtime, model and locale availability separately and accepts the
model identity and generation options supplied by the run configuration. The
OpenRouter adapter uses the fixed OpenRouter chat-completions endpoint, derives
its strict response schema from both checked-in #12 schemas, requires an exact
model, non-empty provider-routing object, explicit inference parameters and a
positive finite timeout, and requires a separately supplied request authorizer
before sending anything. It does not add, infer or alter any fallback field;
the separately authorised run must supply and record every routing value.
Offline and network unavailable states normalize to `providerUnavailable`;
cancellation, timeout and transport failure remain explicit and do not become
refusals.

Every structurally valid proposal passes through exact canonical mapping and
the unchanged local validator. The in-memory execution record keeps
`failedCanonicalMapping`, `invalidLocalPlan` and `localValidationBlocked`
distinct. Invalid/partial generator structure remains
`invalidGeneratorOutput`; later scorer failure remains owned by the unchanged
#12 scorer. None of these states grants save, execution or treadmill-control
authority, and normalized results always emit an empty `claimedAuthorities`.

Raw normalized results may be written only by `EvaluationRunWriter` to a path
whose final components are `Evaluation/WorkoutImport/.runs`. The writer rejects
every other destination. That directory is ignored by Git and is never copied
into either app target.

## Local readiness configuration

The shared evaluation scheme contains no environment values. The readiness
screen reads only an unshared local launch environment and never displays a
credential. It remains **Not ready** until the operator supplies the common
keys below:

- `PACEPROMPT_EVALUATION_PROVIDER` (`apple` or `openrouter`)
- `PACEPROMPT_MODEL_ID`
- `PACEPROMPT_RUN_CONFIGURATION_ID`
- `PACEPROMPT_REPETITION_COUNT`
- `PACEPROMPT_APP_COMMIT`
- `PACEPROMPT_DEVICE_LOCALE`
- `PACEPROMPT_INFERENCE_PARAMETERS_JSON`

OpenRouter readiness additionally requires
`PACEPROMPT_OPENROUTER_PROVIDER_ROUTING_JSON`,
`PACEPROMPT_OPENROUTER_TIMEOUT_SECONDS`, and
`PACEPROMPT_OPENROUTER_API_KEY`. The key is read only from the process launch
environment, wrapped as a redacted value and used only for the Authorization
header. It must not be added to a shared scheme, source, build setting, log,
artifact or summary. A Ready display means only that the declared configuration
and current availability checks permit a later operator action; it is not
inference evidence and does not itself invoke a provider.

Build and test the developer boundary without installing it or making a provider
call:

```sh
xcodebuild -project PacePrompt.xcodeproj -scheme PacePromptEvaluation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project PacePrompt.xcodeproj -scheme PacePromptEvaluation \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Bounded handoff to issue #14

Issue #14 remains blocked until this implementation is accepted and the
operator separately confirms the named iPhone, installation and run authority.
Before any provider invocation, #14 must ratify and supply the exact Apple and
OpenRouter model set, routing and generation settings, repetition count, run
order, warm-up policy, network conditions, timeout/cancellation policy,
spending limit, comparison rubric, hard safety gates and decision rule. It must
also supply a request authorizer that enforces those remote-run decisions. Do
not turn the deterministic test fixtures or the readiness screen into
comparison evidence.

The #14 run must preserve raw normalized evidence only under `.runs/`, score
completed results with the unchanged scorer, label simulator, physical-iPhone
and remote-provider evidence separately, and stop for human ratification. No
production inference issue, fallback, credential UI, persistence change,
treadmill connection or treadmill operation follows automatically.
