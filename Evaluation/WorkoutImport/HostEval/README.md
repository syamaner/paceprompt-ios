# PacePrompt host evaluation

This directory contains the developer-only prompt-v2 evaluation harness for
GitHub issue #15. It runs on the development host. It is not part of the iOS
application and provides no evidence about Apple Foundation Models, an iPhone,
Bluetooth, FTMS, HealthKit, watchOS or physical workout execution.

The accepted v1 contracts, corpus, scorer and results remain unchanged. This
harness projects each completed v2 result into a one-case, ephemeral v1
compatibility corpus under the ignored run directory, then invokes the
unchanged deterministic scorer.

The first frozen v2 run is also immutable. Its evidence showed that several
providers advertise structured output while rejecting keywords in the complete
semantic schema. New v2.1 runs send one common, closed provider-transport schema
without `oneOf`, `const` or `uniqueItems`, then validate every response against
the unchanged full v2 semantic schema on the host. GLM 5.3 Flash and Nemotron 3
Ultra are excluded from v2.1 after their ratified v2 run returned only upstream
429 responses.

The ratified v2.1 run remains unchanged under the ignored evidence directory.
For new v2.2 runs, the common provider transport uses required non-null fields
and exact transport-only sentinels; the host removes only those exact sentinels
before applying the unchanged full-v2 semantic schema. DeepSeek V4 Flash joins
GLM 5.3 Flash and Nemotron 3 Ultra in the paused set after 14 held-out DeepInfra
responses returned HTTP 429. New calls are globally serial with a fixed two-second
gap between one provider call finishing and the next starting.

The ratified v2.2 run remains unchanged. New v2.3 transport removes
`exclusiveMinimum`, which is outside Google Gemini's documented structured-output
schema subset. The host's unchanged semantic-v2 schema still requires every
duration to be strictly positive.

The ratified v2.3 evidence also remains unchanged. Its Gemini warm-ups returned
HTTP 400 before producing model output. The separately versioned v2.4 diagnostic
changes only the two Gemini models' reasoning controls to disabled. It sends one
unscored `WI-V2-D006` warm-up to each model, sends no held-out cases, and cannot
select a provider.

The separately versioned v2.5 diagnostic enables the reasoning required by both
pinned Gemini endpoints while omitting reasoning effort and response exclusion.
It otherwise retains the v2.4 two-warm-up, zero-held-out scope and run policy.

The ratified v2.6 curl probe isolated the Gemini rejection to the full nested
provider-transport schema: both pinned routes accepted the complete prompt and
eight development examples with a trivial strict schema. The separately
versioned v2.7 compatibility diagnostic therefore changes only the provider
transport strategy. Its `shallowStepV27` schema flattens duration, speed and
inclination fields inside each step. Host code expands those fields and then
applies the unchanged semantic-v2 schema and deterministic scorer boundary.

Transport selection is a closed, immutable registry keyed by requested model,
canonical revision and provider endpoint. Both Gemini routes share
`shallowStepV27`; the three OpenAI/Anthropic routes retain `nestedV23`. An
unknown route, revision drift or disagreement with a model's declared strategy
fails closed. There is no reflection, dynamic discovery or strategy fallback.

The ratified v2.7 compatibility evidence remains unchanged. Both pinned Gemini
routes still returned HTTP 400 before producing model output. The separately
versioned v2.8 compatibility diagnostic changes only those routes to
`flatEnvelopeV28`: outcome, proposal and step value objects are projected into
one top-level provider envelope, then rebuilt on the host before the unchanged
semantic-v2 validation. Field meanings, enum values, prompt, eight development
examples, reasoning settings, endpoint pins, pacing and failure policy remain
unchanged. OpenAI and Anthropic routes continue to use `nestedV23` in the v2.8
registry.

The accepted v2.8 evidence showed that flattening the semantic envelope still
returned Google AI Studio `400 INVALID_ARGUMENT` before model output. New v2.9
runs complete the strategy-pattern boundary: every transport strategy owns an
immutable provider schema profile and validates its schema before payload
construction. Both Gemini routes share `semanticJsonV29`, whose strict provider
schema is one closed object containing one string. That string contains the
canonical semantic-v2 JSON. The host decodes it with duplicate-key rejection,
then applies the unchanged full semantic-v2 schema and deterministic scorer.
Malformed inner JSON remains a model-quality failure.

`googleGeminiMinimalV29` permits only the four schema keywords required by that
one-property envelope and rejects extra properties, nested objects and enum
expansion offline. OpenAI and Anthropic continue to share `nestedV23` and its
`portableStrictV23` profile. Registry, strategy and profile mismatches all fail
closed; no reflection, runtime discovery or fallback selects another shape.

## Evidence boundary

All raw requests, responses, transcripts, framework logs, temporary scorer
projections and normalized results are written only below:

```text
Evaluation/WorkoutImport/.runs/host-eval/<run-id>/
```

