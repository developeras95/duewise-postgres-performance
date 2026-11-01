-- Case 2: the client statement. Measures everything for this case in one go:
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/cases/02-client-statement/run.sql
--
-- The statement is measured for three clients: the largest (295,286 invoices), one at the top-1%
-- boundary (788) and the median (44), plus the write cost of a part payment. That set runs three times:
--   before      Duewise v1.0.3 plus case 1's index (the cases build on each other, as the final
--               migration will)
--   after-lean  with fix-lean.sql: ordered partial index
--   after       with fix.sql: the same plus INCLUDE, so the table is never read (the chosen fix)
-- Leaves fix.sql's index in place; undo.sql removes it.

\set ON_ERROR_STOP on
\set QUIET on
\set case 02-client-statement

\echo '== Case 2: client statement =='
SET client_min_messages = warning;
\ir undo.sql
RESET client_min_messages;
ANALYZE invoice;

\set variant before-largest
\set query cases/02-client-statement/statement-largest.sql
\ir ../../harness/measure.sql

\set variant before-top-1pct
\set query cases/02-client-statement/statement-top-1pct.sql
\ir ../../harness/measure.sql

\set variant before-median
\set query cases/02-client-statement/statement-median.sql
\ir ../../harness/measure.sql
\set variant before-partial-payment
\set query cases/02-client-statement/partial-payment.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

\echo
\echo 'Creating the index from fix-lean.sql ...'
\timing on
\ir fix-lean.sql
\timing off
VACUUM (ANALYZE) invoice;
\ir ../../harness/index-size.sql

\set variant after-lean-largest
\set query cases/02-client-statement/statement-largest.sql
\ir ../../harness/measure.sql

\set variant after-lean-top-1pct
\set query cases/02-client-statement/statement-top-1pct.sql
\ir ../../harness/measure.sql

\set variant after-lean-median
\set query cases/02-client-statement/statement-median.sql
\ir ../../harness/measure.sql
\set variant after-lean-partial-payment
\set query cases/02-client-statement/partial-payment.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false

DROP INDEX perf_invoice_client_statement_lean;
\echo
\echo 'Creating the index from fix.sql ...'
\timing on
\ir fix.sql
\timing off
VACUUM (ANALYZE) invoice;
\ir ../../harness/index-size.sql

\set variant after-largest
\set query cases/02-client-statement/statement-largest.sql
\ir ../../harness/measure.sql

\set variant after-top-1pct
\set query cases/02-client-statement/statement-top-1pct.sql
\ir ../../harness/measure.sql

\set variant after-median
\set query cases/02-client-statement/statement-median.sql
\ir ../../harness/measure.sql
\set variant after-partial-payment
\set query cases/02-client-statement/partial-payment.sql
\set rollback true
\ir ../../harness/measure.sql
\set rollback false
