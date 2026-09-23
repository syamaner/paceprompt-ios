# Issue #145 standing restart and compatible-repair contract r1

Status: operator-approved zero-spend working contract. The operator replied
"I approve" to the exact standing-restart and compatible-repair proposal in
the 23 September 2026 Codex conversation. This is conversational authority
for zero-spend preparation only; the live issue #145 gate has not yet been
amended. This document defines
requirements for a future, separately versioned full-matrix live runner. It is
not a live gate, a spending-limit ratification, or permission to read a key or
call a provider. The sealed v5 proposal, queue, corpora, scorer and prior run
evidence remain unchanged.

## Standing run lineage

- Before any live call, bind one root run ID, exact evaluation profile and
  hashes, a finite cumulative USD hard limit, and an explicit initial live
  authorization. The missing hard-limit value and exact call plan must be
  separately ratified; this contract does not supply defaults for either.
- That authorization covers any number of **manually initiated** descendant
  restarts that preserve the bound profile and satisfy this contract. A restart
  does not require another human ratification or authorization phrase. It must
  have a fresh run ID, an immutable parent-evidence hash, a finite child call
  plan, and a fresh public route/price preflight before credential access.
- A restart never resets the lineage-wide budget. Reserve the conservative
  worst-case charge before each provider call. Include all prior actual or
  conservatively charged unknown costs when admitting a child. Stop before a
  call that would exceed the hard limit, even if the previous failure was a
  rate limit or its billed cost is unknown. No automatic retries or fallbacks.
- Persist every terminal position and its raw evidence before starting the
  next call. A possibly sent, non-terminal call after interruption becomes an
  explicitly labelled, conservatively charged terminal failure; it is never
  silently replayed. Continue only positions that never started. Preserve the
  original deterministic queue, denominator, model and stratum identities;
  do not replace or erase a failed scored result. A request to retry a terminal
  scored position is a new evaluation proposal, not a restart under this rule.
- Each child verifies the full immutable ancestry, source identity, credential
  admission and spend ledger before it may run. Cancellation and failed
  integrity checks stop closed. Lineage depth has no policy limit; the finite
  cumulative budget and finite child call plans are the execution bounds.

## Compatible developer-only repairs

A small repair may proceed without re-ratifying the unchanged evaluation
profile when it changes only developer-only HostEval orchestration, tests or
documentation and preserves the complete ratified profile and policy hashes
apart from their separately recorded host-source identity. In particular, it
leaves all of these byte- or behaviour-identical: production
prompt and examples; candidate and route pins; outbound payload and response
contract; corpora and expected answers; deterministic queue and denominator;
generation settings; scorer and scoring gates; cumulative spending limit;
concurrency, pacing and timeouts; cancellation and rate-limit disposition;
warm-up admission; cache settings; automatic and HTTP retry counts; fallback
rules; data collection and returned-route identity requirements. Credential
and fail-closed safety boundaries may only be preserved or tightened, never
expanded. A repair must not reinterpret earlier evidence or rewrite a sealed
file.

The repair record binds the old and new source hashes, the complete diff,
focused validation, an independent review, and the next child's new source
hash. Previously sealed child gates are not edited or replayed. The standing
lineage authorization survives only if the repair meets every invariant above.
Any change to a frozen input, scoring meaning or spend bound, or any expansion
of credential or safety authority, requires a new versioned profile and
separate human approval.

For a compatible repair confined to `Evaluation/WorkoutImport/HostEval/`, run
the focused HostEval suite plus affected corpus, schema, scorer and static
checks, inspect the full diff, run `git diff --check`, and obtain independent
review. The full iOS simulator/build gate is not required unless app, shared
test/build, release, production, safety or repository validation inputs change,
or the focused review finds cross-boundary risk. This is a validation-scope
rule, not permission to skip an applicable focused check or to call a provider.

## Unchanged decisions and remaining gates

Before any live use, the issue #145 live-run gate must be amended to recognise
the standing lineage authorization, and a reviewed runner must enforce this
contract mechanically. Until then, the existing run-specific authorization
rule continues to govern. This contract does not choose a route, model,
generation setting, repetition count, queue order, timeout, scoring gate or
USD amount. The two replacement routes still need accepted compatibility
proof. No full-matrix live runner or
lineage gate is implemented by this document. Publication, model selection,
production configuration, TestFlight release, merge and issue closure remain
separate decisions.
