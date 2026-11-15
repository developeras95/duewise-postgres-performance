-- Case 3, part 2: the order every client list is shown in, so the first page without search text
-- is read from the index instead of sorting every client. Measured on top of part 1, because it
-- also changes how PostgreSQL runs searches (see the README).
CREATE INDEX IF NOT EXISTS perf_client_by_name ON client (name, id);
