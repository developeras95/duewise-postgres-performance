-- The same page 501, asked for by position instead of number ("keyset" or "seek" paging): the 20
-- invoices that come after the last one on the previous page, here (30 Oct 2026, id 4746381), the
-- 10,000th invoice in the generated data. Duewise does not offer this today; it would need the
-- previous page's last issue date and id as parameters instead of a page number.
SELECT i.id, i.amount_paid, i.client_id, c.name, c.email, c.billing_email, c.payment_terms_days,
       i.created_at, i.currency_code, cu.symbol, cu.minor_units, i.due_date, i.invoice_number,
       i.issue_date, i.notes, i.paid_at, i.sent_at, i.status, i.subtotal, i.tax_total, i.total,
       i.updated_at, i.version, i.void_reason, i.voided_at
FROM invoice i
JOIN client c ON c.id = i.client_id
JOIN currency cu ON cu.code = i.currency_code
WHERE (i.issue_date, i.id) < (DATE '2026-10-30', 4746381)
ORDER BY i.issue_date DESC, i.id DESC
FETCH FIRST 20 ROWS ONLY;
