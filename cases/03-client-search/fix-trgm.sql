-- Case 3, part 1: trigram indexes for "contains" search.
--
-- GIN with gin_trgm_ops (pg_trgm) indexes every three-letter piece of the text, so
-- LIKE '%term%' finds the rows containing all of the term's pieces without reading the table.
-- One index per column, on lower(...), exactly as Duewise searches; PostgreSQL combines them for the
-- OR (BitmapOr).
CREATE INDEX IF NOT EXISTS perf_client_name_trgm ON client USING gin (lower(name) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS perf_client_email_trgm ON client USING gin (lower(email) gin_trgm_ops);
