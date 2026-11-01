-- Write cost: what recording a payment does to the invoice row. 1,000 open invoices become PAID,
-- the UPDATE Duewise runs after inserting each payment. Timed with rollback=true, so nothing changes.
UPDATE invoice
SET amount_paid = total, status = 'PAID', paid_at = TIMESTAMPTZ '2026-11-01 10:00+00',
    updated_at = TIMESTAMPTZ '2026-11-01 10:00+00', version = version + 1
WHERE id IN (SELECT id FROM invoice WHERE status = 'SENT' ORDER BY id LIMIT 1000);
