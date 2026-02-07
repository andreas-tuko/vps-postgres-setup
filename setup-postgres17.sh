#!/usr/bin/env bash
# setup-postgres17.sh
# Idempotent, interactive setup for PostgreSQL 17 + pgbouncer, backups, firewall, fail2ban.
# Designed for Ubuntu 24.04+. Edges: uses PGDG repo to install postgresql-17.
# WARNING: Run as root (sudo). Review before running in production.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

STATE_FILE="/etc/pg-setup.conf"
BACKUP_DIR="/var/backups/postgresql"
PG_VERSION="17"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
PG_HBA_FILE="${PG_CONF_DIR}/pg_hba.conf"
PG_CONF_FILE="${PG_CONF_DIR}/postgresql.conf"
PG_SSL_DIR="/etc/ssl/postgresql"
PG_USER="postgres"

# Logging helper
log() { echo "==> $*"; }

# Ensure running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must be run as root (or with sudo)."
  exit 1
fi

# load previous answers if present
if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  . "${STATE_FILE}"
fi

# persist settings helper
save_state() {
  cat > "${STATE_FILE}" <<-EOF
# pg setup state - DO NOT MANUALLY EDIT UNLESS YOU KNOW WHAT YOU'RE DOING
PG_VERSION="${PG_VERSION}"
DB_LISTEN_ADDRESSES="${DB_LISTEN_ADDRESSES:-'localhost'}"
DB_PORT="${DB_PORT:-5432}"
ALLOWED_IPS="${ALLOWED_IPS:-127.0.0.1/32}"
PG_SSL="${PG_SSL:-no}"
SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/postgresql/server.crt}"
SSL_KEY_FILE="${SSL_KEY_FILE:-/etc/ssl/postgresql/server.key}"
ENABLE_WAL_ARCHIVE="${ENABLE_WAL_ARCHIVE:-no}"
WAL_S3_BUCKET="${WAL_S3_BUCKET:-}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
PGBOUNCER_ENABLED="${PGBOUNCER_ENABLED:-yes}"
EOF
  chmod 600 "${STATE_FILE}"
  log "Saved state to ${STATE_FILE}"
}

# Ask with default helper
ask() {
  local prompt="$1"; local default="$2"; local varname="$3"
  if [[ -n "${!varname-}" ]]; then
    printf "%s [%s] (from state) : " "${prompt}" "${!varname}"
  else
    printf "%s [%s]: " "${prompt}" "${default}"
  fi
  read -r answer || answer=""
  if [[ -z "${answer}" ]]; then
    if [[ -n "${!varname-}" ]]; then
      true # keep existing
    else
      eval "${varname}='${default}'"
    fi
  else
    eval "${varname}='${answer}'"
  fi
}

# Prepare interactive defaults (only if not present)
if [[ -z "${DB_LISTEN_ADDRESSES-}" ]]; then
  DB_LISTEN_ADDRESSES="0.0.0.0"
fi
if [[ -z "${DB_PORT-}" ]]; then
  DB_PORT="5432"
fi
if [[ -z "${ALLOWED_IPS-}" ]]; then
  ALLOWED_IPS="127.0.0.1/32"
fi
if [[ -z "${PG_SSL-}" ]]; then
  PG_SSL="no"
fi
if [[ -z "${BACKUP_RETENTION_DAYS-}" ]]; then
  BACKUP_RETENTION_DAYS="14"
fi
if [[ -z "${PGBOUNCER_ENABLED-}" ]]; then
  PGBOUNCER_ENABLED="yes"
fi
if [[ -z "${ENABLE_WAL_ARCHIVE-}" ]]; then
  ENABLE_WAL_ARCHIVE="no"
fi

echo "PostgreSQL ${PG_VERSION} automated setup (idempotent)."
echo "If you re-run the script it will re-use saved answers from ${STATE_FILE}."
echo

# Interactive prompts (non-blocking if state exists)
ask "Postgres listen addresses (comma or space separated)" "${DB_LISTEN_ADDRESSES}" DB_LISTEN_ADDRESSES
ask "Postgres port" "${DB_PORT}" DB_PORT
ask "Allowed IPs/CIDRs for DB access (comma-separated). Example: 203.0.113.4/32,198.51.100.0/24" "${ALLOWED_IPS}" ALLOWED_IPS
ask "Enable SSL for Postgres? (yes/no)" "${PG_SSL}" PG_SSL

