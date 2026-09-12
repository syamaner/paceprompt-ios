#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"

usage() {
  cat <<'EOF'
Usage: record_simulator.sh --output /absolute/path.mov [options]

Options:
  --udid UDID           Simulator UDID (default: booted)
  --seconds N           Duration from 1 to 300 seconds (default: 30)
  --codec h264|hevc     Video codec (default: h264)
  --display DISPLAY     Simulator display (default: internal)
  --rotate DIRECTION    none, clockwise, or counterclockwise (default: none)
  --dry-run             Validate and print the command without recording
  -h, --help            Show this help
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
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

wait_for_nonempty_file() {
  local target="$1"
  local attempt=0
  while ((attempt < 50)); do
    [[ -s "$target" ]] && return 0
    sleep 0.1
    attempt=$((attempt + 1))
  done
  return 1
}

output=""
udid="booted"
duration="30"
codec="h264"
display="internal"
rotation="none"
dry_run=0

while (($#)); do
  case "$1" in
    --output) [[ $# -ge 2 ]] || fail "--output needs a value"; output="$2"; shift 2 ;;
    --udid) [[ $# -ge 2 ]] || fail "--udid needs a value"; udid="$2"; shift 2 ;;
    --seconds) [[ $# -ge 2 ]] || fail "--seconds needs a value"; duration="$2"; shift 2 ;;
    --codec) [[ $# -ge 2 ]] || fail "--codec needs a value"; codec="$2"; shift 2 ;;
    --display) [[ $# -ge 2 ]] || fail "--display needs a value"; display="$2"; shift 2 ;;
    --rotate) [[ $# -ge 2 ]] || fail "--rotate needs a value"; rotation="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$output" ]] || fail "--output is required"
[[ "$output" == /* ]] || fail "--output must be an absolute path"
[[ "$output" == *.mov ]] || fail "--output must end in .mov"
[[ "$duration" =~ ^[0-9]+$ ]] || fail "--seconds must be an integer"
((duration >= 1 && duration <= 300)) || fail "--seconds must be between 1 and 300"
[[ "$codec" == "h264" || "$codec" == "hevc" ]] || fail "--codec must be h264 or hevc"
[[ "$rotation" == "none" || "$rotation" == "clockwise" || "$rotation" == "counterclockwise" ]] || fail "--rotate must be none, clockwise, or counterclockwise"
[[ -d "$(dirname "$output")" ]] || fail "output directory does not exist"
reject_repository_path "$output" "--output"
[[ ! -e "$output" ]] || fail "output already exists: $output"
command -v xcrun >/dev/null || fail "xcrun is unavailable"
if [[ "$rotation" != "none" ]]; then
  command -v ffmpeg >/dev/null || fail "ffmpeg is required for orientation normalisation"
fi

if ((dry_run)); then
  record_target="$output"
  [[ "$rotation" == "none" ]] || record_target="RAW_CAPTURE.mov"
  command=(xcrun simctl io "$udid" recordVideo "--codec=$codec" "--display=$display" "$record_target")
  printf 'dry run:'
  printf ' %q' "${command[@]}"
  printf '\n'
  if [[ "$rotation" != "none" ]]; then
    [[ "$rotation" == "clockwise" ]] && transpose="transpose=clock" || transpose="transpose=cclock"
    [[ "$codec" == "h264" ]] && encoder="libx264" || encoder="libx265"
    normalise=(ffmpeg -v error -i RAW_CAPTURE.mov -vf "$transpose" -an -c:v "$encoder" -crf 18 -preset medium -movflags +faststart "$output")
    printf 'dry run:'
    printf ' %q' "${normalise[@]}"
    printf '\n'
  fi
  exit 0
fi

recorder_pid=""
temporary_directory=""
temporary_parent=""
capture_succeeded=0
cleanup() {
  if [[ -n "$recorder_pid" ]] && kill -0 "$recorder_pid" 2>/dev/null; then
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true
  fi
  if [[ -n "$temporary_parent" && -d "$temporary_directory" && "$(dirname "$temporary_directory")" == "$temporary_parent" && "$(basename "$temporary_directory")" == .paceprompt-simulator-video.* ]]; then
    rm -f "$temporary_directory/raw.mov"
    rmdir "$temporary_directory" 2>/dev/null || true
  fi
  ((capture_succeeded)) || rm -f "$output"
}

record_target="$output"
if [[ "$rotation" != "none" ]]; then
  temporary_parent="$(cd "$(dirname "$output")" && pwd -P)"
  temporary_directory="$(mktemp -d "$temporary_parent/.paceprompt-simulator-video.XXXXXX")"
  record_target="$temporary_directory/raw.mov"
fi
command=(xcrun simctl io "$udid" recordVideo "--codec=$codec" "--display=$display" "$record_target")
trap cleanup INT TERM EXIT

"${command[@]}" &
recorder_pid=$!
sleep "$duration"
if kill -0 "$recorder_pid" 2>/dev/null; then
  kill -INT "$recorder_pid"
  wait "$recorder_pid" || true
fi
recorder_pid=""

wait_for_nonempty_file "$record_target" || fail "recording contained no encoded frame; include a visible Simulator transition or use a longer duration"
if [[ "$rotation" != "none" ]]; then
  [[ "$rotation" == "clockwise" ]] && transpose="transpose=clock" || transpose="transpose=cclock"
  [[ "$codec" == "h264" ]] && encoder="libx264" || encoder="libx265"
  ffmpeg -v error -i "$record_target" -vf "$transpose" -an -c:v "$encoder" -crf 18 -preset medium -movflags +faststart "$output"
  [[ -s "$output" ]] || fail "orientation normalisation did not produce a non-empty file"
fi
chmod 600 "$output"
capture_succeeded=1
cleanup
temporary_directory=""
temporary_parent=""
trap - INT TERM EXIT

echo "recorded simulator framebuffer: $output"
shasum -a 256 "$output"
