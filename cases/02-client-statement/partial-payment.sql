-- Write cost: a part payment on 1,000 sent invoices. They stay open, so they stay in this case's
-- index, and amount_paid (which the covering index carries) changes. Timed with rollback=true.
UPDATE invoice
SET amount_paid = round(total / 2, 2), status = 'PARTIALLY_PAID',
    updated_at = TIMESTAMPTZ '2026-11-01 10:00+00', version = version + 1
WHERE id IN (SELECT id FROM invoice WHERE status = 'SENT' ORDER BY id LIMIT 1000);
