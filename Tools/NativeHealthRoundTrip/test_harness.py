import argparse
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import harness


class HarnessTests(unittest.TestCase):
    def test_evidence_is_immutable_and_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); file = root / 'receipt'
            harness.retain(file, b'original'); harness.retain(file, b'original')
            with self.assertRaises(ValueError): harness.retain(file, b'changed')
            self.assertEqual(file.read_bytes(), b'original')
            link = root / 'link'; link.symlink_to(file)
            with self.assertRaises(ValueError): harness.retain(link, b'original')

    def test_invalid_prepare_never_invokes_git_or_simulator(self):
        with patch.object(harness, 'command') as command, patch.object(harness, 'sim') as sim:
            for output, ref in [('/Users/unsafe-output', 'a' * 40), ('/private/tmp/unused-probe', 'main')]:
                with self.assertRaises(ValueError):
                    harness.prepare(argparse.Namespace(output=output, ref=ref, repo='.', writer_api='v3'))
            command.assert_not_called(); sim.assert_not_called()

    def test_prepare_copies_complete_files_and_seals_exact_new_device_guards(self):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as tmp:
            root = Path(tmp) / 'proof'
            ref = 'a' * 40
            phone = '00000000-0000-4000-8000-000000000001'
            watch = '00000000-0000-4000-8000-000000000002'
            pair = '00000000-0000-4000-8000-000000000003'
            def git(args, **_):
                if args[1] == 'rev-parse': return (ref + '\n').encode()
                return ('// whole file\n' + args[-1] + '\n// final line\n').encode()
            with patch.object(harness, 'command', side_effect=git), patch.object(harness, 'sim', side_effect=[phone, watch, pair]) as sim:
                harness.prepare(argparse.Namespace(output=str(root), ref=ref, repo='.', writer_api='v3'))
            self.assertEqual([call.args[0] for call in sim.call_args_list], ['create', 'create', 'pair'])
            evidence = json.loads((root / 'evidence.json').read_text())
            harness.verify(root, evidence)
            self.assertIn(watch, (root / 'Probe.swift').read_text())
            self.assertIn(phone, (root / 'Companion.swift').read_text())
            for path in harness.SOURCES:
                self.assertEqual((root / 'Production' / Path(path).name).read_bytes(), git(['git', 'show', ref + ':' + path]))
            project = json.loads((root / 'project.json').read_text())
            self.assertEqual(project['targets']['NativeProducerProbe']['sources'], ['Production', 'Probe.swift'])
            self.assertEqual(project['targets']['SyntheticCompanion']['sources'], ['Companion.swift'])
            extra = root / 'Production/unreviewed.swift'; extra.write_text('unexpected')
            with self.assertRaises(ValueError): harness.verify(root, evidence)
            extra.unlink()
            (root / 'Probe.swift').write_text('guard removed')
            with self.assertRaises(ValueError): harness.verify(root, evidence)

    def test_device_or_pair_drift_is_rejected(self):
        evidence = {'phone': {'udid': 'p', 'name': 'fresh phone'}, 'watch': {'udid': 'w', 'name': 'fresh watch'}, 'pair': 'pair'}
        devices = {'devices': {harness.PHONE_RUNTIME: [{'udid': 'p', 'name': 'fresh phone', 'deviceTypeIdentifier': harness.PHONE_TYPE}],
                               harness.WATCH_RUNTIME: [{'udid': 'w', 'name': 'fresh watch', 'deviceTypeIdentifier': harness.WATCH_TYPE}]}}
        pairs = {'pairs': {'pair': {'phone': {'udid': 'p'}, 'watch': {'udid': 'w'}}}}
        with patch.object(harness, 'sim', side_effect=[json.dumps(devices), json.dumps(pairs)]):
            self.assertEqual(set(harness.verify_devices(evidence)), {'phone', 'watch'})
        pairs['pairs']['pair']['phone']['udid'] = 'someone-else'
        with patch.object(harness, 'sim', side_effect=[json.dumps(devices), json.dumps(pairs)]):
            with self.assertRaises(ValueError): harness.verify_devices(evidence)
        devices['devices'][harness.PHONE_RUNTIME][0]['name'] = 'existing personal simulator'
        with patch.object(harness, 'sim', return_value=json.dumps(devices)):
            with self.assertRaises(ValueError): harness.verify_devices(evidence)

    def test_unresolved_attempt_and_duplicate_save_never_terminate_or_launch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'outputs').mkdir()
            evidence = {'writerAPI': 'v3', 'stage': 'installed', 'artifactHashes': {}}
            with patch.object(harness, 'collect', return_value='request synthetic workout read permission'), patch.object(harness, 'sim') as sim, patch.object(harness.subprocess, 'run') as command:
                with self.assertRaises(ValueError): harness.run_case(root, evidence, 'v3-paused')
                sim.assert_not_called(); command.assert_not_called()
            (root / 'outputs/v3-paused.receipt.json').write_text('{}')
            with patch.object(harness, 'collect', return_value='SUCCESS: saved/query/archive activities=2'), patch.object(harness, 'sim') as sim, patch.object(harness.subprocess, 'run') as command:
                with self.assertRaises(ValueError): harness.run_case(root, evidence, 'v3-paused')
                sim.assert_not_called(); command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
