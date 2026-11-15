-- GET /api/v1/clients?q=agro: a common word, 2,492 clients ("Bluebird Agro Co", ...). The page
-- has 20 of them, sorted by name.
SELECT c.id, c.address_line1, c.address_line2, c.city, c.country_code, c.postal_code, c.state,
       c.billing_email, c.created_at, c.default_currency_code, c.email, c.name, c.payment_terms_days,
       c.phone, c.reminders_enabled, c.tax_id, c.updated_at, c.version
FROM client c
WHERE lower(c.name) LIKE '%agro%' ESCAPE '\'
   OR lower(c.email) LIKE '%agro%' ESCAPE '\'
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
