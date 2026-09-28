#!/usr/bin/env python3
"""Closed two-bundle release policy, independent of credentials and subprocesses."""
import struct
from pathlib import Path

PHONE_ID = 'com.otherweather.PromptPace'
WATCH_ID = PHONE_ID + '.watchkitapp'
BUNDLES = {
    'phone': {'path': '.', 'id': PHONE_ID, 'executable': 'PacePrompt', 'platform': 'iphoneos',
              'supported': ['iPhoneOS'], 'family': [1], 'minimum': '17.0', 'macho_platform': 2,
              'cpus': {0x100000c}},
    'watch': {'path': 'Watch/PacePromptWatch.app', 'id': WATCH_ID, 'executable': 'PacePromptWatch',
              'platform': 'watchos', 'supported': ['WatchOS'], 'family': [4], 'minimum': '10.0',
              'macho_platform': 4, 'cpus': {0x100000c, 0x200000c}},
}
PHONE_READ = 'PacePrompt on iPhone does not read Apple Health data. It saves iPhone-only workouts when you choose Save to Apple Health. Apple Watch separately records Watch-assisted workouts.'
PHONE_WRITE = 'PacePrompt saves a completed indoor workout and optional treadmill distance to Apple Health only when you choose Save to Apple Health.'
WATCH_READ = 'PacePrompt uses available heart rate and HealthKit-calculated active energy during your Apple Watch workout. Sensor values stay in HealthKit and are not copied to iPhone History.'
WATCH_WRITE = 'PacePrompt saves one Apple Watch workout with execution intervals, available active energy and optional treadmill distance. Workouts without usable execution intervals are discarded.'
BLUETOOTH = 'PacePrompt uses Bluetooth to connect to your treadmill and request speed and inclination targets during a workout you begin at its physical console.'
MAGICS = {bytes.fromhex(s) for s in ['feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca']}


def role(name):
    if name not in BUNDLES:
        raise ValueError('Unknown signing role')
    return BUNDLES[name]


def metadata(info, version, build, name):
    b = role(name)
    expected = {'CFBundleIdentifier': b['id'], 'CFBundleExecutable': b['executable'],
                'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version,
                'CFBundleVersion': build, 'DTPlatformName': b['platform'],
                'CFBundleSupportedPlatforms': b['supported'], 'UIDeviceFamily': b['family'],
                'MinimumOSVersion': b['minimum'], 'ITSAppUsesNonExemptEncryption': False,
                'NSHealthShareUsageDescription': PHONE_READ if name == 'phone' else WATCH_READ,
                'NSHealthUpdateUsageDescription': PHONE_WRITE if name == 'phone' else WATCH_WRITE}
    if name == 'watch':
        expected.update(WKApplication=True, WKCompanionAppBundleIdentifier=PHONE_ID,
                        WKBackgroundModes=['workout-processing'])
    else:
        expected.update(NSBluetoothAlwaysUsageDescription=BLUETOOTH, UIBackgroundModes=['bluetooth-central'])
    for key, value in expected.items():
        if type(info.get(key)) is not type(value) or info[key] != value:
            raise ValueError(f'{name}: unexpected or missing {key}')
    if any(key in info for key in ['NSExtension', 'WKWatchKitApp', 'WKAppBundleIdentifier']):
        raise ValueError('Unsupported extension/legacy Watch topology')
    if name == 'watch' and ('NSBluetoothAlwaysUsageDescription' in info or 'UIBackgroundModes' in info):
        raise ValueError('Unexpected Watch capability declaration')


