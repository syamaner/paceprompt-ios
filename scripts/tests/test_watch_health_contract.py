"""Synthetic specification oracle; no production transport, sensor or HealthKit code."""
import copy
from datetime import datetime
import json
import math
from pathlib import Path
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'docs/fixtures/watch-health-v1'
NS = 'com.otherweather.PromptPace.'


def load(name):
    return json.loads((FIXTURES / f'{name}.synthetic.json').read_text())


def timestamp(value):
    parsed = datetime.strptime(value, '%Y-%m-%dT%H:%M:%S.%fZ')
    assert parsed.strftime('%Y-%m-%dT%H:%M:%S.') + f'{parsed.microsecond // 1000:03d}Z' == value
    return parsed


def integer(value, minimum=0):
    assert type(value) is int and minimum <= value <= 2**63 - 1


def number(value):
    assert type(value) in (int, float) and math.isfinite(value)


def validate(m):
    assert set(m) == {'schemaVersion', 'kind', 'summaryID', 'revision', 'workoutActivity',
                      'workoutStart', 'workoutEnd', 'final', 'localOutcome', 'intervals', 'distance'}
    assert type(m['schemaVersion']) is int and m['schemaVersion'] == 1
    assert m['kind'] == 'manifest'
    assert str(uuid.UUID(m['summaryID'])) == m['summaryID']
    integer(m['revision'], 1)
    assert m['workoutActivity'] in ('indoorWalking', 'indoorRunning')
    assert type(m['final']) is bool
    assert len(json.dumps(m, separators=(',', ':')).encode()) <= 32768
    assert type(m['intervals']) is list and len(m['intervals']) <= 64
    start = timestamp(m['workoutStart'])
    end = timestamp(m['workoutEnd']) if m['final'] else None
    if m['final']:
        assert end > start and m['localOutcome'] in ('completed', 'stoppedByUser', 'failed', 'interrupted')
    else:
        assert m['workoutEnd'] is None and m['localOutcome'] is None
    previous_end, previous_id = start, None
    for i in m['intervals']:
        assert set(i) == {'segmentIndex', 'intervalIndex', 'startedAt', 'endedAt', 'prescribed',
                          'effectiveSpeed', 'effectiveInclination', 'settledObservation', 'endReason'}
        integer(i['segmentIndex']); integer(i['intervalIndex'])
        identity = (i['segmentIndex'], i['intervalIndex'])
        if previous_id is None or identity[0] > previous_id[0]:
            assert identity[1] == 0
        else:
            assert identity == (previous_id[0], previous_id[1] + 1)
        a, b = timestamp(i['startedAt']), timestamp(i['endedAt'])
        assert previous_end <= a < b and (end is None or b <= end)
        p, s, g, o = (i[k] for k in ('prescribed', 'effectiveSpeed', 'effectiveInclination', 'settledObservation'))
        assert set(p) == {'kind', 'speedKilometresPerHour', 'inclinationPercent'}
        assert p['kind'] in ('warmUp', 'interval', 'recovery', 'coolDown')
        assert set(s) == {'kilometresPerHour', 'source'} and set(g) == {'percent', 'source'}
        assert s['source'] in ('planned', 'manualOverride') and g['source'] in ('planned', 'manualOverride')
        assert set(o) == {'observedAt', 'speedKilometresPerHour', 'inclinationPercent', 'provenance'}
        assert timestamp(o['observedAt']) == a
        assert o['provenance'] == 'fr30zTreadmillDataCurrentEpoch'
        for value in (p['speedKilometresPerHour'], p['inclinationPercent'], s['kilometresPerHour'],
                      g['percent'], o['speedKilometresPerHour'], o['inclinationPercent']):
            number(value)
        assert i['endReason'] in ('planTransition', 'targetChanged', 'paused', 'completed', 'endedByUser', 'interrupted', 'failed')
        previous_end, previous_id = b, identity
    d = m['distance']
    if d['state'] == 'unavailable':
        assert set(d) == {'state'}
    else:
        assert set(d) == {'state', 'metres', 'provenance'} and d['state'] == 'accepted'
        number(d['metres'])
        assert m['final'] and d['metres'] > 0 and d['provenance'] == 'fr30zCumulativeDistanceDelta'


