#!/usr/bin/env bash
# setup-postgres17.sh — production PostgreSQL 17 on a raw Ubuntu 22.04 / 24.04 VPS
#
#   PostgreSQL 17 (PGDG) · pgBackRest (WAL archiving, PITR, optional S3) · PgBouncer (auth_query)
#   streaming replica · UFW · Fail2Ban (SSH) · systemd backup timers · optional Prometheus exporter
#
# Usage:
#   sudo ./setup-postgres17.sh --config /root/pg.conf            # primary (unattended, re-runnable)
#   sudo ./setup-postgres17.sh --config /root/pg.conf --role replica
#   sudo ./setup-postgres17.sh --interactive                     # asks the main questions
#   sudo ./setup-postgres17.sh --help
#
# The config file is plain KEY=VALUE (never sourced as shell). See --help for keys.
# License: MIT

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
umask 022

readonly SCRIPT_VERSION="2.0.0"
readonly PG_VERSION=17
readonly PG_CLUSTER=main
readonly PG_ETC="/etc/postgresql/${PG_VERSION}/${PG_CLUSTER}"
readonly PG_DATA="/var/lib/postgresql/${PG_VERSION}/${PG_CLUSTER}"
readonly PG_CERT_DIR="${PG_ETC}/certs"
readonly PG_SERVICE="postgresql@${PG_VERSION}-${PG_CLUSTER}"
readonly STATE_DIR="/etc/pg-setup"
readonly CRED_FILE="${STATE_DIR}/credentials.env"
readonly RUNTIME_FILE="${STATE_DIR}/runtime.env"
readonly LOG_FILE="/var/log/pg-setup.log"
readonly BIN_DIR="/usr/local/sbin"

# ----------------------------------------------------------------------------
# logging
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then C_G=$'\033[0;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[0;31m'; C_B=$'\033[0;34m'; C_N=$'\033[0m'
else C_G=""; C_Y=""; C_R=""; C_B=""; C_N=""; fi
_ts() { date +'%Y-%m-%d %H:%M:%S'; }
log()     { printf '%s[%s]%s %s\n' "${C_G}" "$(_ts)" "${C_N}" "$*" | tee -a "${LOG_FILE}" >&2; }
warn()    { printf '%s[%s] WARNING:%s %s\n' "${C_Y}" "$(_ts)" "${C_N}" "$*" | tee -a "${LOG_FILE}" >&2; }
err()     { printf '%s[%s] ERROR:%s %s\n' "${C_R}" "$(_ts)" "${C_N}" "$*" | tee -a "${LOG_FILE}" >&2; }
section() { printf '\n%s== %s ==%s\n' "${C_B}" "$*" "${C_N}" | tee -a "${LOG_FILE}" >&2; }
die()     { err "$*"; exit 1; }
trap 'err "failed at line ${LINENO}: ${BASH_COMMAND}  (log: ${LOG_FILE})"' ERR

# ----------------------------------------------------------------------------
# configuration
# ----------------------------------------------------------------------------
readonly ALLOWED_KEYS=(
    ROLE PG_PORT PG_LISTEN_ADDRESSES ALLOWED_CIDRS PG_MAX_CONNECTIONS
    PG_SHARED_BUFFERS_MB PG_EFFECTIVE_CACHE_MB PG_WORK_MEM_MB PG_MAINTENANCE_WORK_MEM_MB
    PG_MAX_WAL_SIZE PG_MAX_SLOT_WAL_KEEP_SIZE PG_LOG_MIN_DURATION_MS ENABLE_DATA_CHECKSUMS
    PG_SSL_CERT_FILE PG_SSL_KEY_FILE
    ENABLE_FIREWALL ENABLE_FAIL2BAN SSH_PORT PG_DIRECT_ACCESS
    ENABLE_PGBOUNCER PGBOUNCER_PORT PGBOUNCER_LISTEN PGBOUNCER_POOL_MODE
    PGBOUNCER_MAX_CLIENT_CONN PGBOUNCER_DEFAULT_POOL_SIZE PGBOUNCER_MAX_DB_CONNECTIONS
    ENABLE_BACKUPS BACKUP_FULL_ONCALENDAR BACKUP_DIFF_ONCALENDAR BACKUP_RETENTION_FULL BACKUP_RETENTION_DIFF
    BACKUP_S3_BUCKET BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_KEY BACKUP_S3_KEY_SECRET
    BACKUP_S3_URI_STYLE BACKUP_S3_PATH ALERT_WEBHOOK_URL
    ENABLE_EXPORTER
    PRIMARY_HOST PRIMARY_PORT REPLICA_SLOT FORCE_WIPE
    REPLICATION_PASSWORD PGBOUNCER_AUTH_PASSWORD PGBOUNCER_ADMIN_PASSWORD MONITOR_PASSWORD BACKUP_CIPHER_PASS
    APP_DB_NAME APP_DB_USER APP_DB_PASSWORD
)

CONFIG_FILE=""; INTERACTIVE=no; CLI_ROLE=""; CLI_YES=""

usage() {
    cat <<'EOF'
setup-postgres17.sh [--config FILE] [--role primary|replica] [--interactive] [--yes] [--help]

Config keys (KEY=VALUE, '#' comments; environment variables work too, the file wins):

  ROLE=primary|replica          default primary
  PG_PORT=5432
  PG_LISTEN_ADDRESSES=localhost use '*' or an IP only if remote clients/replicas connect directly
  ALLOWED_CIDRS=                comma list (e.g. 203.0.113.10/32,10.0.0.0/24): may reach PgBouncer
                                (and Postgres directly if PG_DIRECT_ACCESS=yes / replicas)
  PG_DIRECT_ACCESS=no           open the Postgres port (not just PgBouncer) to ALLOWED_CIDRS
  PG_MAX_CONNECTIONS=200
  PG_*_MB=                      leave empty for auto-sizing from RAM
  PG_MAX_WAL_SIZE=4GB   PG_MAX_SLOT_WAL_KEEP_SIZE=10GB   PG_LOG_MIN_DURATION_MS=1000
  ENABLE_DATA_CHECKSUMS=yes     only applied when the cluster is fresh (re-creates the empty default cluster)
  PG_SSL_CERT_FILE= PG_SSL_KEY_FILE=  your own certificate; blank = self-signed

  ENABLE_FIREWALL=yes  ENABLE_FAIL2BAN=yes  SSH_PORT=(auto-detected)

  ENABLE_PGBOUNCER=yes  PGBOUNCER_PORT=6432  PGBOUNCER_LISTEN=127.0.0.1  (use '*' to expose)
  PGBOUNCER_POOL_MODE=transaction  PGBOUNCER_MAX_CLIENT_CONN=1000
  PGBOUNCER_DEFAULT_POOL_SIZE=20   PGBOUNCER_MAX_DB_CONNECTIONS=100

  ENABLE_BACKUPS=yes
  BACKUP_FULL_ONCALENDAR='Sun *-*-* 02:00:00'   BACKUP_DIFF_ONCALENDAR='Mon..Sat *-*-* 02:00:00'
  BACKUP_RETENTION_FULL=4  BACKUP_RETENTION_DIFF=14
  BACKUP_S3_BUCKET= BACKUP_S3_ENDPOINT= BACKUP_S3_REGION= BACKUP_S3_KEY= BACKUP_S3_KEY_SECRET=
  BACKUP_S3_URI_STYLE=host|path  BACKUP_S3_PATH=/pgbackrest
  ALERT_WEBHOOK_URL=            POSTed (JSON {"text":...}) when a scheduled backup fails

  ENABLE_EXPORTER=no            prometheus-postgres-exporter on 127.0.0.1:9187

  Replica only:  PRIMARY_HOST=  PRIMARY_PORT=5432  REPLICA_SLOT=replica1  FORCE_WIPE=yes
                 and the primary's REPLICATION_PASSWORD, PGBOUNCER_AUTH_PASSWORD, PGBOUNCER_ADMIN_PASSWORD
                 (copy them from /etc/pg-setup/credentials.env on the primary)

  Optional first database:  APP_DB_NAME= APP_DB_USER= APP_DB_PASSWORD=

Secrets left blank are generated and stored in /etc/pg-setup/credentials.env (mode 600).
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)      CONFIG_FILE="${2:?--config needs a file}"; shift 2 ;;
            --role)        CLI_ROLE="${2:?--role needs a value}"; shift 2 ;;
            --interactive) INTERACTIVE=yes; shift ;;
            --yes|-y)      CLI_YES=yes; shift ;;
            --help|-h)     usage; exit 0 ;;
            *)             usage; die "unknown argument: $1" ;;
        esac
    done
}

