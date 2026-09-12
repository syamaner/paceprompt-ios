# End-to-end feature rollout capture

Use this workflow to document a new feature from intent through validated result without continuously recording the developer's desktop or unrelated Codex history.

## Capture short chapters

Capture only chapters that add evidence. A useful sequence is:

1. **Intent and boundary** - a 10-20 second Codex-window clip showing the feature request, accepted scope, and exclusions.
2. **Implementation checkpoint** - a 10-30 second Codex-window clip showing the relevant diff or focused code region. Do not show unrelated task history, credentials, personal paths, logs, or prompts.
3. **Feature behaviour** - a 15-45 second Simulator-framebuffer clip demonstrating the primary interaction with synthetic data.
4. **Validation and review** - a 10-30 second Codex-window clip showing concise, non-sensitive test/review evidence.
5. **Finished result** - an optional 10-20 second Simulator clip showing the final stable state.

The sequence is guidance, not a claim that every feature needs five chapters. Omit chapters that add no useful evidence. Keep each clip at or below the script's 300-second limit and keep the assembled video below 15 minutes.

Every Codex chapter needs its own freshly inspected preview and SHA-256 receipt. Start recording from outside the Codex window being captured so that the live pixel preflight can confirm the approved UI has not changed. Keep both side panels collapsed for the entire recording. If either opens, a notification appears, or unrelated/private content becomes visible, discard that chapter and recapture it. Simulator chapters must use `record_simulator.sh` and remain separate from physical-device or treadmill claims.

If implementation already happened before recording began, label the Codex chapter as a **review walkthrough**. Never present a reconstructed walkthrough as contemporaneous implementation footage.

## Inspect before assembly

Run `inspect_video.sh` on every chapter. Verify the reported absence of audio and visually inspect the start, middle, and end frames. Play any chapter whose intermediate content could differ materially from those samples. Do not assemble a clip merely because its command succeeded.

## Assemble approved chapters

Use one `--segment` argument per approved chapter in narrative order:

```sh
.agents/skills/paceprompt-video-capture/scripts/assemble_feature_rollout.py \
  --title "Landscape exercise refinement" \
  --segment "Intent and boundary=/private/tmp/paceprompt-capture/codex-intent.mov" \
  --segment "Feature behaviour=/private/tmp/paceprompt-capture/simulator-demo.mov" \
  --segment "Validation and review=/private/tmp/paceprompt-capture/codex-validation.mov" \
  --output /private/tmp/paceprompt-capture/feature-rollout.mov \
  --manifest /private/tmp/paceprompt-capture/feature-rollout.json
```

The assembler rejects audio, repository-contained media, existing output paths, individual clips longer than five minutes, and total duration above 15 minutes. It normalises approved inputs into a silent 1920 x 1080 H.264 video and writes a local manifest with chapter labels, dimensions, durations, paths, and SHA-256 values.

Inspect the assembled video again with `inspect_video.sh` and play it completely before any sharing or publication. Assembly and inspection do not authorise publication.
