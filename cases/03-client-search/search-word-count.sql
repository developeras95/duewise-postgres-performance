-- GET /api/v1/clients?q=agro: the count Spring Data adds for totalElements.
SELECT count(c.id)
FROM client c
WHERE lower(c.name) LIKE '%agro%' ESCAPE '\'
   OR lower(c.email) LIKE '%agro%' ESCAPE '\';
