# Changelog

All notable changes to this study. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-16

The complete study: five of Duewise's requests measured at 5 million invoices, fixed, and measured again.

### Added

- The environment: PostgreSQL 17 in Docker with fixed settings, and Duewise's schema.
- A data generator for any number of invoices, reproducible from a seed, shaped like a real business
  (uneven clients, statuses by age, five currencies), with a validator for every rule Duewise relies on.
- The measurement harness: median of 11 warm runs, the full `EXPLAIN (ANALYZE, BUFFERS)` plan of each, and
  write costs timed with rollback.
- Case 1, the overdue invoices list: 339 ms to 0.56 ms with a partial index.
- Case 2, the client statement: 95 ms to 7.1 ms for the largest client with a covering index.
- Case 3, client search: 18–20 ms to under 2 ms with trigram indexes; an index on names was measured and left
  out because it made some searches slower.
- Case 4, the invoice list as it opens: 959 ms to 0.42 ms; the 200 ms count needed an API change.
- Case 5, a monthly revenue report: 767 ms to 0.02 ms with a materialized view and a BRIN index.
- The results summary, and how the fixes went into Duewise 1.2.0.
- CI that reproduces the whole study at 20,000 invoices on every push, and a release workflow.