The run writer rejects other destinations. Credentials are read only from the
local `OPENROUTER_API_KEY` environment at invocation time and are never written
to configuration, logs or manifests. Output redaction replaces any exact
credential value before evidence is persisted.

Each serial provider attempt also installs a bounded handler on the `inspect_ai`
logger. Its redacted records, including non-fatal provider-adapter warnings, are
written to that attempt's `framework-logs/*-python-logging.json` file and the
handler is removed when the attempt ends. An empty record list is preserved when
Inspect emits no Python log records.

## Reproducible environment

The environment is locked for Python 3.13, Inspect AI 0.3.263 and the minimum
OpenAI-compatible client required by that Inspect provider (`openai==3.1.0`):

```sh
cd Evaluation/WorkoutImport/HostEval
uv sync --frozen --python 3.13
```

This creates only `HostEval/.venv`, which is ignored locally and does not alter
the iOS dependency graph.

## Safe commands

The following commands are offline and never invoke a model:

```sh
uv run paceprompt-host-eval verify
uv run paceprompt-host-eval enumerate
uv run paceprompt-host-eval mock-payloads --run-id <new-run-id>
uv run python -m unittest discover -s tests -v
```

Preparing a gate reads only OpenRouter's public catalogue and sends all model
requests to a local mock transport:

```sh
uv run paceprompt-host-eval prepare-gate --run-id <new-run-id>
```

The current Gemini reasoning diagnostic has its own gate and a frozen `$2.00` cap:

```sh
uv run paceprompt-host-eval prepare-diagnostic-gate --run-id <new-run-id>
```

The v2.7 shared-strategy diagnostic also has a separate two-call, zero-held-out
gate and frozen `$2.00` cap:

```sh
uv run paceprompt-host-eval prepare-strategy-diagnostic-gate --run-id <new-run-id>
```

The full v2.7 five-model matrix is also frozen now, before compatibility results
are observed. Its gate must not be authorised until the v2.7 diagnostic evidence
has been separately ratified:

```sh
uv run paceprompt-host-eval prepare-strategy-gate --run-id <new-run-id>
```

The v2.8 flat-envelope diagnostic has its own two-call, zero-held-out gate and
frozen `$2.00` cap. Preparing it reads public catalogue metadata and exercises
the complete payloads against the local mock transport only:

```sh
uv run paceprompt-host-eval prepare-flat-strategy-diagnostic-gate \
  --run-id <new-run-id>
```

The full v2.8 five-model configuration is separately frozen but must not be
authorised until successful v2.8 compatibility evidence is human-ratified:

```sh
uv run paceprompt-host-eval prepare-flat-strategy-gate --run-id <new-run-id>
```

The v2.9 provider-profile diagnostic also has a distinct two-call,
zero-held-out gate and frozen `$2.00` cap:

```sh
uv run paceprompt-host-eval prepare-semantic-json-strategy-diagnostic-gate \
  --run-id <new-run-id>
```

Its full five-model configuration is frozen separately and cannot be enabled by
the diagnostic gate:

```sh
uv run paceprompt-host-eval prepare-semantic-json-strategy-gate \
  --run-id <new-run-id>
```

There is intentionally no implicit live mode. A live command requires all of:

- `--live`;
- an exact run-specific authorization phrase printed by `operator-gate`;
- `OPENROUTER_API_KEY` in the unshared process environment;
- the frozen `$20.00` cap and a passing worst-case preflight;
- a current catalogue snapshot matching every frozen model and endpoint;
- the same non-resumable run ID whose gate was ratified.

For a locally ignored `.env`, export it into only the live command's process:

```sh
set -a
source .env
set +a
uv run paceprompt-host-eval run --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 20.00
```

The live command first rechecks every versioned hash, refreshes the public
catalogue, rejects model/endpoint/revision/quantisation drift, and recomputes
the conservative preflight. Only then does it read the environment variable.
Each request also carries the selected endpoint's per-million-token
`provider.max_price`; the local guard reserves a conservative per-call maximum
before dispatch. A failed, partial or cancelled exchange remains in the run
directory and the run cannot be resumed.

After the diagnostic gate is inspected and separately authorised, its only live
entry point is:

```sh
uv run paceprompt-host-eval run-diagnostic --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 2.00
```

The v2.7 strategy diagnostic has a distinct live entry point so an older gate
cannot authorise it accidentally:

```sh
uv run paceprompt-host-eval run-strategy-diagnostic \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 2.00
```

After successful compatibility evidence and separate ratification of the full
gate, the full matrix likewise uses a distinct entry point:

```sh
uv run paceprompt-host-eval run-strategy --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 20.00
```

The v2.8 diagnostic and full matrix likewise use distinct live commands, so no
earlier gate or authorisation phrase can enable them:

```sh
uv run paceprompt-host-eval run-flat-strategy-diagnostic \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 2.00

uv run paceprompt-host-eval run-flat-strategy \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 20.00
```

The v2.9 live entry points are likewise distinct:

