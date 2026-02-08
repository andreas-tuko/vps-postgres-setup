#!/usr/bin/env bash
# setup-postgres17-enterprise.sh
# Enterprise-grade PostgreSQL 17 setup with security, monitoring, backup, and maintenance
# Target: Ubuntu 22.04/24.04 LTS
# Author: Production-Ready PostgreSQL Automation
# License: MIT

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

readonly SCRIPT_VERSION="1.0.1"
readonly PG_VERSION="17"
readonly STATE_FILE="/etc/postgresql-setup.state"
readonly BACKUP_DIR="/var/backups/postgresql"
readonly LOG_DIR="/var/log/postgresql-setup"
readonly PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
readonly PG_HBA_FILE="${PG_CONF_DIR}/pg_hba.conf"
readonly PG_CONF_FILE="${PG_CONF_DIR}/postgresql.conf"
readonly PG_SSL_DIR="/etc/ssl/postgresql"
readonly SCRIPTS_DIR="/usr/local/bin"
readonly MONITORING_DIR="/opt/postgresql-monitoring"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_DIR}/setup.log"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "${LOG_DIR}/setup.log"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "${LOG_DIR}/setup.log"
}

log_section() {
    echo | tee -a "${LOG_DIR}/setup.log"
    echo -e "${BLUE}========================================${NC}" | tee -a "${LOG_DIR}/setup.log"
    echo -e "${BLUE}$*${NC}" | tee -a "${LOG_DIR}/setup.log"
    echo -e "${BLUE}========================================${NC}" | tee -a "${LOG_DIR}/setup.log"
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "${ID}" != "ubuntu" ]]; then
        log_warn "This script is designed for Ubuntu. Detected: ${ID}"
        read -p "Continue anyway? (yes/no): " -r
        if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
            exit 1
        fi
    fi
    
    log "Detected OS: ${PRETTY_NAME}"
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
        log "Loaded previous configuration from ${STATE_FILE}"
        return 0
    fi
    return 1
}

save_state() {
    cat > "${STATE_FILE}" << EOF
# PostgreSQL Enterprise Setup State File
# Generated: $(date)
# Version: ${SCRIPT_VERSION}

# Database Configuration
DB_LISTEN_ADDRESSES="${DB_LISTEN_ADDRESSES}"
DB_PORT="${DB_PORT}"
DB_MAX_CONNECTIONS="${DB_MAX_CONNECTIONS}"
DB_SHARED_BUFFERS="${DB_SHARED_BUFFERS}"
DB_EFFECTIVE_CACHE="${DB_EFFECTIVE_CACHE}"
DB_WORK_MEM="${DB_WORK_MEM}"
DB_MAINTENANCE_WORK_MEM="${DB_MAINTENANCE_WORK_MEM}"

# Security Configuration
ALLOWED_IPS="${ALLOWED_IPS}"
ENABLE_SSL="${ENABLE_SSL}"
SSL_CERT_FILE="${SSL_CERT_FILE}"
SSL_KEY_FILE="${SSL_KEY_FILE}"
ENABLE_FIREWALL="${ENABLE_FIREWALL}"
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN}"
SSH_PORT="${SSH_PORT}"

# Backup Configuration
ENABLE_BACKUPS="${ENABLE_BACKUPS}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION}"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED}"
REMOTE_BACKUP_TYPE="${REMOTE_BACKUP_TYPE}"
S3_BUCKET="${S3_BUCKET}"
S3_REGION="${S3_REGION}"

# High Availability
ENABLE_WAL_ARCHIVING="${ENABLE_WAL_ARCHIVING}"
WAL_ARCHIVE_DESTINATION="${WAL_ARCHIVE_DESTINATION}"
ENABLE_REPLICATION="${ENABLE_REPLICATION}"
REPLICATION_SLOTS="${REPLICATION_SLOTS}"

# Connection Pooling
ENABLE_PGBOUNCER="${ENABLE_PGBOUNCER}"
PGBOUNCER_PORT="${PGBOUNCER_PORT}"
PGBOUNCER_POOL_MODE="${PGBOUNCER_POOL_MODE}"
PGBOUNCER_MAX_CLIENT_CONN="${PGBOUNCER_MAX_CLIENT_CONN}"
PGBOUNCER_DEFAULT_POOL_SIZE="${PGBOUNCER_DEFAULT_POOL_SIZE}"

# Monitoring
ENABLE_MONITORING="${ENABLE_MONITORING}"
MONITORING_RETENTION_DAYS="${MONITORING_RETENTION_DAYS}"

# Logging
LOG_DESTINATION="${LOG_DESTINATION}"
LOG_MIN_DURATION="${LOG_MIN_DURATION}"
LOG_CONNECTIONS="${LOG_CONNECTIONS}"
LOG_DISCONNECTIONS="${LOG_DISCONNECTIONS}"

# Setup Metadata
SETUP_DATE="$(date)"
SETUP_COMPLETE="true"
EOF
    
    chmod 600 "${STATE_FILE}"
    log "Configuration saved to ${STATE_FILE}"
}

# ============================================================================
# INTERACTIVE PROMPTS
# ============================================================================

ask() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local current_value="${!varname:-}"
    
    if [[ -n "${current_value}" ]]; then
        printf "${BLUE}%s${NC} [current: ${GREEN}%s${NC}]: " "${prompt}" "${current_value}"
    else
        printf "${BLUE}%s${NC} [default: ${YELLOW}%s${NC}]: " "${prompt}" "${default}"
    fi
    
    read -r answer
    
    if [[ -z "${answer}" ]]; then
        if [[ -n "${current_value}" ]]; then
            eval "${varname}='${current_value}'"
        else
            eval "${varname}='${default}'"
        fi
    else
        eval "${varname}='${answer}'"
    fi
}

ask_yn() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local current_value="${!varname:-}"
    
    if [[ -n "${current_value}" ]]; then
        printf "${BLUE}%s${NC} (yes/no) [current: ${GREEN}%s${NC}]: " "${prompt}" "${current_value}"
    else
        printf "${BLUE}%s${NC} (yes/no) [default: ${YELLOW}%s${NC}]: " "${prompt}" "${default}"
    fi
    
    read -r answer
    
    if [[ -z "${answer}" ]]; then
        if [[ -n "${current_value}" ]]; then
            eval "${varname}='${current_value}'"
        else
            eval "${varname}='${default}'"
        fi
    else
        answer=$(echo "${answer}" | tr '[:upper:]' '[:lower:]')
        if [[ "${answer}" =~ ^(yes|y|true|1)$ ]]; then
            eval "${varname}='yes'"
        else
            eval "${varname}='no'"
        fi
    fi
}

