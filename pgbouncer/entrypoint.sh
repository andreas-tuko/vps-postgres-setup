#!/usr/bin/env bash
# Renders pgbouncer.ini + userlist from environment into /tmp (container filesystem is read-only).
set -Eeuo pipefail

: "${PGBOUNCER_AUTH_PASSWORD:?PGBOUNCER_AUTH_PASSWORD is required}"
: "${PGBOUNCER_ADMIN_PASSWORD:?PGBOUNCER_ADMIN_PASSWORD is required}"

CFG=/tmp/pgbouncer
install -d -m 0700 "${CFG}"

# userlist.txt: double any embedded quotes
q() { local s="${1//\"/\"\"}"; printf '"%s"' "${s}"; }
umask 077
{
    printf '%s %s\n' "$(q pgbouncer_auth)"  "$(q "${PGBOUNCER_AUTH_PASSWORD}")"
    printf '%s %s\n' "$(q pgbouncer_admin)" "$(q "${PGBOUNCER_ADMIN_PASSWORD}")"
} > "${CFG}/userlist.txt"

if [[ -n "${TLS_CERT_B64:-}" && -n "${TLS_KEY_B64:-}" ]]; then
    printf '%s' "${TLS_CERT_B64}" | base64 -d > "${CFG}/server.crt"
    printf '%s' "${TLS_KEY_B64}"  | base64 -d > "${CFG}/server.key"
else
    echo "pgbouncer: generating self-signed TLS certificate (set TLS_CERT_B64/TLS_KEY_B64 for a real one)" >&2
    openssl req -x509 -newkey rsa:3072 -sha256 -days 825 -nodes -subj "/CN=pgbouncer" \
        -keyout "${CFG}/server.key" -out "${CFG}/server.crt" 2>/dev/null
fi

pool_mode="${PGBOUNCER_POOL_MODE:-transaction}"
case "${pool_mode}" in session|transaction|statement) ;; *) echo "invalid PGBOUNCER_POOL_MODE" >&2; exit 1 ;; esac
# DISCARD ALL is only right for session pooling; in transaction mode it just burns round-trips.
reset_query=""; [[ "${pool_mode}" == session ]] && reset_query="DISCARD ALL"

cat > "${CFG}/pgbouncer.ini" <<INI
[databases]
* = host=${PG_HOST:-postgres-primary} port=5432 auth_dbname=postgres

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
unix_socket_dir =
pidfile =

auth_type = scram-sha-256
auth_file = ${CFG}/userlist.txt
auth_user = pgbouncer_auth
auth_query = SELECT usename, passwd FROM pgbouncer.get_auth(\$1)
admin_users = pgbouncer_admin
stats_users = pgbouncer_admin

pool_mode = ${pool_mode}
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN:-1000}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE:-20}
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = ${PGBOUNCER_MAX_DB_CONNECTIONS:-100}
max_prepared_statements = ${PGBOUNCER_MAX_PREPARED_STATEMENTS:-100}
server_reset_query = ${reset_query}
ignore_startup_parameters = extra_float_digits,options

server_lifetime = 3600
server_idle_timeout = 600
query_wait_timeout = 120
client_idle_timeout = 0

client_tls_sslmode = require
client_tls_key_file = ${CFG}/server.key
client_tls_cert_file = ${CFG}/server.crt
client_tls_protocols = secure
server_tls_sslmode = require

log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
stats_period = 60
INI

exec pgbouncer "${CFG}/pgbouncer.ini"
