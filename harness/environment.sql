-- Records what the timings were measured on: hardware as Docker sees it, PostgreSQL version and
-- settings, and data size. Writes results/environment.csv (replacing it) and prints it.
--
--   docker compose exec postgres psql -U duewise -d duewise -f /work/harness/environment.sql
--
-- Run it once with each set of results. Docker Desktop's version and the host's disk type are not
-- visible from inside the container; add them to the README by hand.

\set ON_ERROR_STOP on
\set QUIET on
\ir install.sql

CREATE TEMP TABLE environment (position serial, key text, value text);

INSERT INTO environment (key, value) VALUES
    ('recorded_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')),
    ('cpu_model', coalesce(nullif(harness.shell(
        'grep -m1 -i "model name" /proc/cpuinfo | cut -d: -f2 || true'), ''), 'not reported')),
    ('cpu_cores_for_docker', harness.shell('nproc')),
    ('memory_for_docker', harness.shell('awk ''/MemTotal/ {printf "%.1f GB", $2 / 1048576}'' /proc/meminfo')),
    ('kernel', harness.shell('uname -srm')),
    ('data_disk_free', harness.shell(format('df -h %s | awk ''NR == 2 {print $4 " free of " $2}''',
                                            current_setting('data_directory')))),
    ('postgresql', version()),
    ('database_size', pg_size_pretty(pg_database_size(current_database()))),
    ('invoices', to_char((SELECT count(*) FROM invoice), 'FM999,999,999')),
    ('line_items', to_char((SELECT count(*) FROM invoice_line_item), 'FM999,999,999')),
    ('payments', to_char((SELECT count(*) FROM payment), 'FM999,999,999')),
    ('clients', to_char((SELECT count(*) FROM client), 'FM999,999,999'));

-- Every setting that differs from PostgreSQL's built-in default, plus a few that shape plans even
-- at their defaults.
INSERT INTO environment (key, value)
SELECT 'setting.' || name, current_setting(name)
FROM pg_settings
WHERE (source NOT IN ('default', 'override', 'client', 'session')
       OR name IN ('jit', 'max_parallel_workers_per_gather', 'enable_seqscan', 'work_mem',
                   'random_page_cost', 'effective_io_concurrency'))
  AND name NOT IN ('application_name', 'client_encoding', 'DateStyle', 'TimeZone', 'log_timezone',
                   'lc_messages', 'lc_monetary', 'lc_numeric', 'lc_time', 'default_text_search_config',
                   'listen_addresses', 'transaction_deferrable', 'transaction_isolation',
                   'transaction_read_only', 'search_path', 'port', 'cluster_name', 'external_pid_file',
                   'unix_socket_directories', 'data_directory', 'config_file', 'hba_file', 'ident_file')
  AND name NOT LIKE 'ssl%' AND name NOT LIKE 'log%'
ORDER BY name;

\copy (SELECT key, value FROM environment ORDER BY position) TO '/work/results/environment.csv' WITH (FORMAT csv, HEADER)

\pset footer off
SELECT key, value FROM environment ORDER BY position;
\echo 'Saved: results/environment.csv'