if [[ "${PG_SSL}" == "yes" ]]; then
  ask "Path for server certificate" "${SSL_CERT_FILE}" SSL_CERT_FILE
  ask "Path for server key" "${SSL_KEY_FILE}" SSL_KEY_FILE
fi

ask "Enable WAL archiving to S3? (no/yes)" "${ENABLE_WAL_ARCHIVE}" ENABLE_WAL_ARCHIVE
if [[ "${ENABLE_WAL_ARCHIVE}" == "yes" ]]; then
  ask "S3 bucket URI (s3://bucket/path/) for WAL archive" "${WAL_S3_BUCKET:-}" WAL_S3_BUCKET
  log "NOTE: AWS credentials must be available to root (env or /root/.aws/)."
fi

ask "Retention days for logical backups (days)" "${BACKUP_RETENTION_DAYS}" BACKUP_RETENTION_DAYS
ask "Enable pgbouncer on this host? (yes/no)" "${PGBOUNCER_ENABLED}" PGBOUNCER_ENABLED

# persist choices
save_state

# Add PGDG apt repository (idempotent)
install_pgdg_repo() {
  if ! grep -q "apt.postgresql.org" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || ! dpkg -l | grep -q "postgresql-${PG_VERSION}"; then
    log "Adding PostgreSQL official APT repository..."
    apt-get update -y
    apt-get install -y wget ca-certificates lsb-release gnupg
    # Add the repository key and source
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
  else
    log "PGDG repo already configured."
  fi
}

install_postgres() {
  if dpkg -l | grep -q "postgresql-${PG_VERSION}"; then
    log "PostgreSQL ${PG_VERSION} already installed."
  else
    log "Installing PostgreSQL ${PG_VERSION}..."
    apt-get install -y "postgresql-${PG_VERSION}" "postgresql-contrib-${PG_VERSION}" postgresql-client-${PG_VERSION}
    log "Installed PostgreSQL ${PG_VERSION}."
  fi
}

install_basic_tools() {
  apt-get install -y ufw fail2ban cron logrotate awscli
  # ensure basic tools present
  apt-get install -y rsync vim less psmisc
}

# Tune postgresql.conf based on memory and basic best-practices
tune_postgres() {
  # detect total memory in MB
  local total_mem_mb
  total_mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo || echo 4096)
  log "Detected ${total_mem_mb} MB RAM. Applying conservative tuning."

  # calculate values; safe defaults
  # shared_buffers = ~25% RAM (but capped)
  local shared_buffers_mb=$(( total_mem_mb / 4 ))
  if (( shared_buffers_mb < 256 )); then shared_buffers_mb=256; fi
  # effective_cache_size ~ 75% RAM
  local effective_cache_mb=$(( (total_mem_mb * 3) / 4 ))
  if (( effective_cache_mb < 768 )); then effective_cache_mb=768; fi
  # work_mem default modest; we'll set a default that works for many connections
  local work_mem_kb=65536 # 64MB
  # maintenance_work_mem
  local maintenance_work_mem_mb=256

  # patch postgresql.conf idempotent
  sed -i.bak -E "s/^[# ]*shared_buffers *=.*$/shared_buffers = '${shared_buffers_mb}MB'/" "${PG_CONF_FILE}" || echo "shared_buffers = '${shared_buffers_mb}MB'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*effective_cache_size *=.*$/effective_cache_size = '${effective_cache_mb}MB'/" "${PG_CONF_FILE}" || echo "effective_cache_size = '${effective_cache_mb}MB'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*work_mem *=.*$/work_mem = '${work_mem_kb}kB'/" "${PG_CONF_FILE}" || echo "work_mem = '${work_mem_kb}kB'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*maintenance_work_mem *=.*$/maintenance_work_mem = '${maintenance_work_mem_mb}MB'/" "${PG_CONF_FILE}" || echo "maintenance_work_mem = '${maintenance_work_mem_mb}MB'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*max_wal_size *=.*$/max_wal_size = '2GB'/" "${PG_CONF_FILE}" || echo "max_wal_size = '2GB'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*checkpoint_timeout *=.*$/checkpoint_timeout = '10min'/" "${PG_CONF_FILE}" || echo "checkpoint_timeout = '10min'" >> "${PG_CONF_FILE}"
  sed -i.bak -E "s/^[# ]*wal_compression *=.*$/wal_compression = on/" "${PG_CONF_FILE}" || echo "wal_compression = on" >> "${PG_CONF_FILE}"

  # listen addresses
  if grep -q "^#*listen_addresses" "${PG_CONF_FILE}"; then
    sed -i -E "s/^#*listen_addresses.*/listen_addresses = '${DB_LISTEN_ADDRESSES//'/' }'/" "${PG_CONF_FILE}"
  else
    echo "listen_addresses = '${DB_LISTEN_ADDRESSES//'/' }'" >> "${PG_CONF_FILE}"
  fi

  # port
  sed -i -E "s/^#*port *=.*$/port = ${DB_PORT}/" "${PG_CONF_FILE}" || echo "port = ${DB_PORT}" >> "${PG_CONF_FILE}"

  # configure WAL archiving if enabled
  if [[ "${ENABLE_WAL_ARCHIVE}" == "yes" && -n "${WAL_S3_BUCKET}" ]]; then
    sed -i -E "s/^#*archive_mode .*$/archive_mode = on/" "${PG_CONF_FILE}" || echo "archive_mode = on" >> "${PG_CONF_FILE}"
    sed -i -E "s/^#*archive_command .*$/archive_command = 'test ! -f \/var\/lib\/postgresql\/wal_archive\/%f \&\& aws s3 cp - \/dev\/null'/" "${PG_CONF_FILE}" || echo "archive_command = 'aws s3 cp - ${WAL_S3_BUCKET}%f'" >> "${PG_CONF_FILE}"
    mkdir -p /var/lib/postgresql/wal_archive || true
    chown -R postgres:postgres /var/lib/postgresql/wal_archive || true
    log "WAL archiving configured (note: ensure aws cli credentials are available)."
  fi

  log "Postgres tuned (shared_buffers=${shared_buffers_mb}MB, effective_cache_size=${effective_cache_mb}MB)."
}