```sh
uv run paceprompt-host-eval run-semantic-json-strategy-diagnostic \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 2.00

uv run paceprompt-host-eval run-semantic-json-strategy \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 20.00
```

Its sealed gate hashes the exact route-to-strategy assignments, both transport
schemas, prompt, development and held-out datasets, model configuration, run
policy, scorer and complete host-harness source tree. Each persisted attempt
records its strategy and schema name. This makes configuration and ordering
repeatable; model sampling remains an observed variable rather than being
silently replayed from cache.

That command makes at most two calls, globally serial, with at least two seconds
measured on a monotonic clock from the first completed call to the second call's
start. It writes the measured inter-call delay into the preserved attempt record.

## Confirmatory v3 run

The confirmatory v3 prompt and corpus are separately versioned and hash-sealed.
The run contains 20 development cases, including eleven ordered few-shot
examples and fixed warm-up `WI-V3-D020`, plus 79 held-out cases. All 99 cases
are labelled `en-GB`. The three-model matrix is GPT-5.6 Sol, GPT-5.6 Luna and
Gemini 3.7 Flash under their own ratified generation and transport profiles.

Offline verification checks the prompt and five corpus hashes, manifest case
hashes, few-shot order hash, review ratification, locale allocation, scorer
aliases, semantic and transport schemas, unchanged scorer compatibility and
model-visible leakage. The deterministic queue contains 711 scored attempts
and carries the sealed corpus hashes before its own hash is calculated:

```sh
uv run paceprompt-host-eval verify-v3
uv run paceprompt-host-eval enumerate-v3
```

Gate preparation reads only the public OpenRouter catalogue and sends the full
three payload shapes to a local mock transport. It reads no credential, makes
zero provider calls and records zero spend:

```sh
uv run paceprompt-host-eval prepare-v3-gate --run-id <new-run-id>
```

The v3 preflight estimates all 714 calls using 5,448 completion tokens per
attempt. Input tokens use the maximum prompt-token-to-compact-request-byte
ratio observed for each route in the sealed v2.9 run, with a 10% safety margin.
It either admits all three repetitions under the fixed `$25.00` limit or admits
none; there is no one-repetition fallback. The separate runtime guard reserves
the full 8,192-token cap before each serial call and includes already settled
actual spend in the next reservation.

The live entry point remains inert without all of `--live`, the exact phrase
sealed into that run's gate, an exact `$25.00` argument, unchanged artefacts and
catalogue, and `OPENROUTER_API_KEY` in the unshared process environment:

```sh
uv run paceprompt-host-eval run-v3 --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 25.00
```

One serial worker preserves the planned queue order with a two-second gap.
There are no retries, fallbacks or cached completions. A first HTTP 429 pauses
only that model, marks its later positions `notStarted/rateLimitPause` without
re-queuing them, and makes it ineligible on completion. Timeouts do not pause a
model. Cancellation and spending-limit stops preserve every remaining attempt
as a terminal not-started record, and the run cannot resume.

The report keeps every scheduled attempt in category floors and composite
denominators, uses exact rational comparison, nearest-rank development-host p95
latency over the OpenRouter route, and never selects a provider. Evidence is
mechanically accepted only after the run-directory integrity audit passes;
provider selection remains a separate human decision and may remain unset.

## Issue #130 prompt-arm acceptance gate

The issue #130 profile compares the byte-identical production v3 prompt with
one developer-only `issue130-r1` prompt candidate. Both arms use the same
`openai/gpt-5.6-sol` canonical revision, OpenAI endpoint, eleven production
examples, v2.3 transport schema, reasoning-disabled generation controls and
unchanged v1 deterministic scorer. The candidate is not bundled into the app
and this profile cannot change the production prompt or route.

The held-out authority is acceptance corpus revision
`issue-130-reviewer-acceptance/r2`, hash
`204c6814cb62523426ed8871d77159f39a4daf4dc495ece7fcc70627e6d22864`.
Its 30 cases run three times against each prompt arm in a deterministic,
balanced serial queue: 180 scored calls plus one transport warm-up per arm.
User-supplied names are checked exactly; unnamed requests require a non-empty
name. All remaining semantic, mapping and local-validator checks use the
unchanged scorer.

Verify and enumerate without network access or a credential:

```sh
uv run --frozen paceprompt-host-eval verify-issue130
uv run --frozen paceprompt-host-eval enumerate-issue130
```

Gate preparation reads only the public OpenRouter catalogue and exercises the
complete request locally against a mock transport. It does not read
`OPENROUTER_API_KEY`, make a provider inference call or set a spending limit:

```sh
uv run --frozen paceprompt-host-eval prepare-issue130-gate \
  --run-id <new-run-id>
```

The resulting ignored `operator-gate.json` reports the conservative worst-case
cost for all 182 calls and stops in
`awaitingSeparateOperatorSpendingLimitRatification`. Only after the operator
ratifies an exact USD ceiling at or above that sealed preflight may the gate be
sealed:

```sh
uv run --frozen paceprompt-host-eval seal-issue130-gate \
  --run-id <prepared-run-id> --spending-limit-usd <exact-ratified-limit>
```