class Oracle:
    """Staged-prefix oracle, deliberately not a HealthKit/session implementation."""
    def __init__(self, summary):
        self.summary = summary
        self.applied = None
        self.fault = False
        self.confirmed = False
        self.frozen = False

    @property
    def revision(self):
        return self.applied['revision'] if self.applied else 0

    def receive(self, m):
        if self.frozen:
            return self.revision
        try:
            validate(m)
            assert m['summaryID'] == self.summary
            if m['revision'] < self.revision:
                return self.revision
            if m['revision'] == self.revision:
                assert m == self.applied
                return self.revision
            if self.applied:
                assert not self.applied['final']
                assert m['workoutActivity'] == self.applied['workoutActivity']
                assert m['workoutStart'] == self.applied['workoutStart']
                assert m['intervals'][:len(self.applied['intervals'])] == self.applied['intervals']
            self.applied = copy.deepcopy(m)
        except (AssertionError, ValueError, KeyError, TypeError, OverflowError):
            self.fault = True
        return self.revision

    def finalize(self, revision):
        if not self.frozen and self.applied and self.applied['final'] and type(revision) is int and revision == self.revision:
            self.confirmed = True

    def freeze(self):
        self.frozen = True
        return ('complete' if self.confirmed and not self.fault and self.applied['intervals']
                and self.applied['localOutcome'] in ('completed', 'stoppedByUser') else 'incomplete')


