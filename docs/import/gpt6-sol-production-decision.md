# GPT-6 Sol production decision — 26 September 2026

The operator accepted the separately authorised `sol56-vs-sol6-20260922-01`
comparison, explicitly selected GPT-6 Sol, reaffirmed “so we use gpt 6 sol”, and
authorised the bounded production change, reviewed merge and existing internal
TestFlight workflow. This implements that human selection, not an automatic
scorer winner.

## Evidence and limitations

The accepted [comparison report](../../Evaluation/WorkoutImport/Summaries/issue145-sol56-vs-sol6-2026-09-22.md)
and aggregate/audit are preserved byte-for-byte from reviewed comparison branch
commit `9e36bdc`; their [manifest](../../Evaluation/WorkoutImport/Summaries/issue145-sol56-vs-sol6-publication-manifest.json)
SHA-256 is `02b5c4e236a6192d15597b3eba3bd85b3738fc2fb1db0403a80cdc38fa5b0717`.
GPT-6 Sol was strict-exact on 105/109 cases versus 102/109 for GPT-5.6 Sol, with
three paired gains and no paired losses, effectively equal observed cost and lower
host p95. This is one repetition, not repetition-stability or device evidence.
Both models failed unchanged eligibility gates: the acceptance corpus has no
qualifying capability case, and held-out category floors were missed. The operator's
choice does not relax the scorer, fill coverage gaps or claim gate eligibility.

The separately published eleven-model matrix did not include GPT-6 Sol and selects
no replacement. Its availability failures, rate-limit pauses, uncertain sends and
unchanged gate results remain protected. No further inference run or spend is
authorised by this implementation.

## Closed scope and rollback

- Request alias `openai/gpt-6-sol`; accepted revision `openai/gpt-6-sol-20260922`.
- Keep exact OpenRouter endpoint and OpenAI-only route, no fallback, collection
  denial, reasoning disabled, 8,192-token production ceiling and existing timeouts.
- Keep issue130-r2 prompt, examples, schemas, parser acceptance rules, mapping,
  local validator, consent and separate save behaviour unchanged.
- Update disclosure and synthetic identity fixtures; reject old-model and drifted
  revision identities. No live credential or provider call is needed for tests.
- Internal TestFlight only: version 1.0.1 build 10, via the existing tag-triggered
  GitHub Actions workflow after complete local validation, exact-head review,
  reviewed main merge and exact-main CI. No public App Store submission.
- Rollback requires a reviewed change restoring GPT-5.6 Sol and a new build number;
  no silent route fallback, tag movement or replay of an ambiguous upload.

App installation and user testing remain separate from simulator and release
workflow evidence. This record does not claim physical treadmill acceptance.
