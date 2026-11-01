-- Checks the generated data after generate.sql has run.
--
--   psql -U duewise -d duewise -f /work/generator/validate.sql
--
-- "today" is the fixed study date the generator used (2026-11-01). Pass -v today=... if you
-- generated with a different one.
--
-- Part 1 lists rule checks. Every row must show 0 problems; the script stops with an error if any
-- does not. The generator loads rows with foreign keys and triggers switched off for speed, so this
-- is where we prove the data would have passed them.
-- Part 2 prints the shape of the data (statuses, currencies, client skew, lines per invoice) so it
-- can be compared with what the README promises.

\set ON_ERROR_STOP on
\set QUIET on
\if :{?today}
\else
    \set today 2026-11-01
\endif
\pset footer off

\echo
\echo 'Part 1: rule checks (every count must be 0)'
CREATE TEMP TABLE check_result AS
SELECT * FROM (
    SELECT 'invoice without a client' AS rule,
           count(*) AS problems
    FROM invoice AS i LEFT JOIN client AS c ON c.id = i.client_id WHERE c.id IS NULL
    UNION ALL
    SELECT 'invoice with an unknown currency',
           count(*)
    FROM invoice AS i LEFT JOIN currency AS cu ON cu.code = i.currency_code WHERE cu.code IS NULL
    UNION ALL
    SELECT 'line item without an invoice',
           count(*)
    FROM invoice_line_item AS l LEFT JOIN invoice AS i ON i.id = l.invoice_id WHERE i.id IS NULL
    UNION ALL
    SELECT 'payment without an invoice',
           count(*)
    FROM payment AS p LEFT JOIN invoice AS i ON i.id = p.invoice_id WHERE i.id IS NULL
    UNION ALL
    SELECT 'payment with an unknown method',
           count(*)
    FROM payment AS p LEFT JOIN payment_method AS m ON m.id = p.payment_method_id WHERE m.id IS NULL
    UNION ALL
    SELECT 'invoice without line items',
           count(*)
    FROM invoice AS i WHERE NOT EXISTS (SELECT 1 FROM invoice_line_item AS l WHERE l.invoice_id = i.id)
    UNION ALL
    SELECT 'invoice totals differ from its lines',
           count(*)
    FROM invoice AS i
    JOIN (SELECT invoice_id, sum(line_subtotal) AS s, sum(line_tax) AS t
          FROM invoice_line_item GROUP BY invoice_id) AS l ON l.invoice_id = i.id
    WHERE i.subtotal <> l.s OR i.tax_total <> l.t
    UNION ALL
    SELECT 'line subtotal is not quantity x price',
           count(*)
    FROM invoice_line_item WHERE line_subtotal <> round(quantity * unit_price, 2)
    UNION ALL
    SELECT 'amount_paid differs from its payments',
           count(*)
    FROM invoice AS i
    LEFT JOIN (SELECT invoice_id, sum(amount) AS paid FROM payment GROUP BY invoice_id) AS p
           ON p.invoice_id = i.id
    WHERE i.amount_paid <> coalesce(p.paid, 0)
    UNION ALL
    SELECT 'status does not match amount_paid',
           count(*)
    FROM invoice
    WHERE (status = 'PAID' AND amount_paid <> total)
       OR (status = 'PARTIALLY_PAID' AND NOT (amount_paid > 0 AND amount_paid < total))
       OR (status IN ('DRAFT', 'SENT', 'VOID') AND amount_paid <> 0)
    UNION ALL
    SELECT 'timestamps do not match status',
           count(*)
    FROM invoice
    WHERE (status = 'DRAFT' AND (invoice_number IS NOT NULL OR sent_at IS NOT NULL))
       OR (status <> 'DRAFT' AND sent_at IS NULL)
       OR ((status = 'PAID') <> (paid_at IS NOT NULL))
       OR ((status = 'VOID') <> (voided_at IS NOT NULL))
    UNION ALL
    SELECT 'payment outside issue date .. day before today',
           count(*)
    FROM payment AS p JOIN invoice AS i ON i.id = p.invoice_id
    WHERE p.paid_on < i.issue_date OR p.paid_on >= date :'today'
    UNION ALL
    SELECT 'invoice number does not match its issue year',
           count(*)
    FROM invoice
    WHERE invoice_number IS NOT NULL
      AND invoice_number NOT LIKE 'INV-' || extract(year FROM issue_date)::int || '-%'
    UNION ALL
    SELECT 'counter behind the highest number of its year',
           count(*)
    FROM (SELECT extract(year FROM issue_date)::int AS y,
                 max(split_part(invoice_number, '-', 3)::int) AS highest
          FROM invoice WHERE invoice_number IS NOT NULL GROUP BY 1) AS n
    LEFT JOIN invoice_number_counter AS c ON c.invoice_year = n.y
    WHERE c.last_value IS DISTINCT FROM n.highest
    UNION ALL
    SELECT 'identity sequence behind the data (client)',
           CASE WHEN coalesce(pg_sequence_last_value(pg_get_serial_sequence('client', 'id')::regclass), 0)
                     >= (SELECT coalesce(max(id), 0) FROM client) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'identity sequence behind the data (invoice)',
           CASE WHEN coalesce(pg_sequence_last_value(pg_get_serial_sequence('invoice', 'id')::regclass), 0)
                     >= (SELECT coalesce(max(id), 0) FROM invoice) THEN 0 ELSE 1 END
) AS checks;

