# PostgreSQL 17 Enterprise-Ready VPS Setup

[![PostgreSQL Version](https://img.shields.io/badge/PostgreSQL-17-blue.svg)](https://www.postgresql.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange.svg)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A **production-grade, interactive, and idempotent** PostgreSQL 17 setup script for Ubuntu VPS environments. Designed for startups, enterprises, and small teams who need a robust, secure, and maintainable database infrastructure without the complexity of managed services.

---

## 🚀 Features

### Core Database
- **PostgreSQL 17** from official PGDG repository (LTS)
- Auto-tuned configuration based on system resources (RAM, CPU)
- Optimized settings for OLTP workloads
- Support for streaming replication and high availability
- WAL archiving for point-in-time recovery

### Security & Compliance
- 🔒 **UFW Firewall** with IP whitelisting
- 🛡️ **Fail2Ban** for intrusion prevention (SSH + PostgreSQL)
- 🔐 **SSL/TLS encryption** with auto-generated or custom certificates
- 🔑 **SCRAM-SHA-256** authentication (modern password hashing)
- 📋 Granular access control via `pg_hba.conf`

### Performance & Scalability
- ⚡ **PgBouncer** connection pooling (transaction/session/statement modes)
- 📊 Optimized memory settings (shared buffers, work mem, cache)
- 🔄 Automatic vacuuming and statistics collection
- 📈 Query performance tracking and slow query logging
- 💾 SSD-optimized I/O settings

### Backup & Recovery
- 🗄️ Automated daily/weekly/hourly backups
- 📦 Compressed backup support (custom format)
- ☁️ **S3/cloud storage** integration for off-site backups
- ⏰ Configurable retention policies
- 🔄 One-command restore functionality
- 📝 WAL archiving for PITR (Point-In-Time Recovery)

### Monitoring & Maintenance
- 📊 Real-time connection and query monitoring
- 📝 Comprehensive logging (connections, slow queries, errors)
- 🔍 Log analysis and error reporting tools
- 📈 Metrics collection for external monitoring systems
- 🧹 Automated vacuum and analyze scheduling

### Developer Experience
- 🎯 **Fully idempotent** - safe to re-run without side effects
- 💬 Interactive prompts with smart defaults
- 💾 Configuration persistence across runs (`/etc/postgresql-setup.state`)
- 🎨 Colorized output with clear progress indicators
- 📚 Comprehensive maintenance scripts included
- 🔧 One-command database and user creation

---

## 📋 Requirements

### Minimum System Requirements
- **OS:** Ubuntu 22.04 LTS or 24.04 LTS
- **CPU:** 2 vCPUs (4+ recommended for production)
- **RAM:** 4 GB (8+ GB recommended for production)
- **Storage:** 40 GB SSD (RAID-10 recommended for production)
- **Network:** Static IP address recommended

### Recommended Production Setup
- **CPU:** 4-8 vCPUs
- **RAM:** 16-32 GB
- **Storage:** 200+ GB NVMe SSD with RAID-10
- **Network:** 1 Gbps network, dedicated private network
- **Monitoring:** External monitoring (Prometheus, Datadog, etc.)

### Access Requirements
- Root access or sudo privileges
- SSH access to the server
- (Optional) AWS credentials for S3 backups

---

## 🎯 Quick Start

### 1. Download the Script

```bash
# Via wget
wget https://raw.githubusercontent.com/your-repo/vps-postgres-setup/main/setup-postgres17-enterprise.sh

# Via curl
curl -O https://raw.githubusercontent.com/your-repo/vps-postgres-setup/main/setup-postgres17-enterprise.sh
```

### 2. Make Executable

```bash
chmod +x setup-postgres17-enterprise.sh
```

### 3. Run the Setup

```bash
sudo ./setup-postgres17-enterprise.sh
```

### 4. Follow Interactive Prompts

The script will guide you through configuration:

```
Database Configuration:
  ✓ Listen addresses (0.0.0.0 for public, localhost for local)
  ✓ Port (default: 5432)
  ✓ Maximum connections
  ✓ Memory allocation (auto-calculated)

Security Configuration:
  ✓ Allowed IP addresses/CIDRs
  ✓ Enable SSL/TLS
  ✓ Firewall setup
  ✓ Fail2Ban configuration

Backup Configuration:
  ✓ Schedule (hourly/daily/weekly)
  ✓ Retention period
  ✓ Compression
  ✓ Remote backup (S3)

High Availability:
  ✓ WAL archiving
  ✓ Replication setup

Connection Pooling:
  ✓ PgBouncer configuration
  ✓ Pool mode and sizing
```

### 5. Verify Installation

```bash
# Check PostgreSQL status
sudo pg-status.sh

# Test connection
psql -h localhost -p 5432 -U postgres

# View summary
cat /var/log/postgresql-setup/setup.log
```

---

## 📚 Usage Guide

### Creating Your First Database

```bash
# Interactive creation
sudo pg-create-db-user.sh myapp myapp_user

# This will:
# 1. Prompt for password
# 2. Create the user with SCRAM-SHA-256 authentication
# 3. Create the database owned by the user
# 4. Grant appropriate privileges
# 5. Add user to PgBouncer (if enabled)
```

### Connecting to PostgreSQL

#### Direct Connection
```bash
# Command line
psql -h localhost -p 5432 -U myapp_user -d myapp

# Connection string
postgresql://myapp_user:password@localhost:5432/myapp
```

#### Via PgBouncer (Recommended)
```bash
# Command line
psql -h localhost -p 6432 -U myapp_user -d myapp

# Connection string (for your application)
postgresql://myapp_user:password@localhost:6432/myapp
```

#### SSL/TLS Connection
```bash
psql "postgresql://myapp_user:password@hostname:5432/myapp?sslmode=require"
```

### Application Configuration Examples

#### Django
```python
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'myapp',
        'USER': 'myapp_user',
        'PASSWORD': 'password',
        'HOST': 'localhost',
        'PORT': '6432',  # PgBouncer
        'OPTIONS': {
            'sslmode': 'require',
        }
    }
}
```

#### Node.js (pg)
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 6432,  // PgBouncer
  database: 'myapp',
  user: 'myapp_user',
  password: 'password',
  ssl: {
    rejectUnauthorized: false
  },
  max: 20,  // max pool size
  idleTimeoutMillis: 30000,
});
```

#### Ruby on Rails
```yaml
production:
  adapter: postgresql
  encoding: unicode
  database: myapp
  pool: 25
  username: myapp_user
  password: <%= ENV['DATABASE_PASSWORD'] %>
  host: localhost
  port: 6432  # PgBouncer
