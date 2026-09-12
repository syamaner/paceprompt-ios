#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, NoReturn


MAX_SEGMENT_SECONDS = 300
MAX_TOTAL_SECONDS = 900


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_outside_repository(path: Path, repository: Path, label: str) -> Path:
    if not path.is_absolute():
        fail(f"{label} must be an absolute path")
    resolved = path.resolve(strict=False)
    try:
        resolved.relative_to(repository)
    except ValueError:
        return resolved
    fail(f"{label} must be outside the Git worktree")


def probe(path: Path) -> dict[str, Any]:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    streams = payload.get("streams", [])
    video_streams = [stream for stream in streams if stream.get("codec_type") == "video"]
    audio_streams = [stream for stream in streams if stream.get("codec_type") == "audio"]
    if len(video_streams) != 1:
        fail(f"segment must contain exactly one video stream: {path}")
    if audio_streams:
        fail(f"audio stream detected; do not assemble segment: {path}")
    try:
        duration = float(payload["format"]["duration"])
    except (KeyError, TypeError, ValueError):
        fail(f"could not read segment duration: {path}")
    if duration <= 0 or duration > MAX_SEGMENT_SECONDS:
        fail(f"segment duration must be greater than 0 and at most {MAX_SEGMENT_SECONDS} seconds: {path}")
    video = video_streams[0]
    return {
        "duration_seconds": duration,
        "width": int(video["width"]),
        "height": int(video["height"]),
        "codec": str(video.get("codec_name", "unknown")),
    }


def parse_segment(value: str) -> tuple[str, Path]:
    if "=" not in value:
        fail("--segment must use LABEL=/absolute/path.mov")
    label, raw_path = value.split("=", 1)
    label = label.strip()
    if not label:
        fail("segment label must not be empty")
    return label, Path(raw_path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Assemble privacy-approved silent feature-rollout chapters."
    )
    parser.add_argument("--title", required=True)
    parser.add_argument("--segment", action="append", required=True, metavar="LABEL=/ABSOLUTE/PATH.mov")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--fps", type=int, default=30)
    args = parser.parse_args()

    if not args.title.strip():
        fail("--title must not be empty")
    if len(args.segment) < 2:
        fail("at least two approved segments are required")
    if args.width < 320 or args.height < 240 or not 1 <= args.fps <= 60:
        fail("invalid output dimensions or frame rate")
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        fail("ffmpeg and ffprobe are required")

    repository = Path(__file__).resolve().parents[4]
    output = require_outside_repository(args.output, repository, "--output")
    manifest = require_outside_repository(args.manifest, repository, "--manifest")
    if output.suffix.lower() != ".mov":
        fail("--output must end in .mov")
    if manifest.suffix.lower() != ".json":
        fail("--manifest must end in .json")
    if not output.parent.is_dir() or not manifest.parent.is_dir():
        fail("output and manifest parent directories must exist")
    if output.exists() or manifest.exists():
        fail("output or manifest already exists")

    chapters: list[dict[str, Any]] = []
    inputs: list[Path] = []
    total_duration = 0.0
    for raw_segment in args.segment:
        label, path = parse_segment(raw_segment)
        path = require_outside_repository(path, repository, "segment path")
        if not path.is_file():
            fail(f"segment does not exist: {path}")
        metadata = probe(path)
        total_duration += metadata["duration_seconds"]
        inputs.append(path)
        chapters.append(
            {
                "label": label,
                "path": str(path),
                "sha256": sha256(path),
                **metadata,
            }
        )
    if total_duration > MAX_TOTAL_SECONDS:
        fail(f"total duration exceeds {MAX_TOTAL_SECONDS} seconds")

    filters = []
    for index in range(len(inputs)):
        filters.append(
            f"[{index}:v:0]scale={args.width}:{args.height}:force_original_aspect_ratio=decrease,"
            f"pad={args.width}:{args.height}:(ow-iw)/2:(oh-ih)/2:color=black,"
            f"setsar=1,fps={args.fps},format=yuv420p,setpts=PTS-STARTPTS[v{index}]"
        )
    joined = "".join(f"[v{index}]" for index in range(len(inputs)))
    filters.append(f"{joined}concat=n={len(inputs)}:v=1:a=0[outv]")

    command = ["ffmpeg", "-v", "error"]
    for path in inputs:
        command.extend(["-i", str(path)])
    command.extend(
        [
            "-filter_complex",
            ";".join(filters),
            "-map",
            "[outv]",
            "-an",
            "-c:v",
            "libx264",
            "-crf",
            "18",
            "-preset",
            "medium",
            "-movflags",
            "+faststart",
            str(output),
        ]
    )

    try:
        subprocess.run(command, check=True)
        assembled = probe(output)
        if assembled["width"] != args.width or assembled["height"] != args.height:
            fail("assembled video dimensions do not match the requested output")
        payload = {
            "schema_version": 1,
            "title": args.title.strip(),
            "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "audio_streams": 0,
            "chapters": chapters,
            "output": {
                "path": str(output),
                "sha256": sha256(output),
                **assembled,
            },
        }
        manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        os.chmod(output, 0o600)
        os.chmod(manifest, 0o600)
    except BaseException:
        if output.exists():
            output.unlink()
        if manifest.exists():
            manifest.unlink()
        raise

    print(f"assembled_video={output}")
    print(f"manifest={manifest}")
    print(f"sha256={payload['output']['sha256']}")
    print("audio_streams=0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
