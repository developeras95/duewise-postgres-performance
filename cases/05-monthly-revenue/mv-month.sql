-- The report for October 2026, read from the materialized view (fix-mv.sql).
SELECT month, currency_code, payments, received
FROM perf_monthly_revenue
WHERE month >= DATE '2026-10-01' AND month < DATE '2026-11-01'
ORDER BY 1, 2;