```

---

## 🛠️ Maintenance Scripts

All scripts are installed in `/usr/local/bin/` and prefixed with `pg-`:

### Database Management

#### `pg-create-db-user.sh`
Create new database and user with automatic PgBouncer integration.

```bash
# Basic usage
sudo pg-create-db-user.sh <database_name> <username>

# With options
sudo pg-create-db-user.sh myapp myapp_user --owner-only
sudo pg-create-db-user.sh analytics analytics_user --no-password
```

#### `pg-status.sh`
Comprehensive status report including connections, sizes, replication, locks.

```bash
sudo pg-status.sh
```

Output includes:
- Service status
- Active connections by database
- Database sizes
- Replication status
- Long-running queries
- Lock information
- PgBouncer statistics

#### `pg-restart.sh`
Safe restart of PostgreSQL and PgBouncer services.

```bash
sudo pg-restart.sh
```

### Backup & Restore

#### `pg-backup.sh`
Run manual backup of all databases.

```bash
# Run backup now
sudo pg-backup.sh

# Backups are stored in:
# /var/backups/postgresql/
#   ├── database1_20240208_143022.sql.custom
#   ├── database2_20240208_143022.sql.custom
#   └── globals_20240208_143022.sql
```

Features:
- Individual database backups
- Compressed custom format
- Automatic rotation based on retention policy
- S3 upload (if configured)
- Includes roles and permissions (globals)

#### `pg-restore.sh`
Restore from backup file.

```bash
# List available backups
sudo pg-restore.sh