# ============================================================================
# INTERACTIVE CONFIGURATION
# ============================================================================

configure_database() {
    log_section "DATABASE CONFIGURATION"
    
    DB_LISTEN_ADDRESSES="${DB_LISTEN_ADDRESSES:-0.0.0.0}"
    DB_PORT="${DB_PORT:-5432}"
    DB_MAX_CONNECTIONS="${DB_MAX_CONNECTIONS:-200}"
    
    ask "PostgreSQL listen addresses (0.0.0.0 for all, localhost for local only)" "${DB_LISTEN_ADDRESSES}" DB_LISTEN_ADDRESSES
    ask "PostgreSQL port" "${DB_PORT}" DB_PORT
    ask "Maximum connections" "${DB_MAX_CONNECTIONS}" DB_MAX_CONNECTIONS
    
    # Auto-calculate optimal settings based on system resources
    local total_mem_mb
    total_mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    
    local suggested_shared_buffers=$((total_mem_mb / 4))
    local suggested_effective_cache=$((total_mem_mb * 3 / 4))
    local suggested_work_mem=$((total_mem_mb / DB_MAX_CONNECTIONS / 2))
    local suggested_maintenance=$((total_mem_mb / 16))
    
    [[ ${suggested_shared_buffers} -lt 256 ]] && suggested_shared_buffers=256
    [[ ${suggested_shared_buffers} -gt 8192 ]] && suggested_shared_buffers=8192
    [[ ${suggested_work_mem} -lt 4 ]] && suggested_work_mem=4
    [[ ${suggested_work_mem} -gt 128 ]] && suggested_work_mem=128
    [[ ${suggested_maintenance} -lt 64 ]] && suggested_maintenance=64
    
    DB_SHARED_BUFFERS="${DB_SHARED_BUFFERS:-${suggested_shared_buffers}}"
    DB_EFFECTIVE_CACHE="${DB_EFFECTIVE_CACHE:-${suggested_effective_cache}}"
    DB_WORK_MEM="${DB_WORK_MEM:-${suggested_work_mem}}"
    DB_MAINTENANCE_WORK_MEM="${DB_MAINTENANCE_WORK_MEM:-${suggested_maintenance}}"
    
    log "System memory: ${total_mem_mb}MB"
    ask "Shared buffers (MB)" "${DB_SHARED_BUFFERS}" DB_SHARED_BUFFERS
    ask "Effective cache size (MB)" "${DB_EFFECTIVE_CACHE}" DB_EFFECTIVE_CACHE
    ask "Work memory per operation (MB)" "${DB_WORK_MEM}" DB_WORK_MEM
    ask "Maintenance work memory (MB)" "${DB_MAINTENANCE_WORK_MEM}" DB_MAINTENANCE_WORK_MEM
}

configure_security() {
    log_section "SECURITY CONFIGURATION"
    
    ALLOWED_IPS="${ALLOWED_IPS:-127.0.0.1/32}"
    ENABLE_SSL="${ENABLE_SSL:-yes}"
    ENABLE_FIREWALL="${ENABLE_FIREWALL:-yes}"
    ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-yes}"
    SSH_PORT="${SSH_PORT:-22}"
    
    ask "Allowed IP addresses/CIDRs for database access (comma-separated)" "${ALLOWED_IPS}" ALLOWED_IPS
    ask_yn "Enable SSL/TLS for PostgreSQL" "${ENABLE_SSL}" ENABLE_SSL
    
    # Initialize SSL variables even if SSL is disabled (for save_state)
    SSL_CERT_FILE="${SSL_CERT_FILE:-${PG_SSL_DIR}/server.crt}"
    SSL_KEY_FILE="${SSL_KEY_FILE:-${PG_SSL_DIR}/server.key}"
    
    if [[ "${ENABLE_SSL}" == "yes" ]]; then
        ask "SSL certificate path (leave default for self-signed)" "${SSL_CERT_FILE}" SSL_CERT_FILE
        ask "SSL private key path" "${SSL_KEY_FILE}" SSL_KEY_FILE
    fi
    
    ask_yn "Enable UFW firewall" "${ENABLE_FIREWALL}" ENABLE_FIREWALL
    ask_yn "Enable Fail2Ban intrusion prevention" "${ENABLE_FAIL2BAN}" ENABLE_FAIL2BAN
    ask "SSH port (for firewall rules)" "${SSH_PORT}" SSH_PORT
}

configure_backups() {
    log_section "BACKUP CONFIGURATION"
    
    ENABLE_BACKUPS="${ENABLE_BACKUPS:-yes}"
    BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-daily}"
    BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
    BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-yes}"
    REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-no}"
    
    # Initialize remote backup variables even if disabled (for save_state)
    REMOTE_BACKUP_TYPE="${REMOTE_BACKUP_TYPE:-s3}"
    S3_BUCKET="${S3_BUCKET:-}"
    S3_REGION="${S3_REGION:-us-east-1}"
    
    ask_yn "Enable automated backups" "${ENABLE_BACKUPS}" ENABLE_BACKUPS
    
    if [[ "${ENABLE_BACKUPS}" == "yes" ]]; then
        ask "Backup schedule (hourly/daily/weekly)" "${BACKUP_SCHEDULE}" BACKUP_SCHEDULE
        ask "Backup retention (days)" "${BACKUP_RETENTION_DAYS}" BACKUP_RETENTION_DAYS
        ask_yn "Enable backup compression" "${BACKUP_COMPRESSION}" BACKUP_COMPRESSION
        ask_yn "Enable remote backup (S3/cloud storage)" "${REMOTE_BACKUP_ENABLED}" REMOTE_BACKUP_ENABLED
        
        if [[ "${REMOTE_BACKUP_ENABLED}" == "yes" ]]; then
            ask "Remote backup type (s3/azure/gcs)" "${REMOTE_BACKUP_TYPE}" REMOTE_BACKUP_TYPE
            ask "S3 bucket name (s3://bucket-name/path)" "${S3_BUCKET}" S3_BUCKET
            ask "S3 region" "${S3_REGION}" S3_REGION
        fi
    fi
}

