-- GET /api/v1/clients?q=17704: one client, found by a part of its email
-- (bluebird.agro.17704@example.com). The page query Hibernate sends for ClientRepository.search,
-- sorted by name as the client picker and the Clients screen ask for it.
SELECT c.id, c.address_line1, c.address_line2, c.city, c.country_code, c.postal_code, c.state,
       c.billing_email, c.created_at, c.default_currency_code, c.email, c.name, c.payment_terms_days,
       c.phone, c.reminders_enabled, c.tax_id, c.updated_at, c.version
FROM client c
WHERE lower(c.name) LIKE '%17704%' ESCAPE '\'
   OR lower(c.email) LIKE '%17704%' ESCAPE '\'
ORDER BY c.name, c.id
FETCH FIRST 20 ROWS ONLY;
