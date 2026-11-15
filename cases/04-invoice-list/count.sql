-- GET /api/v1/invoices (no filters): the count query Spring Data adds to fill "totalElements"
-- and "totalPages". With no filter, it counts every invoice.
SELECT count(i.id)
FROM invoice i;