# Configure pg_hba.conf with allowed IPs (idempotent)
configure_pg_hba() {
  # backup
  cp -n "${PG_HBA_FILE}" "${PG_HBA_FILE}.orig" || true
  # ensure loopback present
  grep -qE "^host\s+all\s+all\s+127.0.0.1/32" "${PG_HBA_FILE}" || echo "host    all             all             127.0.0.1/32            md5" >> "${PG_HBA_FILE}"

  # process ALLOWED_IPS as comma separated
  IFS=',' read -ra cidrs <<< "${ALLOWED_IPS}"
  for cidr in "${cidrs[@]}"; do
    cidr_trimmed="$(echo "${cidr}" | xargs)"
    # add only if not present
    if ! grep -qE "^host\s+all\s+all\s+${cidr_trimmed}" "${PG_HBA_FILE}"; then
      echo "host    all             all             ${cidr_trimmed}            md5" >> "${PG_HBA_FILE}"
      log "Added pg_hba entry for ${cidr_trimmed}"
    else
      log "pg_hba already has entry for ${cidr_trimmed}"
    fi
  done
}

# Setup SSL certs if requested
setup_ssl() {
  if [[ "${PG_SSL}" == "yes" ]]; then
    mkdir -p "${PG_SSL_DIR}"
    chmod 700 "${PG_SSL_DIR}"
    if [[ ! -f "${SSL_CERT_FILE}" || ! -f "${SSL_KEY_FILE}" ]]; then
      log "Generating self-signed certificate for Postgres at ${SSL_CERT_FILE} / ${SSL_KEY_FILE}"
      openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/CN=$(hostname -f)" \
        -keyout "${SSL_KEY_FILE}" -out "${SSL_CERT_FILE}"
      chmod 600 "${SSL_KEY_FILE}"
      chmod 644 "${SSL_CERT_FILE}"
      chown -R postgres:postgres "${PG_SSL_DIR}" || true
    else
      log "User-supplied certs found; ensuring ownership and permissions."
      chown postgres:postgres "${SSL_CERT_FILE}" "${SSL_KEY_FILE}" || true
      chmod 600 "${SSL_KEY_FILE}" || true
    fi

    # ensure postgresql.conf points to files
    if ! grep -q "ssl = on" "${PG_CONF_FILE}"; then
      echo "ssl = on" >> "${PG_CONF_FILE}"
    fi
    sed -i -E "s|^#*ssl_cert_file = .*|ssl_cert_file = '${SSL_CERT_FILE}'|" "${PG_CONF_FILE}" || echo "ssl_cert_file = '${SSL_CERT_FILE}'" >> "${PG_CONF_FILE}"
    sed -i -E "s|^#*ssl_key_file = .*|ssl_key_file = '${SSL_KEY_FILE}'|" "${PG_CONF_FILE}" || echo "ssl_key_file = '${SSL_KEY_FILE}'" >> "${PG_CONF_FILE}"
    log "SSL configured for Postgres (self-signed or user cert)."
  fi
}

