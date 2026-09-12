#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
window_helper="$script_dir/find_codex_window.swift"
swift_cache="${TMPDIR:-/private/tmp}/paceprompt-video-capture-swift-cache"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"

run_window_helper() {
  mkdir -p "$swift_cache/clang" "$swift_cache/swift"
  CLANG_MODULE_CACHE_PATH="$swift_cache/clang" \
    SWIFT_MODULECACHE_PATH="$swift_cache/swift" \
    "$window_helper" "$@"
}

usage() {
  cat <<'EOF'
Usage:
  capture_codex_workflow.sh list
  capture_codex_workflow.sh preview --window-id ID --preview /absolute/preview.png --receipt /absolute/receipt.plist
  capture_codex_workflow.sh record --receipt /absolute/receipt.plist --approve-preview-sha SHA256 --output /absolute/video.mov [options]

Preview and record options:
  --dry-run         Verify inputs and print the capture command

Record-only options:
  --seconds N       Duration from 1 to 300 seconds (default: 30)
  --show-cursor     Include the pointer
  --show-clicks     Include click indicators
  -h, --help        Show this help

Audio is always disabled. Preview approval is a visual privacy gate, not merely
a command-line confirmation.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

absolute_path() {
  [[ "$1" == /* ]] || fail "$2 must be an absolute path"
}

reject_repository_path() {
  local target="$1"
  local label="$2"
  local resolved
  resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  if [[ -n "$repo_root" && ( "$resolved" == "$repo_root" || "$resolved" == "$repo_root/"* ) ]]; then
    fail "$label must be outside the Git worktree"
  fi
}

privacy_fingerprint() {
  ffmpeg -v error -i "$1" \
    -vf "crop=iw:ih-220:0:80,format=rgb24" \
    -frames:v 1 -f hash -hash sha256 -
}

[[ $# -ge 1 ]] || { usage; exit 1; }
mode="$1"
shift

case "$mode" in
  list)
    [[ $# -eq 0 ]] || fail "list takes no arguments"
    run_window_helper --list
    ;;

  preview)
    window_id=""
    preview=""
    receipt=""
    dry_run=0
    while (($#)); do
      case "$1" in
        --window-id) [[ $# -ge 2 ]] || fail "--window-id needs a value"; window_id="$2"; shift 2 ;;
        --preview) [[ $# -ge 2 ]] || fail "--preview needs a value"; preview="$2"; shift 2 ;;
        --receipt) [[ $# -ge 2 ]] || fail "--receipt needs a value"; receipt="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown preview argument: $1" ;;
      esac
    done

    [[ "$window_id" =~ ^[0-9]+$ ]] || fail "--window-id must be numeric"
    [[ -n "$preview" && -n "$receipt" ]] || fail "--preview and --receipt are required"
    absolute_path "$preview" "--preview"
    absolute_path "$receipt" "--receipt"
    [[ "$preview" == *.png ]] || fail "--preview must end in .png"
    [[ "$receipt" == *.plist ]] || fail "--receipt must end in .plist"
    [[ -d "$(dirname "$preview")" && -d "$(dirname "$receipt")" ]] || fail "output directory does not exist"
    reject_repository_path "$preview" "--preview"
    reject_repository_path "$receipt" "--receipt"
    [[ ! -e "$preview" && ! -e "$receipt" ]] || fail "preview or receipt already exists"
    command -v screencapture >/dev/null || fail "screencapture is unavailable"
    window_signature="$(run_window_helper --require-id "$window_id")"

    preview_command=(screencapture -x -o -a "-l$window_id" "$preview")
    if ((dry_run)); then
      printf 'dry run:'
      printf ' %q' "${preview_command[@]}"
      printf '\n'
      exit 0
    fi

    "${preview_command[@]}"
    [[ -s "$preview" ]] || fail "preview capture failed"
    chmod 600 "$preview"
    preview_sha="$(shasum -a 256 "$preview" | awk '{print $1}')"

    plutil -create xml1 "$receipt"
    plutil -insert schema_version -integer 1 "$receipt"
    plutil -insert window_id -integer "$window_id" "$receipt"
    plutil -insert window_signature -string "$window_signature" "$receipt"
    plutil -insert preview_path -string "$preview" "$receipt"
    plutil -insert preview_sha256 -string "$preview_sha" "$receipt"
    chmod 600 "$receipt"

    echo "preview: $preview"
    echo "receipt: $receipt"
    echo "approve only after visual inspection: $preview_sha"
    ;;

  record)
    receipt=""
    approved_sha=""
    output=""
    duration="30"
    show_cursor=0
    show_clicks=0
    dry_run=0
    while (($#)); do
      case "$1" in
        --receipt) [[ $# -ge 2 ]] || fail "--receipt needs a value"; receipt="$2"; shift 2 ;;
        --approve-preview-sha) [[ $# -ge 2 ]] || fail "--approve-preview-sha needs a value"; approved_sha="$2"; shift 2 ;;
        --output) [[ $# -ge 2 ]] || fail "--output needs a value"; output="$2"; shift 2 ;;
        --seconds) [[ $# -ge 2 ]] || fail "--seconds needs a value"; duration="$2"; shift 2 ;;
        --show-cursor) show_cursor=1; shift ;;
        --show-clicks) show_clicks=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown record argument: $1" ;;
      esac
    done

    [[ -n "$receipt" && -n "$approved_sha" && -n "$output" ]] || fail "--receipt, --approve-preview-sha and --output are required"
    absolute_path "$receipt" "--receipt"
    absolute_path "$output" "--output"
    [[ "$output" == *.mov ]] || fail "--output must end in .mov"
    [[ "$approved_sha" =~ ^[0-9a-fA-F]{64}$ ]] || fail "approval SHA-256 is malformed"
    [[ "$duration" =~ ^[0-9]+$ ]] || fail "--seconds must be an integer"
    ((duration >= 1 && duration <= 300)) || fail "--seconds must be between 1 and 300"
    [[ -f "$receipt" ]] || fail "receipt does not exist"
    [[ -d "$(dirname "$output")" ]] || fail "output directory does not exist"
    reject_repository_path "$output" "--output"
    [[ ! -e "$output" ]] || fail "output already exists: $output"
    command -v screencapture >/dev/null || fail "screencapture is unavailable"
    command -v ffmpeg >/dev/null || fail "ffmpeg is required for the live privacy preflight"
    command -v ffprobe >/dev/null || fail "ffprobe is required for the no-audio verification"

    window_id="$(plutil -extract window_id raw "$receipt")"
    window_signature="$(plutil -extract window_signature raw "$receipt")"
    preview="$(plutil -extract preview_path raw "$receipt")"
    receipt_sha="$(plutil -extract preview_sha256 raw "$receipt")"
    [[ -f "$preview" ]] || fail "receipt preview does not exist"
    actual_sha="$(shasum -a 256 "$preview" | awk '{print $1}')"
    [[ "$actual_sha" == "$receipt_sha" ]] || fail "preview no longer matches its receipt"
    approved_sha_lower="$(printf '%s' "$approved_sha" | tr '[:upper:]' '[:lower:]')"
    receipt_sha_lower="$(printf '%s' "$receipt_sha" | tr '[:upper:]' '[:lower:]')"
    [[ "$approved_sha_lower" == "$receipt_sha_lower" ]] || fail "approval SHA-256 does not match the preview"
    current_window_signature="$(run_window_helper --require-id "$window_id")"
    [[ "$current_window_signature" == "$window_signature" ]] || fail "Codex window geometry changed after preview; create and inspect a new preview"

    command=(screencapture -x -o -a -v "-l$window_id" "-V$duration")
    ((show_cursor)) && command+=(-C)
    ((show_clicks)) && command+=(-k)
    command+=("$output")

    if ((dry_run)); then
      printf 'dry run:'
      printf ' %q' "${command[@]}"
      printf '\n'
      exit 0
    fi

    live_preview="$(mktemp "${TMPDIR:-/private/tmp}/paceprompt-codex-live-preview.XXXXXX.png")"
    capture_succeeded=0
    cleanup_recording() {
      [[ -n "$live_preview" ]] && rm -f "$live_preview"
      ((capture_succeeded)) || rm -f "$output"
    }
    trap cleanup_recording INT TERM EXIT
    screencapture -x -o -a "-l$window_id" "$live_preview"
    [[ -s "$live_preview" ]] || fail "live privacy preflight capture failed"
    approved_content_fingerprint="$(privacy_fingerprint "$preview")"
    live_content_fingerprint="$(privacy_fingerprint "$live_preview")"
    [[ "$live_content_fingerprint" == "$approved_content_fingerprint" ]] || fail "Codex window content changed after preview; create and inspect a fresh preview immediately before recording"
    rm -f "$live_preview"
    live_preview=""

    "${command[@]}"
    [[ -s "$output" ]] || fail "recording did not produce a non-empty file"
    chmod 600 "$output"
    audio_streams="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$output")"
    [[ -z "$audio_streams" ]] || fail "unexpected audio stream detected; do not use this capture"
    capture_succeeded=1
    trap - INT TERM EXIT
    echo "recorded approved Codex window without audio: $output"
    shasum -a 256 "$output"
    ;;

  -h|--help)
    usage
    ;;
  *)
    fail "unknown mode: $mode"
    ;;
esac
