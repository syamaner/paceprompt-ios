#!/usr/bin/env python3
"""Bounded, data-only archive transfer between build and trusted signing runners."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

ARCHIVE = 'PromptPace.xcarchive'
APP = f'{ARCHIVE}/Products/Applications/PacePrompt.app'
MAX_FILES = 20000
MAX_FILE = 512 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024
SHA = re.compile(r'[0-9a-f]{40}\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
TAG = re.compile(r'testflight/(\d+\.\d+(?:\.\d+)?)-b([1-9]\d*)\Z')


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def identity(sha: str, tag: str, run: str, attempt: str) -> dict:
    if not SHA.fullmatch(sha) or not TAG.fullmatch(tag) or not run.isdigit() or attempt != '1':
        raise ValueError('Invalid source/tag/run identity or repeated attempt')
    return {'schema': 1, 'source_sha': sha, 'tag': tag, 'run_id': run, 'run_attempt': attempt}


def permitted(name: str) -> bool:
    return (name == f'{ARCHIVE}/Info.plist' or name.startswith(APP + '/')
            or name.startswith(f'{ARCHIVE}/dSYMs/PacePrompt.app.dSYM/'))


def names_and_sizes(entries: list[tuple[str, int]]) -> None:
    if not entries or len(entries) > MAX_FILES:
        raise ValueError('Archive entry count exceeds policy')
    seen = set()
    total = 0
    for name, size in entries:
        path = PurePosixPath(name)
        # Also reject macOS case-insensitive collisions and non-canonical paths.
        if (path.is_absolute() or '..' in path.parts or '\\' in name
                or str(path) != name or name.casefold() in seen or not permitted(name)):
            raise ValueError('Unexpected, duplicate or unsafe archive path')
        seen.add(name.casefold())
        if size < 0 or size > MAX_FILE:
            raise ValueError('Archive member exceeds size policy')
        total += size
    if total > MAX_TOTAL:
        raise ValueError('Archive exceeds total size policy')


def validate_archive(root: Path, tag: str) -> Path:
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError('Invalid release tag')
    app = root / 'Products/Applications/PacePrompt.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': 'com.otherweather.PromptPace',
                'CFBundleExecutable': 'PacePrompt',
                'CFBundlePackageType': 'APPL',
                'CFBundleShortVersionString': match[1], 'CFBundleVersion': match[2],
                'DTPlatformName': 'iphoneos', 'CFBundleSupportedPlatforms': ['iPhoneOS']}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('Unsigned app identity/platform differs from release')
    if not (app / 'PacePrompt').is_file():
        raise ValueError('Missing app executable')
    archive = plistlib.loads((root / 'Info.plist').read_bytes())
    props = archive.get('ApplicationProperties', {})
    if (props.get('ApplicationPath') != 'Applications/PacePrompt.app'
            or props.get('CFBundleIdentifier') != expected['CFBundleIdentifier']
            or props.get('CFBundleShortVersionString') != match[1]
            or props.get('CFBundleVersion') != match[2]
            or archive.get('ArchiveVersion') != 2):
        raise ValueError('Archive metadata differs from release')
    for path in app.rglob('*'):
        relative = path.relative_to(app)
        if (path.is_symlink() or path.name in {'embedded.mobileprovision', '_CodeSignature'}
                or any(part.endswith(('.app', '.appex', '.framework', '.dylib')) for part in relative.parts)):
            raise ValueError('Signed, linked or nested-code app content is not supported')
    return app


def pack(root: Path, output: Path, context: dict) -> str:
    validate_archive(root, context['tag'])
    files = []
    for path in root.rglob('*'):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode) or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
            raise ValueError('Only regular files/directories can be transferred')
        if path.is_file():
            files.append((path, f'{ARCHIVE}/{path.relative_to(root).as_posix()}'))
    names_and_sizes([(name, path.stat().st_size) for path, name in files])
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr('handoff.json', json.dumps(context, sort_keys=True))
        for path, name in sorted(files):
            bundle.write(path, name)
    return digest_file(output)


def unpack(bundle_path: Path, destination: Path, context: dict, expected_digest: str) -> Path:
    if not DIGEST.fullmatch(expected_digest):
        raise ValueError('Missing or invalid expected archive digest')
    if bundle_path.stat().st_size > MAX_TOTAL:
        raise ValueError('Package exceeds size policy')
    if digest_file(bundle_path) != expected_digest:
        raise ValueError('Archive digest differs from build output')
    # Validate the entire directory before writing anything. Never use extractall.
    with zipfile.ZipFile(bundle_path) as bundle:
        entries = bundle.infolist()
        manifests = [entry for entry in entries if entry.filename == 'handoff.json']
        if len(manifests) != 1 or manifests[0].file_size > 4096:
            raise ValueError('Missing, duplicate or oversized handoff metadata')
        if json.loads(bundle.read(manifests[0])) != context:
            raise ValueError('Archive belongs to another source/tag/run/attempt')
        payload = [entry for entry in entries if entry.filename != 'handoff.json']
        names_and_sizes([(entry.filename, entry.file_size) for entry in payload])
        for entry in entries:
            mode = entry.external_attr >> 16
            if (entry.flag_bits & 1 or entry.is_dir()
                    or (stat.S_IFMT(mode) not in (0, stat.S_IFREG))):
                raise ValueError('Encrypted, linked or non-regular ZIP entry')
        # A fresh destination prevents existing files or symlinks from influencing extraction.
        destination.mkdir(mode=0o700, parents=False, exist_ok=False)
        try:
            for entry in payload:
                path = destination / entry.filename
                path.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(entry) as source, path.open('xb') as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
                path.chmod(0o755 if entry.filename == APP + '/PacePrompt' else 0o644)
            validate_archive(destination / ARCHIVE, context['tag'])
        except Exception:
            shutil.rmtree(destination)
            raise
    return destination / ARCHIVE


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['pack', 'unpack'])
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--attempt', required=True)
    parser.add_argument('--digest')
    args = parser.parse_args()
    try:
        context = identity(args.sha, args.tag, args.run, args.attempt)
        if args.command == 'pack':
            if args.archive is None:
                raise ValueError('Missing archive')
            print(pack(args.archive, args.package, context))
        else:
            if args.destination is None:
                raise ValueError('Missing destination')
            print(unpack(args.package, args.destination, context, args.digest or ''))
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