Sealing prints a run-specific authorization phrase but makes no provider call.
Live execution remains inert without `--live`, that exact phrase, the same
exact spending limit, unchanged artefacts and canonical queue, and current
catalogue prices that still fit the limit. Those checks finish before
`OPENROUTER_API_KEY` is read from the unshared process environment:

```sh
uv run --frozen paceprompt-host-eval run-issue130 \
  --run-id <sealed-run-id> --live \
  --authorization <exact-run-phrase> \
  --spending-limit-usd <exact-ratified-limit>
```

The run is non-resumable, uses one serial worker with a two-second inter-call
gap, has no retries or fallback, and preserves incomplete and infrastructure
outcomes as failures. Neither a high score nor a candidate pass selects a
prompt, changes production or closes issue #130; those remain separate human
decisions.

The completed `issue130-r1` run is sealed evidence and its prompt remains
byte-identical at SHA-256
`4b70d5563b52d195b25c77250b18599416b13bfc0a86ab9f435a74d7514bcf71`.
The developer-only `prompts/issue130-r2/system.md` revision corrects the two
observed semantic boundaries without changing that historical asset: different
explicit numeric values in the same or equivalent unit for the same field and
scope are always contradictions, and a missing non-kind value cannot add
`steps.kind` when the ordered plan has enough materialised steps for positional
kind inference. Revision r2 has
SHA-256 `5e27496875f6fd20d737d8c190fc938bfdc2b2cd3658e48f606dccf64bbdf007`.
It is deliberately absent from `run-policy-issue130-r1.json`; a new run policy,
queue, provider call or spending authority requires a separate operator gate.

`run-policy-issue130-r2-proposal.json` now records one exact recommended
comparison profile for separate ratification. It changes only the candidate arm
from `issue130-r1` to `issue130-r2`; the model, canonical route, schemas,
examples, generation controls, three repetitions, deterministic balanced order,
serial pacing, timeouts, no-retry policy, scorer and hard gates are identical to
the sealed r1 profile. The proposed run ID is
`issue130-prompt-gate-r2-20260920-01`, with 180 scored attempts and two warm-ups
in queue `8939a0960ca0a7a01afff8d3335eebf3bc52989e90d8582150b627bc26024ccc`.

The proposed USD ceiling is `24.102774`. This is an offline worst-case
recalculation using the sealed r1 catalogue rates (`0.000002` input and
`0.00001` output per token), the complete r2 payload bytes, 8,192 reserved
completion tokens per attempt and the existing 4,096-byte framing allowance.
It is not current-price proof. Future gate preparation must refresh the public
catalogue without reading a credential and stop if the current worst case exceeds
the ratified limit.

The operator ratified the exact proposal hash and recommended ceiling in
`issue130-r2-ratification.json`, SHA-256
`158436be3f130bf0c94289e37a1ae7b760da8998fe26ccde1c7af205fc05b910`.
That authority permits public-catalogue gate preparation and zero-spend sealing
only. It explicitly excludes credential access, provider inference, evaluation
spend, production change and live-run authorization.

Verify, enumerate, prepare and seal that exact r2 gate with:

```sh
uv run --frozen paceprompt-host-eval verify-issue130-r2
uv run --frozen paceprompt-host-eval enumerate-issue130-r2
uv run --frozen paceprompt-host-eval prepare-issue130-r2-gate \
  --run-id issue130-prompt-gate-r2-20260920-01
uv run --frozen paceprompt-host-eval seal-issue130-r2-gate \
  --run-id issue130-prompt-gate-r2-20260920-01
```

Sealing generates a new run-specific phrase without reading a credential or
calling the model. The live entry point remains inert unless the operator later
supplies `--live`, that exact generated phrase and the ratified ceiling:

```sh
uv run --frozen paceprompt-host-eval run-issue130-r2 \
  --run-id issue130-prompt-gate-r2-20260920-01 --live \
  --authorization <exact-r2-run-phrase> \
  --spending-limit-usd 24.102774
```

The first r2 run instance terminated fail-closed after both warm-ups returned
`401 User not found`; it made no scored request and recorded no spend. The
immutable recovery proposal `issue130-r2-retry1-proposal.json` binds that
terminal evidence and reuses the exact comparison profile, model, prompt,
queue and recommended ceiling under run ID
`issue130-prompt-gate-r2-20260920-02`. Its only operational correction requires
the launcher to unset any ambient `OPENROUTER_API_KEY` before loading the
operator-designated checkout-root `.env`, so an inherited key cannot override
that file. The proposal permits public-catalogue preparation only; sealing,
credential access, inference and spend still require separate exact
ratification.

Verify and prepare the replacement zero-spend gate with:

```sh
uv run --frozen paceprompt-host-eval verify-issue130-r2-retry
uv run --frozen paceprompt-host-eval prepare-issue130-r2-retry-gate \
  --run-id issue130-prompt-gate-r2-20260920-02
```