# Setup basic firewall rules with UFW
configure_firewall() {
  log "Configuring UFW firewall rules (idempotent)."
  ufw allow OpenSSH >/dev/null || true
  # allow DB port only from allowed IPs
  IFS=',' read -ra cidrs <<< "${ALLOWED_IPS}"
  for cidr in "${cidrs[@]}"; do
    cidr_trimmed="$(echo "${cidr}" | xargs)"
    ufw allow from "${cidr_trimmed}" to any port "${DB_PORT}" proto tcp || true
  done
  # enable ufw if not active
  if ufw status | grep -q "Status: inactive"; then
    ufw --force enable
  fi
  log "UFW rules applied."
}

# Fail2ban minimal config for SSH; optionally more advanced jails can be added
configure_fail2ban() {
  log "Installing minimal Fail2Ban config for SSH."
  apt-get install -y fail2ban
  local jail_conf="/etc/fail2ban/jail.d/pg-setup.local"
  cat > "${jail_conf}" <<-EOF
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
maxretry = 5

EOF
  systemctl restart fail2ban || true
  log "Fail2Ban restarted."
}

# Setup backup and restore scripts
install_maintenance_scripts() {
  mkdir -p "${BACKUP_DIR}"
  chown -R postgres:postgres "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"

  # backup script (logical per-db)
  cat > /usr/local/bin/pg_backup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +%F_%H%M%S)
mkdir -p "${BACKUP_DIR}"
# dump each database separately (except template0, template1)
sudo -u postgres psql -At -c "select datname from pg_database where datistemplate = false" | while read -r db; do
  echo "Backing up ${db}..."
  sudo -u postgres pg_dump -Fc -d "${db}" -f "${BACKUP_DIR}/${db}_${TIMESTAMP}.dump"
done
# rotate old backups
find "${BACKUP_DIR}" -type f -mtime +${BACKUP_RETENTION_DAYS:-14} -delete || true
EOF
  chmod +x /usr/local/bin/pg_backup.sh

  # restore script (asks for file)
  cat > /usr/local/bin/pg_restore_latest.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/backup.dump"
  exit 1
fi
BACKUPFILE="$1"
if [[ ! -f "${BACKUPFILE}" ]]; then
  echo "Backup file not found: ${BACKUPFILE}"
  exit 1
fi
echo "This will restore the backup into a new database schema. Please ensure the target DB exists."
read -rp "Target database name: " TARGETDB
sudo -u postgres pg_restore -d "${TARGETDB}" --clean --no-owner "${BACKUPFILE}"
echo "Restore complete."
EOF
  chmod +x /usr/local/bin/pg_restore_latest.sh

  # restart script
  cat > /usr/local/bin/pg_restart.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
systemctl restart postgresql
systemctl status postgresql --no-pager
EOF
  chmod +x /usr/local/bin/pg_restart.sh

  # status script
  cat > /usr/local/bin/pg_status.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Postgres service:"
systemctl status postgresql --no-pager
echo
echo "Active connections:"
sudo -u postgres psql -c "select datname, count(*) from pg_stat_activity group by datname;"
EOF
  chmod +x /usr/local/bin/pg_status.sh

  log "Maintenance scripts installed in /usr/local/bin: pg_backup.sh, pg_restore_latest.sh, pg_restart.sh, pg_status.sh"
}

