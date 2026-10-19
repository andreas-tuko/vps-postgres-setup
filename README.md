# Enterprise-Ready PostgreSQL 17 on Docker (VPS, Dokploy & Coolify)

[![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL-17-blue.svg)](https://www.postgresql.org/)
[![Docker Hub - Postgres](https://img.shields.io/badge/Docker%20Hub-andreastuko%2Fvps--postgres-blue?logo=docker)](https://hub.docker.com/r/andreastuko/vps-postgres)
[![Docker Hub - PgBouncer](https://img.shields.io/badge/Docker%20Hub-andreastuko%2Fvps--pgbouncer-blue?logo=docker)](https://hub.docker.com/r/andreastuko/vps-pgbouncer)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE.md)

A battle-tested, zero-maintenance PostgreSQL 17 infrastructure built for self-hosted VPS environments. Pre-baked, multi-architecture container images (`linux/amd64`, `linux/arm64`) are pushed to Docker Hub so your server **pulls instantly** without spending minutes compiling or risking out-of-memory errors on deployment.

Works out of the box with **Dokploy** (Compose service), **Coolify** (Docker Compose pack), or **Vanilla Docker Compose**.

---

## ⚡ Architecture & Highlights

* **PostgreSQL 17 (Bookworm):** Preloaded with `pgaudit` and `pg_stat_statements`. Tuned for NVMe/SSD storage and high concurrency.
* **PgBouncer Connection Pooling:** Transaction-mode pooling by default with dynamic SCRAM authentication via `auth_query` (no static userlists to maintain).
* **pgBackRest & Point-In-Time-Recovery (PITR):** Continuous WAL archiving from the first minute. Automated weekly full and daily differential backups scheduled via `supercronic`. Supports AES-256 backup encryption and offsite S3-compatible replication.
* **Instant Pull Deployments:** Uses prebuilt images [`andreastuko/vps-postgres:17`](https://hub.docker.com/r/andreastuko/vps-postgres) and [`andreastuko/vps-pgbouncer:1`](https://hub.docker.com/r/andreastuko/vps-pgbouncer). Zero deploy-time compile or build lag.
* **Optional Profiles:**
  * `replica`: High-availability streaming warm standby with automated physical slot replication.
  * `monitoring`: Prometheus `postgres-exporter` (port 9187) for Grafana dashboards.
* **Hardened Security:** Non-root execution where possible, `no-new-privileges`, read-only root filesystems on PgBouncer, reject unencrypted plaintext traffic, and local loopback binding (`127.0.0.1:6432`) by default.

---

## 🚀 Quick Start (Vanilla Docker Compose)

### 1. Clone & Prepare Environment

```bash
git clone https://github.com/andreas-tuko/vps-postgres-setup.git
cd vps-postgres-setup

# Copy example environment configuration
cp .env.example .env
```

### 2. Generate Required Passwords

Generate high-entropy secrets for the `.env` file:

```bash
# In bash:
sed -i "s|POSTGRES_PASSWORD=|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|REPLICATION_PASSWORD=|REPLICATION_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|PGBOUNCER_AUTH_PASSWORD=|PGBOUNCER_AUTH_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|PGBOUNCER_ADMIN_PASSWORD=|PGBOUNCER_ADMIN_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|MONITOR_PASSWORD=|MONITOR_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|BACKUP_CIPHER_PASS=|BACKUP_CIPHER_PASS=$(openssl rand -hex 24)|" .env
```

> [!IMPORTANT]
> Keep a secure offline backup of `BACKUP_CIPHER_PASS`. Without this encryption passphrase, pgBackRest backups cannot be restored.

### 3. Pull Images & Launch

```bash
# Pull prebuilt multi-arch images from Docker Hub (instant)
docker compose pull

# Launch primary database and PgBouncer pooler
docker compose up -d
```

Check health:

```bash
docker compose ps
docker compose exec postgres-primary pg-status
```

---

## 📦 Deploying on Dokploy or Coolify

### Dokploy

1. Create a new service and choose **Compose**.
2. Point to this repository or paste the contents of `docker-compose.yml`.
3. Fill in your environment variables in the **Environment** tab (see `.env.example`).
4. To allow applications in other Dokploy projects to connect over the internal Docker network, attach `pgbouncer` to the `dokploy-network` network.
5. Click **Deploy**. Dokploy will pull the prebuilt Docker Hub images and start the stack.

### Coolify

1. Create a new Resource and select **Docker Compose**.
2. Select your repository.
3. Paste your environment keys into Coolify's **Environment Variables**.
4. Enable **Connect to Predefined Network** to allow other apps on your VPS to query `pgbouncer:6432`.
5. Deploy.

---

## 🛠️ Management & Day-2 Operations

All administrative commands are executed inside the primary container using helper scripts pre-installed in `/usr/local/bin`:

### 1. Create & Manage Application Databases

#### Via CLI Helper
Create a dedicated database, isolated role, and restricted permissions with one command:

```bash
docker compose exec postgres-primary create-app-db <database_name> <user_role>
```
*(Prompts securely for password if `APP_PASSWORD` environment variable is not passed).*

#### Via GUI Tools & Dokploy / dbx / pgAdmin
The default application user (`APP_DB_USER`, e.g. `default_user`) is configured with `CREATEDB` privileges and access to connect to `postgres`. This allows you to manage multiple tenant databases through visual interfaces (Dokploy Database UI, dbx, pgAdmin, TablePlus, DBeaver) without needing the root `postgres` superuser:

* **Connection String:** `postgresql://<APP_DB_USER>:<APP_DB_PASSWORD>@<HOST>:6432/postgres` (or your specific database)
* **Security Guardrails:** The app user is strictly configured with:
  `CREATEDB NOSUPERUSER NOCREATEROLE NOREPLICATION NOBYPASSRLS`
* This enables full database lifecycle management (creating DBs, creating tables, managing schemas) while preventing privilege escalation or reading root cluster secrets.

### 2. Inspect Database Status

Get a comprehensive real-time dashboard of connections, database sizes, replication status, WAL archiver status, and cache hit ratios:

```bash
docker compose exec postgres-primary pg-status
```

### 3. On-Demand Backups

```bash
# Differential backup (default)
docker compose exec postgres-primary pg-backup diff

# Full backup
docker compose exec postgres-primary pg-backup full

# Inspect backup stanzas
docker compose exec postgres-primary pgbackrest --stanza=main info
```

### 4. Point-In-Time-Recovery (PITR) & Restoring

To restore into your stopped cluster:

```bash
# 1. Stop the database container
docker compose stop postgres-primary

# 2. Restore to latest backup
docker compose run --rm --no-deps postgres-primary pg-restore

# OR: Point-in-time recovery to a specific timestamp (UTC)
docker compose run --rm --no-deps postgres-primary pg-restore \
    --type=time "--target=2026-10-19 12:00:00+00" --target-action=promote

# 3. Restart container
docker compose start postgres-primary
```

---

## 🔄 Streaming Replication (Warm Standby)

To spin up a streaming read replica:

1. In your `.env` file, activate the `replica` profile:

   ```env
   COMPOSE_PROFILES=replica
   REPLICA_SLOT=replica1
   ```

2. Run:

   ```bash
   docker compose up -d
   ```

3. The replica container will automatically detect an empty data volume, stream a basebackup from `postgres-primary`, attach to physical slot `replica1`, and follow continuous WAL streaming.

---

## 📊 Prometheus Monitoring

To enable the PostgreSQL Prometheus exporter:

1. In `.env`, add `monitoring` to `COMPOSE_PROFILES`:

   ```env
   COMPOSE_PROFILES=monitoring
   ```

2. Start the exporter:

   ```bash
   docker compose up -d
   ```

3. Metrics are exposed at `http://<your-vps-ip>:9187/metrics`.

---

## ⚙️ Key Configuration Reference

| Variable | Default | Description |
| --- | --- | --- |
| `POSTGRES_IMAGE` | `andreastuko/vps-postgres:17` | Postgres image pulled from Docker Hub. |
| `PGBOUNCER_IMAGE` | `andreastuko/vps-pgbouncer:1` | PgBouncer image pulled from Docker Hub. |
| `PGBOUNCER_BIND` | `127.0.0.1` | Loopback bind. Set to `0.0.0.0` only if exposing publicly. |
| `PGBOUNCER_PORT` | `6432` | External port for PgBouncer pooler. |
| `PG_SHARED_BUFFERS` | `1GB` | ~25% of server RAM for dedicated host. |
| `PG_EFFECTIVE_CACHE_SIZE` | `3GB` | ~75% of server RAM for dedicated host. |
| `PG_MAX_CONNECTIONS` | `200` | Max Postgres backend sessions. |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Default client connection pool size per user/db pair. |
| `BACKUP_ENABLED` | `yes` | Enables pgBackRest continuous archiving and scheduler. |
| `BACKUP_S3_BUCKET` | *(optional)* | S3-compatible bucket name for offsite replication. |
| `COMPOSE_PROFILES` | *(empty)* | Enable optional services: `replica`, `monitoring`. |

---

## 🔍 Troubleshooting & Common Gotchas

### 1. `ERROR: permission denied for function pg_stat_statements_reset`
* **Cause:** When creating a new database in Dokploy or a database GUI as a non-superuser, PostgreSQL copies `template1`. If `pg_stat_statements` was installed in `template1`, superuser-owned functions reside in `public`. Running `GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "public"` fails because non-superusers cannot grant permissions on functions they do not own.
* **Solution:** `pg_stat_statements` is preloaded cluster-wide via `shared_preload_libraries` in `postgresql.conf` and only created in the maintenance `postgres` DB. It is deliberately omitted from `template1`.
* **Fix for existing clusters:** If your volume was initialized prior to this change, run:
  ```bash
  docker compose exec postgres-primary psql -U postgres -c "
    \c template1
    DROP EXTENSION IF EXISTS pg_stat_statements;
  "
  ```

### 2. S3 / Cloudflare R2 Remote Backups (`ERROR: [028]` or Endpoint Issues)
* **Cloudflare R2 Endpoints:** Do NOT include `https://` in `BACKUP_S3_ENDPOINT`. pgBackRest automatically negotiates TLS. Example: `<account_id>.r2.cloudflarestorage.com`.
* **Path-Style Addressing:** Cloudflare R2 and MinIO require `BACKUP_S3_URI_STYLE=path`.
* **Error `[028]`: `archive-push command ... manifest ... does not match current cluster`:** Occurs if you point a brand new database volume to an existing S3 bucket prefix that contains files from an old or recreated cluster. Solution: Set a clean path in `.env` (e.g. `BACKUP_S3_PATH=/pgbackrest-v2`) or empty the bucket prefix before first initialization.

### 3. Docker Healthchecks and Peer Authentication
* Healthchecks are performed locally inside the container via `pg_isready -h /var/run/postgresql -p 5432 -U postgres`.
* The local UNIX domain socket in `pg_hba.conf` uses `trust` authentication to allow Docker healthchecks (executed as `root`) to verify server readiness without throwing `Peer authentication failed`. TCP connections continue to be protected by SCRAM-SHA-256 and SSL rules.

---

## 🏛️ Repository Structure

```text
├── docker-compose.yml          # Core service definitions (Primary, PgBouncer, Replica, Exporter)
├── .env.example                # Documented configuration template
├── postgres/
│   ├── Dockerfile              # Multi-arch PG17 + pgBackRest + supercronic + pgaudit
│   ├── postgresql.conf         # Static production baseline configuration
│   ├── entrypoint.sh           # Dynamic configuration rendering and TLS bootstrap
│   ├── bin/                    # Admin CLI tools (create-app-db, pg-backup, pg-restore, pg-status)
│   └── initdb.d/               # First-boot bootstrap SQL and stanza initialization
├── pgbouncer/
│   ├── Dockerfile              # Alpine-based hardened PgBouncer
│   └── entrypoint.sh           # Generates pgbouncer.ini and SCRAM auth_query configuration
├── scripts/
│   └── smoke-test.sh           # End-to-end integration and smoke test suite
├── legacy/
│   ├── setup-postgres17.sh     # Legacy bare-metal Ubuntu installer (retained for reference)
│   └── pg.conf.example         # Legacy config template
└── .github/workflows/
    ├── ci.yml                  # Shellcheck and docker compose smoke tests
    └── publish.yml             # Automated multi-arch build & push to Docker Hub
```

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
