-- Write cost: adding clients. 1,000 new clients as POST /api/v1/clients inserts them; every index on
-- client takes each one, and trigram indexes take one entry per three-letter piece of the text.
-- Timed with rollback=true, so nothing changes. The ids are given rather than drawn from the
-- identity column, so the runs do not use up its numbers.
INSERT INTO client (id, name, email, default_currency_code, payment_terms_days)
OVERRIDING SYSTEM VALUE
SELECT 900000000 + g, 'Perf Test Traders ' || g, 'perf.test.' || g || '@example.com', 'INR', 30
FROM generate_series(1, 1000) AS g;
