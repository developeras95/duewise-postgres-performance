-- GET /api/v1/clients?q=yamuna: a common word whose matches all sort near the end of the alphabet
-- (1,679 clients named "Yamuna ..."). Tests what happens when the list's name order and the search
-- pull in different directions.
SELECT c.id, c.address_line1, c.address_line2, c.city, c.country_code, c.postal_code, c.state,
       c.billing_email, c.created_at, c.default_currency_code, c.email, c.name, c.payment_terms_days,
       c.phone, c.reminders_enabled, c.tax_id, c.updated_at, c.version
FROM client c
WHERE lower(c.name) LIKE '%yamuna%' ESCAPE '\'
   OR lower(c.email) LIKE '%yamuna%' ESCAPE '\'
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
