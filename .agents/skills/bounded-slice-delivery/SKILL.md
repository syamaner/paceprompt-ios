---
name: bounded-slice-delivery
description: Deliver one explicitly authorised PacePrompt repository slice, preserving its exclusions, evidence boundaries and handoff requirements. Use for implementation, review or planning that could otherwise drift into later product features.
---

# Bounded Slice Delivery

## Establish the contract

Read `AGENTS.md`, the current user request and the sources it identifies. Treat eventual-product designs as context only. Resolve contradictions that affect the work before implementing them.

Translate the current contract into three sets:

- required outcomes;
- permitted supporting work;
- explicit exclusions.

Keep this boundary visible in the working plan. Do not prepare later product features merely because the architecture will eventually need them.

## Work inside the slice

- Inspect repository and toolchain state before editing.
- Preserve unrelated work and personal configuration.
- Prefer the smallest architecture that meets current acceptance criteria while retaining the seams explicitly required by the contract.
- Add only tests and documentation that prove or explain this slice.
- Do not create a remote, commit, push, publish or operate hardware unless the current user request authorises it.

For FTMS work, also use the repository's `ftms-safe-development` skill.

## Validate claims

Run focused checks while iterating, then the broader checks required by the contract. Review `git diff --check`, the complete diff and repository status before handoff.

Separate these evidence levels in the final report:

- source inspection or static analysis;
- simulator build/test;
- installation on an iPhone;
- observation against the physical FR30z.

Never let a lower evidence level stand in for a higher one. Report exclusions and remaining physical validation, then stop at the slice boundary.