## Direct curl compatibility probe

The separately versioned v2.6 diagnostic bypasses Inspect's live transport while
retaining the same OpenRouter URL, pinned Google AI Studio endpoints and provider
controls. It freezes five payload stages for each Gemini model: unstructured,
trivial strict schema, full transport schema, full prompt with trivial schema,
and the full prompt with the full transport schema. It sends no held-out case.

Preparation refreshes only public metadata and writes ten complete, redacted,
hashed request bodies beneath the new ignored run directory:

```sh
uv run paceprompt-host-eval prepare-curl-probe-gate --run-id <new-run-id>
```

After separate inspection and authorization of that exact gate, the live command
is:

```sh
uv run paceprompt-host-eval run-curl-probe --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 2.00
```

The API key is passed to curl through standard input rather than its command-line
arguments. Response bodies and curl diagnostics are redacted in memory before
being written. Response headers are intentionally not captured. The run permits
at most ten globally serial calls, no retries, a two-second inter-call delay and
a `$2.00` conservative spend ceiling.

Mocked validation and implementation do not grant permission to satisfy that
gate. Provider calls and spending require separate explicit human approval.

## Issue #17 open-weight curl probe

The separately versioned v4 probe checks the nine human-ratified open-weight
model revisions and exact OpenRouter endpoint tags before any full evaluation
profiles are implemented. It sends one minimal synthetic strict-schema request
per route. It does not use the development set, held-out set, frozen workout
prompt or scorer.

Preparation refreshes public catalogue metadata, verifies the frozen v3 assets,
writes nine complete hashed request bodies under the ignored run directory and
enforces a conservative `$0.25` ceiling without reading a credential:

```sh
uv run paceprompt-host-eval prepare-open-weight-curl-probe-gate \
  --run-id <new-run-id>
```

Each payload fixes the exact endpoint tag, disables fallback, requires every
parameter, denies data-collection routes, requires ZDR and caps the endpoint
price at the preparation snapshot. Known quantisation is pinned; the Phala
Qwen2.5 route intentionally omits a quantisation filter because its catalogue
metadata is unknown. Temperature, top-p and reasoning controls are absent so
the first probe isolates basic route and strict-JSON compatibility.

The live entry point remains inert without `--live`, the exact phrase sealed
into that run's gate, an exact `$0.25` argument, unchanged payloads and
catalogue, and `OPENROUTER_API_KEY` in the local unshared environment:

```sh
uv run paceprompt-host-eval run-open-weight-curl-probe \
  --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 0.25
```

Calls are serial with a two-second gap, no retries, a 15-second connection
timeout and a 120-second attempt timeout. HTTP 401, 402 or 403 stops the run and
preserves every remaining attempt as `notStarted/globalHTTPAbort`; individual
route errors remain terminal evidence without automatic substitution. The
report records returned route identity, JSON validity and exact `{"ok": true}`
schema satisfaction, then stops for human review before evaluation work.

After run `issue17-open-weight-curl-probe-20260905-03` proved five routes and
found four upstream-capacity failures, the separately ratified `replacement`
profile keeps those five successful identities locked as prior evidence. It
probes only DeepInfra FP4 for GLM 5.3 Flash, CoreWeave FP4 for MiniMax M3, the
sole qualifying DeepInfra FP4 Nemotron Ultra route once more, and DeepInfra FP8
for Mistral Small 3.2:

```sh
uv run paceprompt-host-eval prepare-open-weight-curl-probe-gate \
  --profile replacement --run-id <new-run-id>
```

Its live command also requires `--profile replacement`, its separately sealed
phrase and the unchanged `$0.25` ceiling. The prior report hash and all five
locked passing route identities are part of the replacement gate.

The separately ratified `nemotron-baseten` profile tests the remaining
Nemotron Ultra candidate on BaseTen FP4 without claiming native strict-output
support. It forces one named function whose arguments carry the same minimal
schema, then parses and validates those arguments locally. The profile is
sealed to both the replacement gate and report, which in turn lock the eight
already successful routes:

```sh
uv run paceprompt-host-eval prepare-open-weight-curl-probe-gate \
  --profile nemotron-baseten --run-id <new-run-id>
```

Fallback remains disabled. A successful diagnostic proves only that the exact
BaseTen route can return the required forced-tool envelope; it does not prove
full workout-prompt quality.

## Issue #17 open-weight evaluation v4

The [candidate matrix](open-weight-candidate-matrix-v4.md) records the
publisher artefacts, licence boundary, hosted-route identity limits, current
indicative prices and the reasons each ratified candidate remains worth
measuring.

The full v4 extension reuses the byte-identical prompt v3, 20 development
cases, 79 held-out cases, semantic review, model-output schema, nested v2.3
transport schema and deterministic scorer. It adds nine open-weight candidate
routes without rerunning or replacing the human-selected Sol reference.

Response-envelope contracts are route-specific and fail closed:

- Eight routes carry the complete nested transport schema through native
  `response_format.json_schema` and require `max_tokens`, `response_format`
  and `structured_outputs` in the selected endpoint's catalogue record.
