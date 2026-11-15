-- The fix for case 4: every invoice, in the list's default order.
--
-- * (issue_date DESC, id DESC): the order the Invoices screen opens in, so the first page is read
--   straight from the index and PostgreSQL stops after 20 rows instead of sorting 5 million.
-- * Not partial: the unfiltered list shows invoices in every status. Case 1's smaller partial index
--   stays for the overdue list, where most of these rows would have to be skipped.
-- * No INCLUDE columns: the page needs 25 columns from three tables, and only 20 rows; reading 20
--   table rows costs far less than making the index carry them.
CREATE INDEX IF NOT EXISTS perf_invoice_by_issue_date
    ON invoice (issue_date DESC, id DESC);
