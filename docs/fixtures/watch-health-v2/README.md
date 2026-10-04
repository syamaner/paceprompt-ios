# Watch interval-distance v2 fixtures

These synthetic projections extend v1 with actual interval-distance endpoints.
`complete.synthetic.json` includes exact first-interval and partial second-interval
coverage; `incomplete.synthetic.json` carries explicit invalid-distance evidence.
The legacy v1 files are unchanged, including the zero-prefix no-workout decision.

The real Swift wire decoder and metadata adapter must reproduce these projections.
The consumer independently validates and encodes them. Copy bytes with recorded
SHA-256 values; never replace them with personal Health data. See the
[contract](../../../design/workout-interval-enrichment-contract.md).
