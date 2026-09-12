#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"

usage() {
  cat <<'EOF'
Usage: inspect_video.sh --video /absolute/video.mov --frames /absolute/new-directory

Verifies video metadata and absence of audio, then exports start, middle, and
end PNG frames for mandatory visual privacy and quality inspection.
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

video=""
frames=""
while (($#)); do
  case "$1" in
    --video) [[ $# -ge 2 ]] || fail "--video needs a value"; video="$2"; shift 2 ;;
    --frames) [[ $# -ge 2 ]] || fail "--frames needs a value"; frames="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$video" && -n "$frames" ]] || fail "--video and --frames are required"
[[ "$video" == /* && "$frames" == /* ]] || fail "paths must be absolute"
[[ -f "$video" ]] || fail "video does not exist"
[[ -d "$(dirname "$frames")" ]] || fail "frames parent directory does not exist"
reject_repository_path "$frames" "--frames"
[[ ! -e "$frames" ]] || fail "frames directory already exists"
command -v ffprobe >/dev/null || fail "ffprobe is unavailable"
command -v ffmpeg >/dev/null || fail "ffmpeg is unavailable"

audio_streams="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$video")"
[[ -z "$audio_streams" ]] || fail "audio stream detected; do not use this capture"

metadata="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -show_entries format=duration -of default=noprint_wrappers=1 "$video")"
duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")"
[[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "could not read video duration"

frame_count="$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$video")"
[[ "$frame_count" =~ ^[1-9][0-9]*$ ]] || fail "could not count encoded video frames"
middle_index=$(((frame_count - 1) / 2))
end_index=$((frame_count - 1))

mkdir "$frames"
chmod 700 "$frames"
ffmpeg -v error -i "$video" -vf "select=eq(n\\,0)" -fps_mode vfr -frames:v 1 "$frames/start.png"
ffmpeg -v error -i "$video" -vf "select=eq(n\\,$middle_index)" -fps_mode vfr -frames:v 1 "$frames/middle.png"
ffmpeg -v error -i "$video" -vf "select=eq(n\\,$end_index)" -fps_mode vfr -frames:v 1 "$frames/end.png"
for frame in "$frames/start.png" "$frames/middle.png" "$frames/end.png"; do
  [[ -s "$frame" ]] || fail "expected inspection frame was not produced: $frame"
done
chmod 600 "$frames"/*.png

echo "$metadata"
echo "encoded_frames=$frame_count"
echo "audio_streams=0"
echo "sha256=$(shasum -a 256 "$video" | awk '{print $1}')"
echo "inspection_frames=$frames/start.png,$frames/middle.png,$frames/end.png"
