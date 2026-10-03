"""Synthetic release data only; no executable is launched or credential used."""
import datetime as dt
import hashlib
import plistlib
import struct
from pathlib import Path
from scripts import testflight_policy as policy

TEAM = 'ABCDEFGHIJ'
CERTIFICATE = b'synthetic DER certificate'
FINGERPRINT = hashlib.sha1(CERTIFICATE).hexdigest().upper()
IDENTITIES = f'  1) {FINGERPRINT} "Apple Distribution: CI ({TEAM})"'
ROOT = Path(__file__).resolve().parents[2]


def info(role, version='1.0.1', build='21'):
    b = policy.role(role)
    result = plistlib.loads((ROOT / ('PacePrompt' if role == 'phone' else 'PacePromptWatch') / 'Info.plist').read_bytes())
    result.update(CFBundleIdentifier=b['id'], CFBundleExecutable=b['executable'],
                  CFBundlePackageType='APPL', CFBundleShortVersionString=version,
                  CFBundleVersion=build, DTPlatformName=b['platform'],
                  CFBundleSupportedPlatforms=b['supported'], UIDeviceFamily=b['family'],
                  MinimumOSVersion=b['minimum'], ITSAppUsesNonExemptEncryption=False)
    if role == "phone":
        result.update(NSHealthShareUsageDescription=policy.PHONE_READ, NSHealthUpdateUsageDescription=policy.PHONE_WRITE, NSBluetoothAlwaysUsageDescription=policy.BLUETOOTH)
    return result


def macho(role, signed=False, platform=None, cpu=None):
    b = policy.role(role)
    cpu = cpu if cpu is not None else (0x100000c if role == 'phone' else 0x200000c)
    commands = struct.pack('<6I', 0x32, 24, platform or b['macho_platform'], 0, 0, 0)
    if signed:
        commands += struct.pack('<4I', 0x1d, 16, 72, 4)
    return struct.pack('<8I', 0xfeedfacf, cpu, 1 if cpu == 0x200000c else 0, 2, 2 if signed else 1, len(commands), 0, 0) + commands + (b'SIGN' if signed else b'')


def fat_watch(signed=False, second_platform=4):
    slices = [macho('watch', signed, cpu=0x100000c), macho('watch', signed, platform=second_platform)]
    offsets = [48, 48 + len(slices[0])]
    return struct.pack('>2I', 0xcafebabe, 2) + b''.join(
        struct.pack('>5I', cpu, 1 if cpu == 0x200000c else 0, offset, len(data), 2)
        for cpu, offset, data in zip([0x100000c, 0x200000c], offsets, slices)) + b''.join(slices)


def entitlements(role):
    app_id = TEAM + '.' + policy.role(role)['id']
    return {'application-identifier': app_id, 'com.apple.developer.team-identifier': TEAM,
            'com.apple.developer.healthkit': True, 'get-task-allow': False,
            'beta-reports-active': True, 'keychain-access-groups': [app_id]}


def profile(role):
    return {'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM], 'Platform': ['iOS', 'xrOS', 'visionOS'],
            'UUID': ('12345678' if role == 'phone' else '87654321') + '-1234-1234-1234-123456789abc',
            'Name': 'Synthetic ' + role, 'ExpirationDate': dt.datetime(2099, 1, 1),
            'DeveloperCertificates': [CERTIFICATE], 'Entitlements': entitlements(role)}


def app_tree(app, version='1.0.1', build='21', signed=False):
    for role, b in policy.BUNDLES.items():
        bundle = app / b['path']; bundle.mkdir(parents=True, exist_ok=True)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps(info(role, version, build)))
        (bundle / b['executable']).write_bytes(macho(role, signed))
        source = ROOT / ('PacePrompt' if role == 'phone' else 'PacePromptWatch') / 'PrivacyInfo.xcprivacy'
        (bundle / 'PrivacyInfo.xcprivacy').write_bytes(source.read_bytes())
        if signed:
            (bundle / 'embedded.mobileprovision').write_bytes(plistlib.dumps(profile(role)))