def activity_metadata(i, sid):
    p, s, g, o = (i[k] for k in ('prescribed', 'effectiveSpeed', 'effectiveInclination', 'settledObservation'))
    fields = dict(timelineSchemaVersion=1, summaryID=sid, segmentIndex=i['segmentIndex'], intervalIndex=i['intervalIndex'],
                  prescribedSegmentKind=p['kind'], prescribedSpeedKilometresPerHour=p['speedKilometresPerHour'],
                  prescribedInclinationPercent=p['inclinationPercent'], effectiveTargetSpeedKilometresPerHour=s['kilometresPerHour'],
                  effectiveTargetInclinationPercent=g['percent'], speedTargetSource=s['source'], inclinationTargetSource=g['source'],
                  observedSpeedKilometresPerHour=o['speedKilometresPerHour'], observedInclinationPercent=o['inclinationPercent'],
                  observedAt=o['observedAt'], observationProvenance=o['provenance'], intervalEndReason=i['endReason'])
    return {NS + key: value for key, value in fields.items()}


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.fixture = load('complete')
        self.first, self.final = self.fixture['manifests']
        self.oracle = Oracle(self.first['summaryID'])

    def test_golden_complete_and_incomplete_projection(self):
        for name in ('complete', 'incomplete'):
            with self.subTest(name=name):
                f = load(name)
                self.assertEqual(f['fixtureSchemaVersion'], 1)
                self.assertIs(f['synthetic'], True)
                o = Oracle(f['manifests'][0]['summaryID'])
                for m in f['manifests']:
                    validate(m)
                    o.receive(m)
                if f['watchReceivedFinalizeRevision'] is not None:
                    self.assertEqual(f['phoneReceivedAckRevision'], o.revision)
                    o.finalize(f['watchReceivedFinalizeRevision'])
                status = o.freeze()
                w = f['expected']['workout']
                self.assertEqual(w['metadata'][NS+'interchangeStatus'], status)
                self.assertEqual(w['metadata'][NS+'manifestRevision'], o.revision)
                self.assertEqual(w['metadata'][NS+'ownership'], 'watchPrimary')
                self.assertEqual(w['metadata'][NS+'interchangeSchemaVersion'], 1)
                self.assertEqual(w['metadata']['HKMetadataKeySyncVersion'], 1)
                self.assertEqual(w['metadata']['HKMetadataKeySyncIdentifier'], NS+'workout.'+o.summary)
                self.assertEqual(f['expected']['readerState'], 'supported'+status.title())
                self.assertEqual(len(w['activities']), len(o.applied['intervals']))
                self.assertEqual(w['metadata'][NS+'intervalCount'], len(w['activities']))
                energy = sum(a['statistics']['activeEnergy'].get('sum', 0) for a in w['activities'])
                self.assertLessEqual(energy, w['statistics']['activeEnergy']['sum'])
                for activity, interval in zip(w['activities'], o.applied['intervals']):
                    self.assertEqual(activity['metadata'], activity_metadata(interval, o.summary))
                    for key in ('startedAt', 'endedAt'):
                        self.assertEqual(activity[key], interval[key])
                    self.assertEqual(activity['activity'], w['activity'])
                    self.assertEqual(activity['location'], 'indoor')
                    self.assertLessEqual(activity['durationSeconds'], (timestamp(activity['endedAt'])-timestamp(activity['startedAt'])).total_seconds())
                self.assertEqual(w['distance']['state'], 'available' if status == 'complete' else 'noDataOrAccess')
                if status == 'complete':
                    self.assertEqual(w['distance']['metres'], o.applied['distance']['metres'])
                for source, stats in [('healthKitWorkoutStatistics', w['statistics'])] + [('healthKitActivityStatistics', a['statistics']) for a in w['activities']]:
                    for metric in stats.values():
                        if metric['state'] == 'available':
                            self.assertEqual(metric['provenance'], source)
                        else:
                            self.assertEqual(metric, {'state': 'noDataOrAccess'})

    def test_duplicate_and_delayed_do_not_duplicate_prefix(self):
        for m in (self.first, self.first, self.final, self.first, self.final):
            self.oracle.receive(m)
        self.assertEqual(self.oracle.revision, 2)
        self.assertEqual(len(self.oracle.applied['intervals']), 2)
        self.assertFalse(self.oracle.fault)

    def test_skipped_revision_accepts_complete_cumulative_state(self):
        m = copy.deepcopy(self.final); m['revision'] = 4
        self.oracle.receive(m); self.oracle.finalize(4)
        self.assertEqual(self.oracle.freeze(), 'complete')

    def test_same_revision_conflict_latches_incomplete(self):
        self.oracle.receive(self.first)
        m = copy.deepcopy(self.first); m['intervals'][0]['effectiveSpeed']['source'] = 'manualOverride'
        self.oracle.receive(m); self.oracle.receive(self.final); self.oracle.finalize(2)
        self.assertEqual(self.oracle.freeze(), 'incomplete')

    def test_prefix_rewrite_or_truncation_rejected_atomically(self):
        for intervals in ([], [self.final['intervals'][1]]):
            o = Oracle(self.first['summaryID']); o.receive(self.first)
            m = copy.deepcopy(self.final); m['intervals'] = intervals
            o.receive(m)
            self.assertEqual(o.revision, 1)
            self.assertEqual(o.applied, self.first)
            self.assertTrue(o.fault)

    def test_rejects_malformed_known_and_unsupported_envelopes(self):
        mutations = [lambda m: m.update(schemaVersion=2), lambda m: m.update(revision=True),
                     lambda m: m.update(revision=2**63), lambda m: m.update(summaryID='bad'),
                     lambda m: m.update(rawHeartRate=[80]), lambda m: m.update(workoutActivity='cycling'),
                     lambda m: m['intervals'][1].update(startedAt=m['intervals'][0]['startedAt']),
                     lambda m: m['intervals'][1].update(endedAt=m['workoutStart']),
                     lambda m: m['intervals'][0]['settledObservation'].pop('observedAt'),
                     lambda m: m['intervals'][0]['effectiveSpeed'].update(kilometresPerHour=float('nan')),
                     lambda m: m.update(intervals=m['intervals']*33),
                     lambda m: m['distance'].update(metres=0)]
        for mutate in mutations:
            m = copy.deepcopy(self.final); mutate(m)
            with self.subTest(manifest=m):
                with self.assertRaises((AssertionError, ValueError, KeyError, TypeError)):
                    validate(m)

    def test_wrong_attempt_does_not_advance(self):
        m = copy.deepcopy(self.first); m['summaryID'] = '00000000-0000-4000-8000-000000000999'
        self.oracle.receive(m)
        self.assertEqual(self.oracle.revision, 0)

    def test_lost_ack_or_finalize_remains_incomplete(self):
        self.oracle.receive(self.final)
        self.assertEqual(self.oracle.freeze(), 'incomplete')
        self.oracle.finalize(2)
        self.assertEqual(self.oracle.freeze(), 'incomplete')

    def test_wrong_final_revision_or_failed_outcome_cannot_complete(self):
        for rev, outcome in ((1, 'completed'), (2, 'failed'), (2, 'interrupted')):
            o = Oracle(self.first['summaryID']); m = copy.deepcopy(self.final); m['localOutcome'] = outcome
            o.receive(m); o.finalize(rev)
            self.assertEqual(o.freeze(), 'incomplete')

    def test_final_is_immutable_and_late_data_cannot_upgrade_saved_state(self):
        self.oracle.receive(self.final)
        m = copy.deepcopy(self.final); m['revision'] = 3
        self.oracle.receive(m)
        self.assertEqual(self.oracle.revision, 2)
        self.assertTrue(self.oracle.fault)
        self.oracle.freeze(); self.oracle.finalize(2)
        self.assertEqual(self.oracle.freeze(), 'incomplete')

    def test_empty_final_has_no_complete_interval_claim(self):
        self.final['intervals'] = []
        self.oracle.receive(self.final); self.oracle.finalize(2)
        self.assertEqual(self.oracle.freeze(), 'incomplete')

    def test_contract_relative_links_exist(self):
        import re
        for path in [ROOT/'design/watch-primary-health-interchange-contract.md', ROOT/'docs/watch-health-interchange-runbook.md', FIXTURES/'README.md']:
            for target in re.findall(r'\]\(([^)]+)\)', path.read_text()):
                if not target.startswith('https://'):
                    self.assertTrue((path.parent/target.split('#')[0]).exists(), (path, target))


if __name__ == '__main__':
    unittest.main()
