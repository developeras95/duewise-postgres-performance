-- Removes case 3's indexes. The other cases' indexes stay: the cases build on each other.
DROP INDEX IF EXISTS perf_client_name_trgm;
DROP INDEX IF EXISTS perf_client_email_trgm;
DROP INDEX IF EXISTS perf_client_by_name;
