-- Option 3: compute the report once and store it. A materialized view holds one row per month and
-- currency (a few hundred rows instead of 4.6 million payments); the report reads it directly.
-- It is a copy: payments recorded after the last REFRESH are not in it until the next one. The
-- unique index allows REFRESH ... CONCURRENTLY, which keeps the old copy readable while it rebuilds.
CREATE MATERIALIZED VIEW IF NOT EXISTS perf_monthly_revenue AS
SELECT date_trunc('month', p.paid_on)::date AS month, i.currency_code,
       count(*) AS payments, sum(p.amount) AS received
FROM payment p
JOIN invoice i ON i.id = p.invoice_id
GROUP BY 1, 2;
CREATE UNIQUE INDEX IF NOT EXISTS perf_monthly_revenue_key ON perf_monthly_revenue (month, currency_code);
