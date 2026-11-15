-- Case 3: client search, as the client picker and the Clients screen use it. Measures everything:
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/cases/03-client-search/run.sql
--
-- 1. removes this case's indexes if an earlier run left them ("before" is Duewise v1.0.3 plus
--    cases 1, 2 and 4)
-- 2. before: the list without search text; searches for part of an email, a common word (whose
--    matches sort early, and one whose matches sort late) and two letters; the count for the
--    common word; the write cost of adding clients
-- 3. with the trigram indexes (fix-trgm.sql): the same
-- 4. with the name index added as well (fix-name.sql): the same
-- 5. removes the name index again: it made some searches slower than no index (see the README)
-- Timings go to results/timings.csv, plans to cases/03-client-search/plans/.
-- Leaves the trigram indexes in place; undo.sql removes them.

\set ON_ERROR_STOP on
\set QUIET on
\set case 03-client-search

\echo '== Case 3: client search =='
SET client_min_messages = warning;
\ir undo.sql
RESET client_min_messages;
VACUUM (ANALYZE) client;

\set variant before-list
\set query cases/03-client-search/list.sql
\ir ../../harness/measure.sql
\set variant before-search-email
\set query cases/03-client-search/search-email.sql
\ir ../../harness/measure.sql
\set variant before-search-word
\set query cases/03-client-search/search-word.sql
\ir ../../harness/measure.sql
\set variant before-search-word-count
\set query cases/03-client-search/search-word-count.sql
\ir ../../harness/measure.sql
\set variant before-search-late
\set query cases/03-client-search/search-late.sql
\ir ../../harness/measure.sql
\set variant before-search-short
\set query cases/03-client-search/search-short.sql
\ir ../../harness/measure.sql
\set variant before-new-clients
\set query cases/03-client-search/new-clients.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the trigram indexes from fix-trgm.sql ...'
\timing on
\ir fix-trgm.sql
\timing off
VACUUM (ANALYZE) client;
\ir ../../harness/index-size.sql

\set variant trgm-list
\set query cases/03-client-search/list.sql
\ir ../../harness/measure.sql
\set variant trgm-search-email
\set query cases/03-client-search/search-email.sql
\ir ../../harness/measure.sql
\set variant trgm-search-word
\set query cases/03-client-search/search-word.sql
\ir ../../harness/measure.sql
\set variant trgm-search-word-count
\set query cases/03-client-search/search-word-count.sql
\ir ../../harness/measure.sql
\set variant trgm-search-late
\set query cases/03-client-search/search-late.sql
\ir ../../harness/measure.sql
\set variant trgm-search-short
\set query cases/03-client-search/search-short.sql
\ir ../../harness/measure.sql
\set variant trgm-new-clients
\set query cases/03-client-search/new-clients.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the name index from fix-name.sql ...'
\timing on
\ir fix-name.sql
\timing off
VACUUM (ANALYZE) client;
\ir ../../harness/index-size.sql

\set variant trgm-name-list
\set query cases/03-client-search/list.sql
\ir ../../harness/measure.sql
\set variant trgm-name-search-email
\set query cases/03-client-search/search-email.sql
\ir ../../harness/measure.sql
\set variant trgm-name-search-word
\set query cases/03-client-search/search-word.sql
\ir ../../harness/measure.sql
\set variant trgm-name-search-word-count
\set query cases/03-client-search/search-word-count.sql
\ir ../../harness/measure.sql
\set variant trgm-name-search-late
\set query cases/03-client-search/search-late.sql
\ir ../../harness/measure.sql
\set variant trgm-name-search-short
\set query cases/03-client-search/search-short.sql
\ir ../../harness/measure.sql
\set variant trgm-name-new-clients
\set query cases/03-client-search/new-clients.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Removing the name index: the chosen fix is the trigram indexes alone.'
DROP INDEX perf_client_by_name;
