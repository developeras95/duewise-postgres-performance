-- The fix for case 2: each client's open invoices, in the statement's order, carrying every column
-- the statement prints.
--
-- * Partial (WHERE status IN ...): only open invoices, so a client's paid history (88% of their
--   invoices) is never read.
-- * (client_id, currency_code, due_date, id): one client's rows sit together, already in the
--   statement's ORDER BY, so there is no sort.
-- * INCLUDE (...): the other columns the statement shows, so it is answered from the index alone and
--   the table is never visited (an index-only scan). INCLUDE columns are stored but not sorted on.
CREATE INDEX IF NOT EXISTS perf_invoice_client_statement
    ON invoice (client_id, currency_code, due_date, id)
    INCLUDE (invoice_number, issue_date, total, amount_paid)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');