SELECT rule, problems, CASE WHEN problems = 0 THEN 'ok' ELSE 'FAILED' END AS result FROM check_result;

DO $$
DECLARE failed int;
BEGIN
    SELECT count(*) INTO failed FROM check_result WHERE problems <> 0;
    IF failed > 0 THEN
        RAISE EXCEPTION '% rule check(s) failed', failed;
    END IF;
END $$;

\echo
\echo 'Part 2: shape of the data'
\echo
\echo 'Invoices by status'
SELECT status, to_char(count(*), 'FM999,999,999') AS invoices,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percent
FROM invoice GROUP BY status ORDER BY count(*) DESC;

\echo 'Invoices by currency'
SELECT currency_code, to_char(count(*), 'FM999,999,999') AS invoices,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percent
FROM invoice GROUP BY currency_code ORDER BY count(*) DESC;

\echo 'Client skew: share of invoices held by the largest clients'
WITH per_client AS (
    SELECT client_id, count(*) AS n, row_number() OVER (ORDER BY count(*) DESC) AS rank
    FROM invoice GROUP BY client_id
), clients AS (SELECT count(*) AS total FROM client)
SELECT label, round(100.0 * sum(n) / (SELECT count(*) FROM invoice), 1) AS percent_of_invoices
FROM per_client, clients,
     LATERAL (VALUES ('largest 1% of clients', 0.01), ('largest 10% of clients', 0.10)) AS v(label, share)
WHERE rank <= greatest(1, ceil(total * share))
GROUP BY label ORDER BY label;

\echo 'Line items and payments per invoice'
SELECT round((SELECT count(*) FROM invoice_line_item)::numeric / nullif((SELECT count(*) FROM invoice), 0), 2)
           AS lines_per_invoice,
       round((SELECT count(*) FROM payment)::numeric / nullif((SELECT count(*) FROM invoice), 0), 2)
           AS payments_per_invoice,
       (SELECT min(issue_date) FROM invoice) AS first_issue,
       (SELECT max(issue_date) FROM invoice) AS last_issue;

\echo 'Overdue on the study date (open invoices past their due date)'
SELECT to_char(count(*), 'FM999,999,999') AS overdue_invoices
FROM invoice
WHERE status IN ('SENT', 'PARTIALLY_PAID') AND due_date < date :'today';

\echo 'Table sizes'
SELECT relname AS "table",
       to_char(n_live_tup, 'FM999,999,999') AS "rows (estimate)",
       pg_size_pretty(pg_relation_size(relid)) AS heap,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes,
       pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_stat_user_tables
WHERE relname IN ('client', 'invoice', 'invoice_line_item', 'payment')
ORDER BY pg_total_relation_size(relid) DESC;
