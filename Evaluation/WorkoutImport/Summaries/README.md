# Reviewed aggregate summaries only

This directory is reserved for explicitly reviewed aggregate evidence and
non-sensitive provenance. A future committed summary may include counts,
declared scoring versions, corpus hash, app commit, non-identifying device
class, OS/locale, provider/model identity, run configuration identity and
measurement methods.

Do not commit complete prompts, complete model outputs, request headers, API
keys, provider credentials, personal or health data, device identifiers,
treadmill captures or raw run files here. Raw synthetic run evidence belongs in
ignored `../.runs/`. Nothing is uploaded automatically.

Issue #12 commits no provider or model comparison summary because no provider
run, physical-iPhone run, model set, repetition count, spending limit, rubric,
hard safety gate or decision rule is authorised.

Reviewed summaries:

- [`issue145-together-matrix-2026-09-26.md`](issue145-together-matrix-2026-09-26.md)
  records the accepted amended eleven-model Together lineage, including
  admission failures, rate-limit pauses and uncertain sends. The additive
  aggregate, token/cost coverage supplement and mechanical audit are bound by
  [`issue145-together-matrix-publication-manifest.json`](issue145-together-matrix-publication-manifest.json).
  All fixed denominators and unchanged gate results are retained; no production
  model is selected and raw evidence remains ignored.

- [`consolidated-evaluation-2026-09-06.md`](consolidated-evaluation-2026-09-06.md)
  brings together the v3/v4 decision evidence, historical v2.9 screening,
  front-loaded classification metrics and deterministic-scoring methodology,
  detailed category tables, four comparison charts, twelve confusion matrices
  and aggregate-only machine-readable data. Reproduce the reporting extension
  with `python3 -B build_classification_diagnostics.py --check` from this directory.
- [`open-weight-v4-2026-09-05.md`](open-weight-v4-2026-09-05.md) records the
  issue #17 host-side open-weight evaluation and the ratified decision to retain
  `openai/gpt-5.6-sol`.
- [`issue145-stage-a-2026-09-20.md`](issue145-stage-a-2026-09-20.md) records
  the separately authorised four-model Stage A evaluation of the issue #130 r2
  production prompt. Its exact aggregate and mechanical audit are published as
  [`issue145-stage-a-data.json`](issue145-stage-a-data.json) and
  [`issue145-stage-a-evidence-integrity.json`](issue145-stage-a-evidence-integrity.json).
  [`issue145-stage-a-publication-manifest.json`](issue145-stage-a-publication-manifest.json)
  hash-binds those files, the human report and the ignored run provenance; run
  `python3 -B Evaluation/WorkoutImport/Summaries/verify_issue145_stage_a_publication.py`
  to verify the committed publication.
- [`issue145-stage-b-and-comparison-2026-09-22.md`](issue145-stage-b-and-comparison-2026-09-22.md)
  publishes the accepted Stage B aggregate and the protected three-repetition
  Stage A+B comparison. The comparison deliberately selects no model and
  preserves the inherited capability-gate result without relaxing the scorer.
  [`issue145-stage-a-b-publication-manifest.json`](issue145-stage-a-b-publication-manifest.json)
  binds the exact ratified proposal, ratification, new aggregate artifacts,
  ignored-run provenance and protected historical summaries. Verify it with
  `python3 -B Evaluation/WorkoutImport/Summaries/verify_issue145_stage_a_b_publication.py`.
