-- Fills the Duewise tables with realistic, reproducible data.
--
--   docker compose exec postgres psql -U duewise -d duewise -v invoices=5000000 -f /work/generator/generate.sql
--
-- Parameters (psql -v name=value), all optional:
--   invoices  number of invoices (default 5000000); clients = invoices / 100, at least 10
--   seed      changes all random choices; the same seed always produces the same data (default 42)
--
-- "Today" is fixed at 2026-11-01, so overdue days and ageing are the same on every run and machine.
-- Randomness comes from a hash of (row number, seed), not from random(), so results do not depend on
-- row order, parallel workers or how many times the script ran before.
--
-- Existing clients, invoices, line items, payments and reminder log rows are deleted first.
-- Reference data (currencies, payment methods, reminder settings) is kept.

\set ON_ERROR_STOP on
\if :{?invoices}
\else
  \set invoices 5000000
\endif
\if :{?seed}
\else
  \set seed 42
\endif
\set today 2026-11-01
\timing on
\pset footer off

SELECT greatest(10, :invoices / 100) AS clients \gset
\echo
\echo 'Generating' :invoices 'invoices for' :clients 'clients (seed' :seed ', today' :today ')'

-- ---- helpers ---------------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS gen;

-- Uniform number in [0, 1) from a row key and a salt; same inputs give the same number every time.
CREATE OR REPLACE FUNCTION gen.rnd(n bigint, salt integer) RETURNS double precision
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$ SELECT (hashint8extended(n, salt) & 9007199254740991)::double precision / 9007199254740992.0 $$;

-- One element of an array, chosen by r in [0, 1).
CREATE OR REPLACE FUNCTION gen.pick(choices text[], r double precision) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$ SELECT choices[1 + floor(r * cardinality(choices))::integer] $$;

-- ---- start clean ------------------------------------------------------------------------------
\echo '1/8 Removing previous data'
TRUNCATE payment, invoice_line_item, reminder_log, invoice, client, invoice_number_counter RESTART IDENTITY;
DROP TABLE IF EXISTS gen.inv, gen.line, gen.inv_total, gen.pay;

-- Foreign keys are checked by triggers; switching them off makes the bulk load several times faster.
-- The data is consistent by construction, and validate.sql checks every relationship afterwards.
-- CHECK constraints and unique indexes stay active throughout.
SET session_replication_role = replica;

