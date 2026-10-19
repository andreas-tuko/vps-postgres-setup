#!/usr/bin/env bash
# First-init only: service roles, PgBouncer auth function, extensions, optional first app database.
set -Eeuo pipefail

psql -X -v ON_ERROR_STOP=1 -d postgres \
    -v repl_pw="${REPLICATION_PASSWORD}" \
    -v auth_pw="${PGBOUNCER_AUTH_PASSWORD}" \
    -v mon_pw="${MONITOR_PASSWORD}" <<'SQL'
SELECT format('CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD %L', :'repl_pw') \gexec
SELECT format('CREATE ROLE pgbouncer_auth WITH LOGIN PASSWORD %L', :'auth_pw') \gexec
SELECT format('CREATE ROLE monitor WITH LOGIN PASSWORD %L', :'mon_pw') \gexec
GRANT pg_monitor TO monitor;

-- PgBouncer looks users up through auth_query, so no per-user userlist is ever needed.
CREATE SCHEMA pgbouncer;
CREATE FUNCTION pgbouncer.get_auth(p_usename text)
RETURNS TABLE (usename name, passwd text)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS
$$ SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename = p_usename $$;
REVOKE ALL ON FUNCTION pgbouncer.get_auth(text) FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO pgbouncer_auth;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(text) TO pgbouncer_auth;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL

# Make every future database inherit pg_stat_statements.
psql -X -v ON_ERROR_STOP=1 -d template1 -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'

if [[ -n "${APP_DB_NAME:-}" && -n "${APP_DB_USER:-}" && -n "${APP_DB_PASSWORD:-}" ]]; then
    APP_PASSWORD="${APP_DB_PASSWORD}" create-app-db "${APP_DB_NAME}" "${APP_DB_USER}"
fi
