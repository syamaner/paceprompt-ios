"""Subprocess stub used only by the synthetic release orchestration test."""
import json
import os
import plistlib
import shutil
import sys
import zipfile
from pathlib import Path
sys.path.insert(0, os.environ['MOCK_REPO'])
from scripts.tests import release_fixtures as f

command = Path(sys.argv[0]).name
args = sys.argv[1:]
state = Path(os.environ['MOCK_STATE'])
with (state / 'calls.jsonl').open('a') as output:
    output.write(json.dumps([command, *args]) + '\n')
role = 'watch' if args and 'PacePromptWatch.app' in args[-1] else 'phone'
failure = os.environ.get('MOCK_FAIL', '')
if command == 'python3':
    if any(Path(arg).name == 'testflight_api.py' for arg in args):
        sys.exit(0)
    os.execv(sys.executable, [sys.executable, *args])
elif command == 'security':
    if args[0] == 'cms': sys.stdout.buffer.write(Path(args[-1]).read_bytes())
    elif args[0] == 'find-identity': print(f.IDENTITIES)
elif command == 'openssl':
    assert args == ['rand', '-hex', '32']; print('a' * 64)
elif command == 'codesign':
    if '--force' in args:
        if failure == 'sign-' + role: sys.exit(1)
        bundle = Path(args[-1]); executable = 'PacePromptWatch' if role == 'watch' else 'PacePrompt'
        (bundle / executable).write_bytes(f.fat_watch(signed=True) if role == 'watch' else f.macho(role, signed=True))
        (state / (role + '-entitlements.plist')).write_bytes(Path(args[args.index('--entitlements') + 1]).read_bytes())
    elif '--verify' in args:
        if failure == 'verify-' + role: sys.exit(1)
    elif '--entitlements' in args:
        entitlements = plistlib.loads((state / (role + '-entitlements.plist')).read_bytes())
        if failure == 'hidden-entitlement' and role == 'watch' and 'arm64_32' in args:
            entitlements['unapproved-capability'] = True
        sys.stdout.buffer.write(plistlib.dumps(entitlements))
    elif any(arg.startswith('--extract-certificates=') for arg in args):
        prefix = next(arg.split('=', 1)[1] for arg in args if arg.startswith('--extract-certificates='))
        Path(prefix + '0').write_bytes(b'wrong certificate' if failure == 'hidden-certificate' and role == 'watch' and 'arm64_32' in args else f.CERTIFICATE)
    else:
        print('Identifier=' + ('other.app' if failure == 'hidden-identifier' and role == 'watch' and 'arm64_32' in args else f.policy.role(role)['id']))
        print('TeamIdentifier=' + f.TEAM)
        print('Authority=Apple Distribution: CI')
elif command == 'xcodebuild':
    assert '-exportArchive' in args and '-project' not in args
    options = Path(args[args.index('-exportOptionsPlist') + 1])
    shutil.copyfile(options, state / 'export-options.plist')
    archive = Path(args[args.index('-archivePath') + 1])
    app = archive / 'Products/Applications/PacePrompt.app'
    destination = Path(args[args.index('-exportPath') + 1]); destination.mkdir()
    with zipfile.ZipFile(destination / 'PacePrompt.ipa', 'w') as bundle:
        for path in app.rglob('*'):
            if path.is_file(): bundle.write(path, 'Payload/PacePrompt.app/' + path.relative_to(app).as_posix())
        if failure == 'extra-app': bundle.writestr('Payload/Extra.app/Extra', f.macho('phone', signed=True))
        # Apple's documented default includes optional symbols; omission must fail closed.
        if plistlib.loads(options.read_bytes()).get('uploadSymbols') is not False or failure == 'extra-symbols':
            bundle.writestr('Symbols/00000000-0000-0000-0000-000000000000.symbols', b'synthetic symbols')
elif command == 'xcrun':
    assert args[:2] == ['altool', '--upload-app']
else:
    raise AssertionError((command, args))
