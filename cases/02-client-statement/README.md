# Case 2: the client statement

**Result:** the statement of the largest client went from **95 ms to 7.1 ms** with a 55 MB covering
index; typical clients were already fast and stay that way. The price is on writes: a part payment
became about 30% slower, still about 26 µs per invoice.

Measured on 5,000,000 invoices, median of 11 warm runs; hardware and settings in the
[main README](../../README.md#hardware). Case 1's index is in place throughout, because the cases
build on each other the way the final migration does.

## The request

`GET /api/v1/clients/{id}/statement`: every open invoice of one client with its balance and days
overdue, grouped by currency. It is plain SQL in Duewise's `StatementRepository`:

```sql
SELECT ... FROM invoice i JOIN currency c ON c.code = i.currency_code
WHERE i.client_id = :clientId AND i.status IN ('SENT', 'PARTIALLY_PAID')
ORDER BY i.currency_code, i.due_date, i.id;
```

Its cost depends on the client, and clients are very uneven (the largest 1% hold 30% of all invoices),
so it is measured for three of them:

| Client | Invoices | Open | Query |
| --- | ---: | ---: | --- |
| #1, the largest | 295,286 | 36,633 | [`statement-largest.sql`](statement-largest.sql) |
| #511, the top-1% boundary | 788 | 120 | [`statement-top-1pct.sql`](statement-top-1pct.sql) |
| #20250, the median | 44 | 4 | [`statement-median.sql`](statement-median.sql) |

## Before

For the median client this is already cheap: `ix_invoice_client` finds 44 invoices and 4 survive.
For the largest client PostgreSQL combines two indexes, `ix_invoice_client` (296,586 entries) and
case 1's open-invoices index (669,904 entries), and intersects them
([plan](plans/before-largest.txt)):

```
Bitmap Heap Scan on invoice i  (actual rows=36633 loops=1)
  Heap Blocks: exact=28042
  ->  BitmapAnd
        ->  Bitmap Index Scan on ix_invoice_client  (actual rows=296586)
        ->  Bitmap Index Scan on perf_invoice_open_by_issue_date  (actual rows=669904)
```

It then reads 28,042 table pages for 36,633 rows and sorts them. Reading over 950,000 index entries
and 28,000 pages to print one statement is the waste to remove.

## The fix, and the alternative measured with it

Both indexes contain only open invoices, with one client's rows next to each other, already in the
statement's order:

```sql
-- fix-lean.sql (measured for comparison)
CREATE INDEX perf_invoice_client_statement_lean
    ON invoice (client_id, currency_code, due_date, id)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');

-- fix.sql (the chosen fix)
CREATE INDEX perf_invoice_client_statement
    ON invoice (client_id, currency_code, due_date, id)
    INCLUDE (invoice_number, issue_date, total, amount_paid)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');
```

The lean index removes the sort and the intersection, but still reads every row from the table.
The covering one adds the remaining printed columns with `INCLUDE`: they are stored in the index
but not sorted on, so the whole statement is answered from the index ([plan](plans/after-largest.txt)):

```
Index Only Scan using perf_invoice_client_statement on invoice i  (actual rows=36633 loops=1)
  Heap Fetches: 1
```

## Results

| | Before | Lean index | **Covering index** |
| --- | ---: | ---: | ---: |
| Largest client | 94.7 ms | 22.5 ms | **7.1 ms** (13× faster) |
| Top-1% client | 0.31 ms | 0.093 ms | **0.083 ms** |
| Median client | 0.058 ms | 0.040 ms | **0.050 ms** |
| Part payment on 1,000 invoices | 19.9 ms | 24.1 ms | **26.1 ms** |
| Index size | | 26 MB | **55 MB** |
| Build time (5M rows) | | 0.49 s | **0.61 s** |

Pages touched for the largest client fell from 31,580 to 18,744, and they are now index pages read in
order (plus the visibility map, which says the table need not be checked) rather than table pages
scattered across 800 MB. The median client was never a problem: below
0.1 ms in every column, where the differences are noise.

## The cost

- **Size:** 55 MB, against 26 MB for the lean index. The `INCLUDE` columns double it, and buy a
  further 3× on the largest client.
- **Writes:** a part payment keeps the invoice open, so its entry in this index is rewritten, and in
  case 1's too. Timing 1,000 part payments (each run rolled back,
  [`partial-payment.sql`](partial-payment.sql)): 19.9 ms before, 26.1 ms after, about **+30%**, or
  roughly 6 µs more per payment. That is the clearest write cost so far, and still small: Duewise
  records payments one at a time, each in a transaction costing far more than 26 µs.

## Was it worth it?

For Duewise, yes, but this case shows where the gain goes. 99% of clients were already served in
well under a millisecond; the index exists for the few large clients whose statements grow with
their history. Without it the largest client's statement takes 95 ms today and would keep growing;
with it, the statement reads only that client's open invoices, so it grows only with what is
actually owed.

The lean index is the reasonable choice if write speed or disk matters more: 4× faster for the
largest client at half the size, with a smaller write cost (+21% instead of +31%).

## Reproduce

```bash
docker compose exec postgres psql -U duewise -d duewise -f /work/cases/02-client-statement/run.sql
```

[`run.sql`](run.sql) removes this case's indexes if present, measures before, then with the lean
index, then with the covering one, which it leaves in place. [`undo.sql`](undo.sql) removes it.
