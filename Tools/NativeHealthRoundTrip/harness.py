#!/usr/bin/env python3
"""Bounded synthetic-only native Health round trip. Never changes Health permissions."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
PHONE_BUNDLE = 'com.otherweather.PromptPace'
WATCH_BUNDLE = PHONE_BUNDLE + '.watchkitapp'
PHONE_RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
WATCH_RUNTIME = 'com.apple.CoreSimulator.SimRuntime.watchOS-27-0'
PHONE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
WATCH_TYPE = 'com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm'
SOURCES = ['PacePromptWatch/WatchHealthKitAdapter.swift', 'Shared/WatchInterchange/WatchWire.swift',
           'Shared/WatchInterchange/WatchHealthMetadata.swift', 'Shared/WatchInterchange/WatchRecordingAdapter.swift',
           'Shared/WatchInterchange/WatchBuilderAssembly.swift', 'Shared/WatchInterchange/WatchWorkoutLifecycle.swift',
           'PacePrompt/Import/StrictImportJSON.swift']
LEGACY_CASES = ['v1-complete', 'v2-paused', 'v2-rich', 'v2-incomplete', 'v2-rich-rejected']
V3_CASES = ['v3-paused', 'v3-zero', 'v3-incomplete'] + ['v3-safe-' + str(i) for i in range(8)] + ['v3-rich']


def command(args, *, cwd=None, timeout=60):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, timeout=timeout).stdout


def sim(*args):
    return command(['xcrun', 'simctl', *args]).decode().strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def retain(path, data):
    """Existing evidence is immutable; equal copies are harmless."""
    if path.is_symlink():
        raise ValueError('Evidence path is a symlink')
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError('Refusing changed evidence: ' + path.name)
    else:
        with path.open('xb') as output:
            output.write(data)
        path.chmod(0o600)


def verify(root, evidence):
    if str(root) != evidence['output'] or evidence['syntheticOnly'] is not True:
        raise ValueError('Not the original synthetic workspace')
    for path, digest in evidence['inputHashes'].items():
        file = root / path
        if file.is_symlink() or sha(file.read_bytes()) != digest:
            raise ValueError('Changed harness/source input: ' + path)
    if sorted(p.name for p in (root / 'Production').iterdir()) != sorted(Path(p).name for p in SOURCES):
        raise ValueError('Unexpected production compile input')


def verify_devices(evidence):
    devices = json.loads(sim('list', 'devices', '--json'))['devices']
    selected = {}
    for key, runtime, kind in [('phone', PHONE_RUNTIME, PHONE_TYPE), ('watch', WATCH_RUNTIME, WATCH_TYPE)]:
        matches = [d for d in devices.get(runtime, []) if d['udid'] == evidence[key]['udid']]
        if len(matches) != 1 or matches[0]['name'] != evidence[key]['name'] or matches[0]['deviceTypeIdentifier'] != kind:
            raise ValueError('Dedicated fresh simulator identity changed')
        selected[key] = matches[0]
    pairs = json.loads(sim('list', 'pairs', '--json'))['pairs']
    pair = pairs[evidence['pair']]
    if pair['phone']['udid'] != evidence['phone']['udid'] or pair['watch']['udid'] != evidence['watch']['udid']:
        raise ValueError('Dedicated companion pair changed')
    return selected


def prepare(args):
    root = Path(args.output).resolve()
    if root.exists() or not root.is_relative_to(Path('/private/tmp')):
        raise ValueError('Output must be an absent directory under /private/tmp')
    if not re.fullmatch('[0-9a-f]{40}', args.ref):
        raise ValueError('An exact full lowercase producer commit SHA is required')
    repo = Path(args.repo).resolve()
    resolved = command(['git', 'rev-parse', args.ref + '^{commit}'], cwd=repo).decode().strip()
    if resolved != args.ref:
        raise ValueError('Producer revision did not resolve exactly')
    sources = {path: command(['git', 'show', args.ref + ':' + path], cwd=repo) for path in SOURCES}
    root.mkdir(mode=0o700)
    tag = uuid.uuid4().hex[:8]
    evidence = {'syntheticOnly': True, 'output': str(root), 'producerCommit': args.ref,
                'writerAPI': args.writer_api, 'productionHashes': {p: sha(v) for p, v in sources.items()},
                'harnessHashes': {name: sha((HERE / name).read_bytes()) for name in ['harness.py', 'Probe.template.swift', 'Companion.template.swift', 'case-identities.json']},
                'stage': 'creating', 'transportExclusion': 'Native mirroring is a test no-op; wire bytes are delivered in-process.'}
    for key, runtime, kind in [('phone', PHONE_RUNTIME, PHONE_TYPE), ('watch', WATCH_RUNTIME, WATCH_TYPE)]:
        name = 'PP Synthetic Native ' + tag + ' ' + key
        identifier = sim('create', name, kind, runtime)
        uuid.UUID(identifier)
        evidence[key] = {'udid': identifier, 'name': name}
        write_json(root / 'evidence.json', evidence)  # Retain partial setup on failure; never delete devices.
    evidence['pair'] = sim('pair', evidence['watch']['udid'], evidence['phone']['udid'])
    (root / 'Production').mkdir()
    for path, data in sources.items():
        (root / 'Production' / Path(path).name).write_bytes(data)
    identities = json.loads((HERE / 'case-identities.json').read_text())
    if set(identities) != set(LEGACY_CASES + V3_CASES) or any(not re.fullmatch('[0-9]{4}', v) for v in identities.values()) or len(set(identities.values())) != len(identities):
        raise ValueError('Invalid explicit scenario identity map')
    suffixes = '[' + ', '.join(json.dumps(k) + ':' + json.dumps(v) for k, v in sorted(identities.items())) + ']'
    evidence['caseIdentities'] = identities
    for name in ['Probe', 'Companion']:
        source = (HERE / (name + '.template.swift')).read_text()
        source = source.replace('__WATCH_UDID__', evidence['watch']['udid']).replace('__PHONE_UDID__', evidence['phone']['udid']).replace('__CASE_SUFFIXES__', suffixes)
        (root / (name + '.swift')).write_text(source)
    info = {'CFBundleDisplayName': 'Synthetic Health Probe', 'WKApplication': True,
            'WKCompanionAppBundleIdentifier': PHONE_BUNDLE, 'WKBackgroundModes': ['workout-processing'],
            'NSHealthShareUsageDescription': 'Read only this fresh simulator synthetic workout.',
            'NSHealthUpdateUsageDescription': 'Save synthetic workouts on this fresh simulator only.'}
    (root / 'Info.plist').write_bytes(plistlib.dumps(info))
    (root / 'Probe.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.healthkit': True}))
    project = {'name': 'NativeProducerProbe', 'settings': {'base': {'SWIFT_VERSION': '5.0',
               'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'LEGACY_WRITER' if args.writer_api == 'legacy' else ''}},
               'targets': {
        'SyntheticCompanion': {'type': 'application', 'platform': 'iOS', 'deploymentTarget': '27.0',
            'sources': ['Companion.swift'], 'dependencies': [{'target': 'NativeProducerProbe', 'embed': True}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': PHONE_BUNDLE,
                'INFOPLIST_KEY_CFBundleDisplayName': 'Synthetic Companion', 'TARGETED_DEVICE_FAMILY': '1,2'}}, 'scheme': {}},
        'NativeProducerProbe': {'type': 'application', 'platform': 'watchOS', 'deploymentTarget': '27.0',
            'sources': ['Production', 'Probe.swift'], 'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': WATCH_BUNDLE,
                'INFOPLIST_FILE': 'Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Probe.entitlements'}}, 'scheme': {}}}}
    write_json(root / 'project.json', project)
    inputs = list((root / 'Production').iterdir()) + [root / name for name in ['Probe.swift', 'Companion.swift', 'Info.plist', 'Probe.entitlements', 'project.json']]
    evidence['inputHashes'] = {str(p.relative_to(root)): sha(p.read_bytes()) for p in inputs}
    evidence['stage'] = 'prepared'
    write_json(root / 'evidence.json', evidence)
    print(json.dumps({'output': str(root), 'phone': evidence['phone'], 'watch': evidence['watch']}, indent=2))


def build_install(root, evidence):
    devices = verify_devices(evidence)
    command(['xcodegen', 'generate', '--spec', 'project.json'], cwd=root)
    with (root / 'build.log').open('xb') as log:
        subprocess.run(['xcodebuild', '-project', 'NativeProducerProbe.xcodeproj', '-scheme', 'SyntheticCompanion',
            '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', 'DerivedData',
            'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=', 'build'],
            cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
    products = root / 'DerivedData/Build/Products'
    apps = {'phone': products / 'Debug-iphonesimulator/SyntheticCompanion.app',
            'watch': products / 'Debug-watchsimulator/NativeProducerProbe.app'}
    evidence['artifactHashes'] = {str(p.relative_to(root)): sha(p.read_bytes()) for app in apps.values() for p in app.rglob('*') if p.is_file()}
    for key, app in apps.items():
        identifier = evidence[key]['udid']
        if devices[key]['state'] != 'Booted':
            sim('boot', identifier)
        sim('install', identifier, str(app))
    evidence['stage'] = 'installed'
    write_json(root / 'evidence.json', evidence)
    print('Installed only on the newly created synthetic simulator pair; no Health authorization changed.')


def collect(root, evidence):
    verify_devices(evidence)
    docs = Path(sim('get_app_container', evidence['watch']['udid'], WATCH_BUNDLE, 'data')) / 'Documents'
    output = root / 'outputs'
    output.mkdir(exist_ok=True)
    if output.is_symlink():
        raise ValueError('Output directory is a symlink')
    log = ''
    if not docs.exists():
        return log
    for file in docs.iterdir():
        if file.is_symlink():
            raise ValueError('Unexpected symlink in synthetic app output')
        if not file.is_file():
            continue
        data = file.read_bytes()
        if file.name == 'probe.log':
            log = data.decode()
            attempts = output / 'attempt-logs'; attempts.mkdir(exist_ok=True)
            if attempts.is_symlink():
                raise ValueError('Attempt directory is a symlink')
            retain(attempts / (sha(data) + '.log'), data)
            (output / 'probe.latest.log').write_bytes(data)  # Explicit mutable view; hash snapshots stay immutable.
        elif file.name.endswith(('.receipt.json', '.manifest.json', '.hkworkout')):
            retain(output / file.name, data)
    if 'SUCCESS: saved/query/archive activities=' in log:
        receipts = list(docs.glob('*.receipt.json'))
        if receipts:
            latest = max(receipts, key=lambda p: p.stat().st_mtime)
            retain(output / latest.name.replace('.receipt.json', '.log'), log.encode())
    write_json(root / 'output-hashes.json', {str(p.relative_to(output)): sha(p.read_bytes()) for p in output.rglob('*') if p.is_file() and p.name != 'probe.latest.log'})
    return log


def run_case(root, evidence, name):
    allowed = LEGACY_CASES + ([] if evidence['writerAPI'] == 'legacy' else V3_CASES)
    if name not in allowed or evidence['stage'] != 'installed':
        raise ValueError('Scenario is not supported by this installed synthetic host')
    for path, digest in evidence['artifactHashes'].items():
        if sha((root / path).read_bytes()) != digest:
            raise ValueError('Built synthetic artifact changed')
    log = collect(root, evidence)
    if (root / 'outputs' / (name + '.receipt.json')).exists():
        raise ValueError('Refusing duplicate scenario save')
    if log and not ('SUCCESS: saved/query/archive activities=' in log or log.startswith('READY:')):
        raise ValueError('Previous attempt is unresolved. Keep it alive for authorization/readback or recover explicitly; never overwrite it.')
    # A completed/ready host may be stopped; an unresolved native operation is never terminated here.
    subprocess.run(['xcrun', 'simctl', 'terminate', evidence['watch']['udid'], WATCH_BUNDLE], capture_output=True, timeout=30)
    sim('launch', evidence['watch']['udid'], WATCH_BUNDLE, name)
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        time.sleep(1)
        log = collect(root, evidence)
        if (root / 'outputs' / (name + '.receipt.json')).exists():
            print(log); return
        if 'ERROR:' in log or 'TIMEOUT:' in log:
            raise RuntimeError(log)
    print('Bounded runner finished waiting. Leave the app alive for its native prompt; use collect after authorization.\n' + log)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    prepare_parser = sub.add_parser('prepare')
    prepare_parser.add_argument('--repo', required=True)
    prepare_parser.add_argument('--ref', required=True)
    prepare_parser.add_argument('--writer-api', choices=['legacy', 'v3'], required=True)
    prepare_parser.add_argument('--output', required=True)
    for action in ['build-install', 'run', 'collect']:
        p = sub.add_parser(action); p.add_argument('--output', required=True)
        if action == 'run': p.add_argument('--case', required=True)
    args = parser.parse_args()
    if args.action == 'prepare':
        prepare(args); return
    root = Path(args.output).resolve()
    evidence = json.loads((root / 'evidence.json').read_text())
    verify(root, evidence)
    if args.action == 'build-install': build_install(root, evidence)
    elif args.action == 'run': run_case(root, evidence, args.case)
    else: print(collect(root, evidence))


if __name__ == '__main__':
    main()
