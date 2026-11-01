# Case 1: the overdue invoices list

**Result:** the first page of overdue invoices went from **339 ms to 0.56 ms**, and its count from
**195 ms to 36 ms**, with one 26 MB partial index. Recording payments did not get measurably slower.

Measured on 5,000,000 invoices, median of 11 warm runs; hardware and settings in the
[main README](../../README.md#hardware).

## The request

`GET /api/v1/invoices?overdue=true`: the list of invoices with money owed past their due date,
newest first, 20 per page. Spring Data sends two queries for it:

- [`page.sql`](page.sql): the 20 rows, with client and currency joined in (Duewise's `@EntityGraph`)
- [`count.sql`](count.sql): the total, for `totalElements` and `totalPages` in the response

Both filter on `status IN ('SENT', 'PARTIALLY_PAID') AND due_date < today`. On the study date,
**592,044** invoices match: 12% of the table.

## Before: every query reads the whole table

Duewise v1.0.3 has no index on `status`, `due_date` or `issue_date`, so both queries scan all
5 million invoices ([plan](plans/before-page.txt)):

```
Parallel Seq Scan on invoice i  (actual rows=197348 loops=3)
  Rows Removed by Filter: 1469319
```

Three processes read about 103,000 pages (800 MB) and throw away 88% of the rows. The page query then
sorts the 592,044 survivors to keep 20.

## What did not work: an index on `due_date`

The obvious fix, `CREATE INDEX ... ON invoice (due_date) WHERE status IN ('SENT', 'PARTIALLY_PAID')`,
improved the count by only about 25% in a trial run. The overdue invoices are spread across the whole
table, one or more on 99% of its pages, so finding them through the index and then reading each row
still reads almost every page. With this much of the table matching, an index only pays off if the
query can be answered **from the index alone**, without visiting the table.

## The fix

[`fix.sql`](fix.sql):

```sql
CREATE INDEX perf_invoice_open_by_issue_date
    ON invoice (issue_date DESC, id DESC, due_date)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');
```

| Part | Why |
| --- | --- |
| `WHERE status IN (...)` | Partial index: only the ~670,000 open invoices, so it is small and paid invoices never need skipping |
| `issue_date DESC, id DESC` | Exactly the list's sort order, so the first page is read in order and PostgreSQL stops after 20 rows |
| `due_date` last | "due before today" is checked inside the index, and with `id` it makes the count an index-only scan |

## After

| Query | Before | After | Faster | Pages read before → after |
| --- | ---: | ---: | ---: | ---: |
| First page of 20 | 338.8 ms | **0.56 ms** | ~600× | 103,738 → 136 |
| Count | 195.2 ms | **35.7 ms** | 5.5× | 102,207 → 300,020 * |
| Record 1,000 payments | 17.9 ms | 17.2 ms | no measurable change | 41,031 → 41,776 |

\* The count touches more pages than before, but they are the index's 3,300 pages and the
visibility map, revisited from memory; it reads none of the table's 800 MB
([plan](plans/after-count.txt): `Parallel Index Only Scan ... Heap Fetches: 31`).

The page query now walks the index from the newest open invoice and stops at the 20th overdue one
([plan](plans/after-page.txt)):

```
Index Scan using perf_invoice_open_by_issue_date on invoice i  (actual rows=20 loops=1)
  Index Cond: (due_date < '2026-11-01'::date)
```

## The cost

- **Size:** 26 MB, 3% of the 801 MB table, because only open invoices are in it.
- **Build:** 0.4 s on 5 million rows.
- **Writes:** recording a payment changes `status`, a column the index depends on. Timing 1,000
  payment updates (each run rolled back, [`record-payment.sql`](record-payment.sql)) showed no
  measurable difference: 17.9 ms before, 17.2 ms after, within run-to-run variation. A paid invoice
  leaves the index's `WHERE` clause, so most payments add no index entry at all.

## What is left

The count still visits all 592,044 matching index entries, so it grows with the number of overdue
invoices: 36 ms today, more as overdue invoices pile up. If that ever matters, the fix is in the
application rather than the database: return a `Slice` (is there a next page?) instead of a `Page`
with an exact total, or cache the total.

## Reproduce

```bash
docker compose exec postgres psql -U duewise -d duewise -f /work/cases/01-overdue-list/run.sql
```

[`run.sql`](run.sql) removes the index if present, measures before, creates it, and measures after.
[`undo.sql`](undo.sql) removes it again.
