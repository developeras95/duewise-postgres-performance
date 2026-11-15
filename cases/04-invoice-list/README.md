# Case 4: the invoice list, as it first opens

**Result:** the first page of the unfiltered invoice list went from **959 ms to 0.42 ms** with a
150 MB index in the list's sort order; page 501 went from 1,083 ms to 11.5 ms, and to 0.41 ms with
keyset paging. The count beside it stays at **200 ms**: no index makes counting 5 million rows
cheap, so that part needs an API change, not an index.

Measured on 5,000,002 invoices, median of 11 warm runs; hardware and settings in the
[main README](../../README.md#hardware). Cases 1 and 2's indexes are in place throughout, because
the cases build on each other the way the final migration does.

## The request

`GET /api/v1/invoices` with no filters, sorted by issue date, newest first: what the
[web app](https://github.com/developeras95/duewise-web)'s Invoices screen asks for when it opens.
On this database the screen took 1.7 to 4.3 seconds to show its first 20 rows.

Spring Data sends two queries for it. The page, with the client and currency joined in
([`page.sql`](page.sql)):

```sql
SELECT i.id, ..., c.name, ..., cu.symbol, ...
FROM invoice i
JOIN client c ON c.id = i.client_id
JOIN currency cu ON cu.code = i.currency_code
ORDER BY i.issue_date DESC, i.id DESC
FETCH FIRST 20 ROWS ONLY;
```

and the count that fills `totalElements` and `totalPages` ([`count.sql`](count.sql)):

```sql
SELECT count(i.id) FROM invoice i;
```

Also measured: page 501 by page number ([`page-501.sql`](page-501.sql), `OFFSET 10000`), and the
write cost of creating 1,000 drafts ([`new-drafts.sql`](new-drafts.sql), rolled back).

## Before

No index is in the list's order, so PostgreSQL reads every invoice, joins all 5 million to their
client and currency, and keeps the newest 20 ([plan](plans/before-page.txt)):

```
Limit  (actual rows=20)
  ->  Gather Merge
        ->  Sort  (actual rows=14 loops=3)
              Sort Key: i.issue_date DESC, i.id DESC
              Sort Method: top-N heapsort  Memory: 36kB
              ->  Hash Join  ...
                    ->  Parallel Seq Scan on invoice i
```

105,290 pages, the whole 811 MB table, for 20 rows. Page 501 does the same and keeps 10,020 rows
instead of 20.

The count is already as good as it gets: PostgreSQL counts the primary key's entries, an index-only
scan in three parallel processes ([plan](plans/before-count.txt)). It still has to visit all
5 million.

## The fix

```sql
CREATE INDEX perf_invoice_by_issue_date
    ON invoice (issue_date DESC, id DESC);
```

Every invoice, in the list's default order, with the id that Duewise adds to make the order stable.
It is not partial, because the unfiltered list shows every status; case 1's partial index stays for
the overdue list, where most of these entries would have to be skipped. It has no `INCLUDE`
columns: the page needs 25 columns from three tables but only 20 rows, and reading 20 table rows is
cheap.

The first page is now read from the start of the index, and PostgreSQL stops after 20 rows
([plan](plans/after-page.txt)):

```
Limit  (actual rows=20)
  ->  Nested Loop
        ->  Nested Loop
              ->  Index Scan using perf_invoice_by_issue_date on invoice i  (actual rows=20)
              ->  Memoize  ->  Index Scan using client_pkey on client c
        ->  ...  currency
```

## Results

| | Before | After | |
| --- | ---: | ---: | --- |
| First page | 958.8 ms | **0.42 ms** | 2,300× faster; 86 pages instead of 105,290 |
| Page 501 (`OFFSET 10000`) | 1,083.4 ms | **11.5 ms** | still reads the 10,000 rows before it |
| Page 501, keyset | | **0.41 ms** | as fast as the first page, at any depth |
| Count | 202.2 ms | **200.8 ms** | unchanged |
| Count, estimated | | **0.017 ms** | PostgreSQL's own row estimate |
| Creating 1,000 drafts | 57.4 ms | 35.1 ms | within noise; see below |
| Index size | | **150 MB** | 18% of the table |
| Build time (5M rows) | | **1.4 s** | |

## Paging by number, and the keyset alternative

With the index, page 501 costs 11.5 ms: the database walks the first 10,000 entries of the index,
joins each one, and throws them away ([plan](plans/after-page-501.txt)). The cost grows with the
page number: page 5,000 would read 100,000 rows.

Keyset paging asks for "the 20 after this invoice" instead of "page 501"
([`keyset.sql`](keyset.sql)):

```sql
WHERE (i.issue_date, i.id) < (DATE '2026-10-30', 4746381)
ORDER BY i.issue_date DESC, i.id DESC
FETCH FIRST 20 ROWS ONLY;
```

The row comparison is answered by the same index (`Index Cond` in the
[plan](plans/after-keyset-501.txt)), so every page costs what the first one does: 0.41 ms. The price
is in the API: the client sends the previous page's last issue date and id instead of a page
number, and can no longer jump to "page 300" directly. For a screen that people page through a few
pages at a time, numbered pages with the index are fine; keyset is for programs that read the whole
list.

## The count

The index does not help the count, and no index can. `count(*)` over the whole table must visit every
row's index entry (an index-only scan of the primary key, before and after: see
[before](plans/before-count.txt) and [after](plans/after-count.txt)). It costs 200 ms today and
grows with the table.

After the fix, the count is 99.8% of the list's database time. The options, all API changes:

1. **Keep the exact count.** Correct, 200 ms, and slower every year.
2. **Estimate it when there is no filter.** PostgreSQL keeps an estimate of each table's row count,
   updated by autovacuum and `ANALYZE` ([`count-estimate.sql`](count-estimate.sql)): 4,993,865 against
   5,000,002 after this run's `ANALYZE`, 0.12% off, in 0.017 ms. The screen would say "about 5,000,000 invoices". Filtered
   lists still count exactly, and are smaller.
3. **No total at all** (Spring Data's `Slice`): the page says only whether there is a next page.

## The cost

- **Size:** 150 MB, the largest index in the study so far, because it covers all 5 million rows. The
  smaller alternative would have to leave some invoices out of the list.
- **Writes:** every new invoice adds one entry. Creating 1,000 drafts touched 20,291 pages instead of
  17,267, about 3 more per invoice; the timing (57 ms before, 35 ms after, with the before runs
  spread from 43 to 100 ms) is within this machine's noise, so the cost is too small to measure here.
  Payments and voids do not change `issue_date`, so they do not move the entry.

## Was it worth it?

Yes. The default view of the busiest screen went from about a second of database time to under a
millisecond, for 150 MB and no measurable write cost. With the index, the count is what is left,
and that needs a decision about the API rather than another index: this study recommends the
estimate (option 2) for the unfiltered list in the same Duewise release as the index.

## Reproduce

```bash
docker compose exec postgres psql -U duewise -d duewise -f /work/cases/04-invoice-list/run.sql
```

[`run.sql`](run.sql) removes this case's index if present, measures before, creates the index from
[`fix.sql`](fix.sql) and measures again, plus the keyset and estimate alternatives. It leaves the
index in place; [`undo.sql`](undo.sql) removes it.
