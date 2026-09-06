#!/usr/bin/env python3
"""Offline provenance and production-bundle checks. Never reads .env or .runs."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Evaluation/WorkoutImport/HostEval'
RESOURCES = ROOT / 'PacePrompt/Import/ImportResources'
HASHES = {
    'system.md': 'd58800efc4b0e01994a1a5be1a1d644ce52dbb6bb7c12655745dc78b6e355fd3',
    'transport.json': 'd4901b2dc3b1a57654ed5d6f7e96bdce30687062913036f86e616fb2f5a9bba0',
    'examples.json': '0313c531454bae3545ec97118be33232f53b0b62613a2339d8a96dbe21a680fd',
}

def verify():
    for name, expected in HASHES.items():
        assert hashlib.sha256((RESOURCES / name).read_bytes()).hexdigest() == expected, name
    assert (RESOURCES / 'system.md').read_bytes() == (SOURCE / 'prompts/v3/system.md').read_bytes()
    assert (RESOURCES / 'transport.json').read_bytes() == (SOURCE / 'schemas/v2.3/workout-import-provider-transport-v2.3.schema.json').read_bytes()
    cases = {c['id']: c for c in json.loads((SOURCE / 'datasets/v3/development/cases.json').read_text())}
    manifest = json.loads((SOURCE / 'datasets/v3/development/manifest.json').read_text())
    messages = []
    assert len(manifest['fewShotCaseIDs']) == 11
    for identifier in manifest['fewShotCaseIDs']:
        case = cases[identifier]
        outcome = copy.deepcopy(case['expected']['modelOutput'])
        value = outcome['outcome']
        if value['type'] == 'proposal':
            value['proposal'] = {'present': True, **value['proposal']}
            value['reasonCategory'] = 'notApplicable'
            value['affectedPaths'] = []
        else:
            value['proposal'] = {'present': False, 'contractVersion': 'notApplicable', 'suggestedName': '', 'activity': 'notApplicable', 'steps': []}
        capabilities = json.dumps(case['capabilities'], sort_keys=True, separators=(',', ':'))
        messages.extend([
            {'role': 'user', 'content': f"Locale: {case['locale']}\nCapabilities: {capabilities}\nWorkout request:\n{case['prompt']}"},
            {'role': 'assistant', 'content': json.dumps(outcome, ensure_ascii=False, sort_keys=True, separators=(',', ':'))},
        ])
    assert messages == json.loads((RESOURCES / 'examples.json').read_text())
    fixture = json.loads((ROOT / 'docs/import/outbound-request.json').read_text())
    assert fixture['messages'][1:-1] == messages
    assert fixture['messages'][0] == {'role': 'system', 'content': (RESOURCES / 'system.md').read_text()}
    assert fixture['response_format']['json_schema']['schema'] == json.loads((RESOURCES / 'transport.json').read_text())
    for file in (ROOT / 'PacePrompt').rglob('*.swift'):
        text = file.read_text()
        assert 'Evaluation/' not in text, file
        if file.parent.name == 'Import':
            for prohibited in ['print(', 'NSLog(', 'UserDefaults', 'write(to:', 'FileHandle']:
                assert prohibited not in text, (file, prohibited)
            if file.name == 'ImportDiagnostics.swift':
                assert text.startswith('#if DEBUG\n'), file
                assert text.rstrip().endswith('#endif'), file
                assert text.count('Logger(') == 1, file
                assert 'event.code, privacy: .public' in text, file
            else:
                assert 'Logger(' not in text, file
    print('PASS: pinned hashes, eleven ordered model-visible examples, complete fixture and source privacy checks')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-bundle', type=Path)
    args = parser.parse_args()
    verify()
    if args.app_bundle:
        for path in args.app_bundle.rglob('*'):
            assert not any(x in path.parts for x in ['Evaluation', 'Corpus', 'Contracts', '.runs', 'HostEval']), path
        for name, expected in HASHES.items():
            assert hashlib.sha256((args.app_bundle / 'ImportResources' / name).read_bytes()).hexdigest() == expected
        print('PASS: built production bundle contains pinned resources and no evaluation artifacts')
