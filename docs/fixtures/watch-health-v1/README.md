# Watch Health interchange v1 synthetic fixtures

These two files are shared producer/reader contract projections for PacePrompt
#115 and WeeklyHealthReport #80, governed by the
[accepted contract](../../../design/watch-primary-health-interchange-contract.md).
They are not real HealthKit records, entire Daily JSON documents or production
adapters. All identities, times, heart rates, energy and distances are synthetic.

- `complete.synthetic.json`: cumulative revisions 1 and 2, final ack and
  confirmation, two intervals separated by a physical-pause/settling gap,
  independent manual speed override, 100 m single-source distance.
- `incomplete.synthetic.json`: mirror lost after applied revision 1 before the
  final handshake, one valid prefix activity, available workout statistics,
  missing activity statistics and omitted distance. The phone still cannot save.

`fixtureSchemaVersion` versions the test wrapper. Manifest/interchange schema 1,
activity timeline schema 1, local summary schemas 1/2, PacePrompt JSON format 1
and WeeklyHealthReport Daily schema 4 are independent version domains.

`expected.workout` is the portable readback projection: adapter-produced HealthKit
activity UUIDs are replaced by stable synthetic UUIDs; NSDate values use UTC
strings and Apple's sync keys use symbolic names. The tests derive recognized
activity metadata from manifest fields and compare it to the explicit golden
projection. `expected.readerState` and the side-effect counters are expectations,
not claims of real API execution. Each activity's 60-second duration and the
workout's 140-second pause-adjusted duration illustrate independent HealthKit
statistics; local executed duration is 120 seconds in the complete fixture.

Validate with:

```sh
python3 -B -m unittest discover -s scripts/tests -p 'test_watch_health_contract.py' -v
```

At #80 implementation, copy both JSON files byte-for-byte from the accepted
PacePrompt merge commit, record that commit and SHA-256 digest in the consumer's
fixture manifest, then run its own decoder/encoder/fake-store tests. Compute the
digests with `shasum -a 256 docs/fixtures/watch-health-v1/*.json`. Do not fetch
fixtures dynamically during app execution or introduce a source-code dependency.
Any semantic change requires an explicit contract version/review and coordinated
fixture update. Never replace these files with device output.
