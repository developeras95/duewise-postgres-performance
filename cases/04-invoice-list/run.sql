-- Case 4: the invoice list as it first opens, with no filters. Measures everything in one go:
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/cases/04-invoice-list/run.sql
--
-- 1. removes the fix if an earlier run left it ("before" is Duewise v1.0.3 plus cases 1 and 2)
-- 2. before: the first page, the count, page 501, and the write cost of creating drafts
-- 3. creates the index from fix.sql and records its size and build time
-- 4. after: the same, plus two alternatives Duewise does not use yet: keyset paging and the
--    estimated count
-- Timings go to results/timings.csv, plans to cases/04-invoice-list/plans/.
-- Leaves the fix in place; undo.sql removes it.

\set ON_ERROR_STOP on
\set QUIET on
\set case 04-invoice-list

\echo '== Case 4: invoice list, no filters =='
SET client_min_messages = warning;
\ir undo.sql
RESET client_min_messages;
VACUUM (ANALYZE) invoice;

\set variant before-page
\set query cases/04-invoice-list/page.sql
\ir ../../harness/measure.sql
\set variant before-count
\set query cases/04-invoice-list/count.sql
\ir ../../harness/measure.sql
\set variant before-page-501
\set query cases/04-invoice-list/page-501.sql
\ir ../../harness/measure.sql
\set variant before-new-drafts
\set query cases/04-invoice-list/new-drafts.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the index from fix.sql ...'
\timing on
\ir fix.sql
\timing off
VACUUM (ANALYZE) invoice;
\ir ../../harness/index-size.sql

\set variant after-page
\set query cases/04-invoice-list/page.sql
\ir ../../harness/measure.sql
\set variant after-count
\set query cases/04-invoice-list/count.sql
\ir ../../harness/measure.sql
\set variant after-page-501
\set query cases/04-invoice-list/page-501.sql
\ir ../../harness/measure.sql
\set variant after-keyset-501
\set query cases/04-invoice-list/keyset.sql
\ir ../../harness/measure.sql
\set variant count-estimate
\set query cases/04-invoice-list/count-estimate.sql
\ir ../../harness/measure.sql
\set variant after-new-drafts
\set query cases/04-invoice-list/new-drafts.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false
