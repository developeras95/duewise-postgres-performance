-- Removes case 2's indexes. Case 1's index is left alone.
DROP INDEX IF EXISTS perf_invoice_client_statement;
DROP INDEX IF EXISTS perf_invoice_client_statement_lean;
