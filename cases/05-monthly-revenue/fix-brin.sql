-- Option 2: a BRIN (block range) index on the payment date. Instead of one entry per payment it keeps
-- the lowest and highest date of each block of 128 table pages, so it is tiny. It works because
-- payments are stored in roughly the order they are recorded, so each block covers a short span of
-- dates (the correlation between paid_on and the physical order is 0.99999 here).
CREATE INDEX IF NOT EXISTS perf_payment_paid_on_brin ON payment USING brin (paid_on);