- Nemotron Ultra on BaseTen carries the same complete schema through one
  forced `submit_workout_import_result` function and requires `max_tokens`,
  `tools` and `tool_choice`. The harness reads only that named call's argument
  string, then applies the same transport normalization, semantic schema and
  scorer used by native responses. Inspect's lossy `ToolParams` conversion is
  deliberately bypassed so `maxItems` and every other schema keyword remain
  present in the wire payload.

Every model profile separately pins its canonical revision, endpoint tag,
quantisation when reported, required parameter set, response contract, maximum
output, omitted sampling/reasoning fields and `zdr: true`. Unknown routes,
contracts, parameter profiles and materially different duplicate endpoint tags
are rejected. The only duplicate-tag exception is BaseTen's two catalogue
records, and only while every non-telemetry field is identical.

Offline configuration and deterministic queue verification make no network or
credential access:

```sh
uv run --frozen paceprompt-host-eval verify-open-weight-v4
uv run --frozen paceprompt-host-eval enumerate-open-weight-v4
```

Gate preparation performs a read-only public catalogue refresh and writes nine
complete mocked payloads, the 2,133-attempt scored queue, nine warm-ups, hashes
and the conservative 2,142-call cost preflight under the ignored run directory:

```sh
uv run --frozen paceprompt-host-eval prepare-open-weight-v4-gate \
  --run-id <new-run-id>
```

The preflight treats every serialized request byte as a possible input token,
adds 4,096 framing tokens, and reserves the full 8,192 output-token cap for
every call. It has no reduced-repetition fallback. A total above the fixed
`$25.00` ceiling produces a blocked gate and no calls.

Live execution remains inert without `--live`, the exact run-specific phrase
from an admitted sealed gate and the exact `$25.00` limit:

```sh
uv run --env-file <local-env-path> --frozen paceprompt-host-eval \
  run-open-weight-v4 --run-id <ratified-run-id> --live \
  --authorization <exact-run-phrase> --spending-limit-usd 25.00
```

The run uses one serial worker, a two-second minimum gap, zero retries, three
indivisible repetitions and one transport/schema warm-up per model. A failed
warm-up prevents that model's held-out calls. A first 429 pauses only that model
and preserves later entries in place as `notStarted/rateLimitPause`; timeout,
cancellation and spending-stop evidence use the unchanged v3 denominator
rules. Raw exchanges and normalized evidence remain under `.runs` only.

The v4 report keeps Sol's sealed #15 metrics as fixed reference evidence,
reports native and forced-tool transport complexity separately, selects no
automatic winner and cannot change the production provider. Any displacement
of Sol remains a separate human decision after the evidence audit.

## Issue #145 full-matrix v5 preparation

The additive v5 profile evaluates the current issue #130 r2 production prompt
against two separately reported, byte-preserved strata: the 79-case v3 held-out
regression corpus and the 30-case reviewer-authored issue #130 acceptance
corpus. It does not rewrite either corpus, their manifests, the schemas or the
deterministic scorer. Three repetitions over 12 declared models produce 3,924
scored attempts, plus one warm-up per model for 3,936 planned calls.

The profile retains each model's previously ratified v3 or v4 generation and
transport settings. It replaces two catalogue routes that are no longer
available: Mistral Small 2603 uses `mistral/zdr`, and DeepSeek v4 Flash uses
`deepinfra/fp8`. Those replacements remain blocked from live use until a
separately authorised compatibility probe succeeds.

Offline verification and queue enumeration do not use the network, read a
credential or expose a live command:

```sh
uv run --frozen paceprompt-host-eval verify-issue145-v5
uv run --frozen paceprompt-host-eval enumerate-issue145-v5
```

Zero-spend gate preparation reads only the public catalogue, writes 12 mocked
route-aware payloads, freezes the deterministic queue and calculates a
conservative cost estimate under the ignored run directory:

```sh
uv run --frozen paceprompt-host-eval prepare-issue145-v5-gate \
  --run-id <new-run-id>
```

Preparation intentionally emits no authorisation phrase and cannot admit the
matrix: the hard spending limit is `null`. A later run requires separate probe
evidence, exact spending-limit ratification, a newly bound run instance and
explicit live authorisation. Results must remain separated by stratum and no
automatic winner, publication or production-route change is permitted.

The additive `issue145-full-matrix-route-probe-proposal-r1.json` freezes two
ordered, zero-scored compatibility calls for the changed Mistral and DeepSeek
routes, bound to the 22 September public-catalogue preparation. Its SHA-256 is
`2c4b2a6122a50fd5acc029f9282cd8bd3bb429072afe6b174ed446058715b500`.
The separate `issue145-full-matrix-route-probe-ratification-r1.json` binds the
exact run ID and USD 0.01192791 hard limit to zero-spend runner implementation
and gate sealing only. It explicitly withholds credential, provider, spend and
live-run authority. The ignored parent preparation must still be present and
byte-identical; a clean checkout without it cannot seal this probe.

