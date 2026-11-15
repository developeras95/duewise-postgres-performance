-- GET /api/v1/invoices?page=500 (no filters): page 501 of 20 rows, 10,000 rows in.
-- Paging by number makes the database produce and throw away every row before the page.
SELECT i.id, i.amount_paid, i.client_id, c.name, c.email, c.billing_email, c.payment_terms_days,
       i.created_at, i.currency_code, cu.symbol, cu.minor_units, i.due_date, i.invoice_number,
       i.issue_date, i.notes, i.paid_at, i.sent_at, i.status, i.subtotal, i.tax_total, i.total,
       i.updated_at, i.version, i.void_reason, i.voided_at
FROM invoice i
JOIN client c ON c.id = i.client_id
JOIN currency cu ON cu.code = i.currency_code
ORDER BY i.issue_date DESC, i.id DESC
OFFSET 10000 ROWS
FETCH NEXT 20 ROWS ONLY;
