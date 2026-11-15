-- Case 5: a monthly revenue report. Measures everything in one go:
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/cases/05-monthly-revenue/run.sql
--
-- The report (money received per month and currency) is measured for one month and for twelve,
-- with the write cost of recording payments, in four states:
--   before   Duewise v1.0.3 plus cases 1 to 4
--   btree    with a covering B-tree on the payment date (fix-btree.sql), then removed
--   brin     with a BRIN index on the payment date (fix-brin.sql)
--   mv       read from a materialized view (fix-mv.sql), plus the time to refresh it
-- Timings go to results/timings.csv, plans to cases/05-monthly-revenue/plans/.
-- Leaves the BRIN index and the materialized view in place; undo.sql removes them.

\set ON_ERROR_STOP on
\set QUIET on
\set case 05-monthly-revenue

\echo '== Case 5: monthly revenue report =='
SET client_min_messages = warning;
\ir undo.sql
RESET client_min_messages;
VACUUM (ANALYZE) payment;

\set variant before-month
\set query cases/05-monthly-revenue/month.sql
\ir ../../harness/measure.sql
\set variant before-year
\set query cases/05-monthly-revenue/year.sql
\ir ../../harness/measure.sql
\set variant before-record-payments
\set query cases/05-monthly-revenue/record-payments.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the B-tree from fix-btree.sql ...'
\timing on
\ir fix-btree.sql
\timing off
VACUUM (ANALYZE) payment;
\ir ../../harness/index-size.sql

\set variant btree-month
\set query cases/05-monthly-revenue/month.sql
\ir ../../harness/measure.sql
\set variant btree-year
\set query cases/05-monthly-revenue/year.sql
\ir ../../harness/measure.sql
\set variant btree-record-payments
\set query cases/05-monthly-revenue/record-payments.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

DROP INDEX perf_payment_paid_on;

\echo
\echo 'Creating the BRIN index from fix-brin.sql ...'
\timing on
\ir fix-brin.sql
\timing off
VACUUM (ANALYZE) payment;
\ir ../../harness/index-size.sql

\set variant brin-month
\set query cases/05-monthly-revenue/month.sql
\ir ../../harness/measure.sql
\set variant brin-year
\set query cases/05-monthly-revenue/year.sql
\ir ../../harness/measure.sql
\set variant brin-record-payments
\set query cases/05-monthly-revenue/record-payments.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the materialized view from fix-mv.sql ...'
\timing on
\ir fix-mv.sql
\timing off
ANALYZE perf_monthly_revenue;
SELECT count(*) AS rows, pg_size_pretty(pg_total_relation_size('perf_monthly_revenue')) AS size
FROM perf_monthly_revenue;

\set variant mv-month
\set query cases/05-monthly-revenue/mv-month.sql
\ir ../../harness/measure.sql
\set variant mv-year
\set query cases/05-monthly-revenue/mv-year.sql
\ir ../../harness/measure.sql

\echo
\echo 'Refreshing the materialized view (CONCURRENTLY, as an application would), three times ...'
\timing on
REFRESH MATERIALIZED VIEW CONCURRENTLY perf_monthly_revenue;
REFRESH MATERIALIZED VIEW CONCURRENTLY perf_monthly_revenue;
REFRESH MATERIALIZED VIEW CONCURRENTLY perf_monthly_revenue;
\timing off
