"""Execute the real release shell with synthetic data and all Apple tools stubbed."""
import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from scripts.tests import release_fixtures as f


@unittest.skipUnless(sys.platform == 'darwin', 'release shell uses macOS base64')
class ReleaseOrchestrationTests(unittest.TestCase):
    def run_release(self, failure=''):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        root = Path(temporary.name); binaries = root / 'bin'; binaries.mkdir()
        stub = (f.ROOT / 'scripts/tests/release_tool_stub.py').read_text()
        for command in ('python3', 'security', 'openssl', 'codesign', 'xcodebuild', 'xcrun'):
            path = binaries / command; path.write_text('#!' + sys.executable + '\n' + stub); path.chmod(0o755)
        archive = root / 'verified/PromptPace.xcarchive'
        f.app_tree(archive / 'Products/Applications/PacePrompt.app')
        (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {}}))
        encode = lambda data: base64.b64encode(data).decode()
        env = {**os.environ, 'HOME': str(root / 'home'), 'RUNNER_TEMP': str(root),
               'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
               'MOCK_REPO': str(f.ROOT), 'MOCK_STATE': str(root), 'MOCK_FAIL': failure,
               'TRUSTED_TOOLS_ROOT': str(f.ROOT), 'PACEPROMPT_RELEASE_SOURCE_ROOT': str(f.ROOT),
               'RELEASE_TOOLS_SHA': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=f.ROOT, text=True).strip(),
               'ASC_KEY_ID': 'SYNTHETIC0', 'ASC_ISSUER_ID': 'synthetic', 'ASC_TEAM_ID': f.TEAM,
               'ASC_API_KEY_P8_B64': encode(b'synthetic'), 'DIST_P12_B64': encode(b'synthetic'),
               'DIST_P12_PASSWORD': 'synthetic',
               'DIST_PROFILE_B64': encode(plistlib.dumps(f.profile('phone'))),
               'DIST_WATCH_PROFILE_B64': encode(plistlib.dumps(f.profile('watch'))),
               'RELEASE_TAG': 'testflight/1.0.1-b16', 'RELEASE_SHA': 'a' * 40,
               'GITHUB_STEP_SUMMARY': str(root / 'summary')}
        if failure == 'swapped-profile': env['DIST_WATCH_PROFILE_B64'] = env['DIST_PROFILE_B64']
        result = subprocess.run(['/bin/bash', str(f.ROOT / 'scripts/testflight_release.sh')],
                                env=env, text=True, capture_output=True, timeout=45)
        calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
        self.assertFalse((root / 'testflight').exists(), 'temporary signing files must be removed')
        self.assertFalse(list((root / 'home').rglob('*.mobileprovision')), 'installed profiles must be removed')
        self.assertFalse(list((root / 'home').rglob('*.p8')), 'API key must be removed')
        return result, calls, root

    def test_inside_out_signing_explicit_map_and_single_upload_after_both_verifications(self):
        result, calls, root = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        signs = [call for call in calls if call[0] == 'codesign' and '--force' in call]
        self.assertEqual(len(signs), 2)
        self.assertTrue(signs[0][-1].endswith('/Watch/PacePromptWatch.app'))
        self.assertTrue(signs[1][-1].endswith('/Applications/PacePrompt.app'))
        options = plistlib.loads((root / 'export-options.plist').read_bytes())
        self.assertEqual(options['provisioningProfiles'], {f.policy.role(role)['id']: f.profile(role)['UUID'] for role in ('phone', 'watch')})
        self.assertIs(options['testFlightInternalTestingOnly'], True)
        self.assertIs(options['manageAppVersionAndBuildNumber'], False)
        self.assertIs(options['uploadSymbols'], False)
        uploads = [i for i, call in enumerate(calls) if call[0] == 'xcrun']
        verifies = [i for i, call in enumerate(calls) if call[0] == 'codesign' and '--verify' in call]
        self.assertEqual(len(uploads), 1); self.assertEqual(len(verifies), 2)
        self.assertGreater(uploads[0], max(verifies))
        displays = [call for call in calls if call[0] == 'codesign' and '--verbose=4' in call]
        self.assertEqual([call[call.index('--architecture') + 1] for call in displays], ['arm64', 'arm64_32', 'arm64'])

    def test_each_bundle_failure_blocks_upload_and_signing_failure_blocks_export(self):
        for failure in ('sign-watch', 'sign-phone', 'verify-watch', 'verify-phone', 'swapped-profile',
                        'hidden-entitlement', 'hidden-certificate', 'hidden-identifier', 'extra-app', 'extra-symbols'):
            with self.subTest(failure=failure):
                result, calls, _ = self.run_release(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(call[0] == 'xcrun' for call in calls))
                if failure.startswith('sign-') or failure == 'swapped-profile':
                    self.assertFalse(any(call[0] == 'xcodebuild' for call in calls))