def macho(data, name, signed=False):
    """Inspect every bounded Mach-O slice; never execute candidate code."""
    b = role(name)
    def u32(offset, endian='<'):
        if offset < 0 or offset + 4 > len(data):
            raise ValueError('Truncated Mach-O')
        return struct.unpack_from(endian + 'I', data, offset)[0]
    magic = data[:4]
    if magic in (bytes.fromhex('cafebabe'), bytes.fromhex('cafebabf')):
        wide = magic == bytes.fromhex('cafebabf'); count = u32(4, '>'); width = 32 if wide else 20
        if not 1 <= count <= 2 or 8 + count * width > len(data):
            raise ValueError('Invalid fat Mach-O slice count')
        slices = []
        boundary = 8 + count * width
        for i in range(count):
            pos = 8 + i * width
            if wide:
                cpu, subtype, offset, size, align, reserved = struct.unpack_from('>IIQQII', data, pos)
                if reserved: raise ValueError('Invalid fat Mach-O reserved value')
            else:
                cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', data, pos)
            if align > 20 or offset < boundary or offset % (1 << align) or size < 28 or offset + size > len(data):
                raise ValueError('Invalid fat Mach-O slice bounds')
            slices.append((offset, size, cpu, subtype))
        ordered = sorted(slices)
        if any(a[0] + a[1] > z[0] for a, z in zip(ordered, ordered[1:])):
            raise ValueError('Overlapping Mach-O slices')
    else:
        slices = [(0, len(data), None, None)]
    cpus = set()
    for offset, size, outer_cpu, outer_subtype in slices:
        header_magic = data[offset:offset+4]
        if header_magic not in (bytes.fromhex('cffaedfe'), bytes.fromhex('cefaedfe')):
            raise ValueError('Unsupported Mach-O executable header')
        header = 32 if header_magic == bytes.fromhex('cffaedfe') else 28
        if size < header: raise ValueError('Truncated Mach-O header')
        cpu, subtype, filetype, count, commands = [u32(offset + n) for n in (4, 8, 12, 16, 20)]
        if (cpu not in b['cpus'] or cpu in cpus or filetype != 2
                or subtype != (1 if cpu == 0x200000c else 0)):
            raise ValueError('Unexpected architecture, duplicate slice or non-executable Mach-O')
        if outer_cpu is not None and (cpu, subtype) != (outer_cpu, outer_subtype):
            raise ValueError('Fat/thin Mach-O identity mismatch')
        cpus.add(cpu)
        end = offset + header + commands; cursor = offset + header
        if not 1 <= count <= 4096 or end > offset + size:
            raise ValueError('Invalid Mach-O load-command bounds')
        platforms = []; signatures = 0
        for _ in range(count):
            if cursor + 8 > end: raise ValueError('Truncated Mach-O load command')
            command, length = u32(cursor), u32(cursor+4)
            if length < 8 or length % 4 or cursor + length > end:
                raise ValueError('Invalid Mach-O load command')
            if command == 0x32:  # LC_BUILD_VERSION
                if length < 24: raise ValueError('Truncated build-version command')
                platforms.append(u32(cursor+8))
            if command == 0x1d:  # LC_CODE_SIGNATURE
                if not signed: raise ValueError('Unsigned executable contains a signature command')
                if length != 16: raise ValueError('Invalid signature command')
                start, length_of_signature = u32(cursor+8), u32(cursor+12)
                if start < header + commands or not length_of_signature or start + length_of_signature > size:
                    raise ValueError('Invalid signature bounds')
                signatures += 1
            cursor += length
        if cursor != end or platforms != [b['macho_platform']] or (signed and signatures != 1):
            raise ValueError('Unexpected device platform or signature state')
    if name == 'watch' and 0x200000c not in cpus:
        raise ValueError('Watch archive lacks its watchOS 10-compatible arm64_32 slice')
    return cpus


def app_graph(app: Path, signed=False):
    """Closed topology, including disguised executable content and filesystem aliases."""
    bundles = {name: app / b['path'] for name, b in BUNDLES.items()}
    executables = {path / BUNDLES[name]['executable'] for name, path in bundles.items()}
    profiles = {path / 'embedded.mobileprovision' for path in bundles.values()}
    signatures = {path / '_CodeSignature' for path in bundles.values()}
    if app.is_symlink() or not all(p.is_dir() and not p.is_symlink() for p in bundles.values()):
        raise ValueError('Missing or linked required app bundle')
    seen = set()
    for path in app.rglob('*'):
        relative = path.relative_to(app); text = relative.as_posix()
        if text.casefold() in seen or path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('Duplicate, linked or special app content')
        seen.add(text.casefold())
        if path.name == '_CodeSignature' and (not signed or path not in signatures):
            raise ValueError('Unexpected signature content')
        if path.name == 'embedded.mobileprovision' and (not signed or path not in profiles):
            raise ValueError('Unexpected provisioning content')
        for i, part in enumerate(relative.parts):
            if part.lower().endswith(('.app','.appex','.framework','.dylib','.xpc','.bundle')):
                ancestor = app.joinpath(*relative.parts[:i+1])
                if ancestor != bundles['watch']:
                    raise ValueError('Unsupported nested code container')
        if path.is_file():
            with path.open('rb') as stream: magic = stream.read(4)
            if magic in MAGICS and path not in executables:
                raise ValueError('Unexpected executable resource')
    if not all(p.is_file() for p in executables): raise ValueError('Missing executable')
    if signed and not all(p.is_file() for p in profiles): raise ValueError('Missing distribution profile')
    return bundles
