"""The treadmill command-surface check fails on each change it exists to catch."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('verify_treadmill_control_surface',
                                              ROOT / 'scripts/verify_treadmill_control_surface.py')
assert SPEC is not None and SPEC.loader is not None
surface = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(surface)


class TreadmillControlSurfaceTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        for relative in (surface.WRITE_EDGE, *surface.COMMAND_ROUTE_FILES):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    def append(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a') as handle:
            handle.write(text)

    def test_checked_in_sources_are_closed(self):
        self.assertEqual(surface.violations(ROOT), [])

    def test_reviewed_copy_is_closed(self):
        self.assertEqual(surface.violations(self.root), [])

    def test_second_write_edge_fails(self):
        self.append('PacePrompt/Bluetooth/Shortcut.swift', 'peripheral.writeValue(data, for: c, type: .withResponse)\n')
        self.assertTrue(any('exactly one reviewed CoreBluetooth write edge' in v for v in surface.violations(self.root)))

    def test_missing_write_edge_fails(self):
        (self.root / surface.WRITE_EDGE).write_text('// no write\n')
        self.assertTrue(any('found none' in v for v in surface.violations(self.root)))

    def test_start_stop_or_pause_route_fails(self):
        for route in ('case start', 'case .stop:', 'submit(.pause)'):
            with self.subTest(route=route):
                self.setUp()
                self.append(surface.COMMAND_ROUTE_FILES[0], f'\n{route}\n')
                self.assertTrue(any('Start, Stop or Pause' in v for v in surface.violations(self.root)))

    def test_state_restoration_fails(self):
        self.append('PacePrompt/Bluetooth/Restore.swift', 'let k = CBCentralManagerOptionRestoreIdentifierKey\n')
        self.assertTrue(any('state restoration' in v for v in surface.violations(self.root)))


if __name__ == '__main__':
    unittest.main()