# Install and configure pgbouncer (if enabled)
install_pgbouncer() {
  if [[ "${PGBOUNCER_ENABLED}" != "yes" ]]; then
    log "pgbouncer disabled by configuration."
    return
  fi
  if dpkg -l | grep -q pgbouncer; then
    log "pgbouncer already installed."
  else
    apt-get install -y pgbouncer
  fi

  mkdir -p /etc/pgbouncer
  cat > /etc/pgbouncer/pgbouncer.ini <<-EOF
[databases]
# admin/db mapping: direct to postgres for now; keep DB names the same
* = host=127.0.0.1 port=${DB_PORT}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
server_reset_query = DISCARD ALL
max_client_conn = 200
default_pool_size = 20
EOF

  # create userlist file from postgres users (empty now)
  touch /etc/pgbouncer/userlist.txt
  chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt
  chmod 600 /etc/pgbouncer/userlist.txt

  systemctl enable --now pgbouncer
  log "pgbouncer configured and started on 127.0.0.1:6432. Update /etc/pgbouncer/userlist.txt with \"\\\"username\\\" \\\"md5passwordhash\\\"\" entries or use provided helper."
}

# Helper to add a DB user and database (script)
install_create_db_user_script() {
  cat > /usr/local/bin/pg_create_db_user.sh <<'EOF'
#!/usr/bin/env bash
# Usage: pg_create_db_user.sh dbname username
set -euo pipefail
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <dbname> <username>"
  exit 1
fi
DB="$1"; USER="$2"
read -rp "Password for ${USER}: " -s PWD; echo
sudo -u postgres psql -c "CREATE USER ${USER} WITH PASSWORD '${PWD}';" || true
sudo -u postgres psql -c "CREATE DATABASE ${DB} WITH OWNER = ${USER};" || true
echo "Created DB ${DB} and user ${USER}."
# optionally add to pgbouncer userlist if installed
if [[ -f /etc/pgbouncer/userlist.txt ]]; then
  # create md5 password hash
  HASH=$(sudo -u postgres psql -tA -c "select md5('${PWD}'||'${USER}');")
  echo "\"${USER}\" \"md5${HASH}\"" >> /etc/pgbouncer/userlist.txt
  chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt || true
  chmod 600 /etc/pgbouncer/userlist.txt
  systemctl restart pgbouncer || true
  echo "Added user to pgbouncer userlist."
fi
EOF
  chmod +x /usr/local/bin/pg_create_db_user.sh
}

# Apply configuration, restart postgres and basic checks
finalize_and_restart() {
  log "Reloading postgresql config and restarting..."
  systemctl daemon-reload || true
  systemctl restart postgresql
  sleep 1
  systemctl status postgresql --no-pager || true
  log "Running quick pg_isready check..."
  sudo -u postgres pg_isready -p "${DB_PORT}" -q && log "Postgres reports ready on port ${DB_PORT}." || log "pg_isready reports not ready (check logs)."
}

# MAIN sequence
install_basic_tools
install_pgdg_repo
install_postgres
tune_postgres
configure_pg_hba
if [[ "${PG_SSL}" == "yes" ]]; then
  mkdir -p "$(dirname "${SSL_CERT_FILE}")"
  setup_ssl
fi
configure_firewall
configure_fail2ban
install_maintenance_scripts
install_pgbouncer
install_create_db_user_script
finalize_and_restart

echo
log "Setup complete. Helpful next steps:."
cat <<-EOHELP

- State file saved: ${STATE_FILE}
- Backup directory: ${BACKUP_DIR}. Use /usr/local/bin/pg_backup.sh to run a backup.
- Create DB/user helper: /usr/local/bin/pg_create_db_user.sh
- Restore helper: /usr/local/bin/pg_restore_latest.sh
- Pgbouncer listens on 127.0.0.1:6432 (if enabled). Point your app's pool to pgbouncer:
    DATABASE_URL=postgresql://user:pass@127.0.0.1:6432/dbname

Security checklist (please follow):
- Ensure only allowed IPs appear in ${PG_HBA_FILE} and UFW.
- Store backups off-server (s3/R2/other). If you enabled WAL archiving, ensure AWS credentials are available.
- Test the restore process immediately in a staging environment.

Important notes:
- This script aims to be conservative and idempotent. Still: review config files in ${PG_CONF_DIR} and /etc/pgbouncer before deploying to production.
- For high availability, streaming replication, automated failover, and managed-like operations, plan a second node with synchronous replication or consider patroni/pg_auto_failover later.
EOHELP

exit 0
