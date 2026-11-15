-- Write cost: recording payments. 1,000 payments as POST /api/v1/invoices/{id}/payments inserts them
-- (without the invoice update, measured in cases 1 and 2). Every index on payment takes each one.
-- Timed with rollback=true, so nothing changes; the ids are given rather than drawn from the identity
-- column, so the runs do not use up its numbers.
INSERT INTO payment (id, invoice_id, payment_method_id, amount, paid_on)
OVERRIDING SYSTEM VALUE
SELECT 900000000 + g, g, 2, 100.000, DATE '2026-11-14'
FROM generate_series(1, 1000) AS g;