configure_high_availability() {
    log_section "HIGH AVAILABILITY & REPLICATION"
    
    ENABLE_WAL_ARCHIVING="${ENABLE_WAL_ARCHIVING:-no}"
    ENABLE_REPLICATION="${ENABLE_REPLICATION:-no}"
    
    # Initialize HA variables even if disabled (for save_state)
    WAL_ARCHIVE_DESTINATION="${WAL_ARCHIVE_DESTINATION:-/var/lib/postgresql/wal_archive}"
    REPLICATION_SLOTS="${REPLICATION_SLOTS:-2}"
    
    ask_yn "Enable WAL (Write-Ahead Log) archiving" "${ENABLE_WAL_ARCHIVING}" ENABLE_WAL_ARCHIVING
    
    if [[ "${ENABLE_WAL_ARCHIVING}" == "yes" ]]; then
        ask "WAL archive destination (local path or s3://)" "${WAL_ARCHIVE_DESTINATION}" WAL_ARCHIVE_DESTINATION
    fi
    
    ask_yn "Configure for replication (streaming replication)" "${ENABLE_REPLICATION}" ENABLE_REPLICATION
    
    if [[ "${ENABLE_REPLICATION}" == "yes" ]]; then
        ask "Number of replication slots" "${REPLICATION_SLOTS}" REPLICATION_SLOTS
    fi
}

configure_connection_pooling() {
    log_section "CONNECTION POOLING (PgBouncer)"
    
    ENABLE_PGBOUNCER="${ENABLE_PGBOUNCER:-yes}"
    
    # Initialize PgBouncer variables even if disabled (for save_state)
    PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"
    PGBOUNCER_POOL_MODE="${PGBOUNCER_POOL_MODE:-transaction}"
    PGBOUNCER_MAX_CLIENT_CONN="${PGBOUNCER_MAX_CLIENT_CONN:-1000}"
    PGBOUNCER_DEFAULT_POOL_SIZE="${PGBOUNCER_DEFAULT_POOL_SIZE:-25}"
    
    ask_yn "Enable PgBouncer connection pooling" "${ENABLE_PGBOUNCER}" ENABLE_PGBOUNCER
    
    if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
        ask "PgBouncer listen port" "${PGBOUNCER_PORT}" PGBOUNCER_PORT
        ask "Pool mode (session/transaction/statement)" "${PGBOUNCER_POOL_MODE}" PGBOUNCER_POOL_MODE
        ask "Maximum client connections" "${PGBOUNCER_MAX_CLIENT_CONN}" PGBOUNCER_MAX_CLIENT_CONN
        ask "Default pool size per user/database" "${PGBOUNCER_DEFAULT_POOL_SIZE}" PGBOUNCER_DEFAULT_POOL_SIZE
    fi
}

