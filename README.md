# Duewise PostgreSQL performance study

[![CI](https://github.com/developeras95/duewise-postgres-performance/actions/workflows/ci.yml/badge.svg)](https://github.com/developeras95/duewise-postgres-performance/actions/workflows/ci.yml)
![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL-17-336791)
![License: proprietary](https://img.shields.io/badge/license-proprietary-lightgrey)

What happens to an invoicing database at **5 million invoices**, and how to make its slow queries fast again,
with measured evidence for every change.

This repository loads the real schema of [Duewise](https://github.com/developeras95/duewise-invoicing-api)
with realistic data, finds the queries that slow down at scale, and fixes each one. Every fix is backed by
`EXPLAIN (ANALYZE, BUFFERS)` plans and timings from before and after, together with its cost: index size and
slower writes. The indexes that earn their place go back into Duewise as a migration.

## Results

Five requests Duewise serves, at 5 million invoices, before and after each fix. Median database time of
11 warm runs; every number has its query plans in the case's folder.

| Case | Request | Before | After | Fix | What it costs |
| --- | --- | ---: | ---: | --- | --- |
| [1](cases/01-overdue-list/README.md) | Overdue invoices, first page | 339 ms | **0.56 ms** | Partial index on open invoices, in the list's order | 26 MB; no measurable write cost |
| [2](cases/02-client-statement/README.md) | Statement of the largest client | 95 ms | **7.1 ms** | Partial covering index on (client, currency, due date) | 55 MB; part payments +30% |
| [3](cases/03-client-search/README.md) | Client search by part of a name or email | 18–20 ms | **0.04–1.8 ms** | `pg_trgm` GIN indexes on name and email | 6.6 MB; new clients +34%, about 6 µs each |
| [4](cases/04-invoice-list/README.md) | Invoice list as it opens | 959 ms | **0.42 ms** | Index in the list's order | 150 MB; no measurable write cost |
| [5](cases/05-monthly-revenue/README.md) | Revenue per month, twelve months | 767 ms | **0.02 ms** | Materialized view refreshed nightly, plus a BRIN index | 72 kB; 1.3 s per refresh |

About 240 MB of indexes in all, against 3.8 GB of data.

### What an index could not fix

- **Counting.** The invoice list's total read every row: 200 ms with or without an index (case 4). The fix
  was an API change: above 100,000 invoices, Duewise now reports PostgreSQL's estimate, 0.12% off, in 0.017 ms.
- **Deep pages.** Page 501 of the invoice list still costs 11.5 ms with the index, and more for every page
  after it. Keyset paging ("the 20 after this one") costs 0.41 ms on any page, but changes the API, so it is
  documented and not adopted.
- **The report's join.** Indexes on the payment date made the monthly report only 27% faster, because most
  of its time goes on finding each payment's currency on its invoice (case 5). Storing the result did what no
  index could.

### What was measured and left out

- An index on client names (case 3): it made the first page of clients 500× faster and some searches
  **slower than no index at all**, depending on where in the alphabet the matches fall.
- A B-tree on payment dates (case 5): 215 MB, 9,000 times the size of the BRIN index, for a few milliseconds
  more on a query the stored report answers anyway.

## Back in Duewise

The fixes went into [Duewise 1.2.0](https://github.com/developeras95/duewise-invoicing-api/releases/tag/v1.2.0)
as migration
[`V6`](https://github.com/developeras95/duewise-invoicing-api/blob/v1.2.0/src/main/resources/db/migration/V6__performance_indexes_and_revenue_report.sql),
each index commented with the case that measured it:

| Study | Duewise |
| --- | --- |
| `perf_invoice_open_by_issue_date` | `ix_invoice_open_by_issue_date` |
| `perf_invoice_client_statement` | `ix_invoice_client_statement` |
| `perf_client_name_trgm`, `perf_client_email_trgm` | `ix_client_name_trgm`, `ix_client_email_trgm` |
| `perf_invoice_by_issue_date` | `ix_invoice_by_issue_date` |
| `perf_payment_paid_on_brin` | `ix_payment_paid_on_brin` |
| `perf_monthly_revenue` | `monthly_revenue`, behind the new `GET /api/v1/reports/revenue` |

Duewise 1.2.0 also estimates the unfiltered invoice count, and the
[web app 1.1.0](https://github.com/developeras95/duewise-web/releases/tag/v1.1.0) shows the revenue report and
"about 4,994,000 invoices". On this study's database, `V6` took 6.3 s to apply, and the plans of every case's
query were checked again with Duewise's own indexes.

## The cases

Each case has its own folder with the queries, the fix, the saved plans and a write-up of what was
found and what it costs.

| # | Request | Problem at 5M invoices | Fix | Result |
| --- | --- | --- | --- | --- |
| [1](cases/01-overdue-list/README.md) | Overdue invoices list | Reads every invoice to find the open, overdue ones | Partial index on open invoices, in the list's order | Page **339 ms → 0.56 ms**, count 195 → 36 ms; 26 MB |
| [2](cases/02-client-statement/README.md) | Client statement | The largest client's statement reads ~300,000 invoices and intersects two indexes | Partial covering index on (client, currency, due date) | Largest client **95 ms → 7.1 ms**; 55 MB; part payments +30% |
| [3](cases/03-client-search/README.md) | Client search by part of name or email | `LIKE '%term%'` cannot use a B-tree index, so every keystroke reads every client | Trigram (`pg_trgm`) GIN indexes on name and email | Search **18–20 ms → 0.04–1.8 ms**; 6.6 MB; new clients +34%. An index on the list's order was tested and left out: it made some searches slower than no index |
| [4](cases/04-invoice-list/README.md) | Invoice list as it first opens, and deep pages | Reads and sorts all 5M invoices for 20 rows; `OFFSET` throws away every earlier row | Index in the list's order; keyset paging; estimated count | Page **959 ms → 0.42 ms**, page 501 1,083 → 11.5 ms (keyset 0.41 ms); 150 MB. The 200 ms count needs an API change |
| [5](cases/05-monthly-revenue/README.md) | Monthly revenue report (not in Duewise yet) | Joins every payment of the period to its invoice for the currency | Materialized view refreshed nightly, plus a BRIN index on `paid_on` | One month **185 ms**, twelve months **767 ms → 0.02 ms** from the view (48 kB, 1.3 s to refresh). Indexes alone: −27% at best, and a B-tree costs 215 MB against BRIN's 24 kB |

The cases build on each other: each one is measured with the earlier cases' indexes in place, the way
the final migration will add them together.

## Run it

Needs only [Docker Desktop](https://www.docker.com/products/docker-desktop/) and about 15 GB of free disk.

```bash
docker compose up -d
docker compose exec postgres psql -U duewise -d duewise -c "\dt"
```

The first start creates the Duewise schema (11 tables). The database runs on port **5433**, separate from a
Duewise development database on 5432, and keeps its data in its own Docker volume. Remove everything with
`docker compose down -v`.

Then fill it with data and check the result (a few minutes; about 4 GB):

```bash
docker compose exec postgres psql -U duewise -d duewise -v invoices=5000000 -f /work/generator/generate.sql
docker compose exec postgres psql -U duewise -d duewise -f /work/generator/validate.sql
```

`invoices` sets the scale (for example `-v invoices=20000` for a quick try) and `seed` (default 42) picks the
data: the same seed always produces exactly the same rows. Running the generator again replaces the data.

## The data

Generated by `generator/generate.sql` with the defaults: three years of invoicing up to a fixed study date,
1 November 2026, so the results do not change with the day they are run.

| Table | Rows | Size incl. indexes |
| --- | ---: | ---: |
| `invoice_line_item` | 12.5 million | 1.95 GB |
| `invoice` | 5 million | 1.22 GB |
| `payment` | 4.6 million | 624 MB |
| `client` | 50,000 | 16 MB |

The data is shaped like a real business, because uniform random data hides the problems this study is about:

- **Uneven clients.** The largest 1% of clients hold 30% of all invoices (the largest 10% hold 55%), so
  some client statements read thousands of rows and others a handful.
- **Statuses by age.** 81.6% paid, 6.8% partly paid, 6.6% sent, 3.0% draft, 2.0% void. Older invoices are
  mostly paid; recent ones are mostly open. 592,044 invoices are overdue on the study date.
- **Currencies.** 79.6% INR, then USD, EUR, GBP and AED, each with its usual tax rates (GST 18%, 12%, 5% or
  0% for INR).
- **Lines and payments.** 1 to 5 lines per invoice (2.5 on average), rounded to 2 decimals as Duewise does;
  5% of paid invoices are settled in two payments.

For speed, the generator loads rows with foreign keys and triggers switched off. `generator/validate.sql`
then proves the data would have passed them, and checks every rule Duewise relies on: totals match
their lines, amount paid matches the payments, status matches the amounts, and each
year's invoice-number counter matches the highest number issued. It stops with an error if any check fails.

## How the measurements are made

- The schema is copied unchanged from Duewise v1.0.3 (`schema/`); no table is altered for the study.
- PostgreSQL settings are fixed in `compose.yaml` and are part of the results: every timing was measured
  with exactly those values, on the hardware listed below.
- Each query runs 3 times to warm the cache, then 11 timed runs; the result is the **median** execution
  time, with the minimum and maximum alongside it.
- Times are measured inside PostgreSQL with `EXPLAIN (ANALYZE, TIMING OFF)`: the query runs in full, but
  network and client time are excluded, and so is the overhead of timing each plan node.
- One further run is saved with `EXPLAIN (ANALYZE, BUFFERS)`, so every number comes with the plan that
  produced it: which indexes were used, how many rows each step read and how many pages came from memory or
  disk.
- Write costs (how much an index slows down inserts) are measured the same way, with each run rolled back
  so every run starts from the same data.
- [CI](.github/workflows/ci.yml) reproduces the whole study on every push: a fresh database, 20,000 generated
  invoices, every case from before to after, then every undo. At that scale the timings are only a smoke
  test; the results above come from 5 million invoices.

### The harness

```bash
# time one query and save its plan
docker compose exec postgres psql -U duewise -d duewise -f /work/harness/measure.sql \
    -v case=00-try -v variant=before -v query=harness/example-query.sql

# record the hardware, PostgreSQL version and settings
docker compose exec postgres psql -U duewise -d duewise -f /work/harness/environment.sql
```

| Variable | Meaning |
| --- | --- |
| `case` | Folder under `cases/` where the plan is saved |
| `variant` | Label such as `before` or `after`; the plan is saved as `cases/<case>/plans/<variant>.txt` |
| `query` | File with one SQL statement, relative to the repository root |
| `runs`, `warmups` | Timed and warm-up runs (default 11 and 3) |
| `rollback` | `true` to undo every run, for timing `INSERT`, `UPDATE` or `DELETE` |

Every measurement adds a line to `results/timings.csv` (median, min, max, planning time, rows, pages read)
and a row to the `harness.measurement` table. `results/environment.csv` holds the hardware and settings.
On PowerShell, put the command on one line or end each line with a backtick (`` ` ``) instead of `\`.

## Hardware

Recorded by `harness/environment.sql` (full list in [`results/environment.csv`](results/environment.csv)):

| | |
| --- | --- |
| CPU | AMD Ryzen 9 7900X, 12 cores / 24 threads, all 24 available to Docker |
| Memory available to Docker | 15.2 GB |
| Platform | Docker Desktop on Windows, WSL 2 (Linux 6.6) |
| PostgreSQL | 17.11 (`postgres:17-alpine`), settings as in `compose.yaml` |
| Data | 5,000,000 invoices, 12.5 million line items, 4.6 million payments: 3.8 GB on disk |

Every result is from warm runs, so the data the query needs is in memory (2 GB `shared_buffers` plus the
operating system's cache). That is the normal state of a busy production database; the plans also show how
many pages each query had to touch, which is what grows as data grows.

## Repository layout

```
schema/      Duewise's tables, loaded when the database is first created
generator/   SQL that fills the tables with realistic data at a chosen scale
harness/     SQL that times queries, saves their plans and records the environment
cases/       one folder per case: queries, plans before and after, write-up
results/     measured timings, index sizes and the environment, as CSV
.github/     CI that reproduces the study at small scale, and the release workflow
```

Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

Copyright © 2026 Abhijit Saha. **All rights reserved.** Published for reading and evaluation; see
[LICENSE](LICENSE). PostgreSQL and its extensions are open source under the PostgreSQL License.