```sh
uv run --frozen paceprompt-host-eval verify-issue145-route-probes
uv run --frozen paceprompt-host-eval prepare-issue145-route-probes-gate \
  --run-id issue145-full-matrix-route-probes-v5-20260922-01
uv run --frozen paceprompt-host-eval seal-issue145-route-probes-gate \
  --run-id issue145-full-matrix-route-probes-v5-20260922-01
```

These commands read no credential, refresh no catalogue and make no provider
call. The sealed gate still requires separate exact-run live authorisation.
Live execution, if later authorised, refreshes only the two public routes,
rejects route or price increases before key lookup, runs serially with no
retry or fallback, and stops after a failed compatibility call. Its report is
diagnostic, never an automatic winner or full-matrix admission. The 3,936-call
full-matrix preparation separately estimated USD 98.742225560 at snapshot
prices; that is not a ratified hard limit and the final run must be freshly
bound after route proof.

The first probe instance ended after one HTTP 429 on the Mistral route. Its
ignored raw evidence is preserved and its original run ID remains
non-resumable. A zero-spend recovery gate can create a fresh child instance
bound to exact hashes of the terminal parent gate, live admission, report,
audit, state and complete raw-evidence tree. It reuses the frozen two-call
profile and USD 0.01192791 per-instance
limit; it does not infer a retry, change the route, score cases or merge
attempts across instances. Preparation and sealing make no inference call and
read no credential:

```sh
uv run --frozen paceprompt-host-eval prepare-issue145-route-probes-recovery-gate \
  --parent-run-id issue145-full-matrix-route-probes-v5-20260922-01 \
  --run-id <new-unique-run-id>
uv run --frozen paceprompt-host-eval seal-issue145-route-probes-recovery-gate \
  --run-id <same-new-run-id>
```

The child gate derives a new exact authorization phrase. The operator must
authorize that specific phrase and the same finite hard limit before any live
execution; there is no automatic restart. The live command performs the same
fresh catalogue, route and price preflight before credential lookup. A child
that enters live execution is also non-resumable. If it ends as an audited
terminal failure, the same preparation command can name that child as
`--parent-run-id` and create another uniquely named descendant. Each child
has its own finite cap and exact authorization; there are no automatic retries
or cumulative spend assumptions. This recovery lineage is limited to the
two-route probe, not the unratified 3,936-call matrix.

The operator-approved [issue #145 standing restart and compatible-repair
contract](issue145-standing-restart-and-repair-r1.md) sets the requirements
for a future separately versioned full-matrix runner. It does not retroactively
change this probe's exact child-authorization rule, make the sealed v5 matrix
resumable, or authorise a provider call.

### Cost-bounded four-model Stage A

The additive Stage A proposal preserves the twelve-model review while reducing
the first live decision to the four highest weighted composites in the sealed
v3 and v4 summaries: Sol, Gemini 3.7 Flash, Qwen 3.8 27B and Luna. It retains
all 109 cases but performs one repetition, producing 436 scored attempts and
four warm-ups. The deterministic queue and a fresh public-catalogue cost
preflight are bound by `issue145-stage-a-proposal-r1.json`.

The output ceiling remains 8,192 for Stage A. Lowering it to 2,048 is not yet
mechanically safe because the schema permits 64 steps and unbounded text,
Gemini's medium reasoning shares the output allowance, and the protected
summary does not contain per-attempt output-token maxima. Stage A must retain
reported token evidence so a later Stage B ceiling can be reviewed rather than
guessed.

Offline verification, enumeration and zero-spend preparation are:

```sh
uv run --frozen paceprompt-host-eval verify-issue145-stage-a
uv run --frozen paceprompt-host-eval enumerate-issue145-stage-a
uv run --frozen paceprompt-host-eval prepare-issue145-stage-a-gate \
  --run-id <new-run-id>
```

The prepared gate has no authorisation phrase or hard limit. After exact profile
and limit ratification, sealing installs the ratified limit and derives a phrase
from the complete gate without reading a credential:

```sh
uv run --frozen paceprompt-host-eval seal-issue145-stage-a-gate \
  --run-id <ratified-run-id>
```

Live execution is separately fail-closed behind `--live`, the exact sealed
phrase and the exact ratified limit. It rechecks source, queue, payload,
catalogue and cost evidence before reading `OPENROUTER_API_KEY`. Stage B cannot
start automatically and requires a separately reviewed profile after Stage A
token, cost, completion and route evidence is available.

### Three-model Stage B proposal

The Stage B proposal retains the three candidates that passed their Stage A
warm-up and completed all 109 scored positions: Sol, Qwen 3.8 27B and Luna.
Gemini 3.7 Flash remains excluded because its Stage A warm-up failed the strict
schema at `$.outcome`; this proposal does not silently recover or reroute it.

