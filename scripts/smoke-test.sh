#!/usr/bin/env bash
# End-to-end check used by CI (and runnable locally): needs docker + a populated .env.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
dc() { docker compose "$@"; }
# .env is not shell-safe (cron expressions), so read single keys instead of sourcing it.
get() { grep -E "^$1=" .env | tail -1 | cut -d= -f2-; }
APP_DB_NAME="$(get APP_DB_NAME)"; APP_DB_USER="$(get APP_DB_USER)"
APP_DB_PASSWORD="$(get APP_DB_PASSWORD)"; POSTGRES_PASSWORD="$(get POSTGRES_PASSWORD)"
COMPOSE_PROFILES="$(get COMPOSE_PROFILES)"
wait_healthy() {
    local svc="$1"
    for _ in $(seq 1 60); do
        [[ "$(docker inspect -f '{{.State.Health.Status}}' "$(dc ps -q "${svc}")" 2>/dev/null)" == healthy ]] && return 0
        sleep 5
    done
    dc logs "${svc}" | tail -80; echo "${svc} never became healthy" >&2; return 1
}

dc up -d --build
wait_healthy postgres-primary
wait_healthy pgbouncer

echo "== login through PgBouncer (SCRAM via auth_query) =="
dc exec -T -e PGPASSWORD="${APP_DB_PASSWORD}" postgres-primary \
    psql "host=pgbouncer port=6432 dbname=${APP_DB_NAME} user=${APP_DB_USER} sslmode=require" \
    -Atc "create table smoke(id int); insert into smoke values (1); select count(*) from smoke;" | grep -q 1

echo "== remote superuser / plaintext must be rejected =="
if dc exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres-primary \
    psql "host=postgres-primary dbname=postgres user=postgres sslmode=require" -c 'select 1' 2>/dev/null; then
    echo "remote superuser login was allowed!" >&2; exit 1
fi

echo "== WAL archiving + backup =="
dc exec -T postgres-primary gosu postgres psql -Atc "select pg_switch_wal()" >/dev/null
sleep 10
dc exec -T postgres-primary gosu postgres psql -Atc "select failed_count from pg_stat_archiver" | grep -qx 0
dc exec -T postgres-primary pg-backup full
dc exec -T postgres-primary pgbackrest --stanza=main info | grep -q "full backup"

if [[ ",${COMPOSE_PROFILES}," == *",replica,"* ]]; then
    echo "== replica =="
    wait_healthy postgres-replica
    dc exec -T postgres-replica gosu postgres psql -Atc "select pg_is_in_recovery()" | grep -qx t
    dc exec -T postgres-primary gosu postgres psql -Atc "select count(*) from pg_stat_replication where state='streaming'" | grep -qx 1
fi
echo "SMOKE TEST PASSED"
