-- The fix for case 1: open invoices only, in the list's sort order, with the due date in the index.
--
-- * Partial (WHERE status IN ...): only the ~670,000 open invoices, not all 5 million, so the index
--   stays small (26 MB) and paid invoices never have to be skipped.
-- * (issue_date DESC, id DESC): the list's default order, so the first page is read straight from
--   the index and PostgreSQL stops after 20 rows instead of sorting every overdue invoice.
-- * due_date as the last key column: "due_date < today" is checked inside the index, and together
--   with id it lets the count query be answered from the index alone (an index-only scan).
CREATE INDEX IF NOT EXISTS perf_invoice_open_by_issue_date
    ON invoice (issue_date DESC, id DESC, due_date)
    WHERE status IN ('SENT', 'PARTIALLY_PAID');
