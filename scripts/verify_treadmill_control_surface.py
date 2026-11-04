#!/usr/bin/env python3
"""Check the closed treadmill command surface in production sources.

Production may write to the treadmill from exactly one reviewed CoreBluetooth
edge, must not route an FTMS Start, Stop or Pause command, and must not opt into
CoreBluetooth state restoration. Both the hosted fast checks and
scripts/validate_local.sh run this, so a change to the shape of the code that
talks to the treadmill fails the build rather than relying on review.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRITE_EDGE = 'PacePrompt/Bluetooth/CoreBluetoothFTMSControlPointLink.swift'
COMMAND_ROUTE_FILES = (
    'PacePrompt/Bluetooth/FTMSControlPointCodec.swift',
    'PacePrompt/Bluetooth/FTMSControlPointTransport.swift',
    'PacePrompt/Execution/ProductionWorkoutExecutionBinding.swift',
)
WRITE_CALL = re.compile(r'\.writeValue\(')
START_STOP_ROUTE = re.compile(r'case (?:start|stop|pause)$|case \.(?:start|stop|pause)|submit\(\.(?:start|stop|pause)', re.M)
STATE_RESTORATION = re.compile(r'CBCentralManagerOptionRestoreIdentifierKey|willRestoreState')


def _production_sources(root):
    return sorted((root / 'PacePrompt').rglob('*.swift'))


def violations(root=ROOT):
    """Return a list of human-readable violations; empty means the surface is closed."""
    found = []
    write_sites = []
    for path in _production_sources(root):
        relative = path.relative_to(root).as_posix()
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if WRITE_CALL.search(line):
                write_sites.append(f'{relative}:{number}')
            if STATE_RESTORATION.search(line):
                found.append(f'{relative}:{number}: production must not opt into CoreBluetooth state restoration')
    if len(write_sites) != 1 or not write_sites[0].startswith(WRITE_EDGE + ':'):
        found.append('production must contain exactly one reviewed CoreBluetooth write edge in '
                     f'{WRITE_EDGE}; found {write_sites or "none"}')
    for relative in COMMAND_ROUTE_FILES:
        path = root / relative
        if not path.is_file():
            found.append(f'{relative}: expected command-route file is missing')
            continue
        for match in START_STOP_ROUTE.finditer(path.read_text()):
            number = path.read_text().count('\n', 0, match.start()) + 1
            found.append(f'{relative}:{number}: production unexpectedly contains an FTMS Start, Stop or Pause route')
    return found


def main():
    found = violations()
    for item in found:
        print(item, file=sys.stderr)
    if found:
        return 1
    print('Treadmill command surface is closed: one write edge, no Start/Stop/Pause route, no state restoration')
    return 0


if __name__ == '__main__':
    sys.exit(main())
