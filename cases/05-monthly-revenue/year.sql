-- The same report for the last twelve months (November 2025 to October 2026, 1,558,432 payments):
-- a year-to-date or annual summary.
SELECT date_trunc('month', p.paid_on)::date AS month, i.currency_code,
       count(*) AS payments, sum(p.amount) AS received
FROM payment p
JOIN invoice i ON i.id = p.invoice_id
WHERE p.paid_on >= DATE '2025-11-01' AND p.paid_on < DATE '2026-11-01'
GROUP BY 1, 2
ORDER BY 1, 2;