is_allowed_key() { local k; for k in "${ALLOWED_KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done; return 1; }

# Safe KEY=VALUE reader: no sourcing, no eval, allow-listed keys only.
load_kv_file() {
    local file="$1" line key val
    [[ -f "${file}" ]] || die "config file not found: ${file}"
    local mode; mode="$(stat -c '%a' "${file}")"
    [[ "${mode}" =~ ^[0-7]*[0-7]00$|^[0-7]00$ ]] || warn "${file} is accessible by others (mode ${mode}); it may contain secrets — chmod 600"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%$'\r'}"
        [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "${line}" == *=* ]] || die "${file}: invalid line: ${line}"
        key="${line%%=*}"; val="${line#*=}"
        key="${key//[[:space:]]/}"
        is_allowed_key "${key}" || die "${file}: unknown key '${key}'"
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
        if [[ "${val}" =~ ^\"(.*)\"$ || "${val}" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
        printf -v "${key}" '%s' "${val}"
    done < "${file}"
}

set_defaults() {
    : "${ROLE:=primary}" "${PG_PORT:=5432}" "${PG_LISTEN_ADDRESSES:=localhost}" "${ALLOWED_CIDRS:=}"
    : "${PG_MAX_CONNECTIONS:=200}" "${PG_SHARED_BUFFERS_MB:=}" "${PG_EFFECTIVE_CACHE_MB:=}"
    : "${PG_WORK_MEM_MB:=}" "${PG_MAINTENANCE_WORK_MEM_MB:=}"
    : "${PG_MAX_WAL_SIZE:=4GB}" "${PG_MAX_SLOT_WAL_KEEP_SIZE:=10GB}" "${PG_LOG_MIN_DURATION_MS:=1000}"
    : "${ENABLE_DATA_CHECKSUMS:=yes}" "${PG_SSL_CERT_FILE:=}" "${PG_SSL_KEY_FILE:=}"
    : "${ENABLE_FIREWALL:=yes}" "${ENABLE_FAIL2BAN:=yes}" "${SSH_PORT:=}" "${PG_DIRECT_ACCESS:=no}"
    : "${ENABLE_PGBOUNCER:=yes}" "${PGBOUNCER_PORT:=6432}" "${PGBOUNCER_LISTEN:=127.0.0.1}"
    : "${PGBOUNCER_POOL_MODE:=transaction}" "${PGBOUNCER_MAX_CLIENT_CONN:=1000}"
    : "${PGBOUNCER_DEFAULT_POOL_SIZE:=20}" "${PGBOUNCER_MAX_DB_CONNECTIONS:=100}"
    : "${ENABLE_BACKUPS:=yes}" "${BACKUP_FULL_ONCALENDAR:=Sun *-*-* 02:00:00}"
    : "${BACKUP_DIFF_ONCALENDAR:=Mon..Sat *-*-* 02:00:00}"
    : "${BACKUP_RETENTION_FULL:=4}" "${BACKUP_RETENTION_DIFF:=14}"
    : "${BACKUP_S3_BUCKET:=}" "${BACKUP_S3_ENDPOINT:=}" "${BACKUP_S3_REGION:=}" "${BACKUP_S3_KEY:=}"
    : "${BACKUP_S3_KEY_SECRET:=}" "${BACKUP_S3_URI_STYLE:=host}" "${BACKUP_S3_PATH:=/pgbackrest}"
    : "${ALERT_WEBHOOK_URL:=}" "${ENABLE_EXPORTER:=no}"
    : "${PRIMARY_HOST:=}" "${PRIMARY_PORT:=5432}" "${REPLICA_SLOT:=replica1}" "${FORCE_WIPE:=no}"
    : "${REPLICATION_PASSWORD:=}" "${PGBOUNCER_AUTH_PASSWORD:=}" "${PGBOUNCER_ADMIN_PASSWORD:=}"
    : "${MONITOR_PASSWORD:=}" "${BACKUP_CIPHER_PASS:=}"
    : "${APP_DB_NAME:=}" "${APP_DB_USER:=}" "${APP_DB_PASSWORD:=}"
}

ask() { # ask "prompt" VAR   (no eval; printf -v)
    local prompt="$1" var="$2" cur="${!2}" ans
    read -r -p "${prompt} [${cur}]: " ans || true
    [[ -z "${ans}" ]] || printf -v "${var}" '%s' "${ans}"
}

interactive_prompts() {
    [[ "${INTERACTIVE}" == yes ]] || return 0
    [[ -t 0 ]] || die "--interactive needs a terminal"
    section "INTERACTIVE CONFIGURATION (Enter keeps the value in brackets)"
    ask "Role (primary/replica)" ROLE
    ask "Postgres listen addresses (localhost, '*', or an IP)" PG_LISTEN_ADDRESSES
    ask "Allowed client CIDRs (comma separated, empty = local only)" ALLOWED_CIDRS
    ask "Expose PgBouncer on (127.0.0.1 or '*')" PGBOUNCER_LISTEN
    ask "Enable UFW firewall (yes/no)" ENABLE_FIREWALL
    ask "Enable Fail2Ban for SSH (yes/no)" ENABLE_FAIL2BAN
    ask "Enable backups (yes/no)" ENABLE_BACKUPS
    ask "S3 bucket for off-site backups (empty = none)" BACKUP_S3_BUCKET
    if [[ -n "${BACKUP_S3_BUCKET}" ]]; then
        ask "S3 endpoint" BACKUP_S3_ENDPOINT; ask "S3 region" BACKUP_S3_REGION
        ask "S3 access key" BACKUP_S3_KEY
        read -r -s -p "S3 secret key: " BACKUP_S3_KEY_SECRET; echo
    fi
    if [[ "${ROLE}" == replica ]]; then ask "Primary host" PRIMARY_HOST; fi
}

# ----------------------------------------------------------------------------
# validation
# ----------------------------------------------------------------------------
is_yes() { [[ "$1" == yes ]]; }
need_int() { [[ "${2}" =~ ^[0-9]+$ ]] || die "$1 must be a number (got '${2}')"; }
valid_secret() { [[ "$1" =~ ^[A-Za-z0-9._~+=-]{16,128}$ ]]; }
valid_ident() { [[ "$1" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; }

validate_config() {
    [[ "${ROLE}" == primary || "${ROLE}" == replica ]] || die "ROLE must be primary or replica"
    need_int PG_PORT "${PG_PORT}"; need_int PGBOUNCER_PORT "${PGBOUNCER_PORT}"
    need_int PG_MAX_CONNECTIONS "${PG_MAX_CONNECTIONS}"
    [[ "${PG_PORT}" != "${PGBOUNCER_PORT}" ]] || die "PG_PORT and PGBOUNCER_PORT must differ"
    [[ "${PGBOUNCER_POOL_MODE}" =~ ^(session|transaction|statement)$ ]] || die "invalid PGBOUNCER_POOL_MODE"
    [[ "${PG_LISTEN_ADDRESSES}" =~ ^[A-Za-z0-9.:,*_-]+$ ]] || die "invalid PG_LISTEN_ADDRESSES"
    [[ "${PGBOUNCER_LISTEN}" =~ ^[A-Za-z0-9.:*_-]+$ ]] || die "invalid PGBOUNCER_LISTEN"
    [[ "${PG_MAX_WAL_SIZE}" =~ ^[0-9]+(MB|GB)$ && "${PG_MAX_SLOT_WAL_KEEP_SIZE}" =~ ^[0-9]+(MB|GB)$ ]] || die "WAL sizes need an MB/GB suffix"
    [[ "${REPLICA_SLOT}" =~ ^[a-z0-9_]{1,63}$ ]] || die "REPLICA_SLOT must be lowercase letters, digits, underscore"
    [[ "${BACKUP_S3_URI_STYLE}" =~ ^(host|path)$ ]] || die "BACKUP_S3_URI_STYLE must be host or path"
    local c
    if [[ -n "${ALLOWED_CIDRS}" ]]; then
        IFS=',' read -ra _c <<< "${ALLOWED_CIDRS}"
        for c in "${_c[@]}"; do
            c="${c//[[:space:]]/}"
            [[ "${c}" =~ ^[0-9a-fA-F:.]+/[0-9]+$ ]] || die "ALLOWED_CIDRS entry '${c}' must be CIDR (use /32 for a single IP)"
            [[ "${c}" != 0.0.0.0/0 && "${c}" != ::/0 ]] || die "refusing ${c}: list specific networks"
        done
    fi
    [[ -z "${APP_DB_NAME}${APP_DB_USER}" ]] || { valid_ident "${APP_DB_NAME}" && valid_ident "${APP_DB_USER}" || die "APP_DB_NAME/USER must match ^[a-z_][a-z0-9_]{0,62}\$"; }
    if [[ -n "${BACKUP_S3_BUCKET}" ]]; then
        local v; for v in BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_KEY BACKUP_S3_KEY_SECRET; do
            [[ -n "${!v}" ]] || die "${v} is required when BACKUP_S3_BUCKET is set"
        done
    fi
    if [[ "${ROLE}" == replica ]]; then
        [[ -n "${PRIMARY_HOST}" ]] || die "PRIMARY_HOST is required for ROLE=replica"
        [[ "${PRIMARY_HOST}" =~ ^[A-Za-z0-9.:_-]+$ ]] || die "invalid PRIMARY_HOST"
    fi
    if [[ -n "${PG_SSL_CERT_FILE}${PG_SSL_KEY_FILE}" ]]; then
        [[ "${PG_SSL_CERT_FILE}" == /* && "${PG_SSL_KEY_FILE}" == /* && -f "${PG_SSL_CERT_FILE}" && -f "${PG_SSL_KEY_FILE}" ]] || die "PG_SSL_CERT_FILE and PG_SSL_KEY_FILE must both be existing absolute paths"
    fi
}

# ----------------------------------------------------------------------------
# secrets: config/env value > stored value > generated; always persisted
# ----------------------------------------------------------------------------
cred_read() { [[ -f "${CRED_FILE}" ]] && sed -n "s/^$1=//p" "${CRED_FILE}" | tail -1 || true; }
cred_write() {
    local k="$1" v="$2"
    touch "${CRED_FILE}"; chmod 600 "${CRED_FILE}"
    if grep -q "^${k}=" "${CRED_FILE}"; then
        local tmp; tmp="$(mktemp)"; chmod 600 "${tmp}"
        grep -v "^${k}=" "${CRED_FILE}" > "${tmp}" || true
        printf '%s=%s\n' "${k}" "${v}" >> "${tmp}"; mv "${tmp}" "${CRED_FILE}"
    else
        printf '%s=%s\n' "${k}" "${v}" >> "${CRED_FILE}"
    fi
}
secret() { # secret VAR [generate|require]
    local var="$1" mode="${2:-generate}" val="${!1}" stored
    if [[ -z "${val}" ]]; then
        stored="$(cred_read "${var}")"; val="${stored}"
    fi
    if [[ -z "${val}" ]]; then
        [[ "${mode}" == generate ]] || die "${var} must be provided (copy it from the primary's ${CRED_FILE})"
        val="$(openssl rand -hex 24)"
    fi
    valid_secret "${val}" || die "${var} must be 16-128 chars of [A-Za-z0-9._~+=-]"
    printf -v "${var}" '%s' "${val}"
    cred_write "${var}" "${val}"
}

# ----------------------------------------------------------------------------
# preflight
# ----------------------------------------------------------------------------
preflight() {
    section "Preflight"
    [[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0 ..."
    install -d -m 0700 "${STATE_DIR}"
    touch "${LOG_FILE}"; chmod 600 "${LOG_FILE}"
    [[ -f /etc/os-release ]] || die "cannot detect OS"
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID}" == ubuntu && "${VERSION_ID}" =~ ^(22\.04|24\.04)$ ]] || die "supported: Ubuntu 22.04 / 24.04 (found ${PRETTY_NAME})"
    command -v systemctl >/dev/null || die "systemd is required"
    [[ "$(ps -p 1 -o comm=)" == systemd ]] || die "systemd must be PID 1 (containers are not supported — use the Docker Compose project)"
    local free_mb; free_mb="$(df -Pm /var/lib | awk 'NR==2{print $4}')"
    (( free_mb > 5000 )) || warn "only ${free_mb}MB free under /var/lib — Postgres + WAL + local backups need much more"
    log "OS: ${PRETTY_NAME} | role: ${ROLE} | script ${SCRIPT_VERSION}"
}

# ----------------------------------------------------------------------------
# packages
# ----------------------------------------------------------------------------
apt_install() { apt-get install -y -qq --no-install-recommends "$@" >>"${LOG_FILE}" 2>&1; }

install_packages() {
    section "Packages"
    apt-get update -qq >>"${LOG_FILE}" 2>&1
    apt_install ca-certificates curl gnupg lsb-release openssl jq
    if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
        install -d -m 0755 /usr/share/keyrings
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --yes -o /usr/share/keyrings/postgresql-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
            > /etc/apt/sources.list.d/pgdg.list
        apt-get update -qq >>"${LOG_FILE}" 2>&1
    fi
    local pkgs=("postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" "postgresql-${PG_VERSION}-pgaudit" pgbackrest logrotate)
    is_yes "${ENABLE_PGBOUNCER}" && pkgs+=(pgbouncer)
    is_yes "${ENABLE_FIREWALL}" && pkgs+=(ufw)
    is_yes "${ENABLE_FAIL2BAN}" && pkgs+=(fail2ban)
    is_yes "${ENABLE_EXPORTER}" && pkgs+=(prometheus-postgres-exporter)
    apt_install "${pkgs[@]}"
    # The packaged service units must not start a second, unmanaged pgbouncer with the stock config
    # until we have written ours; they are (re)started explicitly later.
    log "packages installed"
}

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
as_pg() { runuser -u postgres -- "$@"; }
psql_pg() { as_pg psql -X -v ON_ERROR_STOP=1 -p "${PG_PORT}" "$@"; }
wait_pg() {
    for _ in $(seq 1 60); do
        pg_isready -q -p "${PG_PORT}" -h /var/run/postgresql && return 0; sleep 2
    done
    journalctl -u "${PG_SERVICE}" -n 40 --no-pager >&2 || true
    die "PostgreSQL did not become ready"
}
cidr_list() { local c; IFS=',' read -ra _l <<< "${ALLOWED_CIDRS}"; for c in "${_l[@]}"; do c="${c//[[:space:]]/}"; [[ -n "${c}" ]] && echo "${c}"; done; }

# ----------------------------------------------------------------------------
# cluster
# ----------------------------------------------------------------------------
prepare_cluster() {
    section "Cluster"
    if ! pg_lsclusters -h | awk '{print $1" "$2}' | grep -qx "${PG_VERSION} ${PG_CLUSTER}"; then
        local initopts=(); is_yes "${ENABLE_DATA_CHECKSUMS}" && initopts+=(--data-checksums)
        pg_createcluster "${PG_VERSION}" "${PG_CLUSTER}" -e UTF8 --locale C.UTF-8 -- "${initopts[@]}"
        log "created cluster ${PG_VERSION}/${PG_CLUSTER}"
    elif [[ ! -f "${STATE_DIR}/cluster.initialized" ]] && is_yes "${ENABLE_DATA_CHECKSUMS}" && [[ "${ROLE}" == primary ]]; then
        # Debian creates the cluster without checksums. Re-create it only if it is demonstrably untouched.
        systemctl start "${PG_SERVICE}" || true
        wait_pg_any
        local extra; extra="$(as_pg psql -X -Atq -p "$(cluster_port)" -c "select count(*) from pg_database where not datistemplate and datname <> 'postgres'" || echo 1)"
        local rolecount; rolecount="$(as_pg psql -X -Atq -p "$(cluster_port)" -c "select count(*) from pg_roles where rolname !~ '^pg_' and rolname <> 'postgres'" || echo 1)"
        if [[ "${extra}" == 0 && "${rolecount}" == 0 ]]; then
            log "fresh default cluster detected — re-creating it with data checksums"
            pg_dropcluster --stop "${PG_VERSION}" "${PG_CLUSTER}"
            pg_createcluster "${PG_VERSION}" "${PG_CLUSTER}" -e UTF8 --locale C.UTF-8 -- --data-checksums
        else
            warn "cluster already contains data/roles — leaving it as is (data checksums NOT enabled; see pg_checksums)"
        fi
    fi
    touch "${STATE_DIR}/cluster.initialized"
    install -d -m 0755 "${PG_ETC}/conf.d"
    grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf.d'" "${PG_ETC}/postgresql.conf" \
        || printf "\ninclude_dir = 'conf.d'\n" >> "${PG_ETC}/postgresql.conf"
}
cluster_port() { pg_lsclusters -h | awk -v v="${PG_VERSION}" -v c="${PG_CLUSTER}" '$1==v && $2==c {print $3}'; }
wait_pg_any() { local p; for _ in $(seq 1 30); do p="$(cluster_port)"; pg_isready -q -p "${p}" -h /var/run/postgresql && return 0; sleep 2; done; die "default cluster did not start"; }

# ----------------------------------------------------------------------------
# TLS
# ----------------------------------------------------------------------------
setup_tls() {
    section "TLS"
    install -d -m 0750 -o postgres -g postgres "${PG_CERT_DIR}"
    if [[ -n "${PG_SSL_CERT_FILE}" ]]; then
        install -m 0644 -o postgres -g postgres "${PG_SSL_CERT_FILE}" "${PG_CERT_DIR}/server.crt"
        install -m 0600 -o postgres -g postgres "${PG_SSL_KEY_FILE}"  "${PG_CERT_DIR}/server.key"
        log "using supplied certificate"
    elif [[ ! -f "${PG_CERT_DIR}/server.crt" || ! -f "${PG_CERT_DIR}/server.key" ]]; then
        openssl req -x509 -newkey rsa:3072 -sha256 -days 825 -nodes \
            -subj "/CN=$(hostname -f 2>/dev/null || hostname)" \
            -keyout "${PG_CERT_DIR}/server.key" -out "${PG_CERT_DIR}/server.crt" 2>/dev/null
        chown postgres:postgres "${PG_CERT_DIR}/server.crt" "${PG_CERT_DIR}/server.key"
        chmod 0644 "${PG_CERT_DIR}/server.crt"; chmod 0600 "${PG_CERT_DIR}/server.key"
        warn "generated a self-signed certificate; supply PG_SSL_CERT_FILE/PG_SSL_KEY_FILE if clients use verify-full"
    fi
}

# ----------------------------------------------------------------------------
# postgresql.conf (drop-in) and pg_hba.conf
# ----------------------------------------------------------------------------
calc_memory() {
    local mem_mb; mem_mb="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
    local sb=$(( mem_mb / 4 )) ecs=$(( mem_mb * 3 / 4 )) mw=$(( mem_mb / 16 ))
    (( sb < 128 )) && sb=128; (( sb > 16384 )) && sb=16384
    (( mw < 64 )) && mw=64;   (( mw > 2048 )) && mw=2048
    local wm=$(( (mem_mb - sb) / (PG_MAX_CONNECTIONS * 3) ))
    (( wm < 4 )) && wm=4; (( wm > 64 )) && wm=64
    : "${PG_SHARED_BUFFERS_MB:=${sb}}" "${PG_EFFECTIVE_CACHE_MB:=${ecs}}" "${PG_WORK_MEM_MB:=${wm}}" "${PG_MAINTENANCE_WORK_MEM_MB:=${mw}}"
    log "RAM ${mem_mb}MB -> shared_buffers ${PG_SHARED_BUFFERS_MB}MB, effective_cache_size ${PG_EFFECTIVE_CACHE_MB}MB, work_mem ${PG_WORK_MEM_MB}MB, maintenance_work_mem ${PG_MAINTENANCE_WORK_MEM_MB}MB"
}

write_pg_conf() {
    section "postgresql.conf"
    calc_memory
    local archive_block
    if [[ "${ROLE}" == primary ]] && is_yes "${ENABLE_BACKUPS}"; then
        archive_block="archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push \"%p\"'
archive_timeout = 60"
    else
        archive_block="archive_mode = off"
    fi
    local replica_block=""
    if [[ "${ROLE}" == replica ]]; then
        replica_block="primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=replicator passfile=/var/lib/postgresql/.pgpass sslmode=require application_name=${REPLICA_SLOT}'
primary_slot_name = '${REPLICA_SLOT}'"
    fi
    cp -a "${PG_ETC}/conf.d/90-setup.conf" "${PG_ETC}/conf.d/90-setup.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    cat > "${PG_ETC}/conf.d/90-setup.conf" <<EOF
# Managed by setup-postgres17.sh ${SCRIPT_VERSION} — re-running the script regenerates this file.
# Put your own overrides in a later file (e.g. 95-local.conf).

# connections
port = ${PG_PORT}
listen_addresses = '${PG_LISTEN_ADDRESSES}'
max_connections = ${PG_MAX_CONNECTIONS}
tcp_keepalives_idle = 60
tcp_keepalives_interval = 10
tcp_keepalives_count = 6
idle_in_transaction_session_timeout = '10min'

# memory
shared_buffers = '${PG_SHARED_BUFFERS_MB}MB'
effective_cache_size = '${PG_EFFECTIVE_CACHE_MB}MB'
work_mem = '${PG_WORK_MEM_MB}MB'
maintenance_work_mem = '${PG_MAINTENANCE_WORK_MEM_MB}MB'

# security
password_encryption = 'scram-sha-256'
ssl = on
ssl_cert_file = '${PG_CERT_DIR}/server.crt'
ssl_key_file = '${PG_CERT_DIR}/server.key'
ssl_min_protocol_version = 'TLSv1.2'
ssl_prefer_server_ciphers = on
ssl_ciphers = 'HIGH:!aNULL:!MD5:!3DES'

# WAL, archiving, replication
wal_level = replica
wal_compression = on
wal_log_hints = on
max_wal_senders = 10
max_replication_slots = 10
max_wal_size = '${PG_MAX_WAL_SIZE}'
min_wal_size = '1GB'
max_slot_wal_keep_size = '${PG_MAX_SLOT_WAL_KEEP_SIZE}'
checkpoint_timeout = '15min'
checkpoint_completion_target = 0.9
hot_standby = on
hot_standby_feedback = on
${archive_block}
${replica_block}

# planner (SSD/NVMe assumed)
random_page_cost = 1.1
effective_io_concurrency = 200

# extensions / statistics
shared_preload_libraries = 'pg_stat_statements,pgaudit'
pg_stat_statements.track = all
pgaudit.log = 'ddl,role'
pgaudit.log_catalog = off
track_io_timing = on
track_functions = pl

# logging (Debian writes stderr to /var/log/postgresql/postgresql-${PG_VERSION}-${PG_CLUSTER}.log, rotated by logrotate)
log_line_prefix = '%m [%p] %q%u@%d/%a '
log_min_duration_statement = ${PG_LOG_MIN_DURATION_MS}
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_temp_files = '10MB'
log_autovacuum_min_duration = '1s'
log_timezone = 'UTC'
timezone = 'UTC'
EOF
    chown postgres:postgres "${PG_ETC}/conf.d/90-setup.conf"; chmod 0644 "${PG_ETC}/conf.d/90-setup.conf"
}

write_pg_hba() {
    section "pg_hba.conf"
    cp -a "${PG_ETC}/pg_hba.conf" "${PG_ETC}/pg_hba.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    {
        echo "# Managed by setup-postgres17.sh ${SCRIPT_VERSION}"
        echo "# TYPE    DATABASE     USER         ADDRESS            METHOD"
        echo "local     all          all                             peer"
        echo "local     replication  all                             peer"
        echo "# superuser + replication role never log in to normal databases over TCP"
        echo "host      all          postgres     0.0.0.0/0          reject"
        echo "host      all          postgres     ::/0               reject"
        echo "host      all          replicator   0.0.0.0/0          reject"
        echo "host      all          replicator   ::/0               reject"
        echo "hostnossl all          all          0.0.0.0/0          reject"
        echo "hostnossl all          all          ::/0               reject"
        echo "# local PgBouncer / exporter"
        echo "hostssl   all          all          127.0.0.1/32       scram-sha-256"
        echo "hostssl   all          all          ::1/128            scram-sha-256"
        local c
        while IFS= read -r c; do
            [[ -n "${c}" ]] || continue
            echo "hostssl   replication  replicator   ${c}   scram-sha-256"
            if is_yes "${PG_DIRECT_ACCESS}"; then echo "hostssl   all          all          ${c}   scram-sha-256"; fi
        done < <(cidr_list)
    } > "${PG_ETC}/pg_hba.conf"
    chown postgres:postgres "${PG_ETC}/pg_hba.conf"; chmod 0640 "${PG_ETC}/pg_hba.conf"
}

# ----------------------------------------------------------------------------
# roles & PgBouncer auth function (primary)
# ----------------------------------------------------------------------------
bootstrap_roles() {
    section "Roles"
    export REPL_PW="${REPLICATION_PASSWORD}" AUTH_PW="${PGBOUNCER_AUTH_PASSWORD}" MON_PW="${MONITOR_PASSWORD}"
    psql_pg -d postgres <<'SQL'
\getenv repl_pw REPL_PW
\getenv auth_pw AUTH_PW
\getenv mon_pw  MON_PW

SELECT format('CREATE ROLE replicator LOGIN REPLICATION') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='replicator') \gexec
SELECT format('ALTER ROLE replicator WITH LOGIN REPLICATION PASSWORD %L', :'repl_pw') \gexec
SELECT format('CREATE ROLE pgbouncer_auth LOGIN') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='pgbouncer_auth') \gexec
SELECT format('ALTER ROLE pgbouncer_auth WITH LOGIN PASSWORD %L', :'auth_pw') \gexec
SELECT format('CREATE ROLE monitor LOGIN') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='monitor') \gexec
SELECT format('ALTER ROLE monitor WITH LOGIN PASSWORD %L', :'mon_pw') \gexec
GRANT pg_monitor TO monitor;

CREATE SCHEMA IF NOT EXISTS pgbouncer;
CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename text)
RETURNS TABLE (usename name, passwd text)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS
$$ SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename = p_usename $$;
REVOKE ALL ON FUNCTION pgbouncer.get_auth(text) FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO pgbouncer_auth;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(text) TO pgbouncer_auth;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL
    # Do NOT install pg_stat_statements into template1.
    # If installed in template1, all newly created databases inherit pg_stat_statements_reset()
    # owned by postgres in public schema. When non-superuser app roles run
    # 'GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "public"', PostgreSQL fails with
    # "ERROR: permission denied for function pg_stat_statements_reset".
    unset REPL_PW AUTH_PW MON_PW
    if [[ -n "${APP_DB_NAME}" && -n "${APP_DB_USER}" && -n "${APP_DB_PASSWORD}" ]]; then
        APP_PASSWORD="${APP_DB_PASSWORD}" "${BIN_DIR}/pg-create-db" "${APP_DB_NAME}" "${APP_DB_USER}"
    fi
}

# ----------------------------------------------------------------------------
# replica bootstrap
# ----------------------------------------------------------------------------
setup_replica_data() {
    section "Replica bootstrap"
    if [[ -f "${STATE_DIR}/replica.cloned" ]]; then log "replica already cloned from a primary — skipping"; return 0; fi
    if [[ "${FORCE_WIPE}" != yes ]]; then
        [[ -t 0 ]] || die "this will DELETE ${PG_DATA}. Re-run with FORCE_WIPE=yes (or --yes) to confirm."
        read -r -p "This DELETES all data in ${PG_DATA} and clones ${PRIMARY_HOST}. Type 'yes' to continue: " a
        [[ "${a}" == yes ]] || die "aborted"
    fi
    esc() { local s="${1//\\/\\\\}"; printf '%s' "${s//:/\\:}"; }
    printf '%s:%s:*:replicator:%s\n' "${PRIMARY_HOST}" "${PRIMARY_PORT}" "$(esc "${REPLICATION_PASSWORD}")" > /var/lib/postgresql/.pgpass
    chown postgres:postgres /var/lib/postgresql/.pgpass; chmod 0600 /var/lib/postgresql/.pgpass
    systemctl stop "${PG_SERVICE}" || true
    until PGSSLMODE=require as_pg env PGPASSFILE=/var/lib/postgresql/.pgpass pg_isready -q -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}"; do log "waiting for ${PRIMARY_HOST}..."; sleep 3; done
    find "${PG_DATA}" -mindepth 1 -delete
    local bb=(env PGSSLMODE=require PGPASSFILE=/var/lib/postgresql/.pgpass pg_basebackup -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U replicator -D "${PG_DATA}" -X stream --checkpoint=fast -S "${REPLICA_SLOT}")
    if ! as_pg "${bb[@]}" -C; then
        warn "slot ${REPLICA_SLOT} may already exist — retrying with it"
        find "${PG_DATA}" -mindepth 1 -delete
        as_pg "${bb[@]}"
    fi
    as_pg touch "${PG_DATA}/standby.signal"
    touch "${STATE_DIR}/replica.cloned"
    log "replica cloned from ${PRIMARY_HOST}"
}

# ----------------------------------------------------------------------------
# pgBackRest + systemd timers
# ----------------------------------------------------------------------------
setup_pgbackrest() {
    section "pgBackRest"
    umask 077
    {
        cat <<EOF
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=${BACKUP_RETENTION_FULL}
repo1-retention-diff=${BACKUP_RETENTION_DIFF}
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=${BACKUP_CIPHER_PASS}
compress-type=zst
compress-level=3
process-max=2
start-fast=y
delta=y
archive-async=y
spool-path=/var/spool/pgbackrest
archive-push-queue-max=10GiB
log-level-console=info
log-level-file=info
EOF
        if [[ -n "${BACKUP_S3_BUCKET}" ]]; then
            cat <<EOF
repo2-type=s3
repo2-path=${BACKUP_S3_PATH}
repo2-s3-bucket=${BACKUP_S3_BUCKET}
repo2-s3-endpoint=${BACKUP_S3_ENDPOINT}
repo2-s3-region=${BACKUP_S3_REGION}
repo2-s3-key=${BACKUP_S3_KEY}
repo2-s3-key-secret=${BACKUP_S3_KEY_SECRET}
repo2-s3-uri-style=${BACKUP_S3_URI_STYLE}
repo2-cipher-type=aes-256-cbc
repo2-cipher-pass=${BACKUP_CIPHER_PASS}
repo2-retention-full=${BACKUP_RETENTION_FULL}
repo2-retention-diff=${BACKUP_RETENTION_DIFF}
EOF
        fi
        cat <<EOF

[main]
pg1-path=${PG_DATA}
pg1-port=${PG_PORT}
pg1-socket-path=/var/run/postgresql
pg1-user=postgres
EOF
    } > /etc/pgbackrest/pgbackrest.conf
    umask 022
    chown postgres:postgres /etc/pgbackrest/pgbackrest.conf; chmod 0600 /etc/pgbackrest/pgbackrest.conf
    install -d -m 0750 -o postgres -g postgres /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
    {
        echo "ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL}"
    } > "${RUNTIME_FILE}"
    chmod 600 "${RUNTIME_FILE}"
}

finish_pgbackrest() {
    as_pg pgbackrest --stanza=main stanza-create
    as_pg pgbackrest --stanza=main check || warn "pgbackrest check failed — see: journalctl -u ${PG_SERVICE} and /var/log/pgbackrest"
    if ! as_pg pgbackrest --stanza=main info --output=json | jq -e '.[0].backup | length > 0' >/dev/null 2>&1; then
        log "taking initial full backup (this can take a while)"
        "${BIN_DIR}/pg-backup" full || warn "initial backup failed"
    fi
    cat > /etc/systemd/system/pg-backup@.service <<'EOF'
[Unit]
Description=PostgreSQL pgBackRest %i backup
After=postgresql.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pg-backup %i
Nice=10
IOSchedulingClass=idle
EOF
    local t
    for t in full diff; do
        local cal; [[ "${t}" == full ]] && cal="${BACKUP_FULL_ONCALENDAR}" || cal="${BACKUP_DIFF_ONCALENDAR}"
        cat > "/etc/systemd/system/pg-backup-${t}.timer" <<EOF
[Unit]
Description=PostgreSQL ${t} backup schedule

[Timer]
OnCalendar=${cal}
RandomizedDelaySec=10min
Persistent=true
Unit=pg-backup@${t}.service

[Install]
WantedBy=timers.target
EOF
    done
    systemctl daemon-reload
    systemctl enable --now pg-backup-full.timer pg-backup-diff.timer >>"${LOG_FILE}" 2>&1
    log "backup timers enabled (systemctl list-timers 'pg-backup-*')"
}

# ----------------------------------------------------------------------------
# PgBouncer
# ----------------------------------------------------------------------------
setup_pgbouncer() {
    section "PgBouncer"
    local ver prep=""
    ver="$(pgbouncer --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 0.0)"
    if [[ "$(printf '%s\n1.21\n' "${ver}" | sort -V | head -1)" == "1.21" ]]; then prep="max_prepared_statements = 100"; fi
    local reset=""; [[ "${PGBOUNCER_POOL_MODE}" == session ]] && reset="DISCARD ALL"
    q() { local s="${1//\"/\"\"}"; printf '"%s"' "${s}"; }
    cp -a /etc/pgbouncer/pgbouncer.ini "/etc/pgbouncer/pgbouncer.ini.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    umask 077
    { printf '%s %s\n' "$(q pgbouncer_auth)" "$(q "${PGBOUNCER_AUTH_PASSWORD}")"
      printf '%s %s\n' "$(q pgbouncer_admin)" "$(q "${PGBOUNCER_ADMIN_PASSWORD}")"; } > /etc/pgbouncer/userlist.txt
    umask 022
    chown postgres:postgres /etc/pgbouncer/userlist.txt; chmod 0600 /etc/pgbouncer/userlist.txt
    cat > /etc/pgbouncer/pgbouncer.ini <<EOF
; Managed by setup-postgres17.sh ${SCRIPT_VERSION}
[databases]
* = host=127.0.0.1 port=${PG_PORT} auth_dbname=postgres

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
unix_socket_dir = /var/run/postgresql
listen_addr = ${PGBOUNCER_LISTEN}
listen_port = ${PGBOUNCER_PORT}

auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
auth_user = pgbouncer_auth
auth_query = SELECT usename, passwd FROM pgbouncer.get_auth(\$1)
admin_users = pgbouncer_admin
stats_users = pgbouncer_admin

pool_mode = ${PGBOUNCER_POOL_MODE}
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE}
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = ${PGBOUNCER_MAX_DB_CONNECTIONS}
server_reset_query = ${reset}
ignore_startup_parameters = extra_float_digits,options
${prep}

server_lifetime = 3600
server_idle_timeout = 600
query_wait_timeout = 120

client_tls_sslmode = require
client_tls_key_file = ${PG_CERT_DIR}/server.key
client_tls_cert_file = ${PG_CERT_DIR}/server.crt
client_tls_protocols = secure
server_tls_sslmode = require

log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
stats_period = 60
EOF
    chown postgres:postgres /etc/pgbouncer/pgbouncer.ini; chmod 0640 /etc/pgbouncer/pgbouncer.ini
    systemctl enable pgbouncer >>"${LOG_FILE}" 2>&1
    systemctl restart pgbouncer
    sleep 2
    systemctl is-active --quiet pgbouncer || { journalctl -u pgbouncer -n 30 --no-pager >&2; die "pgbouncer failed to start"; }
    log "PgBouncer listening on ${PGBOUNCER_LISTEN}:${PGBOUNCER_PORT} (pool_mode=${PGBOUNCER_POOL_MODE})"
}

# ----------------------------------------------------------------------------
# firewall, fail2ban, sysctl, exporter
# ----------------------------------------------------------------------------
detect_ssh_ports() {
    if [[ -n "${SSH_PORT}" ]]; then echo "${SSH_PORT}"; return; fi
    local p; p="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -u)"
    echo "${p:-22}"
}

setup_firewall() {
    is_yes "${ENABLE_FIREWALL}" || { warn "firewall disabled by configuration"; return 0; }
    section "UFW firewall (existing rules are preserved)"
    local p c
    for p in $(detect_ssh_ports); do need_int SSH_PORT "${p}"; ufw allow "${p}/tcp" comment 'SSH' >/dev/null; done
    while IFS= read -r c; do
        [[ -n "${c}" ]] || continue
        if is_yes "${ENABLE_PGBOUNCER}"; then ufw allow from "${c}" to any port "${PGBOUNCER_PORT}" proto tcp comment 'PgBouncer' >/dev/null; fi
        if is_yes "${PG_DIRECT_ACCESS}" || [[ "${ROLE}" == primary && -n "${PG_LISTEN_ADDRESSES//localhost/}" ]]; then
            ufw allow from "${c}" to any port "${PG_PORT}" proto tcp comment 'PostgreSQL' >/dev/null
        fi
    done < <(cidr_list)
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw --force enable >/dev/null
    log "UFW enabled (SSH port(s): $(detect_ssh_ports | tr '\n' ' '))"
}

setup_fail2ban() {
    is_yes "${ENABLE_FAIL2BAN}" || return 0
    section "Fail2Ban (SSH only)"
    cat > /etc/fail2ban/jail.d/10-sshd.local <<'EOF'
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
    systemctl enable fail2ban >>"${LOG_FILE}" 2>&1
    systemctl restart fail2ban
}

setup_sysctl() {
    section "Kernel tuning"
    cat > /etc/sysctl.d/90-postgres.conf <<'EOF'
vm.swappiness = 10
EOF
    sysctl -q --system >>"${LOG_FILE}" 2>&1 || true
}

setup_exporter() {
    is_yes "${ENABLE_EXPORTER}" || return 0
    section "Prometheus exporter"
    cat > /etc/default/prometheus-postgres-exporter <<EOF
DATA_SOURCE_NAME='postgresql://monitor:${MONITOR_PASSWORD}@127.0.0.1:${PG_PORT}/postgres?sslmode=require'
ARGS='--web.listen-address=127.0.0.1:9187'
EOF
    chmod 600 /etc/default/prometheus-postgres-exporter
    systemctl enable prometheus-postgres-exporter >>"${LOG_FILE}" 2>&1
    systemctl restart prometheus-postgres-exporter
    log "exporter on 127.0.0.1:9187 (scrape via SSH tunnel or a local Prometheus)"
}

setup_logrotate() {
    cat > /etc/logrotate.d/pg-setup <<'EOF'
/var/log/pg-setup.log /var/log/pgbackrest/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
}
EOF
}

# ----------------------------------------------------------------------------
# operator helper commands
# ----------------------------------------------------------------------------
install_helpers() {
    section "Helper commands in ${BIN_DIR}"

    cat > "${BIN_DIR}/pg-backup" <<'EOF'
#!/usr/bin/env bash
# pg-backup [full|diff|incr]  — backs up to every configured pgBackRest repository.
set -Eeuo pipefail
[[ "${EUID}" -eq 0 ]] || exec sudo "$0" "$@"
type="${1:-diff}"
case "${type}" in full|diff|incr) ;; *) echo "usage: pg-backup [full|diff|incr]" >&2; exit 2 ;; esac
rc=0
mapfile -t repos < <(grep -oE '^repo[0-9]+-path' /etc/pgbackrest/pgbackrest.conf | grep -oE '[0-9]+')
for repo in "${repos[@]}"; do
    echo "== ${type} backup -> repo${repo} =="
    runuser -u postgres -- pgbackrest --stanza=main --repo="${repo}" --type="${type}" backup || rc=1
done
if [[ "${rc}" -ne 0 ]]; then
    url="$(sed -n 's/^ALERT_WEBHOOK_URL=//p' /etc/pg-setup/runtime.env 2>/dev/null | tail -1 || true)"
    if [[ -n "${url}" ]]; then
        curl -fsS -m 15 -H 'Content-Type: application/json' \
            -d "$(jq -n --arg t "pgBackRest ${type} backup FAILED on $(hostname)" '{text:$t}')" "${url}" >/dev/null || true
    fi
fi
exit "${rc}"
EOF

    cat > "${BIN_DIR}/pg-create-db" <<'EOF'
#!/usr/bin/env bash
# pg-create-db <database> <role>   (password from $APP_PASSWORD or interactive prompt)
set -Eeuo pipefail
[[ "${EUID}" -ne 0 ]] || exec runuser -u postgres -- "$0" "$@"
db="${1:?usage: pg-create-db <database> <role>}"; role="${2:?usage: pg-create-db <database> <role>}"
re='^[a-z_][a-z0-9_]{0,62}$'
[[ "${db}" =~ ${re} && "${role}" =~ ${re} ]] || { echo "names must match ${re}" >&2; exit 1; }
if [[ -z "${APP_PASSWORD:-}" ]]; then
    read -rsp "Password for ${role}: " APP_PASSWORD; echo
    read -rsp "Confirm: " confirm; echo
    [[ "${APP_PASSWORD}" == "${confirm}" ]] || { echo "passwords differ" >&2; exit 1; }
fi
[[ -n "${APP_PASSWORD}" ]] || { echo "empty password" >&2; exit 1; }
export APP_PASSWORD
port="$(pg_lsclusters -h | awk '$1==17 && $2=="main" {print $3}')"
psql -X -v ON_ERROR_STOP=1 -p "${port}" -d postgres -v db="${db}" -v usr="${role}" <<'SQL'
\getenv pw APP_PASSWORD
SELECT format('CREATE ROLE %I LOGIN', :'usr') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'usr') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'usr', :'pw') \gexec
SELECT format('ALTER ROLE %I WITH CREATEDB NOSUPERUSER NOCREATEROLE NOREPLICATION NOBYPASSRLS', :'usr') \gexec
SELECT format('GRANT CONNECT ON DATABASE postgres TO %I', :'usr') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'usr') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db') \gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'db', :'usr') \gexec
SQL
echo "ok: database '${db}' owned by '${role}'"
EOF

    cat > "${BIN_DIR}/pg-status" <<'EOF'
#!/usr/bin/env bash
# pg-status — health report
set -Eeuo pipefail
[[ "${EUID}" -ne 0 ]] || exec runuser -u postgres -- "$0" "$@"
port="$(pg_lsclusters -h | awk '$1==17 && $2=="main" {print $3}')"
q() { psql -X -p "${port}" -d postgres -c "$1"; }
pg_lsclusters
pg_isready -h /var/run/postgresql -p "${port}"
echo; echo "## Connections";  q "SELECT datname, state, count(*) FROM pg_stat_activity WHERE datname IS NOT NULL GROUP BY 1,2 ORDER BY 3 DESC;"
echo "## Database sizes"; q "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE NOT datistemplate ORDER BY pg_database_size(datname) DESC;"
echo "## Replication";    q "SELECT application_name, state, sync_state, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag FROM pg_stat_replication;" || true
echo "## Replication slots"; q "SELECT slot_name, active, wal_status, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;" || true
echo "## WAL archiver";   q "SELECT archived_count, failed_count, last_archived_wal, last_failed_wal, last_failed_time FROM pg_stat_archiver;"
echo "## Long transactions (>5 min)"; q "SELECT pid, usename, now()-xact_start AS age, state, left(query,80) AS query FROM pg_stat_activity WHERE xact_start < now()-interval '5 min' ORDER BY age DESC;"
echo "## Cache hit ratio"; q "SELECT round(100.0*sum(blks_hit)/nullif(sum(blks_hit)+sum(blks_read),0),2) AS hit_pct FROM pg_stat_database;"
echo "## Backups"; pgbackrest --stanza=main info || true
EOF

    cat > "${BIN_DIR}/pg-restore" <<'EOF'
#!/usr/bin/env bash
# pg-restore [--yes] [pgbackrest restore options]
#   latest:  sudo pg-restore
#   PITR:    sudo pg-restore --type=time "--target=2026-10-19 10:15:00+00" --target-action=promote
#   from S3: sudo pg-restore --repo=2
set -Eeuo pipefail
[[ "${EUID}" -eq 0 ]] || exec sudo "$0" "$@"
yes=no; [[ "${1:-}" == "--yes" ]] && { yes=yes; shift; }
if [[ "${yes}" != yes ]]; then
    echo "This STOPS PostgreSQL and OVERWRITES the data directory from the backup repository."
    read -rp "Type 'restore' to continue: " a; [[ "${a}" == restore ]] || exit 1
fi
svc="postgresql@17-main"
systemctl stop pgbouncer 2>/dev/null || true
systemctl stop "${svc}"
runuser -u postgres -- pgbackrest --stanza=main --delta "$@" restore
systemctl start "${svc}"
systemctl start pgbouncer 2>/dev/null || true
echo "Restore finished. Check: journalctl -u ${svc} -n 50; then take a fresh full backup (pg-backup full)."
echo "If you have replicas, re-clone them (their timeline diverged)."
EOF

    cat > "${BIN_DIR}/pg-promote" <<'EOF'
#!/usr/bin/env bash
# pg-promote — promote THIS replica to primary (manual failover). Make sure the old primary is dead/fenced first!
set -Eeuo pipefail
[[ "${EUID}" -eq 0 ]] || exec sudo "$0" "$@"
read -rp "Promote this replica to primary? The old primary MUST be down. Type 'promote': " a
[[ "${a}" == promote ]] || exit 1
pg_ctlcluster 17 main promote
cat <<'MSG'
Promoted. Next steps:
  1. Re-run the setup script with ROLE=primary on this host (creates the pgBackRest stanza, backup timers, archiving).
  2. Point applications / PgBouncer at this host.
  3. Rebuild a new replica from this primary.
MSG
EOF
    chmod 0755 "${BIN_DIR}"/pg-backup "${BIN_DIR}"/pg-create-db "${BIN_DIR}"/pg-status "${BIN_DIR}"/pg-restore "${BIN_DIR}"/pg-promote
}

# ----------------------------------------------------------------------------
# summary
# ----------------------------------------------------------------------------
summary() {
    section "Done"
    cat <<EOF

PostgreSQL ${PG_VERSION} (${ROLE}) is configured.

  Cluster      : ${PG_VERSION}/${PG_CLUSTER}   service: ${PG_SERVICE}
  Postgres     : ${PG_LISTEN_ADDRESSES}:${PG_PORT}   (TLS required, SCRAM, remote superuser rejected)
  PgBouncer    : $(is_yes "${ENABLE_PGBOUNCER}" && echo "${PGBOUNCER_LISTEN}:${PGBOUNCER_PORT} (${PGBOUNCER_POOL_MODE})" || echo disabled)
  Backups      : $([[ "${ROLE}" == primary ]] && is_yes "${ENABLE_BACKUPS}" && echo "pgBackRest, local repo /var/lib/pgbackrest$([[ -n "${BACKUP_S3_BUCKET}" ]] && echo " + S3 ${BACKUP_S3_BUCKET}")" || echo "not configured on this host")
  Firewall     : $(is_yes "${ENABLE_FIREWALL}" && echo "UFW enabled" || echo disabled)
  Credentials  : ${CRED_FILE}   (mode 600 — copy BACKUP_CIPHER_PASS somewhere OFF this server)
  Log          : ${LOG_FILE}

Commands:
  sudo pg-create-db <db> <role>      create a database + owner role
  sudo pg-status                     health / replication / archiver / backups
  sudo pg-backup full|diff           manual backup
  sudo pg-restore [opts]             restore / PITR (stops PostgreSQL)
  sudo pg-promote                    promote a replica
  systemctl list-timers 'pg-backup-*'

Connect (through PgBouncer):
  psql "host=<server> port=${PGBOUNCER_PORT} dbname=<db> user=<role> sslmode=require"

Notes:
  * Docker (if installed) publishes ports around UFW — don't run public containers on this host without care.
  * Rehearse a restore on a scratch VM before you need one.
  * Real automatic failover needs Patroni + a 3-node consensus store; this setup gives manual promotion.
EOF
    if [[ "${ROLE}" == primary && -n "${ALLOWED_CIDRS}" ]]; then
        echo "  * To add a replica: run this script with ROLE=replica on the other host, giving it PRIMARY_HOST and the three"
        echo "    passwords from ${CRED_FILE}; set PG_LISTEN_ADDRESSES on the primary to an address that host can reach."
    fi
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
main() {
    parse_args "$@"
    [[ -z "${CONFIG_FILE}" ]] || CONFIG_FILE="$(realpath "${CONFIG_FILE}")"
    [[ -z "${CONFIG_FILE}" ]] || load_kv_file "${CONFIG_FILE}"
    [[ -z "${CLI_ROLE}" ]] || ROLE="${CLI_ROLE}"
    [[ -z "${CLI_YES}"  ]] || FORCE_WIPE="${CLI_YES}"
    cd /   # postgres-owned child processes must not start in an unreadable cwd such as /root
    set_defaults
    interactive_prompts
    validate_config
    preflight

    # secrets
    if [[ "${ROLE}" == primary ]]; then
        secret REPLICATION_PASSWORD; secret PGBOUNCER_AUTH_PASSWORD; secret PGBOUNCER_ADMIN_PASSWORD; secret MONITOR_PASSWORD
        if is_yes "${ENABLE_BACKUPS}"; then secret BACKUP_CIPHER_PASS; fi
    else
        secret REPLICATION_PASSWORD require
        if is_yes "${ENABLE_PGBOUNCER}"; then secret PGBOUNCER_AUTH_PASSWORD require; secret PGBOUNCER_ADMIN_PASSWORD require; fi
        if is_yes "${ENABLE_EXPORTER}"; then secret MONITOR_PASSWORD require; fi
        ENABLE_BACKUPS=no
    fi
    if [[ -n "${APP_DB_NAME}" ]]; then
        [[ -n "${APP_DB_PASSWORD}" ]] || { APP_DB_PASSWORD="$(openssl rand -hex 24)"; cred_write APP_DB_PASSWORD "${APP_DB_PASSWORD}"; }
        valid_secret "${APP_DB_PASSWORD}" || die "APP_DB_PASSWORD must be 16-128 chars of [A-Za-z0-9._~+=-]"
    fi

    install_packages
    install_helpers
    setup_sysctl
    prepare_cluster
    setup_tls
    write_pg_conf
    write_pg_hba

    if [[ "${ROLE}" == primary ]]; then
        if is_yes "${ENABLE_BACKUPS}"; then setup_pgbackrest; fi
        systemctl enable "${PG_SERVICE}" >>"${LOG_FILE}" 2>&1 || true
        systemctl restart "${PG_SERVICE}"; wait_pg
        [[ "$(as_pg psql -X -Atq -p "${PG_PORT}" -c 'select pg_is_in_recovery()')" == f ]] || die "this cluster is a standby; promote it first (pg-promote)"
        bootstrap_roles
        if is_yes "${ENABLE_BACKUPS}"; then finish_pgbackrest; fi
    else
        setup_replica_data
        systemctl enable "${PG_SERVICE}" >>"${LOG_FILE}" 2>&1 || true
        systemctl restart "${PG_SERVICE}"; wait_pg
        [[ "$(as_pg psql -X -Atq -p "${PG_PORT}" -c 'select pg_is_in_recovery()')" == t ]] || warn "replica is not in recovery — check journalctl -u ${PG_SERVICE}"
    fi

    if is_yes "${ENABLE_PGBOUNCER}"; then setup_pgbouncer; fi
    setup_exporter
    setup_fail2ban
    setup_firewall
    setup_logrotate
    summary
    log "setup finished"
}

main "$@"
