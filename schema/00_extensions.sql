-- Runs first (files in this folder run in name order when the database is created).
-- pg_stat_statements records totals for every query; pg_trgm is needed for case 3 (text search).
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
