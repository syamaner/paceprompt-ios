# Contract versioning

The two JSON Schemas are provider-neutral interchange contracts:

- `workout-proposal-v1.schema.json` validates a complete untrusted proposal;
- `workout-import-result-v1.schema.json` validates a normalized run envelope,
  provenance and per-case evidence, and references the proposal schema by its
  local filename.

Both use JSON Schema Draft 2020-12 vocabulary, strict required fields and
`additionalProperties: false`. Schema references are resolved only from the
checked-in contract registry. No network schema lookup occurs.

Changing a contract requires a new versioned file, explicit compatibility
decision, corpus fixtures and hash. An absent or unknown version is never
treated as the current version.
