-- An alternative to counting: PostgreSQL's own estimate of the table's row count, kept up to date
-- by autovacuum and ANALYZE. Accurate to within a fraction of a percent on this table, and free.
-- Only usable for the unfiltered list, and shown as "about 5,000,000".
SELECT reltuples::bigint AS estimated_invoices
FROM pg_class
WHERE oid = 'invoice'::regclass;