configure_monitoring() {
    log_section "MONITORING & LOGGING"
    
    ENABLE_MONITORING="${ENABLE_MONITORING:-yes}"
    LOG_DESTINATION="${LOG_DESTINATION:-csvlog}"
    LOG_MIN_DURATION="${LOG_MIN_DURATION:-1000}"
    LOG_CONNECTIONS="${LOG_CONNECTIONS:-on}"
    LOG_DISCONNECTIONS="${LOG_DISCONNECTIONS:-on}"
    MONITORING_RETENTION_DAYS="${MONITORING_RETENTION_DAYS:-30}"
    
    ask_yn "Enable enhanced monitoring" "${ENABLE_MONITORING}" ENABLE_MONITORING
    ask "Log destination (stderr/csvlog/syslog)" "${LOG_DESTINATION}" LOG_DESTINATION
    ask "Log queries slower than (ms, 0 for all)" "${LOG_MIN_DURATION}" LOG_MIN_DURATION
    ask_yn "Log connections" "${LOG_CONNECTIONS}" LOG_CONNECTIONS
    ask_yn "Log disconnections" "${LOG_DISCONNECTIONS}" LOG_DISCONNECTIONS
    ask "Monitoring data retention (days)" "${MONITORING_RETENTION_DAYS}" MONITORING_RETENTION_DAYS
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

install_prerequisites() {
    log_section "Installing Prerequisites"
    
    apt-get update -qq
    apt-get install -y -qq \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        curl \
        apt-transport-https \
        software-properties-common \
        dirmngr \
        debian-keyring \
        debian-archive-keyring
    
    log "Prerequisites installed"
}

install_postgresql_repository() {
    log_section "Adding PostgreSQL Official Repository"
    
    if grep -q "apt.postgresql.org" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log "PostgreSQL repository already configured"
        return 0
    fi
    
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg
    
    echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
        tee /etc/apt/sources.list.d/pgdg.list
    
    apt-get update -qq
    
    log "PostgreSQL repository added"
}

install_postgresql() {
    log_section "Installing PostgreSQL ${PG_VERSION}"
    
    if dpkg -l | grep -q "postgresql-${PG_VERSION}"; then
        log "PostgreSQL ${PG_VERSION} already installed"
        return 0
    fi
    
    apt-get install -y -qq \
        "postgresql-${PG_VERSION}" \
        "postgresql-contrib-${PG_VERSION}" \
        "postgresql-client-${PG_VERSION}" \
        "postgresql-server-dev-${PG_VERSION}"
    
    systemctl enable postgresql
    systemctl start postgresql
    
    log "PostgreSQL ${PG_VERSION} installed successfully"
}

install_additional_tools() {
    log_section "Installing Additional Tools"
    
    apt-get install -y -qq \
        pgbackrest \
        postgresql-${PG_VERSION}-cron \
        postgresql-${PG_VERSION}-partman \
        postgresql-${PG_VERSION}-pgaudit \
        postgresql-${PG_VERSION}-pg-stat-kcache \
        htop \
        iotop \
        sysstat \
        logrotate \
        rsync \
        parallel \
        pv \
        jq \
        vim \
        less \
        net-tools
    
    if [[ "${REMOTE_BACKUP_ENABLED}" == "yes" ]]; then
        apt-get install -y -qq awscli
    fi
    
    log "Additional tools installed"
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

configure_postgresql() {
    log_section "Configuring PostgreSQL"
    
    # Backup original configuration
    cp "${PG_CONF_FILE}" "${PG_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)" || true
    
    # Network settings
    sed -i "s/^#*listen_addresses.*/listen_addresses = '${DB_LISTEN_ADDRESSES}'/" "${PG_CONF_FILE}"
    sed -i "s/^#*port.*/port = ${DB_PORT}/" "${PG_CONF_FILE}"
    sed -i "s/^#*max_connections.*/max_connections = ${DB_MAX_CONNECTIONS}/" "${PG_CONF_FILE}"
    
    # Memory settings
    sed -i "s/^#*shared_buffers.*/shared_buffers = ${DB_SHARED_BUFFERS}MB/" "${PG_CONF_FILE}"
    sed -i "s/^#*effective_cache_size.*/effective_cache_size = ${DB_EFFECTIVE_CACHE}MB/" "${PG_CONF_FILE}"
    sed -i "s/^#*work_mem.*/work_mem = ${DB_WORK_MEM}MB/" "${PG_CONF_FILE}"
    sed -i "s/^#*maintenance_work_mem.*/maintenance_work_mem = ${DB_MAINTENANCE_WORK_MEM}MB/" "${PG_CONF_FILE}"
    
    # WAL settings
    sed -i "s/^#*wal_buffers.*/wal_buffers = 16MB/" "${PG_CONF_FILE}"
    sed -i "s/^#*min_wal_size.*/min_wal_size = 1GB/" "${PG_CONF_FILE}"
    sed -i "s/^#*max_wal_size.*/max_wal_size = 4GB/" "${PG_CONF_FILE}"
    sed -i "s/^#*checkpoint_completion_target.*/checkpoint_completion_target = 0.9/" "${PG_CONF_FILE}"
    sed -i "s/^#*wal_compression.*/wal_compression = on/" "${PG_CONF_FILE}"
    
    # Query planner
    sed -i "s/^#*random_page_cost.*/random_page_cost = 1.1/" "${PG_CONF_FILE}"
    sed -i "s/^#*effective_io_concurrency.*/effective_io_concurrency = 200/" "${PG_CONF_FILE}"
    
    # Autovacuum tuning
    sed -i "s/^#*autovacuum.*/autovacuum = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*autovacuum_max_workers.*/autovacuum_max_workers = 3/" "${PG_CONF_FILE}"
    sed -i "s/^#*autovacuum_naptime.*/autovacuum_naptime = 10s/" "${PG_CONF_FILE}"
    
    # Logging configuration
    sed -i "s/^#*logging_collector.*/logging_collector = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_destination.*/log_destination = '${LOG_DESTINATION}'/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_directory.*/log_directory = 'log'/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_filename.*/log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_rotation_age.*/log_rotation_age = 1d/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_rotation_size.*/log_rotation_size = 100MB/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_min_duration_statement.*/log_min_duration_statement = ${LOG_MIN_DURATION}/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_connections.*/log_connections = ${LOG_CONNECTIONS}/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_disconnections.*/log_disconnections = ${LOG_DISCONNECTIONS}/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_line_prefix.*/log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_lock_waits.*/log_lock_waits = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_temp_files.*/log_temp_files = 0/" "${PG_CONF_FILE}"
    sed -i "s/^#*log_autovacuum_min_duration.*/log_autovacuum_min_duration = 0/" "${PG_CONF_FILE}"
    
    # Statistics
    sed -i "s/^#*track_activities.*/track_activities = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*track_counts.*/track_counts = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*track_io_timing.*/track_io_timing = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*track_functions.*/track_functions = all/" "${PG_CONF_FILE}"
    
    # Replication settings
    if [[ "${ENABLE_REPLICATION}" == "yes" ]]; then
        sed -i "s/^#*wal_level.*/wal_level = replica/" "${PG_CONF_FILE}"
        sed -i "s/^#*max_wal_senders.*/max_wal_senders = 10/" "${PG_CONF_FILE}"
        sed -i "s/^#*max_replication_slots.*/max_replication_slots = ${REPLICATION_SLOTS}/" "${PG_CONF_FILE}"
        sed -i "s/^#*hot_standby.*/hot_standby = on/" "${PG_CONF_FILE}"
    fi
    
    # WAL archiving
    if [[ "${ENABLE_WAL_ARCHIVING}" == "yes" ]]; then
        sed -i "s/^#*archive_mode.*/archive_mode = on/" "${PG_CONF_FILE}"
        
        if [[ "${WAL_ARCHIVE_DESTINATION}" =~ ^s3:// ]]; then
            sed -i "s|^#*archive_command.*|archive_command = 'aws s3 cp %p ${WAL_ARCHIVE_DESTINATION}%f'|" "${PG_CONF_FILE}"
        else
            mkdir -p "${WAL_ARCHIVE_DESTINATION}"
            chown postgres:postgres "${WAL_ARCHIVE_DESTINATION}"
            chmod 700 "${WAL_ARCHIVE_DESTINATION}"
            sed -i "s|^#*archive_command.*|archive_command = 'test ! -f ${WAL_ARCHIVE_DESTINATION}/%f && cp %p ${WAL_ARCHIVE_DESTINATION}/%f'|" "${PG_CONF_FILE}"
        fi
    fi
    
    log "PostgreSQL configuration updated"
}

configure_pg_hba() {
    log_section "Configuring PostgreSQL Authentication (pg_hba.conf)"
    
    # Backup original
    cp "${PG_HBA_FILE}" "${PG_HBA_FILE}.backup.$(date +%Y%m%d_%H%M%S)" || true
    
    # Create new pg_hba.conf
    cat > "${PG_HBA_FILE}" << 'EOF'
# PostgreSQL Client Authentication Configuration
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections
host    all             all             ::1/128                 scram-sha-256

# Replication connections
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256

# Remote connections (configured during setup)
EOF
    
    # Add allowed IPs
    IFS=',' read -ra ip_array <<< "${ALLOWED_IPS}"
    for ip in "${ip_array[@]}"; do
        ip_trimmed=$(echo "${ip}" | xargs)
        echo "host    all             all             ${ip_trimmed}            scram-sha-256" >> "${PG_HBA_FILE}"
        
        if [[ "${ENABLE_REPLICATION}" == "yes" ]]; then
            echo "host    replication     all             ${ip_trimmed}            scram-sha-256" >> "${PG_HBA_FILE}"
        fi
    done
    
    chmod 640 "${PG_HBA_FILE}"
    chown postgres:postgres "${PG_HBA_FILE}"
    
    log "pg_hba.conf configured with allowed IPs"
}

configure_ssl() {
    if [[ "${ENABLE_SSL}" != "yes" ]]; then
        return 0
    fi
    
    log_section "Configuring SSL/TLS"
    
    mkdir -p "${PG_SSL_DIR}"
    chmod 700 "${PG_SSL_DIR}"
    
    # Generate self-signed certificate if files don't exist
    if [[ ! -f "${SSL_CERT_FILE}" ]] || [[ ! -f "${SSL_KEY_FILE}" ]]; then
        log "Generating self-signed SSL certificate"
        
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$(hostname -f)" \
            -keyout "${SSL_KEY_FILE}" \
            -out "${SSL_CERT_FILE}"
        
        chmod 600 "${SSL_KEY_FILE}"
        chmod 644 "${SSL_CERT_FILE}"
    fi
    
    chown postgres:postgres "${SSL_CERT_FILE}" "${SSL_KEY_FILE}"
    
    # Configure PostgreSQL to use SSL
    sed -i "s/^#*ssl.*/ssl = on/" "${PG_CONF_FILE}"
    sed -i "s|^#*ssl_cert_file.*|ssl_cert_file = '${SSL_CERT_FILE}'|" "${PG_CONF_FILE}"
    sed -i "s|^#*ssl_key_file.*|ssl_key_file = '${SSL_KEY_FILE}'|" "${PG_CONF_FILE}"
    sed -i "s/^#*ssl_prefer_server_ciphers.*/ssl_prefer_server_ciphers = on/" "${PG_CONF_FILE}"
    sed -i "s/^#*ssl_ciphers.*/ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'/" "${PG_CONF_FILE}"
    
    log "SSL/TLS configured"
}

configure_firewall() {
    if [[ "${ENABLE_FIREWALL}" != "yes" ]]; then
        return 0
    fi
    
    log_section "Configuring UFW Firewall"
    
    apt-get install -y -qq ufw
    
    # Reset UFW to clean state
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow "${SSH_PORT}/tcp" comment 'SSH'
    
    # Allow PostgreSQL from allowed IPs
    IFS=',' read -ra ip_array <<< "${ALLOWED_IPS}"
    for ip in "${ip_array[@]}"; do
        ip_trimmed=$(echo "${ip}" | xargs)
        if [[ "${ip_trimmed}" != "127.0.0.1/32" ]]; then
            ufw allow from "${ip_trimmed}" to any port "${DB_PORT}" proto tcp comment 'PostgreSQL'
        fi
    done
    
    # Allow PgBouncer from allowed IPs
    if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
        for ip in "${ip_array[@]}"; do
            ip_trimmed=$(echo "${ip}" | xargs)
            if [[ "${ip_trimmed}" != "127.0.0.1/32" ]]; then
                ufw allow from "${ip_trimmed}" to any port "${PGBOUNCER_PORT}" proto tcp comment 'PgBouncer'
            fi
        done
    fi
    
    # Enable firewall
    ufw --force enable
    
    log "UFW firewall configured and enabled"
}

configure_fail2ban() {
    if [[ "${ENABLE_FAIL2BAN}" != "yes" ]]; then
        return 0
    fi
    
    log_section "Configuring Fail2Ban"
    
    apt-get install -y -qq fail2ban
    
    # Create PostgreSQL jail
    cat > /etc/fail2ban/jail.d/postgresql.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600

[postgresql]
enabled = true
port = 5432
filter = postgresql
logpath = /var/log/postgresql/postgresql-*.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
    
    # Create PostgreSQL filter
    cat > /etc/fail2ban/filter.d/postgresql.conf << 'EOF'
[Definition]
failregex = ^.*FATAL:.*authentication failed for user.*$
            ^.*FATAL:.*password authentication failed for user.*$
            ^.*FATAL:.*no pg_hba.conf entry for host.*$
ignoreregex =
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "Fail2Ban configured for PostgreSQL and SSH"
}

install_pgbouncer() {
    if [[ "${ENABLE_PGBOUNCER}" != "yes" ]]; then
        return 0
    fi
    
    log_section "Installing and Configuring PgBouncer"
    
    apt-get install -y -qq pgbouncer
    
    # Create PgBouncer configuration
    cat > /etc/pgbouncer/pgbouncer.ini << EOF
[databases]
* = host=127.0.0.1 port=${DB_PORT} pool_size=${PGBOUNCER_DEFAULT_POOL_SIZE}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = ${PGBOUNCER_PORT}
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = ${PGBOUNCER_POOL_MODE}
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE}
server_reset_query = DISCARD ALL
server_check_delay = 30
max_db_connections = ${DB_MAX_CONNECTIONS}
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
EOF
    
    # Create empty userlist
    touch /etc/pgbouncer/userlist.txt
    chown postgres:postgres /etc/pgbouncer/userlist.txt
    chmod 600 /etc/pgbouncer/userlist.txt
    
    systemctl enable pgbouncer
    systemctl restart pgbouncer
    
    log "PgBouncer installed and configured on port ${PGBOUNCER_PORT}"
}

# ============================================================================
# MAINTENANCE SCRIPTS
# ============================================================================

create_maintenance_scripts() {
    log_section "Creating Maintenance Scripts"
    
    mkdir -p "${BACKUP_DIR}" "${MONITORING_DIR}"
    chown postgres:postgres "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
    
    # ==================== CREATE DATABASE AND USER SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-create-db-user.sh" << 'SCRIPT_CREATE_DB_USER'
#!/usr/bin/env bash
# Create PostgreSQL database and user

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <database_name> <username> [options]"
    echo "Options:"
    echo "  --no-password     Skip password prompt (use for local trust)"
    echo "  --owner-only      Don't grant public access"
    exit 1
fi

DB_NAME="$1"
DB_USER="$2"
shift 2

NO_PASSWORD=false
OWNER_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-password) NO_PASSWORD=true; shift ;;
        --owner-only) OWNER_ONLY=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "${NO_PASSWORD}" == "false" ]]; then
    read -rsp "Enter password for user ${DB_USER}: " DB_PASSWORD
    echo
    read -rsp "Confirm password: " DB_PASSWORD_CONFIRM
    echo
    
    if [[ "${DB_PASSWORD}" != "${DB_PASSWORD_CONFIRM}" ]]; then
        echo "Passwords don't match!"
        exit 1
    fi
