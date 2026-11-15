-- Option 1: a B-tree on the payment date, covering the two other columns the report reads from
-- payment, so the payments of a period are found without reading the table. 4.6 million entries.
CREATE INDEX IF NOT EXISTS perf_payment_paid_on ON payment (paid_on) INCLUDE (invoice_id, amount);
