---
name: paceprompt-video-capture
description: Capture privacy-reviewed PacePrompt videos from an iOS Simulator framebuffer or a selected Codex window on macOS. Use for simulator demos and Codex workflow clips; do not use as physical-device, Bluetooth, FTMS, or treadmill evidence.
---

# PacePrompt Video Capture

Create short, silent, local video evidence without exposing unrelated Codex tasks or desktop content. Capturing does not authorise publication, hardware access, treadmill operation, Bluetooth activity, or an FTMS Control Point write.

## Choose the capture boundary

- Use `scripts/record_simulator.sh` for the PacePrompt app. It records the selected Simulator framebuffer, never the desktop or Codex.
- Use `scripts/capture_codex_workflow.sh` for a Codex workflow. It records one verified Codex window only, never the full display.
- For a chaptered new-feature rollout, read [references/end-to-end-rollout.md](references/end-to-end-rollout.md) and assemble only clips that have passed their individual privacy checks.
- Use synthetic app states unless a separate task explicitly authorises other data or hardware.
- Keep audio disabled. Do not add `screencapture -g` or `-G` options.

Write captures outside Git, normally under a new directory in `/private/tmp`. Do not add recordings, preview receipts, raw captures, device identifiers, diagnostics, or personal content to the repository.

## Record the Simulator

Boot the intended simulator and place the app in the required synthetic state. List booted devices when identity matters, then record a bounded clip:

```sh
xcrun simctl list devices booted
.agents/skills/paceprompt-video-capture/scripts/record_simulator.sh \
  --udid DEVICE_UDID \
  --seconds 30 \
  --rotate clockwise \
  --output /private/tmp/paceprompt-capture/exercise-landscape.mov
```

The script refuses an existing output file, defaults to H.264, records no audio, and stops after at most 300 seconds. Simulator landscape captures can arrive in a portrait canvas without orientation metadata, so pass `--rotate clockwise` or `--rotate counterclockwise` only after confirming the required direction. A simulator recording is visual simulator evidence only.

## Record a Codex workflow

Use a dedicated Codex window or task containing only the workflow intended for the clip. Before previewing:

1. Collapse the Codex task sidebar so no unrelated task or chat titles are visible.
2. Close or hide unrelated Codex tabs and panels; keep only the intended content and terminal/review surface.
3. Enable a notification-suppressing Focus mode and move transient sensitive windows away.
4. Avoid commands or output that expose credentials, personal paths, device diagnostics, prompts from unrelated tasks, or personal data.

List recordable Codex windows:

```sh
.agents/skills/paceprompt-video-capture/scripts/capture_codex_workflow.sh list
```

Create a still preview and receipt for the chosen window:

```sh
.agents/skills/paceprompt-video-capture/scripts/capture_codex_workflow.sh preview \
  --window-id WINDOW_ID \
  --preview /private/tmp/paceprompt-capture/codex-preview.png \
  --receipt /private/tmp/paceprompt-capture/codex-preview.plist
```

Inspect the preview image itself. Confirm that the sidebar is collapsed and that no unrelated task names, chat content, notifications, secrets, personal data, or unintended panels are visible. Do not infer approval from the filename or receipt. If anything is exposed, correct the window and create a new preview; do not record or attempt to repair the unsafe preview.

Only after that visual inspection, pass the printed SHA-256 approval token to the recording mode:

```sh
.agents/skills/paceprompt-video-capture/scripts/capture_codex_workflow.sh record \
  --receipt /private/tmp/paceprompt-capture/codex-preview.plist \
  --approve-preview-sha SHA256_FROM_INSPECTED_PREVIEW \
  --seconds 30 \
  --output /private/tmp/paceprompt-capture/codex-workflow.mov
```

The script verifies the exact preview and receipt, re-verifies that the same window still belongs to Codex, and takes an immediate live still whose central content fingerprint must match the approved preview before recording can start. The comparison excludes only narrow title and composer strips where Codex shows transient activity; opening a side panel changes the checked content and fails closed. Run the record command from outside the window being captured; invoking it from that same active Codex task can legitimately change the task UI and fail the live preflight. The script records only the approved window, omits audio, refuses clips longer than 300 seconds, and removes partial or rejected output. Cursor and click indicators are opt-in. Do not expand either side panel while recording; abort and recapture if one opens or unrelated content appears.

## Inspect before use

Run:

```sh
.agents/skills/paceprompt-video-capture/scripts/inspect_video.sh \
  --video /private/tmp/paceprompt-capture/codex-workflow.mov \
  --frames /private/tmp/paceprompt-capture/codex-workflow-frames
```

The inspection script fails if an audio stream exists and exports start, middle, and end frames. Visually inspect all three frames and, for clips with meaningful intermediate transitions, inspect additional frames or play the complete clip. Confirm legibility, stable orientation, no notification overlays, and no unrelated/private content before copying, editing, sharing, or publishing it.

## Capture an end-to-end feature rollout

Do not record an entire development session continuously. Capture short, intentional Codex and Simulator chapters, inspect each independently, then join the approved clips with `scripts/assemble_feature_rollout.py`. Follow [the end-to-end rollout procedure](references/end-to-end-rollout.md) whenever the request covers planning through implementation, validation, and the finished feature.

Report the capture source, simulator/device identity when applicable, dimensions, duration, whether audio was absent, the output SHA-256, the inspected frames, and the exact evidence boundary. Keep simulator and Codex workflow video separate from physical-device or treadmill claims.
