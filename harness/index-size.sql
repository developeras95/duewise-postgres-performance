-- Prints the size of every index on the case's table that is not part of Duewise v1.0.3
-- (the study's own indexes all start with "perf_"), and appends them to results/index-sizes.csv.
\set QUIET on
\pset footer off
SELECT indexrelid::regclass AS "index", indrelid::regclass AS "table",
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       pg_size_pretty(pg_relation_size(indrelid)) AS table_size
FROM pg_index WHERE indexrelid::regclass::text LIKE 'perf\_%' ORDER BY 1;
\! test -s /work/results/index-sizes.csv || echo "measured_at,index,table,index_bytes,table_bytes" > /work/results/index-sizes.csv
\copy (SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), indexrelid::regclass::text, indrelid::regclass::text, pg_relation_size(indexrelid), pg_relation_size(indrelid) FROM pg_index WHERE indexrelid::regclass::text LIKE 'perf\_%' ORDER BY 2) TO PROGRAM 'cat >> /work/results/index-sizes.csv' WITH (FORMAT csv)
