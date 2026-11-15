# Case 5: a monthly revenue report

**Result:** money received per month and currency took **185 ms for one month and 767 ms for twelve**.
Indexes on the payment date barely help (185 → 134 ms, twelve months unchanged), because most of the
time goes on joining each payment to its invoice for the currency. A materialized view answers both
in **0.02 ms** from 181 stored rows (48 kB), at the price of being a copy: it costs 1.3 s to refresh,
and payments recorded since the last refresh are not in it.

Measured on 4,622,211 payments (a 370 MB table) for 5,000,002 invoices, median of 11 warm runs;
hardware and settings in the [main README](../../README.md#hardware). Cases 1 to 4's indexes are in
place throughout.

## The request

Duewise has no revenue report yet; this is the one a dashboard or a monthly summary would need. The
currency is stored on the invoice, not on the payment, so every payment is joined to its invoice:
amounts in rupees and dollars cannot be added together ([`month.sql`](month.sql)):

```sql
SELECT date_trunc('month', p.paid_on)::date AS month, i.currency_code,
       count(*) AS payments, sum(p.amount) AS received
FROM payment p
JOIN invoice i ON i.id = p.invoice_id
WHERE p.paid_on >= DATE '2026-10-01' AND p.paid_on < DATE '2026-11-01'
GROUP BY 1, 2
ORDER BY 1, 2;
```

Measured for one month, October 2026 (156,345 payments, [`month.sql`](month.sql)), and for the last
twelve months (1,558,432 payments, [`year.sql`](year.sql)), with the write cost of recording 1,000
payments ([`record-payments.sql`](record-payments.sql), rolled back).

## Before: where the time goes

For one month ([plan](plans/before-month.txt)) PostgreSQL does two things:

```
Nested Loop  (actual rows=52115 loops=3)
  ->  Parallel Seq Scan on payment p        (actual time=49.762..55.420 rows=52115 loops=3)
        Rows Removed by Filter: 1488622
        Buffers: shared hit=47267
  ->  Index Scan using invoice_pkey on invoice i  (actual rows=1 loops=156345)
```

1. **Finding October's payments:** reads all 4.6 million to keep 156,345, about 55 ms.
2. **Finding each one's currency:** 156,345 lookups in the invoice table's primary key, about 115 ms
   and 625,000 of the query's 672,679 page reads.

For twelve months the second part is too large for lookups, so PostgreSQL reads the whole 811 MB
invoice table and joins it with a hash join ([plan](plans/before-year.txt)). Almost all of the 767 ms
is that join.

An index on `paid_on` can only make part 1 faster.

## Three options

**A B-tree on the payment date** ([`fix-btree.sql`](fix-btree.sql)), covering the two columns the
report reads from payment, so the table is not touched:

```sql
CREATE INDEX perf_payment_paid_on ON payment (paid_on) INCLUDE (invoice_id, amount);
```

**A BRIN index** ([`fix-brin.sql`](fix-brin.sql)). Instead of one entry per payment it stores the
lowest and highest date of each block of 128 table pages. It works only because payments are stored
in nearly the order of their dates (the correlation between `paid_on` and the physical order is
0.99999 here), so each block covers a few days, and a range of dates maps to a few blocks:

```sql
CREATE INDEX perf_payment_paid_on_brin ON payment USING brin (paid_on);
```

**A materialized view** ([`fix-mv.sql`](fix-mv.sql)): the report for every month, computed once
and stored, 181 rows (one per month and currency). The unique index allows
`REFRESH MATERIALIZED VIEW CONCURRENTLY`, which keeps the old copy readable while the new one is
computed:

```sql
CREATE MATERIALIZED VIEW perf_monthly_revenue AS
SELECT date_trunc('month', p.paid_on)::date AS month, i.currency_code,
       count(*) AS payments, sum(p.amount) AS received
FROM payment p JOIN invoice i ON i.id = p.invoice_id
GROUP BY 1, 2;
CREATE UNIQUE INDEX perf_monthly_revenue_key ON perf_monthly_revenue (month, currency_code);
```

## Results

| | Before | B-tree | BRIN | Materialized view |
| --- | ---: | ---: | ---: | ---: |
| One month | 184.7 ms | 134.1 ms | 139.3 ms | **0.019 ms** |
| Twelve months | 766.8 ms | 738.0 ms | 750.2 ms | **0.021 ms** |
| Finding one month's payments | 55 ms | 3.7 ms | 10.7 ms | |
| Recording 1,000 payments | 31.6 ms | 31.4 ms | 31.3 ms | (not affected) |
| Size | | 215 MB | **24 kB** | 48 kB |
| Build | | 1.5 s | 0.12 s | 1.5 s; **refresh 1.3 s** |

Both indexes do their own job: finding a month's payments falls from 55 ms to 3.7 ms (B-tree,
[plan](plans/btree-month.txt)) or 10.7 ms (BRIN, which reads 1,259 whole blocks and rechecks their
rows, [plan](plans/brin-month.txt)). But the 156,345 invoice lookups remain, so the report as a whole
improves by only a quarter, and the twelve-month report by 4%. The B-tree is 9,000 times the size of
the BRIN index for a few milliseconds more.

Neither index changes the cost of recording payments measurably (31.3 to 31.6 ms for 1,000).

## The materialized view's catch

It is a copy, correct as of its last refresh. A payment recorded at 10:05 is not in the report until
the next refresh, and a refresh recomputes everything: 1.3 s of work for the database, all 4.6 million
payments joined to their invoices, whether one payment changed or a thousand. That time grows with
the history.

How Duewise would use it:

- **Refresh on a schedule**, for example every night (Duewise already runs its reminder job on a daily schedule), and show
  "as of 02:00" on the report. Months that have ended rarely change, so for them a nightly copy is
  as good as live.
- **Count the current month live** if it must be up to date: one month from the payments directly,
  with the BRIN index, costs about 140 ms, and the view supplies the months before it.
- Refreshing after every payment would not work: 1.3 s of database work for each payment recorded.

## Was it worth it?

The materialized view, yes: a report of any period in 0.02 ms instead of 0.2 to 0.8 s, for 48 kB and
a nightly refresh. It is the right tool because the report only ever needs 181 numbers that change
slowly.

The BRIN index is kept as well: at 24 kB and no measurable write cost it makes "this month so far"
cheaper to compute live. Its benefit depends on payments staying in date order on disk, which holds
because payments are only ever added, in roughly the order they are received.

The B-tree is not: 215 MB for a 50 ms gain on one query that the view answers anyway.

## Reproduce

```bash
docker compose exec postgres psql -U duewise -d duewise -f /work/cases/05-monthly-revenue/run.sql
```

[`run.sql`](run.sql) removes this case's objects if present, measures before, with the B-tree (then
drops it), with the BRIN index, and from the materialized view, then times three refreshes. It leaves
the BRIN index and the view in place; [`undo.sql`](undo.sql) removes them.