# Restore specific backup
sudo pg-restore.sh /var/backups/postgresql/myapp_20240208_143022.sql.custom myapp

# Restore to different database
sudo pg-restore.sh /var/backups/postgresql/myapp_20240208_143022.sql.custom myapp_staging
```

### Maintenance & Optimization

#### `pg-vacuum.sh`
Run vacuum operations on all databases.

```bash
# Standard vacuum and analyze
sudo pg-vacuum.sh

# Analyze only
sudo pg-vacuum.sh analyze

# Full vacuum (locks tables, use during maintenance window)
sudo pg-vacuum.sh full
```

#### `pg-logs.sh`
View and analyze PostgreSQL logs.

```bash
# View last 100 lines
sudo pg-logs.sh

# View last 500 lines
sudo pg-logs.sh 500
```

Shows:
- Recent log entries
- Error summary (last 24 hours)
- Slow query summary

#### `pg-monitor.sh`
Collect metrics for monitoring systems.

```bash
sudo pg-monitor.sh

# Metrics stored in:
# /opt/postgresql-monitoring/metrics/metrics_20240208_143022.yaml
```

Collected metrics:
- Connection counts (total, active, idle)
- Database sizes
- Cache hit ratio
- Transaction rates
- Query performance statistics

---

## 🔒 Security Best Practices

### 1. Change Default Passwords

```bash
# Change postgres superuser password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'strong_random_password';"

# Store in password manager, not in scripts!
```

### 2. Review Access Controls

```bash
# Review pg_hba.conf
sudo vim /etc/postgresql/17/main/pg_hba.conf

# Review UFW rules
sudo ufw status verbose

# Review Fail2Ban status
sudo fail2ban-client status
sudo fail2ban-client status postgresql
```

### 3. Enable SSL/TLS for Remote Connections

If you answered "no" during setup but need SSL later:

```bash
# Generate certificates
sudo openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/CN=$(hostname -f)" \
  -keyout /etc/ssl/postgresql/server.key \
  -out /etc/ssl/postgresql/server.crt

# Set ownership
sudo chown postgres:postgres /etc/ssl/postgresql/server.*
sudo chmod 600 /etc/ssl/postgresql/server.key

# Edit postgresql.conf
sudo vim /etc/postgresql/17/main/postgresql.conf
# Add: ssl = on

# Restart
sudo pg-restart.sh
```

### 4. Regular Security Updates

```bash
# Update PostgreSQL and system packages
sudo apt update
sudo apt upgrade -y

# Check for PostgreSQL-specific updates
sudo apt list --upgradable | grep postgresql
```

### 5. Monitor Failed Login Attempts

```bash
# Check Fail2Ban logs
sudo tail -f /var/log/fail2ban.log

# Check PostgreSQL auth failures
sudo pg-logs.sh | grep -i "authentication failed"
```

### 6. Implement Network Segmentation

```bash
# Allow database access only from application servers
sudo ufw status numbered
sudo ufw delete <rule_number>
sudo ufw allow from 10.0.1.100/32 to any port 5432 proto tcp
```

---

## 📊 Monitoring & Performance

### Key Metrics to Monitor

1. **Connections**
   ```sql
   SELECT count(*), state FROM pg_stat_activity GROUP BY state;
   ```

2. **Database Size Growth**
   ```sql
   SELECT datname, pg_size_pretty(pg_database_size(datname)) 
   FROM pg_database ORDER BY pg_database_size(datname) DESC;
   ```

3. **Cache Hit Ratio** (should be >90%)
   ```sql
   SELECT 
     sum(heap_blks_read) as heap_read,
     sum(heap_blks_hit)  as heap_hit,
     sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) * 100 AS ratio
   FROM pg_statio_user_tables;
   ```

4. **Long Running Queries**
   ```sql
   SELECT pid, now() - query_start AS duration, query 
   FROM pg_stat_activity 
   WHERE state = 'active' AND now() - query_start > interval '1 minute';
   ```

5. **Table Bloat**
   ```sql
   SELECT schemaname, tablename, 
     pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
   FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;
   ```

### Integration with Monitoring Tools

#### Prometheus + Grafana

Install postgres_exporter:
```bash
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
tar xvfz postgres_exporter-0.15.0.linux-amd64.tar.gz
sudo mv postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/