Stage B adds global repetitions 2 and 3 over the same sealed 79-case regression
and 30-case issue #130 acceptance strata. This produces 654 scored attempts and
three warm-ups, for 657 provider calls. Combined comparison is permitted only
after the separate Stage A and Stage B integrity audits pass. The three
repetitions then use a two-of-three per-case majority; there is still no
automatic winner or production-route change.

The only generation change from the retained Stage A profiles is a proposed
6,144-token output ceiling. Stage A reported no output-limit failures and a
maximum of 3,959 output tokens. A 4,096 ceiling was rejected because its 137
token margin is only 3.5%; 6,144 leaves 2,185 tokens, or about 55%, of headroom.

Offline verification and queue enumeration are:

```sh
uv run --frozen paceprompt-host-eval verify-issue145-stage-b
uv run --frozen paceprompt-host-eval enumerate-issue145-stage-b
```

Zero-spend preparation reads only the public catalogue and writes mocked
payloads, the deterministic queue and the conservative cost calculation under
the ignored run directory:

```sh
uv run --frozen paceprompt-host-eval prepare-issue145-stage-b-gate \
  --run-id <preparation-run-id>
```

The committed r1 proposal binds proposed run
`issue145-top3-stage-b-v5-20260921-01`, queue SHA-256
`e505a355a81c9c810c26b6718c0a1324a3cf2ddbc70733ca96dc717852a80346`,
public-catalogue snapshot SHA-256
`a174b002cc20094690b429e4e5a5528e863eb1f7e2c5b8658775ba48e2f4d2e4`
and conservative limit `$32.07052912`. Its SHA-256 is
`1646c57a6da4edeb444ffcae752862824b1fe83ec43dd2357b5cb29faf5bc302`.
The separately recorded r1 ratification binds that proposal, run ID, the
6,144-token output ceiling and the exact `$32.07052912` hard limit. It grants
zero-spend gate preparation and sealing only: no credential read, provider
inference, spending, live run, publication or production change.

After a fresh public-catalogue preparation for the ratified run ID, sealing
rechecks the complete HostEval source tree, every versioned configuration,
ratification, deterministic queue, mocked request, catalogue endpoint and
conservative cost before deriving a run-specific phrase:

```sh
env -u OPENROUTER_API_KEY uv run --frozen paceprompt-host-eval \
  prepare-issue145-stage-b-gate \
  --run-id issue145-top3-stage-b-v5-20260921-01
env -u OPENROUTER_API_KEY uv run --frozen paceprompt-host-eval \
  seal-issue145-stage-b-gate \
  --run-id issue145-top3-stage-b-v5-20260921-01
```

The implemented live command remains inert unless a later operator statement
separately authorises the exact sealed phrase and repeats the exact hard limit:

```sh
paceprompt-host-eval run-issue145-stage-b \
  --run-id issue145-top3-stage-b-v5-20260921-01 \
  --live \
  --authorization <exact-sealed-phrase> \
  --spending-limit-usd 32.07052912
```

Even then the runner revalidates the sealed evidence and a current public
catalogue before it reads `OPENROUTER_API_KEY`. Price increases, route drift,
source drift, any previous live-state file, or a mismatched phrase or limit
fail before credential access. Stage B output is diagnostic and separate;
combination with protected Stage A evidence, model selection, publication and
production changes remain later reviewed decisions.

### Accepted Stage A+B publication

The separately ratified publication proposal is committed as
`issue145-stage-a-b-publication-proposal-r1.json` at SHA-256
`bbef325cd88faac72424b647b692a1217989f4f09c2db80bc1345bb7db1ad3c4`.
Its ratification authorises only the bounded aggregate publication and
exact-head review. It does not authorise raw-run publication, model selection,
scorer or gate relaxation, a production change, merge or issue closure.

The protected comparison combines Stage A repetition 1 with Stage B
repetitions 2 and 3 for the three retained models. It retains 981 scored
attempts over 109 cases and reports each corpus stratum separately. The issue
#130 acceptance stratum contains no `knownCapabilityUnsupported` case, so the
unchanged v3 scorer reports its non-empty capability hard gate as false for
every model. The publication records that structural result explicitly and
does not reinterpret it into an eligible model.

## Frozen protocol

- 17 development cases and 34 held-out cases, with eight fixed few-shot
  examples sourced only from the development set.
- One principal problem selected by the prompt's ordered decision procedure.
- Five ratified v2.3 models. Five scored repetitions, reduced to one before results only when the
  conservative `$20.00` preflight cannot admit five.
- One global worker, a two-second inter-call delay, deterministic case shuffles and balanced model rotation.
- One unscored development warm-up per model. Each model proceeds to its
  held-out cases only when that warm-up passes both the transport and full-v2
  schema checks; otherwise its scored attempts are preserved as
  `notStarted/prerequisiteMismatch`.
- No harness retry, provider fallback, result cache or replay.
- 15-second connection and 180-second per-attempt wall-clock timeouts.
- Evidence-preserving, non-resumable cancellation.

The composite comparison is secondary to the hard gates and disaggregated
results. The harness never selects a production provider.