fi

# Create user
if [[ "${NO_PASSWORD}" == "true" ]]; then
    sudo -u postgres psql -c "CREATE USER ${DB_USER};" 2>/dev/null || echo "User ${DB_USER} already exists"
else
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';" 2>/dev/null || echo "User ${DB_USER} already exists"
fi

# Create database
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || echo "Database ${DB_NAME} already exists"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

if [[ "${OWNER_ONLY}" == "false" ]]; then
    sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};"
fi

echo "✓ Database '${DB_NAME}' and user '${DB_USER}' created successfully"

# Add to PgBouncer if installed
if [[ -f /etc/pgbouncer/userlist.txt && "${NO_PASSWORD}" == "false" ]]; then
    # Generate SCRAM-SHA-256 hash
    HASH=$(sudo -u postgres psql -tAc "SELECT concat('SCRAM-SHA-256\$4096:', encode(digest('${DB_PASSWORD}${DB_USER}', 'sha256'), 'base64'));")
    echo "\"${DB_USER}\" \"${HASH}\"" >> /etc/pgbouncer/userlist.txt
    systemctl reload pgbouncer
    echo "✓ User added to PgBouncer"
fi

echo ""
echo "Connection strings:"
echo "  Direct:    postgresql://${DB_USER}:PASSWORD@localhost:5432/${DB_NAME}"
if [[ -f /etc/pgbouncer/userlist.txt ]]; then
    echo "  PgBouncer: postgresql://${DB_USER}:PASSWORD@localhost:6432/${DB_NAME}"
