-- Write cost: creating invoices. 1,000 new drafts, as POST /api/v1/invoices inserts them (without
-- their lines, which live in another table). Every index on invoice has to take each new row.
-- Timed with rollback=true, so nothing changes. The ids are given (far above the generated ones)
-- rather than drawn from the identity column, so the runs do not use up its numbers. The drafts are
-- spread over every client, at any scale the generator was run with.
INSERT INTO invoice (id, client_id, issue_date, due_date, currency_code, status)
OVERRIDING SYSTEM VALUE
SELECT 900000000 + g, 1 + g % (SELECT count(*) FROM client), DATE '2026-11-01', DATE '2026-12-01', 'INR', 'DRAFT'
FROM generate_series(1, 1000) AS g;
