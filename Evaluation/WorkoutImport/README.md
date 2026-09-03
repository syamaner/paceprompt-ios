# Workout-import evaluation contracts and corpus

This developer-only boundary implements GitHub issue #12 under the accepted
[provider-neutral workout proposal, privacy and evaluation contract](../../design/workout-proposal-privacy-and-evaluation-contract.md).
It contains deterministic static/fixture tooling only. It does not invoke a
model, choose a provider, run on an iPhone, enter production code, persist a
workout or control a treadmill.

## Tracked and local areas

| Area | Source-control boundary |
| --- | --- |
| `Contracts/` | Tracked versioned provider-neutral proposal and normalized result JSON Schemas. |
| `Corpus/v1/` | Tracked reviewed synthetic prompts, semantic expectations, manifest metadata and corpus hash. |
| `Scoring/` | Tracked standard-library-only schema validation, canonical mapping, local validation and scoring. |
| `Tests/` | Tracked synthetic results, deliberately failing fixtures and deterministic tests. |
| `Summaries/` | Tracked only after an aggregate has been explicitly reviewed under the rules in its README. |
| `.runs/` | Ignored local raw run inputs and complete outputs. Never commit this directory or treat it as workout storage. |
| `Sources/` | Reserved by the accepted #6 structure for the separately authorised #13 app, provider and runner work. It is intentionally absent here. |

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