fi
SCRIPT_CREATE_DB_USER
    chmod +x "${SCRIPTS_DIR}/pg-create-db-user.sh"
    
    # ==================== BACKUP SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-backup.sh" << 'SCRIPT_BACKUP'
#!/usr/bin/env bash
# PostgreSQL backup script

set -euo pipefail

BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}
COMPRESSION=${BACKUP_COMPRESSION:-yes}

mkdir -p "${BACKUP_DIR}"

echo "Starting PostgreSQL backup at $(date)"

# Get list of databases
DATABASES=$(sudo -u postgres psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

for db in ${DATABASES}; do
    echo "Backing up database: ${db}"
    
    BACKUP_FILE="${BACKUP_DIR}/${db}_${TIMESTAMP}.sql"
    
    if [[ "${COMPRESSION}" == "yes" ]]; then
        sudo -u postgres pg_dump -Fc "${db}" > "${BACKUP_FILE}.custom"
        echo "  ✓ ${db} backed up to ${BACKUP_FILE}.custom"
    else
        sudo -u postgres pg_dump "${db}" > "${BACKUP_FILE}"
        echo "  ✓ ${db} backed up to ${BACKUP_FILE}"
    fi
done

# Backup globals (roles, tablespaces, etc.)
echo "Backing up globals..."
sudo -u postgres pg_dumpall --globals-only > "${BACKUP_DIR}/globals_${TIMESTAMP}.sql"

# Cleanup old backups
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -delete

# Upload to S3 if configured
if [[ -n "${S3_BUCKET:-}" ]]; then
    echo "Uploading to S3: ${S3_BUCKET}"
    aws s3 sync "${BACKUP_DIR}" "${S3_BUCKET}/postgresql-backups/$(hostname)/" --delete
fi

echo "Backup completed at $(date)"
SCRIPT_BACKUP
    chmod +x "${SCRIPTS_DIR}/pg-backup.sh"
    
    # ==================== RESTORE SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-restore.sh" << 'SCRIPT_RESTORE'
#!/usr/bin/env bash
# PostgreSQL restore script

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <backup_file> <target_database>"
    echo ""
    echo "Available backups:"
    ls -lh /var/backups/postgresql/*.{sql,custom} 2>/dev/null | tail -20
    exit 1
fi

BACKUP_FILE="$1"
TARGET_DB="$2"

if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "WARNING: This will restore ${BACKUP_FILE} into database '${TARGET_DB}'"
echo "Existing data in '${TARGET_DB}' may be affected."
read -rp "Continue? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Restore cancelled"
    exit 0
fi

# Determine restore method based on file extension
if [[ "${BACKUP_FILE}" == *.custom ]]; then
    echo "Restoring custom format backup..."
    sudo -u postgres pg_restore -d "${TARGET_DB}" --clean --if-exists --no-owner --no-acl "${BACKUP_FILE}"
else
    echo "Restoring SQL backup..."
    sudo -u postgres psql -d "${TARGET_DB}" < "${BACKUP_FILE}"
fi

echo "✓ Restore completed successfully"
SCRIPT_RESTORE
    chmod +x "${SCRIPTS_DIR}/pg-restore.sh"
    
    # ==================== STATUS SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-status.sh" << 'SCRIPT_STATUS'
#!/usr/bin/env bash
# PostgreSQL status and health check

set -euo pipefail

echo "========================================="
echo "PostgreSQL Status Report"
echo "========================================="
echo ""

# Service status
echo "Service Status:"
systemctl status postgresql --no-pager -l | head -20
echo ""

# Connection status
echo "Connection Status:"
sudo -u postgres pg_isready -q && echo "✓ PostgreSQL is accepting connections" || echo "✗ PostgreSQL is NOT accepting connections"
echo ""

# Active connections
echo "Active Connections:"
sudo -u postgres psql -c "
SELECT 
    datname as database,
    count(*) as connections,
    max(state) as state
FROM pg_stat_activity 
WHERE datname IS NOT NULL
GROUP BY datname
ORDER BY connections DESC;
"
echo ""

# Database sizes
echo "Database Sizes:"
sudo -u postgres psql -c "
SELECT 
    datname as database,
    pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
"
echo ""

# Replication status
echo "Replication Status:"
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "No replication configured"
echo ""

# Long running queries
echo "Long Running Queries (>1 minute):"
sudo -u postgres psql -c "
SELECT 
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '1 minute'
  AND state != 'idle'
ORDER BY duration DESC;
" 2>/dev/null || echo "No long running queries"
echo ""

# Locks
echo "Lock Status:"
sudo -u postgres psql -c "
SELECT 
    locktype,
    database,
    relation::regclass,
    mode,
    granted,
    count(*)
FROM pg_locks
GROUP BY locktype, database, relation, mode, granted
ORDER BY count(*) DESC
LIMIT 10;
" 2>/dev/null || echo "No locks"
echo ""

# PgBouncer status
if systemctl is-active --quiet pgbouncer; then
    echo "PgBouncer Status:"
    echo "SHOW POOLS;" | psql -U pgbouncer -p 6432 pgbouncer 2>/dev/null || echo "PgBouncer stats unavailable"
fi

echo "========================================="
SCRIPT_STATUS
    chmod +x "${SCRIPTS_DIR}/pg-status.sh"
    
    # ==================== RESTART SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-restart.sh" << 'SCRIPT_RESTART'
#!/usr/bin/env bash
# Safe PostgreSQL restart

set -euo pipefail

echo "Restarting PostgreSQL..."
systemctl restart postgresql

sleep 2

if systemctl is-active --quiet postgresql; then
    echo "✓ PostgreSQL restarted successfully"
    sudo -u postgres pg_isready
else
    echo "✗ PostgreSQL failed to start"
    systemctl status postgresql --no-pager
    exit 1
fi

if systemctl is-active --quiet pgbouncer; then
    echo "Restarting PgBouncer..."
    systemctl restart pgbouncer
    echo "✓ PgBouncer restarted"
fi
SCRIPT_RESTART
    chmod +x "${SCRIPTS_DIR}/pg-restart.sh"
    
    # ==================== LOG ANALYSIS SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-logs.sh" << 'SCRIPT_LOGS'
#!/usr/bin/env bash
# PostgreSQL log analysis

set -euo pipefail

LINES=${1:-100}
LOG_DIR="/var/log/postgresql"

echo "Recent PostgreSQL Logs (last ${LINES} lines):"
echo "========================================="

# Find most recent log file
LATEST_LOG=$(ls -t ${LOG_DIR}/postgresql-*.log 2>/dev/null | head -1)

if [[ -n "${LATEST_LOG}" ]]; then
    tail -n "${LINES}" "${LATEST_LOG}"
else
    echo "No log files found in ${LOG_DIR}"
fi

echo ""
echo "========================================="
echo "Error Summary (last 24 hours):"
find ${LOG_DIR} -name "postgresql-*.log" -mtime -1 -exec grep -i "ERROR\|FATAL\|PANIC" {} \; | tail -20

echo ""
echo "========================================="
echo "Slow Queries (last 24 hours):"
find ${LOG_DIR} -name "postgresql-*.log" -mtime -1 -exec grep "duration:" {} \; | sort -t: -k2 -n | tail -20
SCRIPT_LOGS
    chmod +x "${SCRIPTS_DIR}/pg-logs.sh"
    
    # ==================== VACUUM SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-vacuum.sh" << 'SCRIPT_VACUUM'
#!/usr/bin/env bash
# PostgreSQL vacuum and analyze

set -euo pipefail

MODE=${1:-analyze}

echo "Running VACUUM ${MODE^^} on all databases..."

DATABASES=$(sudo -u postgres psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;")

for db in ${DATABASES}; do
    echo "Processing database: ${db}"
    
    case "${MODE}" in
        full)
            sudo -u postgres psql -d "${db}" -c "VACUUM FULL VERBOSE;"
            ;;
        analyze)
            sudo -u postgres psql -d "${db}" -c "VACUUM ANALYZE VERBOSE;"
            ;;
        *)
            sudo -u postgres psql -d "${db}" -c "VACUUM VERBOSE;"
            ;;
    esac
    
    echo "✓ ${db} completed"
done

echo "All databases vacuumed successfully"
SCRIPT_VACUUM
    chmod +x "${SCRIPTS_DIR}/pg-vacuum.sh"
    
    # ==================== MONITORING SCRIPT ====================
    cat > "${SCRIPTS_DIR}/pg-monitor.sh" << 'SCRIPT_MONITOR'
#!/usr/bin/env bash
# PostgreSQL monitoring and metrics collection

set -euo pipefail

MONITORING_DIR="/opt/postgresql-monitoring"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${MONITORING_DIR}/metrics"

# Collect metrics
{
    echo "timestamp: $(date -Iseconds)"
    echo "---"
    
    # Connection metrics
    echo "connections:"
    sudo -u postgres psql -At -c "SELECT count(*) FROM pg_stat_activity;" | sed 's/^/  total: /'
    sudo -u postgres psql -At -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" | sed 's/^/  active: /'
    sudo -u postgres psql -At -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle';" | sed 's/^/  idle: /'
    
    # Database sizes
    echo "database_sizes:"
    sudo -u postgres psql -At -c "SELECT datname, pg_database_size(datname) FROM pg_database WHERE datistemplate = false;" | \
        while IFS='|' read -r db size; do
            echo "  ${db}: ${size}"
        done
    
    # Cache hit ratio
    echo "cache_hit_ratio:"
    sudo -u postgres psql -At -c "
        SELECT 
            sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) * 100 
        FROM pg_statio_user_tables;
    " | sed 's/^/  percentage: /'
    
    # Transaction rate
    echo "transactions:"
    sudo -u postgres psql -At -c "SELECT sum(xact_commit + xact_rollback) FROM pg_stat_database;" | sed 's/^/  total: /'
    
} > "${MONITORING_DIR}/metrics/metrics_${TIMESTAMP}.yaml"

# Cleanup old metrics
find "${MONITORING_DIR}/metrics" -type f -mtime +${MONITORING_RETENTION_DAYS:-30} -delete

echo "Metrics collected: ${MONITORING_DIR}/metrics/metrics_${TIMESTAMP}.yaml"
SCRIPT_MONITOR
    chmod +x "${SCRIPTS_DIR}/pg-monitor.sh"
    
    log "Maintenance scripts created in ${SCRIPTS_DIR}"
}

# ============================================================================
# CRON JOBS
# ============================================================================

setup_cron_jobs() {
    if [[ "${ENABLE_BACKUPS}" != "yes" ]]; then
        return 0
    fi
    
    log_section "Setting Up Automated Tasks"
    
    # Determine cron schedule
    case "${BACKUP_SCHEDULE}" in
        hourly)
            CRON_SCHEDULE="0 * * * *"
            ;;
        daily)
            CRON_SCHEDULE="0 2 * * *"
            ;;
        weekly)
            CRON_SCHEDULE="0 2 * * 0"
            ;;
        *)
            CRON_SCHEDULE="0 2 * * *"
            ;;
    esac
    
    # Create cron file
    cat > /etc/cron.d/postgresql-maintenance << EOF
# PostgreSQL automated maintenance tasks
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Backup (${BACKUP_SCHEDULE})
${CRON_SCHEDULE} root ${SCRIPTS_DIR}/pg-backup.sh >> ${LOG_DIR}/backup.log 2>&1

# Vacuum analyze (weekly)
0 3 * * 0 root ${SCRIPTS_DIR}/pg-vacuum.sh analyze >> ${LOG_DIR}/vacuum.log 2>&1

# Monitoring (every 5 minutes)
*/5 * * * * root ${SCRIPTS_DIR}/pg-monitor.sh >> ${LOG_DIR}/monitor.log 2>&1
EOF
    
    chmod 644 /etc/cron.d/postgresql-maintenance
    
    log "Cron jobs configured for backups and maintenance"
}

