-- Installs the measurement harness: a "harness" schema with one table and two functions.
-- Safe to run any number of times; measure.sql and environment.sql run it for you.
-- It lives in its own schema, so the generator's TRUNCATE never touches it.

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS harness;

-- One row per measurement: a query, in one variant (for example "before" and "after" an index),
-- timed several times after a few warm-up runs.
CREATE TABLE IF NOT EXISTS harness.measurement (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    measured_at     timestamptz NOT NULL DEFAULT now(),
    case_name       text        NOT NULL,
    variant         text        NOT NULL,
    invoices        bigint      NOT NULL,   -- data scale at the time of the measurement
    runs            int         NOT NULL,
    warmups         int         NOT NULL,
    median_ms       numeric     NOT NULL,   -- execution time, the headline number
    min_ms          numeric     NOT NULL,
    max_ms          numeric     NOT NULL,
    planning_ms     numeric     NOT NULL,   -- median planning time
    result_rows     bigint,
    shared_hit      bigint,                 -- 8 kB pages found in PostgreSQL's cache (last run)
    shared_read     bigint,                 -- 8 kB pages read from the OS / disk (last run)
    top_node        text,                   -- e.g. "Limit", "Aggregate", for a quick sanity check
    query           text        NOT NULL
);

-- Runs a query (warmups + runs) times and records the timings PostgreSQL itself reports.
--
-- Each run is EXPLAIN (ANALYZE, TIMING OFF, BUFFERS): the query executes in full, but its rows are not
-- sent anywhere, so the time excludes network and client. TIMING OFF avoids the clock overhead of
-- per-node timing, which can inflate times of queries that touch millions of rows.
--
-- rollback => true undoes each run, so INSERT/UPDATE/DELETE can be timed repeatedly against the same data.
CREATE OR REPLACE FUNCTION harness.measure(
    p_case     text,
    p_variant  text,
    p_query    text,
    p_runs     int     DEFAULT 11,
    p_warmups  int     DEFAULT 3,
    p_rollback boolean DEFAULT false)
RETURNS harness.measurement
LANGUAGE plpgsql AS $$
DECLARE
    q         text := regexp_replace(btrim(p_query, E' \t\r\n'), ';\s*$', '');
    plan      json;
    exec_ms   numeric[] := '{}';
    plan_ms   numeric[] := '{}';
    result    harness.measurement;
BEGIN
    IF p_runs < 1 OR p_warmups < 0 THEN
        RAISE EXCEPTION 'runs must be at least 1 and warmups at least 0';
    END IF;

    FOR i IN 1 .. p_warmups + p_runs LOOP
        BEGIN
            EXECUTE 'EXPLAIN (ANALYZE, TIMING OFF, BUFFERS, FORMAT JSON) ' || q INTO plan;
            IF p_rollback THEN
                RAISE EXCEPTION USING ERRCODE = 'HR001', MESSAGE = 'undo this run';
            END IF;
        EXCEPTION WHEN SQLSTATE 'HR001' THEN
            NULL;   -- the run's changes are undone; the plan variable keeps its value
        END;
        IF i > p_warmups THEN
            exec_ms := exec_ms || (plan -> 0 ->> 'Execution Time')::numeric;
            plan_ms := plan_ms || (plan -> 0 ->> 'Planning Time')::numeric;
        END IF;
    END LOOP;

    INSERT INTO harness.measurement (case_name, variant, invoices, runs, warmups,
                                     median_ms, min_ms, max_ms, planning_ms,
                                     result_rows, shared_hit, shared_read, top_node, query)
    SELECT p_case, p_variant,
           (SELECT count(*) FROM invoice),
           p_runs, p_warmups,
           round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY v) FROM unnest(exec_ms) AS v)::numeric, 3),
           (SELECT min(v) FROM unnest(exec_ms) AS v),
           (SELECT max(v) FROM unnest(exec_ms) AS v),
           round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY v) FROM unnest(plan_ms) AS v)::numeric, 3),
           (plan -> 0 -> 'Plan' ->> 'Actual Rows')::numeric::bigint,
           (plan -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint,
           (plan -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint,
           plan -> 0 -> 'Plan' ->> 'Node Type',
           q
    RETURNING * INTO result;

    RETURN result;
END $$;

-- Runs a shell command on the database server (inside the container) and returns its output.
-- Used only by environment.sql to record the hardware. Needs a superuser, which "duewise" is.
CREATE OR REPLACE FUNCTION harness.shell(p_command text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    output text;
BEGIN
    IF to_regclass('pg_temp.harness_shell_output') IS NULL THEN
        CREATE TEMP TABLE harness_shell_output (line text);
    END IF;
    TRUNCATE harness_shell_output;
    EXECUTE format('COPY harness_shell_output FROM PROGRAM %L WITH (FORMAT text, DELIMITER E''\x01'')',
                   p_command);
    SELECT string_agg(btrim(line), ' ') INTO output FROM harness_shell_output;
    RETURN output;
END $$;

RESET client_min_messages;
