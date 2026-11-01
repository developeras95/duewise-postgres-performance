-- Example for trying the harness: open invoices of one client, newest first
SELECT id, invoice_number, issue_date, due_date, total - amount_paid AS balance
FROM invoice
WHERE client_id = 42 AND status IN ('SENT', 'PARTIALLY_PAID')
ORDER BY issue_date DESC
LIMIT 50;
