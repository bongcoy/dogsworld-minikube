#!/bin/sh
# Dijalankan DI DALAM pod postgres oleh scripts/setup.ps1 dan scripts/setup.sh.
# Membuat user "datadog" untuk Datadog Database Monitoring. Aman dijalankan berulang.
# Password dibaca dari env DD_PG_PASSWORD (berasal dari Secret datadog-pg-secret), tidak lewat argumen.
set -e

if [ -z "$DD_PG_PASSWORD" ]; then
  echo "DD_PG_PASSWORD kosong. Pastikan Secret datadog-pg-secret ada sebelum pod postgres dibuat." >&2
  exit 1
fi

export PGPASSWORD="$POSTGRES_PASSWORD"
PW_ESC=$(printf '%s' "$DD_PG_PASSWORD" | sed "s/'/''/g")

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'datadog') THEN
    CREATE USER datadog WITH PASSWORD '$PW_ESC';
  ELSE
    ALTER USER datadog WITH PASSWORD '$PW_ESC';
  END IF;
END \$\$;
ALTER ROLE datadog INHERIT;
GRANT pg_monitor TO datadog;
SQL

for DB in postgres "$POSTGRES_DB"; do
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" <<'SQL'
CREATE SCHEMA IF NOT EXISTS datadog;
GRANT USAGE ON SCHEMA datadog TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE OR REPLACE FUNCTION datadog.explain_statement(l_query TEXT, OUT explain JSON)
RETURNS SETOF JSON AS
$$
DECLARE
curs REFCURSOR;
plan JSON;
BEGIN
   SET TRANSACTION READ ONLY;
   OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
   FETCH curs INTO plan;
   CLOSE curs;
   RETURN QUERY SELECT plan;
END;
$$
LANGUAGE 'plpgsql'
RETURNS NULL ON NULL INPUT
SECURITY DEFINER;
CREATE OR REPLACE FUNCTION datadog.column_statistics()
RETURNS TABLE (
    schemaname name, tablename name, attname name,
    n_distinct real, avg_width integer, null_frac real,
    inherited boolean, correlation real, most_common_freqs real[]
) AS
$$ SELECT schemaname, tablename, attname, n_distinct, avg_width, null_frac,
          inherited, correlation, most_common_freqs
          FROM pg_catalog.pg_stats
          WHERE schemaname NOT IN ('pg_catalog', 'information_schema'); $$
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp;
SQL
done

echo "DBM setup selesai"