# Create monitoring user
sudo -u postgres psql -c "CREATE USER postgres_exporter PASSWORD 'exporter_password';"
sudo -u postgres psql -c "GRANT pg_monitor TO postgres_exporter;"

# Configure
export DATA_SOURCE_NAME="postgresql://postgres_exporter:exporter_password@localhost:5432/postgres?sslmode=disable"
/usr/local/bin/postgres_exporter
```

#### Datadog

```bash
# Install Datadog agent
DD_API_KEY=<your_api_key> DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"

# Configure PostgreSQL integration
sudo vim /etc/datadog-agent/conf.d/postgres.d/conf.yaml
```

---

## 🔄 Backup & Recovery Procedures

### Automated Backups

Backups run automatically based on your configuration:

```bash
# Check cron schedule
sudo cat /etc/cron.d/postgresql-maintenance

# Manual backup
sudo pg-backup.sh

# Check backup directory
ls -lh /var/backups/postgresql/
```

### Disaster Recovery

#### Full Database Restore

```bash
# 1. Stop applications
sudo systemctl stop your-app

# 2. Drop and recreate database (careful!)
sudo -u postgres psql -c "DROP DATABASE myapp;"
sudo -u postgres psql -c "CREATE DATABASE myapp OWNER myapp_user;"

# 3. Restore from backup
sudo pg-restore.sh /var/backups/postgresql/myapp_20240208_143022.sql.custom myapp

# 4. Verify
sudo -u postgres psql -d myapp -c "\dt"

