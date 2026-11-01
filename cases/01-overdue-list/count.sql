-- GET /api/v1/invoices?overdue=true: the count query Spring Data adds to fill "totalElements"
-- and "totalPages" in the response. Same filter, no joins.
SELECT count(i.id)
FROM invoice i
WHERE i.status IN ('SENT', 'PARTIALLY_PAID')
  AND i.due_date < DATE '2026-11-01';
