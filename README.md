# Duewise PostgreSQL performance study

![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL-17-336791)
![License: proprietary](https://img.shields.io/badge/license-proprietary-lightgrey)

What happens to an invoicing database at **5 million invoices**, and how to make its slow queries fast again,
with measured evidence for every change.

This repository loads the real schema of [Duewise](https://github.com/developeras95/duewise-invoicing-api)
with realistic data, finds the queries that slow down at scale, and fixes each one. Every fix is backed by
`EXPLAIN (ANALYZE, BUFFERS)` plans and timings from before and after, together with its cost: index size and
slower writes. The indexes that earn their place go back into Duewise as a migration.

> Work in progress: the environment and schema are ready; the data generator, measurement harness and case
> studies are being added.

## The cases

| # | Query | Expected problem at scale | Fix to test |
| --- | --- | --- | --- |
| 1 | Overdue invoices dashboard | Scans every invoice for status and due date | Partial index on `due_date` for open invoices |
| 2 | Client statement by age bucket | Reads all of a client's invoices, then aggregates | Composite covering index on (client, status, due date) |
| 3 | Client search by part of name or email | `LIKE '%term%'` cannot use a B-tree index | Trigram (`pg_trgm`) GIN index |
| 4 | Deep pages of the invoice list | `OFFSET` reads and throws away every earlier row | Keyset pagination on (issue date, id) |
| 5 | Monthly revenue report | Aggregates millions of payments | BRIN index on `paid_on`, compared with a materialized view |

## Run it

Needs only [Docker Desktop](https://www.docker.com/products/docker-desktop/) and about 15 GB of free disk.

```bash
docker compose up -d
docker compose exec postgres psql -U duewise -d duewise -c "\dt"
```

The first start creates the Duewise schema (11 tables). The database runs on port **5433**, separate from a
Duewise development database on 5432, and keeps its data in its own Docker volume. Remove everything with
`docker compose down -v`.

## How the measurements are made

- The schema is copied unchanged from Duewise v1.0.3 (`schema/`); no table is altered for the study.
- PostgreSQL settings are fixed in `compose.yaml` and are part of the results: every timing was measured
  with exactly those values, on the hardware listed below.
- Timings are the median of repeated warm runs, measured inside PostgreSQL, so they exclude network and
  client time.

## Hardware

To be recorded with the first results: CPU, memory available to Docker, disk, Docker Desktop version.

## Repository layout

```
schema/      Duewise's tables, loaded when the database is first created
generator/   SQL that fills the tables with realistic data at a chosen scale
harness/     SQL that times queries and captures their plans
cases/       one folder per case: queries, plans before and after, write-up
results/     measured timings as CSV
```

## License

Copyright © 2026 Abhijit Saha. **All rights reserved.** Published for reading and evaluation; see
[LICENSE](LICENSE). PostgreSQL and its extensions are open source under the PostgreSQL License.
