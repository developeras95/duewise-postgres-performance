-- GET /api/v1/clients (no search text): the first 20 clients by name. What the client picker shows
-- when it opens, and the Clients screen's first page.
SELECT c.id, c.address_line1, c.address_line2, c.city, c.country_code, c.postal_code, c.state,
       c.billing_email, c.created_at, c.default_currency_code, c.email, c.name, c.payment_terms_days,
       c.phone, c.reminders_enabled, c.tax_id, c.updated_at, c.version
FROM client c
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
