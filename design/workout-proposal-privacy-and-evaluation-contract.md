# Workout proposal, privacy and evaluation contract

Status: accepted documentation-only product contract for GitHub issue [#6](https://github.com/syamaner/paceprompt-ios/issues/6). This document does not implement inference, an evaluation corpus or runner, network access, credentials, persistence, treadmill control or workout execution.

## Scope and authority

This contract defines how free text may become an untrusted, provider-neutral workout proposal and how candidate providers may later be compared without weakening local product authority. It is constrained by:

- the repository's current `AGENTS.md` safety, privacy and slice rules;
- the accepted issue [#3](https://github.com/syamaner/paceprompt-ios/issues/3) canonical `WorkoutPlan` schema and deterministic `WorkoutPlanValidator`;
- the accepted issue [#5](https://github.com/syamaner/paceprompt-ios/issues/5) [local workout storage and history contract](local-workout-storage-and-history-contract.md);
- the accepted issue [#10](https://github.com/syamaner/paceprompt-ios/issues/10) versioned saved-plan repository; and
- the accepted issue [#11](https://github.com/syamaner/paceprompt-ios/issues/11) manual validation, exact preview, explicit-confirmation and identity-preserving save/edit flow.

The product concept and `TreadmillDesign.pdf` remain eventual-product context. Their OpenRouter-first wording, model settings and richer product flows are not provider authority here.

## Product decisions

1. A model is an untrusted proposal source. It cannot validate a plan, grant a capability, save data, start an execution flow or control a treadmill.
2. `WorkoutProposal` and `WorkoutPlan` are different domain values. A provider response never decodes directly into `WorkoutPlan` or `WorkoutPlanValidator.ValidatedPlan`.
3. Every provider uses one versioned proposal contract and one provider-neutral generator boundary. Apple on-device generation, OpenRouter and any later candidate adapt to that boundary rather than changing product validation or persistence.
4. All unit conversion, arithmetic, canonical mapping, capability checks and `WorkoutPlanValidator` validation happen deterministically on the device after generation.
5. Missing, ambiguous, contradictory or unsupported safety-relevant facts are never guessed, defaulted, clamped, rounded, reordered or repaired by the model adapter or local mapper.
6. A successfully validated proposal enters the existing exact preview. Only the existing separate confirmation action may pass its `ValidatedPlan` to the saved-plan repository.
7. Apple on-device inference is the local-first candidate. OpenRouter is a comparison candidate, not a default, production dependency or predetermined winner. A hybrid strategy is neither selected nor rejected by this contract.
8. Provider evaluation is developer-only and synthetic. Production prompt handling, evaluation evidence and saved workout data are separate lifecycles.

## Provider-neutral generator boundary

The later generator interface accepts the exact user-entered text, the selected proposal-contract version, supported locale and unit vocabulary, and only the capability facts deliberately included by the caller. It returns exactly one normalized outcome:

| Outcome | Meaning | Required local treatment |
| --- | --- | --- |
| `proposal` | A structurally complete `WorkoutProposal` was returned. | Map and validate locally; do not treat structural success as semantic validity. |
| `clarificationRequired` | The request lacks, ambiguously states or contradicts a required fact. | Identify the affected field or step and ask an actionable question; do not create a partial plan. |
| `unsupportedRequest` | The requested activity, target, unit, operation or complexity cannot be represented by the accepted proposal contract or known product capability. | Explain the unsupported element without substituting a different workout. |
| `refusal` | The provider deliberately declined the request, including an unsafe or medically framed request it will not transform. | Preserve refusal as a terminal generation outcome and offer safe, non-medical next steps where appropriate. |
| `providerUnavailable` | The selected provider or required runtime/model is not currently available. | Keep availability separate from request validity and expose an explicit retry or provider-choice path. |
| `providerFailure` | Invocation, transport, routing or complete-response generation failed. | Report a bounded failure without interpreting absent output as a refusal, clarification or empty plan. |

The boundary does not expose provider SDK types to the production plan, validation, preview or repository layers. Provider adapters may retain their native failure detail only inside the active process or a developer evaluation run; the normalized product outcome uses stable local reason codes and safe user-facing detail.

### Versioned structured-output semantics

The initial semantic contract is identified as `workout-proposal/v1`. Issue [#12](https://github.com/syamaner/paceprompt-ios/issues/12) will encode these semantics as the versioned schemas and fixtures; this issue does not add those files.

A `proposal` outcome represents:

- the proposal-contract version;
- a suggested display name;
- exactly one supported indoor activity;
- an ordered, non-empty sequence of proposed steps; and
- for every step, an explicit kind, label, positive duration quantity, absolute target-speed quantity and absolute target-inclination quantity.

Every quantity carries an explicit value and unit from the versioned proposal vocabulary. A provider must not calculate canonical timestamps, total duration, distance, pace or other derived values. The deterministic mapper converts accepted source units into the canonical #3 units of seconds, kilometres per hour and percent, then the existing preview derives totals locally.

The same semantic fields and outcome discriminator must be representable by Apple Foundation Models guided generation and by strict JSON Schema through OpenRouter. Provider-specific annotations, tool calls, safety metadata, token data or routing data are envelope evidence, not proposal fields, and cannot affect canonical mapping.

Contract versions fail closed. An absent, unknown or unsupported version is a structural failure; it is never interpreted as the current version. A later version requires an explicit compatibility decision and new deterministic fixtures. Unknown outcome discriminators, activity values, step kinds or units fail structurally rather than being ignored or coerced.

### Deterministic mapping and validation

The local pipeline is ordered and non-bypassable:

1. classify provider availability and the normalized generator outcome;
2. validate the complete structured response against the selected proposal-contract version;
3. reject missing, additional where disallowed, non-finite or structurally invalid fields;
4. map the exact activity and ordered steps without insertion, deletion, merging or reordering;
5. convert units using versioned local conversion rules and deterministic decimal arithmetic;
6. calculate canonical and preview-derived values locally;
7. run `WorkoutPlanValidator.validate(_:against:)` against the explicit current capability state;
8. if validation succeeds, show the existing readable preview of the exact complete plan; and
9. only after a separate explicit confirmation, pass that exact `ValidatedPlan` to the existing repository create or identity-preserving replacement operation.

Failure at any stage prevents all later stages. Mapping does not clamp or round a value to a treadmill increment, supply a missing zero inclination, infer walking versus running, invent a warm-up or cool-down, expand shorthand intervals, choose a step order, or resolve contradictory repetitions. Exact deterministic unit conversion may change representation but not meaning; if a converted value cannot be represented exactly under the accepted mapping rule, mapping fails with the source field identified.

Clarification is required when a safety-relevant value or relationship admits more than one reasonable interpretation. Unsupported is required when the request is understood but cannot be represented or is incompatible with a known unsupported capability. Capability unknown remains distinct from unsupported. Provider refusal remains distinct from local validation failure.

All failures must be actionable without echoing sensitive source text into logs. User-facing feedback identifies a stable reason, affected field or step where known, and a safe next action such as clarify, edit, retry availability, select another explicitly disclosed provider or return to manual entry.

## Independent lifecycle states

Implementations must preserve these axes rather than collapse them into a single success, failure or loading flag:

| Axis | Minimum distinct states |
| --- | --- |
| Provider choice | not selected; explicitly selected provider/model |
| Runtime availability | unknown; checking; available; unavailable with reason |
| Generation | not requested; awaiting complete response; complete; provider failure |
| Structure | not checked; valid contract version; malformed; unsupported contract version |
| Normalized outcome | proposal; clarification; unsupported; refusal; unavailable; failure |
| Canonical mapping | not attempted; mapped; failed with reason |
| Semantic validation | not attempted; valid; invalid; capability unknown; target unsupported; invalid capability range |
| Preview and confirmation | not previewable; exact preview ready; unconfirmed; confirmed; cancelled |
| Repository persistence | not attempted; create/update in progress; succeeded; failed while preserving prior data |
| Future execution | outside this pipeline and never implied by any preceding state |

Changing a provider or model invalidates its prior availability and generation state. Editing the source text or proposal invalidates mapping, validation, preview and confirmation. A retry produces a new proposal attempt; it cannot reuse an earlier success claim. Provider availability does not establish generation success, structural validity, semantic validity, persistence or executability.

## Privacy, disclosure and fallback

### Production flow

Apple on-device generation is the preferred privacy candidate only when its required runtime and model are explicitly reported available. Availability must be checked at runtime and represented as `unknown`, `checking`, `available` or `unavailable(reason)`. An unavailable on-device provider does not silently fall back to a network provider, and an available provider does not imply that a particular request succeeded.

Any future remote production path must present a clear disclosure before each request leaves the device, or before a deliberately enabled flow whose scope is equally explicit. The disclosure must identify:

- that the workout text will leave the device;
- the selected remote provider and model or routing constraint;
- the purpose of the request and the data fields to be sent;
- that local deterministic validation and explicit save confirmation still apply; and
- the applicable retention or logging setting without claiming more privacy than the selected route establishes.

The user must make an affirmative choice after seeing that disclosure. Cancellation, dismissal or unavailable consent means no request. Provider switching is explicit and requires disclosure for the newly selected remote route. There is no automatic remote fallback, background retry, speculative request, prompt prefetch or request from a restored stale flow.

In a production flow, raw prompt text, provider request and response bodies, provider errors, routing metadata and transient proposals are process-memory-only by default. They never enter workout storage, history, JSON export, application logs, analytics, crash metadata, shared Xcode schemes or build settings. The owning flow clears them after confirmed save, cancellation or terminal failure and does not restore them after process termination. A future deliberately user-visible technical-details view may render the current in-memory exchange but cannot persist or share it without a separately accepted contract.

### Credentials and complete reset

No production credential is implemented by this issue. Before any later implementation, the accepted credential boundary is:

- store the remote API credential only as a non-synchronizable Keychain item scoped to PacePrompt and accessible only while the device is unlocked;
- do not place credential text or a derived secret in `UserDefaults`, workout storage, JSON export, logs, analytics, crash metadata, source control, Xcode schemes or build settings;
- expose only a redacted presence state to product code and diagnostics;
- require a deliberate replacement or deletion action and clear credential-entry text from memory after completion or cancellation; and
- never send the credential anywhere except the explicitly selected remote provider endpoint for the disclosed request.

A future **Delete remote credential** action removes only that Keychain item and reports failure without claiming deletion. A future **Reset all PacePrompt data** confirmation must list saved plans, any later history, temporary/staging/recovery data, active provider buffers and the Keychain credential as separate categories. It succeeds only after every selected persistent category, including the Keychain item, is removed; partial failure is reported by category and must not be described as a complete reset. The #5 workout-data reset remains a workout-data action until a later UI explicitly adopts this broader confirmation.

## Developer evaluation boundary

Evaluation uses only reviewed synthetic prompts. It must not use copied personal prompts, personal workout or health data, credentials, device identifiers, physical treadmill captures or production provider transcripts.

The developer-only evaluation system is grouped under the approved boundary:

```text
Evaluation/
└── WorkoutImport/
    ├── README.md
    ├── Sources/
    │   ├── App/
    │   ├── Providers/
    │   └── Runner/
    ├── Tests/
    ├── Contracts/
    ├── Corpus/
    │   └── v1/
    ├── Scoring/
    ├── Summaries/
    └── .runs/
```

The Xcode targets may be named `PacePromptEvaluation` and `PacePromptEvaluationTests`, while every provider adapter, evaluation view, runner, raw result and scoring tool remains under this top-level boundary and outside the production app target. Production-shared proposal value types may live beside the existing plan domain only when a later authorised slice needs them. The production target must not depend on evaluation providers, UI, runner, corpus, raw runs or scoring tools.

Tracking and retention rules are:

- `Contracts/`, `Corpus/`, `Scoring/`, `Tests/` and developer documentation are eligible for review and source control when created by #12;
- `.runs/` is ignored and local, contains raw run inputs and complete outputs only for the bounded synthetic evaluation, and is never committed, exported by the app or treated as workout storage;
- raw runs remain only until the operator has reviewed the run, produced any accepted aggregate and deliberately removes them; absence after removal does not invalidate an already committed summary whose provenance and hash remain sufficient to interpret it;
- `Summaries/` is reserved for explicitly reviewed aggregate measurements and non-sensitive environment provenance, never complete prompts, complete model outputs, secrets, request headers, personal identifiers or traceable device identifiers; and
- no raw or aggregate evaluation artefact is uploaded automatically. Provider requests occur only in the separately authorised operator run.

## Shared evaluation method

Issue #12 must create one versioned synthetic corpus, the provider-neutral proposal contract and one deterministic scorer used unchanged for every candidate. Provider adapters may translate native APIs to the common evidence envelope, but they cannot alter cases, expected assertions, scoring rules or hard gates by provider.

Expected outcomes are semantic assertions, not exact prose or another model's judgement. Per-case scoring records at least:

- structural outcome and proposal-contract version;
- fidelity of every explicitly stated duration, speed, inclination, activity and repetition;
- preservation of exact step order and multiplicity;
- expected clarification, unsupported or refusal behaviour and reason category;
- deterministic canonical-mapping and `WorkoutPlanValidator` outcome;
- handling of known unsupported and unknown capabilities; and
- preservation of the rule that the proposal cannot validate, persist, execute or control a treadmill.

Invalid generator structure, failed canonical mapping, a locally invalid `WorkoutPlan` and scorer failure are distinct results. A malformed or incomplete evidence record makes scoring fail closed; it cannot receive a partial success by omitting a required assertion. Machine-readable per-case output and aggregate summaries must reconcile case counts and outcome categories exactly.

### Operational evidence

Operational measurements are recorded separately from semantic scores:

- runtime/provider/model availability and reason when unavailable;
- complete-response latency measured from deliberate invocation to receipt of the complete response, with timeouts and failures retained as outcomes rather than discarded;
- repeatability across identical case, prompt-contract, provider/model, routing and run configuration;
- provider-reported OpenRouter input, cached-input and output tokens plus the explicit pricing source, date, currency and calculation used for any cost estimate; and
- Apple on-device energy, peak memory, thermal state and offline behaviour where the authorised measurement method can observe them.

Unavailable counters and measurements are `unmeasured`, never zero and never inferred. Semantic quality and operational evidence remain separate so lower latency, lower cost or local availability cannot conceal a hard safety failure.

### Provenance and evidence levels

Every run records a stable run identity and the exact:

- app commit;
- proposal-contract, result-contract, corpus and scorer versions;
- corpus manifest hash and prompt/template version;
- device class without a traceable device identifier, OS version and locale;
- provider and model identity, including a provider-supplied immutable model revision when available;
- routing constraints, inference parameters, offline/network condition and run configuration; and
- start/end times and measurement-tool versions needed to interpret operational evidence.

Evidence is labelled as one of:

| Evidence level | What it can establish |
| --- | --- |
| Static/fixture | Contract, corpus, schema and deterministic scorer behaviour only. |
| Simulator | App integration behaviour that does not require a physical inference runtime; never Apple on-device availability, energy or offline evidence. |
| Physical iPhone | Apple runtime and device operational evidence for the recorded iPhone/OS/configuration only. |
| Remote provider | OpenRouter response and operational evidence for the recorded provider/model/route/time only. |

An iPhone result does not generalise to another device or OS. A remote result does not establish local behaviour. Neither establishes treadmill compatibility, Bluetooth command delivery, safe physical motion or workout execution.

### Ratification and regression

Before the #14 operator run, the user must explicitly ratify the exact model set, repetition count, spending limit, comparison rubric, hard safety gates and provider decision rule. These values are intentionally unselected here and must not be inferred by #12 or #13. If authority is absent or a spend limit would be exceeded, the runner fails closed before another remote request.

Each accepted run uses an immutable configuration and fresh run identity. Repetitions do not overwrite one another. A regression comparison is repeated when the proposal contract, corpus, scorer, prompt/template, app mapping, provider/model revision, routing constraints, relevant OS/runtime or decision rule changes. New evidence is compared by stable case ID and aggregate category; it does not rewrite historical evidence or silently combine incompatible configurations.

A provider decision requires every ratified hard safety gate to pass and applies only to the recorded evidence scope. The decision rule may then compare semantic and operational measures as ratified. One demonstration, aggregate score or availability check cannot select a production provider. Any later production-inference issue requires explicit ratification of the #14 evidence and provider decision.

## Ordered follow-on work

1. Issue [#12](https://github.com/syamaner/paceprompt-ios/issues/12) creates the shared synthetic corpus, versioned proposal/result schemas and deterministic scorer.
2. Issue [#13](https://github.com/syamaner/paceprompt-ios/issues/13) creates the developer-only iPhone evaluation target and Apple/OpenRouter adapters after #12 is accepted.
3. Issue [#14](https://github.com/syamaner/paceprompt-ios/issues/14) runs the ratified evaluation on the iPhone 17 Pro Max under explicit operator control after #13 is accepted.
4. A production-inference issue may be created only after the evaluation evidence and provider decision are explicitly ratified.

No follow-on inherits authority for a network request, API key, provider dependency, physical-device operation or production change merely by being listed here. Each issue requires its own current authorisation and must preserve all earlier privacy, validation and evidence boundaries.

## Explicit exclusions

This contract adds no inference implementation, evaluation corpus, schema file, scorer, runner, evaluation target, network call, API-key UI, Keychain item, Apple Foundation Models integration, OpenRouter dependency, plan-persistence change, export implementation, production-provider decision, FTMS Control Point write, workout execution, HealthKit permission, watchOS target or physical-device operation.

Nothing in this document authorises model execution or a physical treadmill command.
