# Deployment Guide

This repository contains a self-contained setup script for PostgreSQL 17 on Ubuntu VPS environments. You can deploy it interactively (manual) or in an unattended fashion (automated).

## Option 1: Manual Deployment (Interactive)

Best for one-off servers where you want to configure settings during installation.

### 1. Connect to your VPS
SSH into your server as `root` (or a user with sudo privileges).

```bash
ssh root@your-vps-ip

```

### 2. Download the Script

Pull the raw script directly from GitHub.

```bash
wget [https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh](https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh)

```

### 3. Permissions & Execution

Make the script executable and run it.

```bash
chmod +x setup-postgres17.sh
sudo ./setup-postgres17.sh

```

### 4. Follow the Prompts

The script will ask you for:

* Listen addresses
* Allowed IPs
* SSL configuration
* Backup retention policies

---

## Option 2: Unattended Deployment (CI/CD, Terraform, Cloud-Init)

You can automate the installation by pre-seeding the configuration file. The script looks for `/etc/pg-setup.conf`. If this file exists, the script will **skip the interactive prompts** and use the values defined there.

### 1. Create the Config File

Create the file `/etc/pg-setup.conf` with your desired settings before running the script.

**Example `cloud-init` or `User Data` script:**

```bash
#!/bin/bash

# 1. Pre-seed configuration
cat > /etc/pg-setup.conf <<EOF
PG_VERSION="17"
DB_LISTEN_ADDRESSES="*"
DB_PORT="5432"
ALLOWED_IPS="10.0.0.5/32,192.168.1.0/24"
PG_SSL="no"
ENABLE_WAL_ARCHIVE="no"
BACKUP_RETENTION_DAYS="7"
PGBOUNCER_ENABLED="yes"
EOF

# 2. Download the setup script
wget [https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh](https://raw.githubusercontent.com/andreas-tuko/vps-postgres-setup/main/setup-postgres17.sh) -O /root/setup-postgres17.sh

# 3. Run non-interactively
chmod +x /root/setup-postgres17.sh
/root/setup-postgres17.sh

```

### Configuration Variables Reference

| Variable | Default | Description |
| --- | --- | --- |
| `DB_LISTEN_ADDRESSES` | `localhost` | IP addresses Postgres listens on (use `*` or `0.0.0.0` for all). |
| `DB_PORT` | `5432` | The port Postgres listens on. |
| `ALLOWED_IPS` | `127.0.0.1/32` | Comma-separated CIDRs allowed in `pg_hba.conf` and UFW. |
| `PG_SSL` | `no` | Set to `yes` to generate self-signed certs or use existing ones. |
| `PGBOUNCER_ENABLED` | `yes` | Set to `no` to skip PgBouncer installation. |
| `BACKUP_RETENTION_DAYS` | `14` | Number of days to keep local backups. |
| `ENABLE_WAL_ARCHIVE` | `no` | Set to `yes` to enable S3 WAL archiving (requires AWS CLI config). |

---

## Post-Deployment Verification

After deployment, verify the services are running:

```bash
# Check PostgreSQL status
systemctl status postgresql

# Check PgBouncer status
systemctl status pgbouncer

# Test local connection
sudo -u postgres psql -c "SELECT version();"

```
