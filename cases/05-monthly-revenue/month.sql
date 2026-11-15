-- A revenue report Duewise does not have yet: money received per month and currency, here for
-- one month (October 2026, 156,345 payments). Currency is on the invoice, so every payment is joined
-- to its invoice: amounts in different currencies cannot be added together.
SELECT date_trunc('month', p.paid_on)::date AS month, i.currency_code,
       count(*) AS payments, sum(p.amount) AS received
FROM payment p
JOIN invoice i ON i.id = p.invoice_id
WHERE p.paid_on >= DATE '2026-10-01' AND p.paid_on < DATE '2026-11-01'
GROUP BY 1, 2
ORDER BY 1, 2;
