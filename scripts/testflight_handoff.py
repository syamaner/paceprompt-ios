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

if __package__:
    from . import testflight_policy as policy
else:
    import testflight_policy as policy

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
    return {'schema': 2, 'source_sha': sha, 'tag': tag, 'run_id': run, 'run_attempt': attempt}


def permitted(name: str) -> bool:
    return (name == f'{ARCHIVE}/Info.plist' or name.startswith(APP + '/')
            or any(name.startswith(f'{ARCHIVE}/dSYMs/{b["executable"]}.app.dSYM/') for b in policy.BUNDLES.values()))


def names_and_sizes(entries: list[tuple[str, int]], allowed=permitted) -> None:
    if not entries or len(entries) > MAX_FILES:
        raise ValueError('Archive entry count exceeds policy')
    seen = set()
    total = 0
    for name, size in entries:
        path = PurePosixPath(name)
        # Also reject macOS case-insensitive collisions and non-canonical paths.
        if (path.is_absolute() or '..' in path.parts or '\\' in name
                or str(path) != name or name.casefold() in seen or not allowed(name)):
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
    bundles = policy.app_graph(app)
    for name, bundle in bundles.items():
        policy.metadata(plistlib.loads((bundle / 'Info.plist').read_bytes()), match[1], match[2], name)
        policy.macho((bundle / policy.role(name)['executable']).read_bytes(), name)
    archive = plistlib.loads((root / 'Info.plist').read_bytes())
    props = archive.get('ApplicationProperties', {})
    if (props.get('ApplicationPath') != 'Applications/PacePrompt.app'
            or props.get('CFBundleIdentifier') != policy.PHONE_ID
            or props.get('CFBundleShortVersionString') != match[1]
            or props.get('CFBundleVersion') != match[2]
            or archive.get('ArchiveVersion') != 2):
        raise ValueError('Archive metadata differs from release')
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
                executables = {str(PurePosixPath(APP) / b['path'] / b['executable']) for b in policy.BUNDLES.values()}
                path.chmod(0o755 if entry.filename in executables else 0o644)
            validate_archive(destination / ARCHIVE, context['tag'])
        except Exception:
            shutil.rmtree(destination)
            raise
    return destination / ARCHIVE


def unpack_ipa(package: Path, destination: Path) -> Path:
    """Exported IPA policy: exactly Payload/PacePrompt.app, no other support/code roots.

    Unknown Apple export layouts require review; they are never silently accepted.
    Directory entries are allowed, but all names/types/bounds are checked first.
    """
    app_name = "Payload/PacePrompt.app"
    if package.stat().st_size > MAX_TOTAL:
        raise ValueError("IPA exceeds size policy")
    with zipfile.ZipFile(package) as bundle:
        entries = bundle.infolist()
        names_and_sizes([(e.filename[:-1] if e.is_dir() else e.filename, e.file_size) for e in entries],
                        lambda name: name in ("Payload", app_name) or name.startswith(app_name + "/"))
        for entry in entries:
            mode = stat.S_IFMT(entry.external_attr >> 16)
            if entry.flag_bits & 1 or mode not in ((0, stat.S_IFDIR) if entry.is_dir() else (0, stat.S_IFREG)):
                raise ValueError("Encrypted, linked or special IPA entry")
        destination.mkdir(mode=0o700, parents=False, exist_ok=False)
        try:
            executable_paths = {str(PurePosixPath(app_name) / b['path'] / b['executable']) for b in policy.BUNDLES.values()}
            for entry in entries:
                path = destination / entry.filename
                if entry.is_dir():
                    path.mkdir(mode=0o700, parents=True, exist_ok=True)
                    continue
                path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with bundle.open(entry) as source, path.open('xb') as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
                path.chmod(0o755 if entry.filename in executable_paths else 0o644)
            app = destination / app_name
            policy.app_graph(app, signed=True)
        except Exception:
            shutil.rmtree(destination)
            raise
    return app


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
