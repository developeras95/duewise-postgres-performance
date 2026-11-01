-- The alternative measured for comparison: the same index without INCLUDE. Half the size, but each
-- row it finds still has to be read from the table.
CREATE INDEX IF NOT EXISTS perf_invoice_client_statement_lean
    ON invoice (client_id, currency_code, due_date, id)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');
