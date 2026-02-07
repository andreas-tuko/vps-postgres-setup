
# PostgreSQL 17 Enterprise-Ready VPS Setup

An **interactive, idempotent setup** for PostgreSQL 17 on Ubuntu 24.04+ VPS, designed for production use by startups, enterprises, and small teams. Includes built-in security, connection pooling, maintenance scripts, and backup/restore tooling.

---

## Features

- Installs **PostgreSQL 17** from official PGDG repository.
- Idempotent and interactive — configuration choices are saved for reuse.
- Automatic tuning based on server RAM (shared_buffers, work_mem, effective_cache_size).
- **Connection pooling** using PgBouncer for stable, high-performance DB access.
- Security features:
  - UFW firewall with allowed IPs for Postgres access.
  - Fail2Ban for SSH brute-force protection.
  - Optional SSL/TLS for Postgres connections.
- Maintenance scripts included:
  - `/usr/local/bin/pg_backup.sh` – logical backups per database.
  - `/usr/local/bin/pg_restore_latest.sh` – restore from backup.
  - `/usr/local/bin/pg_restart.sh` – restart PostgreSQL.
  - `/usr/local/bin/pg_status.sh` – view service and active connections.
  - `/usr/local/bin/pg_create_db_user.sh` – create new database/user with PgBouncer integration.
- Optional WAL archiving to S3-compatible storage.
- Designed to support **multiple applications** from a single Postgres instance.
- Stores configuration in `/etc/pg-setup.conf` for seamless re-runs.

---

## Requirements

- Ubuntu 24.04 or newer
- Minimum recommended VPS:
  - 3 vCPU
  - 4 GB RAM
  - 65 GB SSD (RAID-10 recommended)
- Root access to the server (`sudo`)

---

## Getting Started

1. Upload the script to your VPS:

```bash
scp setup-postgres17.sh root@your-vps-ip:/root/
````

2. Make the script executable:

```bash
chmod +x setup-postgres17.sh
```

3. Run the setup script:

```bash
sudo ./setup-postgres17.sh
```

4. Follow interactive prompts:

   * Listen addresses (e.g., `0.0.0.0` for public access, `127.0.0.1` for local only)
   * Port (default `5432`)
   * Allowed IPs for DB connections
   * Enable SSL/TLS
   * WAL archiving (optional)
   * PgBouncer enablement
   * Backup retention

5. The script will automatically:

   * Install PostgreSQL 17 and dependencies.
   * Tune PostgreSQL for your VPS.
   * Configure firewall, fail2ban, and SSL.
   * Create maintenance scripts in `/usr/local/bin`.
   * Start and verify PostgreSQL and PgBouncer.

---

## Usage

### Connecting your app via PgBouncer

```text
DATABASE_URL=postgresql://user:password@127.0.0.1:6432/dbname
```

### Maintenance

* **Backup all databases:**

```bash
sudo /usr/local/bin/pg_backup.sh
```

* **Restore a backup:**

```bash
sudo /usr/local/bin/pg_restore_latest.sh /var/backups/postgresql/dbname_YYYYMMDD_HHMMSS.dump
```

* **Restart PostgreSQL:**

```bash
sudo /usr/local/bin/pg_restart.sh
```

* **View PostgreSQL status:**

```bash
sudo /usr/local/bin/pg_status.sh
```

* **Create a new database and user:**

```bash
sudo /usr/local/bin/pg_create_db_user.sh newdb newuser
```

---

## Security Recommendations

* Keep only necessary IPs in `/etc/postgresql/17/main/pg_hba.conf` and UFW.
* Store backups off-server (e.g., S3, R2, or other cloud storage).
* Test the restore process in a staging environment.
* Monitor logs, connection counts, and performance metrics regularly.
* For high availability, consider adding a standby server with streaming replication or Patroni/pg_auto_failover.

---

## Advanced Options

* **WAL Archiving:** Store Write-Ahead Logs on S3 for point-in-time recovery.
* **Custom tuning:** Edit `/etc/postgresql/17/main/postgresql.conf` for memory, WAL, or connection settings.
* **Multiple apps:** Create separate databases and users per app, optionally integrate with PgBouncer.

---

## Contributing

Contributions are welcome! Please submit pull requests or issues if you encounter bugs or have improvement suggestions.
