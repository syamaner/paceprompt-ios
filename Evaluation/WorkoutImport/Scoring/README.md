# Scoring implementation

`scorer.py` verifies the corpus and produces machine-readable per-case and
aggregate semantic scores. `schema_validation.py` is the standard-library-only
validator for the finite JSON Schema subset used by the checked-in contracts.

The scorer has no provider branch and invokes no model, SDK or network service.
All arithmetic uses `Decimal`. Its output is measurement evidence, not a
provider recommendation.
