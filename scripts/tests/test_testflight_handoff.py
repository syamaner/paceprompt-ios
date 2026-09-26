"""Contract tests for the hostile-input boundary before release credentials."""
import json
import plistlib
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from scripts import testflight_handoff as handoff
from scripts import testflight_signing as signing


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / handoff.ARCHIVE
        self.app = self.archive / 'Products/Applications/PacePrompt.app'
        self.app.mkdir(parents=True)
        self.context = handoff.identity('a' * 40, 'testflight/1.0-b1', '123', '1')
        info = {'CFBundleIdentifier': 'com.otherweather.PromptPace',
                'CFBundleExecutable': 'PacePrompt', 'CFBundlePackageType': 'APPL',
                'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
                'DTPlatformName': 'iphoneos', 'CFBundleSupportedPlatforms': ['iPhoneOS']}
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (self.app / 'PacePrompt').write_bytes(b'synthetic executable; never launched')
        (self.archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ArchiveVersion': 2, 'ApplicationProperties': {
                'ApplicationPath': 'Applications/PacePrompt.app',
                'CFBundleIdentifier': 'com.otherweather.PromptPace',
                'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1'}}))
        self.package = self.root / 'handoff.zip'
        self.destination = self.root / 'verified'

    def pack(self):
        return handoff.pack(self.archive, self.package, self.context)

    def unpack(self, digest, context=None):
        return handoff.unpack(self.package, self.destination, context or self.context, digest)

    def test_round_trip_preserves_bytes_and_restores_only_executable_permission(self):
        result = self.unpack(self.pack())
        for path in self.archive.rglob('*'):
            if path.is_file():
                self.assertEqual(path.read_bytes(), (result / path.relative_to(self.archive)).read_bytes())
        executable = result / 'Products/Applications/PacePrompt.app/PacePrompt'
        self.assertEqual(executable.stat().st_mode & 0o777, 0o755)
        self.assertEqual((executable.parent / 'Info.plist').stat().st_mode & 0o777, 0o644)

    def test_digest_mismatch_writes_nothing(self):
        self.pack()
        with self.assertRaisesRegex(ValueError, 'digest'):
            self.unpack('b' * 64)
        self.assertFalse(self.destination.exists())

    def test_other_source_tag_run_or_attempt_is_rejected(self):
        digest = self.pack()
        for field, value in [('source_sha', 'b' * 40), ('tag', 'testflight/1.0-b2'),
                             ('run_id', '456'), ('run_attempt', '2'), ('schema', 2)]:
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'another'):
                self.unpack(digest, {**self.context, field: value})
        self.assertFalse(self.destination.exists())

    def test_repeated_attempt_or_non_sha_identity_is_rejected(self):
        for sha, tag, run, attempt in [('main', 'testflight/1.0-b1', '123', '1'),
                                       ('a' * 40, 'testflight/../../x', '123', '1'),
                                       ('a' * 40, 'testflight/1.0-b1', '123', '2')]:
            with self.assertRaises(ValueError):
                handoff.identity(sha, tag, run, attempt)

    def append(self, name, content=b'unsafe', mode=stat.S_IFREG | 0o600):
        entry = zipfile.ZipInfo(name)
        entry.create_system = 3
        entry.external_attr = mode << 16
        with zipfile.ZipFile(self.package, 'a') as bundle:
            bundle.writestr(entry, content)
        return handoff.digest_file(self.package)

    def test_traversal_case_collision_and_unexpected_content_are_rejected_before_writes(self):
        for name in ['../outside', '/absolute', handoff.APP + '/../outside',
                     handoff.APP + '/info.plist', handoff.ARCHIVE + '/scripts/attack.sh',
                     handoff.APP + '//extra', handoff.APP + '/./extra']:
            with self.subTest(name=name):
                self.pack()
                digest = self.append(name)
                with self.assertRaises(ValueError):
                    self.unpack(digest)
                self.assertFalse(self.destination.exists())

    def test_symlink_special_file_and_directory_entries_are_rejected(self):
        for mode in [stat.S_IFLNK | 0o777, stat.S_IFIFO | 0o600, stat.S_IFDIR | 0o700]:
            with self.subTest(mode=mode):
                self.pack()
                digest = self.append(handoff.APP + '/link', b'../../outside', mode)
                with self.assertRaisesRegex(ValueError, 'non-regular'):
                    self.unpack(digest)
                self.assertFalse(self.destination.exists())

    def test_duplicate_manifest_and_oversized_manifest_are_rejected(self):
        for body in [json.dumps(self.context).encode(), b'x' * 4097]:
            self.pack()
            with self.assertWarns(UserWarning):
                digest = self.append('handoff.json', body)
            with self.assertRaisesRegex(ValueError, 'metadata'):
                self.unpack(digest)

    def test_resource_bounds_are_enforced_before_extraction(self):
        digest = self.pack()
        for limit in ['MAX_FILES', 'MAX_FILE', 'MAX_TOTAL']:
            with self.subTest(limit=limit), patch.object(handoff, limit, 1):
                with self.assertRaises(ValueError):
                    self.unpack(digest)
                self.assertFalse(self.destination.exists())

    def test_partial_extraction_failure_is_cleaned_up(self):
        digest = self.pack()
        with patch.object(handoff.shutil, 'copyfileobj', side_effect=OSError('synthetic failure')):
            with self.assertRaises(OSError):
                self.unpack(digest)
        self.assertFalse(self.destination.exists())

    def test_existing_destination_is_not_overwritten(self):
        digest = self.pack()
        self.destination.mkdir()
        sentinel = self.destination / 'sentinel'
        sentinel.write_text('preserve')
        with self.assertRaises(FileExistsError):
            self.unpack(digest)
        self.assertEqual(sentinel.read_text(), 'preserve')

    def test_pack_rejects_links_nested_code_profiles_and_wrong_platform(self):
        for name in ['embedded.mobileprovision', '_CodeSignature', 'Nested.appex',
                     'Frameworks/Evil.framework/Evil', 'libEvil.dylib']:
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'not permitted')
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.pack()
            path.unlink()
        link = self.app / 'link'
        link.symlink_to('/private/tmp')
        with self.assertRaises(ValueError):
            self.pack()
        link.unlink()
        info = plistlib.loads((self.app / 'Info.plist').read_bytes())
        info['DTPlatformName'] = 'iphonesimulator'
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'platform'):
            self.pack()

    def test_signing_entitlements_are_fixed_and_must_be_granted_by_profile(self):
        team = 'ABCDEFGHIJ'
        desired = {'application-identifier': f'{team}.{signing.BUNDLE_ID}',
                   'com.apple.developer.team-identifier': team,
                   'com.apple.developer.healthkit': True, 'get-task-allow': False,
                   'beta-reports-active': True,
                   'keychain-access-groups': [f'{team}.{signing.BUNDLE_ID}']}
        profile = {'Entitlements': {**desired, 'keychain-access-groups': [f'{team}.*'],
                                    'unrequested-capability': True}}
        self.assertEqual(signing.distribution_entitlements(profile, team), desired)
        for key in desired:
            granted = dict(profile['Entitlements'])
            del granted[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                signing.distribution_entitlements({'Entitlements': granted}, team)


if __name__ == '__main__':
    unittest.main()