-- ---- clients ----------------------------------------------------------------------------------
\echo '2/8 Clients'
INSERT INTO client (id, name, email, billing_email, phone, tax_id, address_line1, city, state, postal_code,
                    country_code, default_currency_code, payment_terms_days, reminders_enabled,
                    created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT c,
       w.prefix || ' ' || w.noun || ' ' || w.legal,
       lower(w.prefix || '.' || replace(w.noun, ' ', '')) || '.' || c || '@example.com',
       CASE WHEN gen.rnd(c, :seed * 100 + 5) < 0.4
            THEN 'accounts.' || c || '@example.com' END,
       '+' || CASE geo.country WHEN 'IN' THEN '91' WHEN 'US' THEN '1' WHEN 'GB' THEN '44'
                               WHEN 'AE' THEN '971' ELSE '49' END
           || lpad((floor(gen.rnd(c, :seed * 100 + 6) * 1e9))::bigint::text, 10, '0'),
       CASE geo.country
            WHEN 'IN' THEN lpad((1 + c % 37)::text, 2, '0') || 'AAAC' || chr(65 + (c % 26)::int)
                           || lpad((c % 10000)::text, 4, '0') || 'R1Z' || (c % 10)
            ELSE geo.country || lpad(c::text, 9, '0') END,
       (1 + floor(gen.rnd(c, :seed * 100 + 7) * 200))::int || ' '
           || gen.pick(ARRAY['MG Road', 'Station Road', 'Park Street', 'Market Lane', 'Harbour View',
                             'Industrial Estate', 'Business Park', 'High Street', 'Main Street'],
                       gen.rnd(c, :seed * 100 + 8)),
       geo.city, geo.state,
       lpad((floor(gen.rnd(c, :seed * 100 + 9) * 900000) + 100000)::bigint::text, 6, '0'),
       geo.country, geo.currency,
       (ARRAY[7, 15, 30, 30, 30, 45, 60])[1 + floor(gen.rnd(c, :seed * 100 + 10) * 7)::int],
       gen.rnd(c, :seed * 100 + 11) < 0.95,
       timestamptz '2023-08-01 10:00+05:30' + floor(gen.rnd(c, :seed * 100 + 12) * 90) * interval '1 day',
       timestamptz '2023-08-01 10:00+05:30' + floor(gen.rnd(c, :seed * 100 + 12) * 90) * interval '1 day'
FROM generate_series(1, :clients) AS c
CROSS JOIN LATERAL (
    SELECT gen.pick(ARRAY['Godavari', 'Kaveri', 'Narmada', 'Tapti', 'Krishna', 'Ganga', 'Yamuna', 'Indus',
                          'Saraswati', 'Brahmaputra', 'Mahanadi', 'Sutlej', 'Teesta', 'Periyar', 'Chambal',
                          'Sabarmati', 'Vaigai', 'Pennar', 'Luni', 'Mandovi', 'Northwind', 'Bluebird', 'Summit',
                          'Harbor', 'Evergreen', 'Silverline', 'Redwood', 'Crescent', 'Lighthouse', 'Keystone'],
                    gen.rnd(c, :seed * 100 + 1)) AS prefix,
           gen.pick(ARRAY['Foods', 'Textiles', 'Logistics', 'Pharma', 'Designs', 'Builders', 'Electronics',
                          'Exports', 'Software', 'Studios', 'Traders', 'Motors', 'Agro', 'Media', 'Consulting',
                          'Health Care', 'Packaging', 'Hospitality', 'Furniture', 'Analytics'],
                    gen.rnd(c, :seed * 100 + 2)) AS noun,
           gen.pick(ARRAY['Pvt Ltd', 'Pvt Ltd', 'Pvt Ltd', 'LLP', 'Ltd', 'Inc', 'GmbH', 'Co'],
                    gen.rnd(c, :seed * 100 + 3)) AS legal
) AS w
CROSS JOIN LATERAL (
    SELECT gen.rnd(c, :seed * 100 + 4) AS r
) AS rc
CROSS JOIN LATERAL (
    SELECT CASE WHEN rc.r < 0.80 THEN 'INR' WHEN rc.r < 0.88 THEN 'USD' WHEN rc.r < 0.94 THEN 'EUR'
                WHEN rc.r < 0.98 THEN 'GBP' ELSE 'AED' END AS currency,
           CASE WHEN rc.r < 0.80 THEN 'IN' WHEN rc.r < 0.88 THEN 'US' WHEN rc.r < 0.94 THEN 'DE'
                WHEN rc.r < 0.98 THEN 'GB' ELSE 'AE' END AS country,
           CASE WHEN rc.r < 0.80 THEN gen.pick(ARRAY['Bengaluru', 'Mumbai', 'Pune', 'Chennai', 'Hyderabad',
                                                     'Kolkata', 'Delhi', 'Ahmedabad', 'Kochi', 'Kakinada'],
                                               gen.rnd(c, :seed * 100 + 13))
                WHEN rc.r < 0.88 THEN gen.pick(ARRAY['New York', 'Austin', 'Seattle', 'Chicago', 'Boston'],
                                               gen.rnd(c, :seed * 100 + 13))
                WHEN rc.r < 0.94 THEN gen.pick(ARRAY['Berlin', 'Munich', 'Hamburg', 'Frankfurt'],
                                               gen.rnd(c, :seed * 100 + 13))
                WHEN rc.r < 0.98 THEN gen.pick(ARRAY['London', 'Manchester', 'Leeds', 'Bristol'],
                                               gen.rnd(c, :seed * 100 + 13))
                ELSE gen.pick(ARRAY['Dubai', 'Abu Dhabi', 'Sharjah'], gen.rnd(c, :seed * 100 + 13)) END AS city,
           CASE WHEN rc.r < 0.80 THEN gen.pick(ARRAY['Karnataka', 'Maharashtra', 'Tamil Nadu', 'Telangana',
                                                     'West Bengal', 'Delhi', 'Gujarat', 'Kerala',
                                                     'Andhra Pradesh'], gen.rnd(c, :seed * 100 + 14))
                END AS state
) AS geo;

-- ---- invoice headers (staging) ------------------------------------------------------------------
-- Clients are chosen with a power curve: the largest 1% of clients receive about 30% of all invoices.
-- Issue dates are spread evenly over the three years before "today"; drafts are from the last 30 days.
-- Status depends on age: invoices more than 60 days past due are mostly paid, recent ones mostly open.
\echo '3/8 Invoice headers'
CREATE UNLOGGED TABLE gen.inv AS
WITH base AS (
    SELECT n,
           1 + floor(:clients * power(gen.rnd(n, :seed * 100 + 20), 3.825))::bigint AS client_id,
           gen.rnd(n, :seed * 100 + 21) AS r_kind,
           gen.rnd(n, :seed * 100 + 22) AS r_date,
           gen.rnd(n, :seed * 100 + 23) AS r_status,
           gen.rnd(n, :seed * 100 + 24) AS r_part
    FROM generate_series(1, :invoices) AS n
), dated AS (
    SELECT b.*, c.default_currency_code AS currency_code, c.payment_terms_days AS terms,
           CASE WHEN r_kind < 0.03 THEN 'DRAFT' WHEN r_kind < 0.05 THEN 'VOID' ELSE 'ISSUED' END AS kind,
           CASE WHEN r_kind < 0.03 THEN date :'today' - 1 - floor(r_date * 30)::int
                ELSE date :'today' - 1 - floor(r_date * 1095)::int END AS issue_date
    FROM base AS b
    JOIN client AS c ON c.id = b.client_id
)
SELECT n AS id, client_id, currency_code, terms, issue_date, issue_date + terms AS due_date, r_part,
       CASE WHEN kind = 'DRAFT' THEN 'DRAFT'
            WHEN kind = 'VOID' THEN 'VOID'
            WHEN date :'today' - (issue_date + terms) > 60 THEN
                 CASE WHEN r_status < 0.90 THEN 'PAID' WHEN r_status < 0.96 THEN 'PARTIALLY_PAID' ELSE 'SENT' END
            ELSE CASE WHEN r_status < 0.40 THEN 'PAID' WHEN r_status < 0.60 THEN 'PARTIALLY_PAID' ELSE 'SENT' END
       END AS status
FROM dated;

-- ---- line items (staging) -----------------------------------------------------------------------
-- 1 to 5 lines per invoice (average 2.5). Each line is rounded to 2 decimals, as Duewise does.
\echo '4/8 Line items'
CREATE UNLOGGED TABLE gen.line AS
SELECT i.id AS invoice_id, k AS line_no,
       gen.pick(ARRAY['Consulting', 'Software development', 'Design work', 'Monthly retainer', 'Support hours',
                      'Hosting and maintenance', 'Training session', 'Data migration', 'Audit and review',
                      'Content writing', 'Logo design, 3 concepts', 'Brand guidelines', 'Freight charges',
                      'Raw material supply', 'Packaging material', 'Equipment rental', 'Licence fee',
                      'Installation', 'Annual maintenance contract', 'Travel expenses'],
                gen.rnd(i.id * 8 + k, :seed * 100 + 31)) AS description,
       q.quantity, p.unit_price, t.tax_rate,
       round(q.quantity * p.unit_price, 2) AS line_subtotal,
       round(round(q.quantity * p.unit_price, 2) * t.tax_rate / 100, 2) AS line_tax
FROM gen.inv AS i
CROSS JOIN LATERAL (SELECT gen.rnd(i.id, :seed * 100 + 30) AS r) AS rl
CROSS JOIN LATERAL generate_series(1, CASE WHEN rl.r < 0.30 THEN 1 WHEN rl.r < 0.55 THEN 2 WHEN rl.r < 0.75 THEN 3
                                           WHEN rl.r < 0.90 THEN 4 ELSE 5 END) AS k
CROSS JOIN LATERAL (
    SELECT (1 + floor(power(gen.rnd(i.id * 8 + k, :seed * 100 + 32), 2) * 20))::numeric AS quantity
) AS q
CROSS JOIN LATERAL (
    SELECT round((CASE i.currency_code WHEN 'INR' THEN 500 + gen.rnd(i.id * 8 + k, :seed * 100 + 33) * 49500
                                       WHEN 'AED' THEN 50 + gen.rnd(i.id * 8 + k, :seed * 100 + 33) * 4950
                                       ELSE 20 + gen.rnd(i.id * 8 + k, :seed * 100 + 33) * 1980 END)::numeric, 2)
           AS unit_price
) AS p
CROSS JOIN LATERAL (
    SELECT (CASE i.currency_code
                 WHEN 'INR' THEN (ARRAY[18, 18, 18, 12, 5, 0])[1 + floor(gen.rnd(i.id * 8 + k, :seed * 100 + 34) * 6)::int]
                 WHEN 'GBP' THEN 20
                 WHEN 'EUR' THEN 19
                 WHEN 'AED' THEN 5
                 ELSE 0 END)::numeric AS tax_rate
) AS t;

-- ---- invoice totals, numbers and amounts paid (staging) -----------------------------------------
-- Invoice numbers are gapless per year in issue order, as Duewise assigns them; drafts have none.
\echo '5/8 Totals and invoice numbers'
CREATE UNLOGGED TABLE gen.inv_total AS
SELECT i.*, s.subtotal, s.tax_total, s.subtotal + s.tax_total AS total,
       CASE i.status WHEN 'PAID' THEN s.subtotal + s.tax_total
                     WHEN 'PARTIALLY_PAID' THEN round((s.subtotal + s.tax_total) * (0.2 + 0.6 * i.r_part)::numeric, 2)
                     ELSE 0 END AS amount_paid,
       CASE WHEN i.status = 'DRAFT' THEN NULL
            ELSE row_number() OVER (PARTITION BY i.status = 'DRAFT', extract(year FROM i.issue_date)
                                    ORDER BY i.issue_date, i.id) END AS number_in_year
FROM gen.inv AS i
JOIN (SELECT invoice_id, sum(line_subtotal) AS subtotal, sum(line_tax) AS tax_total
      FROM gen.line GROUP BY invoice_id) AS s ON s.invoice_id = i.id;

-- ---- payments (staging) -------------------------------------------------------------------------
-- Paid invoices: one payment, or two (5%) splitting the amount. Partly paid: one payment.
-- Payment dates fall between the issue date and shortly after the due date, never on or after "today".
\echo '6/8 Payments'
CREATE UNLOGGED TABLE gen.pay AS
SELECT t.id AS invoice_id, x.part,
       CASE WHEN x.parts = 1 THEN t.amount_paid
            WHEN x.part = 1 THEN round(t.amount_paid / 2, 2)
            ELSE t.amount_paid - round(t.amount_paid / 2, 2) END AS amount,
       least(date :'today' - 1,
             t.issue_date + floor(gen.rnd(t.id * 4 + x.part, :seed * 100 + 40) * (t.terms + 25))::int
                          + (x.part - 1) * 10) AS paid_on,
       m.method_id
FROM gen.inv_total AS t
CROSS JOIN LATERAL (
    SELECT CASE WHEN t.status = 'PAID' AND gen.rnd(t.id, :seed * 100 + 41) < 0.05 THEN 2 ELSE 1 END AS parts
) AS np
CROSS JOIN LATERAL (SELECT part, np.parts FROM generate_series(1, np.parts) AS part) AS x
CROSS JOIN LATERAL (
    SELECT CASE WHEN r < 0.40 THEN 1 WHEN r < 0.75 THEN 2 WHEN r < 0.85 THEN 3 WHEN r < 0.95 THEN 4 ELSE 5 END
           AS method_id     -- 1 bank transfer, 2 UPI, 3 card, 4 cheque, 5 cash (seed order in V4)
    FROM (SELECT gen.rnd(t.id * 4 + x.part, :seed * 100 + 42) AS r) AS rr
) AS m
WHERE t.status IN ('PAID', 'PARTIALLY_PAID');

-- ---- load the real tables ------------------------------------------------------------------------
\echo '7/8 Loading invoices, line items and payments'
INSERT INTO invoice (id, invoice_number, client_id, currency_code, status, issue_date, due_date,
                     subtotal, tax_total, total, amount_paid, notes, sent_at, paid_at, voided_at, void_reason,
                     created_at, updated_at)
OVERRIDING SYSTEM VALUE
SELECT t.id,
       CASE WHEN t.number_in_year IS NOT NULL
            THEN 'INV-' || extract(year FROM t.issue_date) || '-' ||
                 -- like Java's %05d: at least five digits, never cut short (lpad would truncate)
                 CASE WHEN t.number_in_year < 100000 THEN lpad(t.number_in_year::text, 5, '0')
                      ELSE t.number_in_year::text END END,
       t.client_id, t.currency_code, t.status, t.issue_date, t.due_date,
       t.subtotal, t.tax_total, t.total, t.amount_paid,
       CASE WHEN t.id % 50 = 0 THEN 'Thank you for your business.' END,
       CASE WHEN t.status <> 'DRAFT' THEN t.issue_date + time '11:00' END,
       CASE WHEN t.status = 'PAID' THEN lp.last_paid + time '15:00' END,
       CASE WHEN t.status = 'VOID' THEN t.issue_date + 2 + time '12:00' END,
       CASE WHEN t.status = 'VOID' THEN 'Raised against the wrong client' END,
       t.issue_date + time '10:00',
       coalesce(lp.last_paid + time '15:00', t.issue_date + time '11:00')
FROM gen.inv_total AS t
LEFT JOIN (SELECT invoice_id, max(paid_on) AS last_paid FROM gen.pay GROUP BY invoice_id) AS lp
       ON lp.invoice_id = t.id;

INSERT INTO invoice_line_item (invoice_id, line_no, description, quantity, unit_price, tax_rate,
                               line_subtotal, line_tax, line_total)
SELECT invoice_id, line_no, description, quantity, unit_price, tax_rate,
       line_subtotal, line_tax, line_subtotal + line_tax
FROM gen.line
ORDER BY invoice_id, line_no;

INSERT INTO payment (invoice_id, payment_method_id, amount, paid_on, reference, created_at)
SELECT invoice_id, method_id, amount, paid_on,
       CASE method_id WHEN 1 THEN 'NEFT' WHEN 2 THEN 'UPI-' WHEN 3 THEN 'CARD-' WHEN 4 THEN 'CHQ-' END
           || CASE WHEN method_id <> 5 THEN (invoice_id * 10 + part)::text END,
       paid_on + time '15:00'
FROM gen.pay
ORDER BY paid_on, invoice_id, part;

INSERT INTO invoice_number_counter (invoice_year, last_value)
SELECT extract(year FROM issue_date)::smallint, max(number_in_year)
FROM gen.inv_total WHERE number_in_year IS NOT NULL
GROUP BY 1;

-- Identity columns continue after the generated ids, so the API can keep inserting.
SELECT setval(pg_get_serial_sequence('client', 'id'), (SELECT max(id) FROM client));
SELECT setval(pg_get_serial_sequence('invoice', 'id'), (SELECT max(id) FROM invoice));

SET session_replication_role = origin;
DROP TABLE gen.inv, gen.line, gen.inv_total, gen.pay;

-- ---- statistics -----------------------------------------------------------------------------------
-- VACUUM marks pages all-visible (needed for index-only scans); ANALYZE gives the planner fresh statistics.
\echo '8/8 VACUUM ANALYZE'
VACUUM (ANALYZE) client, invoice, invoice_line_item, payment, invoice_number_counter;
SELECT pg_stat_statements_reset();

\echo
\echo 'Done. Row counts and sizes:'
SELECT relname AS "table", to_char(n_live_tup, 'FM999,999,999') AS "rows",
       pg_size_pretty(pg_total_relation_size(relid)) AS "size incl. indexes"
FROM pg_stat_user_tables
WHERE relname IN ('client', 'invoice', 'invoice_line_item', 'payment')
ORDER BY pg_total_relation_size(relid) DESC;
