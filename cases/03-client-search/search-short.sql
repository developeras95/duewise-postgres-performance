-- GET /api/v1/clients?q=ag: two letters, as the picker searches while someone is still typing.
-- Trigram indexes need at least three characters to narrow anything down.
SELECT c.id, c.address_line1, c.address_line2, c.city, c.country_code, c.postal_code, c.state,
       c.billing_email, c.created_at, c.default_currency_code, c.email, c.name, c.payment_terms_days,
       c.phone, c.reminders_enabled, c.tax_id, c.updated_at, c.version
FROM client c
WHERE lower(c.name) LIKE '%ag%' ESCAPE '\'
   OR lower(c.email) LIKE '%ag%' ESCAPE '\'
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
