-- Removes case 5's indexes and materialized view. The other cases' indexes stay.
DROP INDEX IF EXISTS perf_payment_paid_on;
DROP INDEX IF EXISTS perf_payment_paid_on_brin;
DROP MATERIALIZED VIEW IF EXISTS perf_monthly_revenue;
