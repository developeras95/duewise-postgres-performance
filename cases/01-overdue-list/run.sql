-- Case 1: the overdue invoices list. Measures everything for this case in one go:
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/cases/01-overdue-list/run.sql
--
-- 1. removes the fix if an earlier run left it, so "before" really is Duewise v1.0.3
-- 2. before: the page query, the count query and the write cost (recording payments)
-- 3. creates the index from fix.sql and records its size and build time
-- 4. after: the same three measurements
-- Timings go to results/timings.csv, plans to cases/01-overdue-list/plans/.
-- Leaves the fix in place; undo.sql removes it.

\set ON_ERROR_STOP on
\set QUIET on
\set case 01-overdue-list

\echo '== Case 1: overdue invoices list =='
SET client_min_messages = warning;
\ir undo.sql
RESET client_min_messages;
ANALYZE invoice;

\set variant before-page
\set query cases/01-overdue-list/page.sql
\ir ../../harness/measure.sql
\set variant before-count
\set query cases/01-overdue-list/count.sql
\ir ../../harness/measure.sql
\set variant before-record-payment
\set query cases/01-overdue-list/record-payment.sql
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
\set query cases/01-overdue-list/page.sql
\ir ../../harness/measure.sql
\set variant after-count
\set query cases/01-overdue-list/count.sql
\ir ../../harness/measure.sql
\set variant after-record-payment
\set query cases/01-overdue-list/record-payment.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false
