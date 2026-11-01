-- Measures one query in one variant and saves the evidence.
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/harness/measure.sql \
--       -v case=01-overdue-dashboard -v variant=before -v query=cases/01-overdue-dashboard/query.sql
--
-- Variables:
--   case      folder name under cases/ (created if missing)
--   variant   a short label such as before, after, keyset
--   query     the query file, relative to the repository root; one statement, may end with ";"
--   runs      timed runs (default 11), after warmups (default 3) that are not counted
--   rollback  true to undo each run, for timing INSERT/UPDATE/DELETE (default false)
--
-- What it produces:
--   1. a row in harness.measurement and a line in results/timings.csv (median, min, max, buffers)
--   2. cases/<case>/plans/<variant>.txt: the full EXPLAIN (ANALYZE, BUFFERS) plan of one more run,
--      with per-node timings, for reading what the database actually did.

\set ON_ERROR_STOP on
\set QUIET on

\if :{?case}
\else
    \echo 'Missing -v case=...'
    \quit
\endif
\if :{?variant}
\else
    \echo 'Missing -v variant=...'
    \quit
\endif
\if :{?query}
\else
    \echo 'Missing -v query=... (a file relative to the repository root)'
    \quit
\endif
\if :{?runs}
\else
    \set runs 11
\endif
\if :{?warmups}
\else
    \set warmups 3
\endif
\if :{?rollback}
\else
    \set rollback false
\endif

\ir install.sql

\set sql `cat /work/:query`
\set plan_dir /work/cases/:case/plans
\set plan_file :plan_dir/:variant.txt
\set timings /work/results/timings.csv

\echo 'Measuring' :case '/' :variant ':' :warmups 'warm-up runs, then' :runs 'timed runs'

\pset footer off
\x on
SELECT case_name AS "case", variant, invoices, runs,
       median_ms, min_ms, max_ms, planning_ms, result_rows, shared_hit, shared_read, top_node
FROM harness.measure(:'case', :'variant', :'sql', :runs, :warmups, :rollback);
\x off

-- Timings, appended to results/timings.csv (header written once).
\! test -s /work/results/timings.csv || echo "measured_at,case,variant,invoices,runs,warmups,median_ms,min_ms,max_ms,planning_ms,result_rows,shared_hit,shared_read,top_node" > /work/results/timings.csv
\copy (SELECT to_char(measured_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), case_name, variant, invoices, runs, warmups, median_ms, min_ms, max_ms, planning_ms, result_rows, shared_hit, shared_read, top_node FROM harness.measurement WHERE id = (SELECT max(id) FROM harness.measurement)) TO PROGRAM 'cat >> /work/results/timings.csv' WITH (FORMAT csv)

-- The plan, with per-node timings and buffers. Run inside a transaction that is rolled back,
-- so a write query leaves no trace.
\set mkdir `mkdir -p :'plan_dir'`
\o :plan_file
\qecho '-- Case:' :case
\qecho '-- Variant:' :variant
\qecho '-- Query file:' :query
\t on
SELECT '-- Measured at: ' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')
       || ', ' || to_char((SELECT count(*) FROM invoice), 'FM999,999,999') || ' invoices'
       || ', median ' || (SELECT median_ms FROM harness.measurement ORDER BY id DESC LIMIT 1) || ' ms'
       || ' over ' || :runs || ' runs';
\t off
\qecho
\qecho :sql
\qecho
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
:sql
;
ROLLBACK;
\o

\echo 'Saved: results/timings.csv and cases/':case'/plans/':variant'.txt'
