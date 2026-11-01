-- GET /api/v1/invoices?overdue=true (first page, default sort: newest issue date first)
-- The page query Hibernate sends for InvoiceRepository.findAll(spec, pageable), with the
-- @EntityGraph loading client and currency in the same query.
SELECT i.id, i.amount_paid, i.client_id, c.name, c.email, c.billing_email, c.payment_terms_days,
       i.created_at, i.currency_code, cu.symbol, cu.minor_units, i.due_date, i.invoice_number,
       i.issue_date, i.notes, i.paid_at, i.sent_at, i.status, i.subtotal, i.tax_total, i.total,
       i.updated_at, i.version, i.void_reason, i.voided_at
FROM invoice i
JOIN client c ON c.id = i.client_id
JOIN currency cu ON cu.code = i.currency_code
WHERE i.status IN ('SENT', 'PARTIALLY_PAID')
  AND i.due_date < DATE '2026-11-01'
ORDER BY i.issue_date DESC, i.id DESC
FETCH FIRST 20 ROWS ONLY;