# ============================================================================
# LOG ROTATION
# ============================================================================

setup_logrotate() {
    log_section "Configuring Log Rotation"
    
    cat > /etc/logrotate.d/postgresql-setup << 'EOF'
/var/log/postgresql-setup/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    missingok
    create 0640 root root
}
EOF
    
    log "Log rotation configured"
}

# ============================================================================
# POST-INSTALLATION
# ============================================================================

apply_configuration() {
    log_section "Applying Configuration"
    
    # Reload PostgreSQL
    systemctl reload postgresql || systemctl restart postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 2
    
    # Verify PostgreSQL is running
    if sudo -u postgres pg_isready -p "${DB_PORT}" -q; then
        log "✓ PostgreSQL is accepting connections on port ${DB_PORT}"
    else
        log_error "PostgreSQL is not ready. Check logs with: journalctl -u postgresql -n 50"
        exit 1
    fi
    
    # Reload PgBouncer if enabled
    if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
        systemctl reload pgbouncer || systemctl restart pgbouncer
        log "✓ PgBouncer reloaded"
    fi
}

create_summary() {
    log_section "Setup Summary"
    
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║        PostgreSQL ${PG_VERSION} Enterprise Setup Complete!           ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

CONFIGURATION SUMMARY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Database:
  • Listen Address: ${DB_LISTEN_ADDRESSES}
  • Port: ${DB_PORT}
  • Max Connections: ${DB_MAX_CONNECTIONS}
  • SSL Enabled: ${ENABLE_SSL}

Memory Configuration:
  • Shared Buffers: ${DB_SHARED_BUFFERS}MB
  • Effective Cache: ${DB_EFFECTIVE_CACHE}MB
  • Work Memory: ${DB_WORK_MEM}MB
  • Maintenance Work Memory: ${DB_MAINTENANCE_WORK_MEM}MB

Security:
  • Firewall (UFW): ${ENABLE_FIREWALL}
  • Fail2Ban: ${ENABLE_FAIL2BAN}
  • Allowed IPs: ${ALLOWED_IPS}

Backup & HA:
  • Automated Backups: ${ENABLE_BACKUPS}
  • Backup Schedule: ${BACKUP_SCHEDULE}
  • Retention: ${BACKUP_RETENTION_DAYS} days
  • WAL Archiving: ${ENABLE_WAL_ARCHIVING}
  • Replication: ${ENABLE_REPLICATION}

Connection Pooling:
  • PgBouncer: ${ENABLE_PGBOUNCER}
$(if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
    echo "  • PgBouncer Port: ${PGBOUNCER_PORT}"
    echo "  • Pool Mode: ${PGBOUNCER_POOL_MODE}"
fi)

AVAILABLE COMMANDS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Database Management:
  pg-create-db-user.sh <db_name> <username>  Create database and user
  pg-status.sh                                Show detailed status
  pg-restart.sh                               Safe restart

Backup & Restore:
  pg-backup.sh                                Run manual backup
  pg-restore.sh <backup_file> <target_db>     Restore from backup

Maintenance:
  pg-vacuum.sh [full|analyze]                 Vacuum databases
  pg-logs.sh [lines]                          View recent logs
  pg-monitor.sh                               Collect metrics

QUICK START:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Create your first database:
   sudo pg-create-db-user.sh myapp myapp_user

2. Check status:
   sudo pg-status.sh

3. Connect to PostgreSQL:
   psql -h localhost -p ${DB_PORT} -U myapp_user -d myapp

$(if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
    echo "4. Connect via PgBouncer (recommended):"
    echo "   psql -h localhost -p ${PGBOUNCER_PORT} -U myapp_user -d myapp"
fi)

IMPORTANT SECURITY NOTES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠  Change the default postgres user password:
   sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'strong_password';"

⚠  Review firewall rules:
   sudo ufw status verbose

⚠  Review authentication settings:
   sudo vim ${PG_HBA_FILE}

⚠  Test backups regularly:
   sudo pg-backup.sh

⚠  Monitor logs:
   sudo pg-logs.sh

CONFIGURATION FILES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• State File: ${STATE_FILE}
• PostgreSQL Config: ${PG_CONF_FILE}
• Authentication: ${PG_HBA_FILE}
• Backup Directory: ${BACKUP_DIR}
• Log Directory: ${LOG_DIR}
$(if [[ "${ENABLE_PGBOUNCER}" == "yes" ]]; then
    echo "• PgBouncer Config: /etc/pgbouncer/pgbouncer.ini"
fi)

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Secure the postgres user password
2. Create your application databases and users
3. Test database connections
4. Verify backups are working
5. Set up monitoring dashboards (optional)
6. Configure application connection strings

Need help? Check logs at: ${LOG_DIR}/setup.log

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Setup
    check_root
    mkdir -p "${LOG_DIR}"
    
    log_section "PostgreSQL ${PG_VERSION} Enterprise Setup - Version ${SCRIPT_VERSION}"
    
    check_os
    
    # Load previous state if exists
    load_state || true
    
    # Interactive configuration
    echo ""
    echo "This script will set up PostgreSQL ${PG_VERSION} with enterprise features."
    echo "Previous settings will be shown in [brackets] if you've run this before."
    echo ""
    read -p "Press Enter to begin configuration..."
    echo ""
    
    configure_database
    configure_security
    configure_backups
    configure_high_availability
    configure_connection_pooling
    configure_monitoring
    
    # Save configuration
    save_state
    
    # Confirm before proceeding
    echo ""
    log_warn "Configuration complete. Ready to install and configure PostgreSQL."
    read -p "Proceed with installation? (yes/no): " -r
    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Installation cancelled by user"
        exit 0
    fi
    
    # Installation
    install_prerequisites
    install_postgresql_repository
    install_postgresql
    install_additional_tools
    
    # Configuration
    configure_postgresql
    configure_pg_hba
    configure_ssl
    configure_firewall
    configure_fail2ban
    install_pgbouncer
    
    # Maintenance
    create_maintenance_scripts
    setup_cron_jobs
    setup_logrotate
    
    # Finalize
    apply_configuration
    create_summary
    
    log "Setup completed successfully at $(date)"
}

# Run main function
main "$@"
