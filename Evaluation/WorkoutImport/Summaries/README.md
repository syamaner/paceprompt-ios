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

- [`open-weight-v4-2026-09-05.md`](open-weight-v4-2026-09-05.md) records the
  issue #17 host-side open-weight evaluation and the ratified decision to retain
  `openai/gpt-5.6-sol`.