# 5. Restart applications
sudo systemctl start your-app
```

#### Point-in-Time Recovery (PITR)

If WAL archiving is enabled:

```bash
# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Remove current data directory
sudo rm -rf /var/lib/postgresql/17/main/*

# 3. Restore base backup
sudo -u postgres tar xzf /var/backups/postgresql/base_backup.tar.gz -C /var/lib/postgresql/17/main/

# 4. Create recovery.signal
sudo -u postgres touch /var/lib/postgresql/17/main/recovery.signal

# 5. Configure recovery
sudo -u postgres cat > /var/lib/postgresql/17/main/postgresql.auto.conf << EOF
restore_command = 'aws s3 cp s3://your-bucket/wal_archive/%f %p'
recovery_target_time = '2024-02-08 14:30:00'
EOF

# 6. Start PostgreSQL
sudo systemctl start postgresql
```

### Testing Backups

**Critical:** Always test your backups!

```bash
# Create test environment
sudo pg-create-db-user.sh myapp_test_restore test_user

# Restore latest backup to test database
LATEST_BACKUP=$(ls -t /var/backups/postgresql/myapp_*.custom | head -1)
sudo pg-restore.sh $LATEST_BACKUP myapp_test_restore

# Verify data
sudo -u postgres psql -d myapp_test_restore -c "SELECT count(*) FROM users;"

# Cleanup
sudo -u postgres psql -c "DROP DATABASE myapp_test_restore;"
```

---

## ⚡ Performance Tuning

### Memory Configuration

The script auto-tunes based on system RAM, but you can customize:

```bash
sudo vim /etc/postgresql/17/main/postgresql.conf
```

**For OLTP workloads (many short transactions):**
```conf
shared_buffers = 25% of RAM
effective_cache_size = 75% of RAM
work_mem = (RAM / max_connections) / 2
maintenance_work_mem = RAM / 16
```

**For OLAP workloads (complex queries, reporting):**
```conf
shared_buffers = 25% of RAM
effective_cache_size = 75% of RAM
work_mem = RAM / 10
maintenance_work_mem = RAM / 8
```

### Connection Pooling Optimization

```bash
sudo vim /etc/pgbouncer/pgbouncer.ini
```

**For web applications:**
```ini
pool_mode = transaction
default_pool_size = (2 * CPU_cores) + effective_spindle_count
max_client_conn = 1000
```

**For long-running transactions:**
```ini
pool_mode = session
default_pool_size = max_connections / 2
```

### Query Optimization

Enable query logging:
```sql
-- Find slow queries
ALTER SYSTEM SET log_min_duration_statement = 100;  -- 100ms
SELECT pg_reload_conf();

-- Create indexes on frequently queried columns
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- Analyze query plans
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

---

## 🔧 Advanced Configuration

### High Availability Setup

#### Streaming Replication

**On Primary:**
```bash
# Already configured if you enabled replication during setup

# Create replication user
sudo -u postgres psql -c "CREATE USER replicator REPLICATION LOGIN PASSWORD 'replication_password';"

# Verify replication slot
sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"
```

**On Standby:**
```bash
# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Remove data directory
sudo rm -rf /var/lib/postgresql/17/main/*

# 3. Base backup from primary
sudo -u postgres pg_basebackup -h primary_ip -D /var/lib/postgresql/17/main -U replicator -P -v -R

# 4. Start PostgreSQL
sudo systemctl start postgresql

# 5. Verify replication
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"
```

### Multiple Database Instances

Run multiple PostgreSQL versions:

```bash
# Install PostgreSQL 16 alongside 17
sudo apt install postgresql-16

# They'll run on different ports:
# PostgreSQL 17: port 5432
# PostgreSQL 16: port 5433
```

### Custom Extensions

```bash
# Install popular extensions
sudo apt install postgresql-17-postgis-3
sudo apt install postgresql-17-pgvector

# Enable in database
sudo -u postgres psql -d myapp -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d myapp -c "CREATE EXTENSION vector;"
```

---

## 🐛 Troubleshooting

### PostgreSQL Won't Start

```bash
# Check logs
sudo tail -100 /var/log/postgresql/postgresql-17-main.log
sudo journalctl -u postgresql -n 100

# Common issues:
# 1. Port already in use
sudo lsof -i :5432

# 2. Incorrect permissions
sudo chown -R postgres:postgres /var/lib/postgresql/17/main
sudo chmod 700 /var/lib/postgresql/17/main

# 3. Configuration error
sudo -u postgres /usr/lib/postgresql/17/bin/postgres --config-file=/etc/postgresql/17/main/postgresql.conf -C shared_buffers
```

### Connection Refused

```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check listen address
sudo grep listen_addresses /etc/postgresql/17/main/postgresql.conf

# Check firewall
sudo ufw status
sudo iptables -L -n | grep 5432

# Check pg_hba.conf
sudo tail /etc/postgresql/17/main/pg_hba.conf
```

### Slow Queries

```bash
# Enable query logging temporarily
sudo -u postgres psql -c "ALTER SYSTEM SET log_min_duration_statement = 100;"
sudo -u postgres psql -c "SELECT pg_reload_conf();"

# Check for missing indexes
sudo -u postgres psql -d myapp -c "
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  AND n_distinct > 100
ORDER BY abs(correlation) DESC;
"

# Run VACUUM ANALYZE
sudo pg-vacuum.sh analyze
```

### Disk Space Issues

```bash
# Check disk usage
df -h /var/lib/postgresql

# Find largest tables
sudo -u postgres psql -c "
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
"

# Clean up old WAL files
sudo pg-vacuum.sh full

# Rotate logs
sudo logrotate -f /etc/logrotate.d/postgresql-common
```

### PgBouncer Issues

```bash
# Check PgBouncer status
sudo systemctl status pgbouncer

# View PgBouncer logs
sudo tail -f /var/log/postgresql/pgbouncer.log

# Connect to PgBouncer admin console
psql -p 6432 -U pgbouncer pgbouncer
# Commands: SHOW POOLS, SHOW DATABASES, SHOW STATS

# Common fix: Reload configuration
sudo systemctl reload pgbouncer
```

---

## 📁 File Locations

### Configuration Files
```
/etc/postgresql-setup.state           # Setup configuration (persistent)
/etc/postgresql/17/main/
  ├── postgresql.conf                 # Main PostgreSQL configuration
  ├── pg_hba.conf                     # Authentication rules
  └── pg_ident.conf                   # User mapping
/etc/pgbouncer/
  ├── pgbouncer.ini                   # PgBouncer configuration
  └── userlist.txt                    # PgBouncer user passwords
/etc/ssl/postgresql/
  ├── server.crt                      # SSL certificate
  └── server.key                      # SSL private key
```

### Data & Logs
```
/var/lib/postgresql/17/main/          # PostgreSQL data directory
/var/log/postgresql/                  # PostgreSQL logs
/var/log/postgresql-setup/            # Setup script logs
/var/backups/postgresql/              # Database backups
/opt/postgresql-monitoring/           # Monitoring metrics
```

### Scripts
```
/usr/local/bin/
  ├── pg-create-db-user.sh           # Create database and user
  ├── pg-backup.sh                    # Backup databases
  ├── pg-restore.sh                   # Restore from backup
  ├── pg-status.sh                    # System status
  ├── pg-restart.sh                   # Safe restart
  ├── pg-logs.sh                      # Log analysis
  ├── pg-vacuum.sh                    # Maintenance
  └── pg-monitor.sh                   # Metrics collection
```

---

## 🔄 Upgrading

### PostgreSQL Minor Version Upgrade

Minor versions (17.0 → 17.1) are automatic:

```bash
sudo apt update
sudo apt upgrade postgresql-17
sudo pg-restart.sh
```

### PostgreSQL Major Version Upgrade

For major versions (17 → 18), use pg_upgrade:

```bash
# Install new version
sudo apt install postgresql-18

# Stop both versions
sudo systemctl stop postgresql

# Run pg_upgrade
sudo -u postgres /usr/lib/postgresql/18/bin/pg_upgrade \
  --old-datadir=/var/lib/postgresql/17/main \
  --new-datadir=/var/lib/postgresql/18/main \
  --old-bindir=/usr/lib/postgresql/17/bin \
  --new-bindir=/usr/lib/postgresql/18/bin

# Start new version
sudo systemctl start postgresql@18-main

# Verify
sudo pg-status.sh
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes on a clean Ubuntu VPS
4. Commit with clear messages (`git commit -m 'Add amazing feature'`)
5. Push to your branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Development Guidelines

- Maintain idempotency - scripts should be safe to re-run
- Add inline comments for complex logic
- Update documentation for new features
- Test on Ubuntu 22.04 and 24.04
- Follow existing code style (shellcheck compliant)

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- PostgreSQL Global Development Group
- PgBouncer maintainers
- Ubuntu Server team
- Community contributors

---

## 📞 Support & Resources

- **Documentation:** [PostgreSQL Official Docs](https://www.postgresql.org/docs/17/)
- **Issues:** [GitHub Issues](https://github.com/your-repo/vps-postgres-setup/issues)
- **Discussions:** [GitHub Discussions](https://github.com/your-repo/vps-postgres-setup/discussions)
- **PostgreSQL Wiki:** [PostgreSQL Wiki](https://wiki.postgresql.org/)

---

## ⚠️ Important Notes

1. **Always test in a staging environment first**
2. **Keep regular backups** - automate and verify them
3. **Monitor your database** - set up alerts for disk space, connections, etc.
4. **Keep PostgreSQL updated** - subscribe to security mailing lists
5. **Document your setup** - maintain a runbook for your team
6. **Plan for growth** - monitor metrics and scale proactively
7. **Security first** - review access controls quarterly

---

**Made with ❤️ for the PostgreSQL community**

For questions, issues, or feature requests, please open an issue on GitHub.
