-- GET /api/v1/clients/20250/statement: the client's open invoices, exactly as StatementRepository sends
-- them (Duewise v1.0.3), for the median client (44 invoices, 4 open).
SELECT i.id,
       i.invoice_number,
       i.currency_code,
       c.minor_units,
       i.issue_date,
       i.due_date,
       i.total - i.amount_paid                             AS balance_due,
       GREATEST(CAST(DATE '2026-11-01' AS date) - i.due_date, 0) AS days_overdue
FROM invoice i
JOIN currency c ON c.code = i.currency_code
WHERE i.client_id = 20250
  AND i.status IN ('SENT', 'PARTIALLY_PAID')
ORDER BY i.currency_code, i.due_date, i.id;
