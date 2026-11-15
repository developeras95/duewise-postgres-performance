# Case 3: client search

**Result:** two trigram indexes (7 MB together) take a search for part of a client's name or email
from **18–20 ms to 0.04–1.8 ms**. A third index, on the order the list is shown in, made the
unfiltered list 500× faster but some searches **slower than with no index at all**, so it is not
part of the fix. Searches of one or two letters stay at 20 ms: trigrams need three.

Measured on 50,001 clients (an 11 MB table) beside 5,000,002 invoices, median of 11 warm runs;
hardware and settings in the [main README](../../README.md#hardware). Cases 1, 2 and 4's indexes are
in place throughout.

## The request

`GET /api/v1/clients?q=...`, sorted by name: what the web app's client picker sends on every
keystroke (after a short pause), and what the Clients screen sends when someone searches. Duewise
looks for the text anywhere in the name or the email, ignoring case
([`ClientRepository.search`](https://github.com/developeras95/duewise-invoicing-api)):

```sql
SELECT c.* FROM client c
WHERE lower(c.name) LIKE '%agro%' ESCAPE '\'
   OR lower(c.email) LIKE '%agro%' ESCAPE '\'
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
```

A B-tree index cannot help with `LIKE '%term%'`: the term can start anywhere, so there is no place in
a sorted list to start looking. Every search reads all 50,001 clients, lowercases two columns of
each and sorts the matches.

Measured searches, chosen to show where each index helps and where it does not:

| Query | Search | Matches | What it tests |
| --- | --- | ---: | --- |
| [`list.sql`](list.sql) | none | 50,001 | the picker as it opens: first 20 by name |
| [`search-email.sql`](search-email.sql) | `17704` | 1 | part of an email |
| [`search-word.sql`](search-word.sql) | `agro` | 2,492 | a common word; its matches sort early ("Bluebird Agro Co") |
| [`search-late.sql`](search-late.sql) | `yamuna` | 1,679 | a common word; its matches all sort last ("Yamuna ...") |
| [`search-short.sql`](search-short.sql) | `ag` | 4,917 | two letters, while someone is still typing |
| [`search-word-count.sql`](search-word-count.sql) | `agro` | | the count beside the page |

## The fix

`pg_trgm` splits text into three-letter pieces (trigrams), and a GIN index with `gin_trgm_ops`
lists, for each piece, the rows that contain it. For `LIKE '%agro%'` PostgreSQL looks up the pieces
of "agro" (`agr`, `gro`), keeps the rows that have all of them, and checks only those ([`fix-trgm.sql`](fix-trgm.sql)):

```sql
CREATE INDEX perf_client_name_trgm  ON client USING gin (lower(name)  gin_trgm_ops);
CREATE INDEX perf_client_email_trgm ON client USING gin (lower(email) gin_trgm_ops);
```

They index `lower(...)` because that is what Duewise searches, and there is one per column, which
PostgreSQL combines for the `OR` ([plan](plans/trgm-search-late.txt)):

```
Limit
  ->  Sort  (top-N heapsort)
        ->  Bitmap Heap Scan on client c  (actual rows=1679)
              ->  BitmapOr
                    ->  Bitmap Index Scan on perf_client_name_trgm   (actual rows=1679)
                    ->  Bitmap Index Scan on perf_client_email_trgm
```

## The index that made things worse

The unfiltered list (the picker as it opens) still sorts all 50,001 clients for 20 rows, so the
obvious next step was an index in the list's order ([`fix-name.sql`](fix-name.sql)):

```sql
CREATE INDEX perf_client_by_name ON client (name, id);
```

It does fix the list: 12.5 ms to 0.023 ms. But PostgreSQL also starts using it for searches. For a
search with thousands of expected matches it reasons that walking the clients in name order and
stopping at the 20th match beats finding all matches and sorting them. That is right for "agro",
whose matches start at "Bluebird Agro Co", and very wrong for "yamuna", whose matches are all at
the end of the alphabet ([plan](plans/trgm-name-search-late.txt)):

```
Limit  (actual time=28.855..28.866 rows=20)
  ->  Index Scan using perf_client_by_name on client c
        Filter: ((lower(name) ~~ '%yamuna%') OR (lower(email) ~~ '%yamuna%'))
        Rows Removed by Filter: 48322
        Buffers: shared hit=48361
```

48,322 clients read one by one in name order, to throw them away: 23 ms, slower than the 18 ms of no
index at all. PostgreSQL cannot know where in the alphabet the matches are, so which searches are
fast depends on luck in the data. The name index is therefore measured, documented, and left out.

## Results

| | Before | Trigram indexes (**the fix**) | + name index |
| --- | ---: | ---: | ---: |
| List, no search | 12.5 ms | 13.0 ms | 0.023 ms |
| Part of an email, 1 match | 18.3 ms | **0.044 ms** | 0.034 ms |
| Common word, early matches | 19.9 ms | **1.8 ms** | 0.027 ms |
| Common word, late matches | 18.4 ms | **1.5 ms** | 23.1 ms ⚠ |
| Its count | 18.8 ms | **1.2 ms** | 1.1 ms |
| Two letters | 20.2 ms | 19.9 ms | 0.031 ms |
| Adding 1,000 clients | 17.4 ms | 23.4 ms | 23.4 ms |
| Index size | | 2.7 + 3.9 MB | + 2.5 MB |
| Build time | | 0.15 + 0.24 s | + 0.05 s |

With the trigram indexes every search of three letters or more costs under 2 ms, whatever the data,
because the work depends on the number of matches, not on where they sort. The two-letter search does
not change: a two-letter term has no complete trigram to look up, so PostgreSQL reads the table
([plan](plans/trgm-search-short.txt)).

## The cost

- **Size:** 6.6 MB for an 11 MB table. (The second size listing printed by `run.sql` shows the
  trigram indexes at 7 and 8 MB: that is after 15,000 test inserts that were rolled back. GIN keeps
  the space for reuse after `VACUUM` rather than giving it back.)
- **Writes:** adding a client writes an entry for every three-letter piece of its name and email,
  a few dozen per client. 1,000 clients took 23.4 ms instead of 17.4 ms, **+34%**, about 6 µs per client,
  and 14,098 pages touched instead of 9,498. More than half of the insert time is the foreign key check on the
  currency, before and after. Clients are added one at a time, by people; 6 µs is not noticeable.

## Was it worth it?

At 50,000 clients search was never slow: 20 ms per keystroke is fine for one person typing. The fix
is worth having because the cost grows with the table (a full read of every client per keystroke,
times everyone typing) while the trigram search grows only with the number of matches, and because
it is cheap: 6.6 MB and 6 µs per new client.

What to leave alone is as useful a finding: the name index makes the first screen faster by 12 ms and
makes some searches slower in a way no one could predict from the search text. If the unfiltered
list ever needs it, the search query should first stop sharing the list's sort order with it (for
example, sorting search results by relevance), so that PostgreSQL never walks the name index for a
search.

## Reproduce

```bash
docker compose exec postgres psql -U duewise -d duewise -f /work/cases/03-client-search/run.sql
```

[`run.sql`](run.sql) removes this case's indexes if present, measures before, with the trigram
indexes, and with the name index added; then it removes the name index again, leaving the chosen fix
in place. [`undo.sql`](undo.sql) removes the rest.
