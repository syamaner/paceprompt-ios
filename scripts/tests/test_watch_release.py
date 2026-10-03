"""Hostile two-bundle policy tests: synthetic bytes, never Apple credentials."""
import datetime as dt
import plistlib
import shutil
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from scripts import testflight_policy as policy, testflight_guard as guard, testflight_signing as signing
from scripts.tests import release_fixtures as f


class WatchReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name) / 'PacePrompt.app'
        f.app_tree(self.app)
        self.watch = self.app / policy.role('watch')['path']

    def test_unsigned_pair_and_each_macho_slice(self):
        guard.unsigned(self.app, 'testflight/1.0.1-b22')
        for signed in (False, True):
            self.assertEqual(policy.macho(f.fat_watch(signed), 'watch', signed), {0x100000c, 0x200000c})
            with self.assertRaisesRegex(ValueError, 'platform'):
                policy.macho(f.fat_watch(signed, second_platform=9), 'watch', signed)
        for role, platform, cpu in [('phone', 7, 0x100000c), ('watch', 9, 0x200000c),
                                    ('phone', 2, 0x1000007), ('watch', 4, 0x100000c)]:
            with self.subTest(role=role, platform=platform, cpu=cpu), self.assertRaises(ValueError):
                policy.macho(f.macho(role, platform=platform, cpu=cpu), role)

    def test_unsigned_rejects_signatures_and_malformed_macho(self):
        for role in policy.BUNDLES:
            with self.assertRaisesRegex(ValueError, 'signature'):
                policy.macho(f.macho(role, signed=True), role)
            with self.assertRaisesRegex(ValueError, 'signature'):
                policy.macho(f.macho(role), role, signed=True)
        valid = f.fat_watch()
        hostile = [b'', valid[:7], valid[:-1], f.macho('phone')[:31],
                   valid[:8] + struct.pack('>I', 0x1000007) + valid[12:],
                   valid[:16] + struct.pack('>I', 0) + valid[20:],
                   valid[:24] + struct.pack('>I', 31) + valid[28:]]
        for data in hostile:
            with self.subTest(data=data[:24]), self.assertRaises(ValueError):
                policy.macho(data, 'watch')

    def test_missing_watch_unknown_bundles_and_disguised_code(self):
        shutil.rmtree(self.watch)
        with self.assertRaisesRegex(ValueError, 'Missing'): policy.app_graph(self.app)
        f.app_tree(self.app)
        for name, data in [('Watch/Extra.app/Info.plist', b'x'),
                           ('Watch/PacePromptWatch.app/Plugins/Evil.appex/Info.plist', b'x'),
                           ('innocent.dat', f.macho('phone')),
                           ('Watch/PacePromptWatch.app/picture.png', f.macho('watch'))]:
            path = self.app / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with self.subTest(name=name), self.assertRaises(ValueError): policy.app_graph(self.app)
            path.unlink()
            while path.parent != self.app and path.parent != self.watch and not any(path.parent.iterdir()):
                path = path.parent; path.rmdir()

    def test_companion_version_privacy_and_post_unpack_tamper(self):
        for role in policy.BUNDLES:
            bundle = self.app / policy.role(role)['path']
            path = bundle / 'Info.plist'; original = path.read_bytes(); info = plistlib.loads(original)
            changes = {'CFBundleVersion': '99', 'CFBundleIdentifier': 'other', 'NSHealthShareUsageDescription': 'changed'}
            if role == 'watch': changes['WKCompanionAppBundleIdentifier'] = 'other'
            for key, value in changes.items():
                path.write_bytes(plistlib.dumps({**info, key: value}))
                with self.subTest(role=role, key=key), self.assertRaises(ValueError):
                    guard.unsigned(self.app, 'testflight/1.0.1-b22')
            path.write_bytes(original)
            privacy = bundle / 'PrivacyInfo.xcprivacy'; original_privacy = privacy.read_bytes()
            privacy.write_bytes(plistlib.dumps({'NSPrivacyTracking': True}))
            with self.assertRaisesRegex(ValueError, 'privacy'): guard.unsigned(self.app, 'testflight/1.0.1-b22')
            privacy.write_bytes(original_privacy)
        (self.watch / 'PacePromptWatch').write_bytes(f.macho('watch', platform=9))
        with self.assertRaisesRegex(ValueError, 'platform'): guard.unsigned(self.app, 'testflight/1.0.1-b22')

    def test_profiles_are_role_bound_and_entitlements_fixed(self):
        for role in policy.BUNDLES:
            profile = f.profile(role)
            signing.validate(profile, f.IDENTITIES, f.TEAM, role=role)
            self.assertEqual(signing.distribution_entitlements(profile, f.TEAM, role), f.entitlements(role))
            for changed in [f.profile('watch' if role == 'phone' else 'phone'),
                            {**profile, 'ExpirationDate': dt.datetime(2000, 1, 1)},
                            {**profile, 'DeveloperCertificates': [b'wrong']},
                            {**profile, 'Platform': ['macOS']},
                            {**profile, 'ProvisionsAllDevices': None}]:
                with self.subTest(role=role, profile=changed), self.assertRaises(ValueError):
                    signing.validate(changed, f.IDENTITIES, f.TEAM, role=role)
        with self.assertRaises(ValueError): signing.distribution_entitlements(f.profile('phone'), f.TEAM, 'arbitrary')

    def test_apple_shared_profile_family_preserves_closed_platform_policy(self):
        for role in policy.BUNDLES:
            profile = f.profile(role)
            accepted = [['iOS'], ['iOS', 'xrOS', 'visionOS']]
            if role == 'watch':
                accepted += [['watchOS'], ['iOS', 'watchOS']]
            for family in accepted:
                with self.subTest(role=role, family=family):
                    signing.validate({**profile, 'Platform': family}, f.IDENTITIES, f.TEAM, role=role)
            for family in (None, [], 'iOS', ['xrOS', 'visionOS'], ['iOS', 'visionOS'],
                           ['visionOS', 'xrOS', 'iOS'], ['iOS', 'iOS'],
                           ['iOS', 'xrOS', 'visionOS', 'macOS']):
                with self.subTest(role=role, family=family), self.assertRaisesRegex(ValueError, 'platform family'):
                    signing.validate({**profile, 'Platform': family}, f.IDENTITIES, f.TEAM, role=role)
        with self.assertRaisesRegex(ValueError, 'platform family'):
            signing.validate({**f.profile('phone'), 'Platform': ['watchOS']}, f.IDENTITIES, f.TEAM)

    def test_shared_profile_family_does_not_authorise_vision_device_code(self):
        for role in policy.BUNDLES:
            signing.validate(f.profile(role), f.IDENTITIES, f.TEAM, role=role)
            for platform in (11, 12):
                for signed in (False, True):
                    with self.subTest(role=role, platform=platform, signed=signed), self.assertRaisesRegex(ValueError, 'platform'):
                        policy.macho(f.macho(role, signed=signed, platform=platform), role, signed)

    def test_watch_project_configurations_must_match_tag(self):
        project = guard.PROJECT.read_text()
        for config in ('02', '03'):
            prefix = 'D115000000000000000007' + config + ' /* '
            start = project.index(prefix, project.index('/* Begin XCBuildConfiguration section */'))
            end = project.index('\n', start)
            altered = project[:start] + project[start:end].replace('CURRENT_PROJECT_VERSION = 22;', 'CURRENT_PROJECT_VERSION = 99;') + project[end:]
            with self.assertRaises(ValueError): guard.check_tag('testflight/1.0.1-b22', altered)

    def test_exported_pair_checks_each_profile_and_exact_entitlements(self):
        f.app_tree(self.app, signed=True)
        def subprocess_output(command, **kwargs):
            bundle = Path(command[-1]); role = 'watch' if 'PacePromptWatch.app' in str(bundle) else 'phone'
            if command[0] == 'security': return plistlib.dumps(profiles[role])
            return f'Identifier={policy.role(role)["id"]}\nTeamIdentifier={f.TEAM}\nAuthority=Apple Distribution: CI\n'
        profiles = {role: f.profile(role) for role in policy.BUNDLES}
        entitlements = {role: f.entitlements(role) for role in policy.BUNDLES}
        with patch.object(guard.subprocess, 'check_output', side_effect=subprocess_output), \
             patch.object(guard.subprocess, 'run') as verify, \
             patch.object(guard, 'verify_signing_leaf') as leaf, \
             patch.object(guard, 'signed_entitlements', side_effect=lambda p, architecture: entitlements['watch' if p == self.watch else 'phone']):
            guard.artifact(self.app, 'testflight/1.0.1-b22', f.TEAM, f.FINGERPRINT)
            self.assertEqual([call.args[0] for call in leaf.call_args_list], [self.watch, self.app])
            self.assertEqual(verify.call_count, 2)
            for role in policy.BUNDLES:
                entitlements[role]['unapproved-capability'] = True
                with self.subTest(role=role), self.assertRaisesRegex(ValueError, 'entitlements'):
                    guard.artifact(self.app, 'testflight/1.0.1-b22', f.TEAM, f.FINGERPRINT)
                del entitlements[role]['unapproved-capability']
                profiles[role]['ExpirationDate'] = dt.datetime(2000, 1, 1)
                with self.assertRaisesRegex(ValueError, 'expired'):
                    guard.artifact(self.app, 'testflight/1.0.1-b22', f.TEAM, f.FINGERPRINT)
                profiles[role] = f.profile(role)

    def test_exported_ipa_paths_types_collisions_and_bounds_fail_before_extraction(self):
        import stat
        import zipfile
        from scripts import testflight_handoff as handoff
        f.app_tree(self.app, signed=True)
        package = self.app.parent / 'export.ipa'
        destination = self.app.parent / 'extracted'
        def pack(extra=None, mode=stat.S_IFREG | 0o644):
            with zipfile.ZipFile(package, 'w') as archive:
                archive.writestr('Payload/', b'')
                for path in self.app.rglob('*'):
                    if path.is_file(): archive.write(path, 'Payload/PacePrompt.app/' + path.relative_to(self.app).as_posix())
                if extra:
                    entry = zipfile.ZipInfo(extra); entry.create_system = 3; entry.external_attr = mode << 16
                    archive.writestr(entry, b'bad')
        pack()
        self.assertEqual(handoff.unpack_ipa(package, destination), destination / 'Payload/PacePrompt.app')
        shutil.rmtree(destination)
        for name, mode in [('Payload/Other.app/code', stat.S_IFREG), ('../escape', stat.S_IFREG),
                           ('SwiftSupport/unreviewed', stat.S_IFREG),
                           ('Symbols/00000000-0000-0000-0000-000000000000.symbols', stat.S_IFREG),
                           ('Payload/PacePrompt.app/info.plist', stat.S_IFREG),
                           ('Payload/PacePrompt.app/link', stat.S_IFLNK),
                           ('Payload/PacePrompt.app/fifo', stat.S_IFIFO)]:
            pack(name, mode)
            with self.subTest(name=name), self.assertRaises(ValueError): handoff.unpack_ipa(package, destination)
            self.assertFalse(destination.exists())
        pack()
        with patch.object(handoff, 'MAX_FILE', 1), self.assertRaises(ValueError): handoff.unpack_ipa(package, destination)
        self.assertFalse(destination.exists())
