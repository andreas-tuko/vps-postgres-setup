# PostgreSQL 17 Deployment Guide

Comprehensive deployment guide for running production-grade PostgreSQL 17 + PgBouncer + pgBackRest on modern VPS environments.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Deployment Option 1: Dokploy](#deployment-option-1-dokploy)
3. [Deployment Option 2: Coolify](#deployment-option-2-coolify)
4. [Deployment Option 3: Vanilla Docker Compose on a VPS](#deployment-option-3-vanilla-docker-compose-on-a-vps)
5. [Docker Hub Prebuilt Images vs Local Building](#docker-hub-prebuilt-images-vs-local-building)
6. [Configuring Remote S3 Backups](#configuring-remote-s3-backups)
7. [High Availability & Streaming Replica Setup](#high-availability--streaming-replica-setup)
8. [Post-Deployment Verification](#post-deployment-verification)

---

## Architecture Overview

This deployment runs as a modular Docker Compose stack:

* **`postgres-primary`**: PostgreSQL 17 with `pgaudit`, `pg_stat_statements`, `pgbackrest` WAL archiver, and `supercronic` automated backup daemon.
* **`pgbouncer`**: Lightweight connection pooler running with a read-only root filesystem and dynamic SCRAM authentication via `auth_query`.
* **`postgres-replica`** *(Optional)*: Warm standby streaming replica attached via physical replication slot.
* **`postgres-exporter`** *(Optional)*: Prometheus exporter on port 9187.

The stack uses pre-built multi-architecture Docker Hub images:

* `andreastuko/vps-postgres:17`
* `andreastuko/vps-pgbouncer:1`

---

## Deployment Option 1: Dokploy

Dokploy makes managing Docker Compose services on single or multiple VPS servers effortless.

### Steps

1. Open your Dokploy Dashboard and navigate to your Project/Environment.
2. Click **Create Service** and select **Compose**.
3. Under **Source**, choose **GitHub** and connect your repository:
   * **Repository**: `andreas-tuko/vps-postgres-setup`
   * **Branch**: `main`
   * **Compose Path**: `docker-compose.yml`
4. Go to the **Environment** tab in Dokploy:
   * Paste the keys from `.env.example`.
   * Fill in strong generated secrets for:
     * `POSTGRES_PASSWORD`
     * `REPLICATION_PASSWORD`
     * `PGBOUNCER_AUTH_PASSWORD`
     * `PGBOUNCER_ADMIN_PASSWORD`
     * `MONITOR_PASSWORD`
     * `BACKUP_CIPHER_PASS`
5. (Optional) Connect to Dokploy Network:
   * To allow backend apps running in other Dokploy projects to communicate with PgBouncer securely without exposing ports to the public internet, uncomment the external network block in `docker-compose.yml`:

     ```yaml
     services:
       pgbouncer:
         networks: [default, shared]
     networks:
       shared: { external: true, name: dokploy-network }
     ```

6. Click **Deploy**. Dokploy will pull the pre-built Docker Hub images and bring up the services.

---

## Deployment Option 2: Coolify

1. Open Coolify and navigate to **Projects** -> **Add Resource**.
2. Select **Docker Compose**.
3. Choose your Git repository and branch (`main`).
4. In the **Environment Variables** tab, define your required passwords.
5. In Coolify's network settings, enable **Connect to Predefined Network** so other containers can access `pgbouncer:6432`.
6. Click **Deploy**.

---

## Deployment Option 3: Vanilla Docker Compose on a VPS

For standalone Ubuntu or Debian VPS instances:

### 1. Install Docker & Compose (if not already installed)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### 2. Clone the Repository

```bash
git clone https://github.com/andreas-tuko/vps-postgres-setup.git /opt/vps-postgres
cd /opt/vps-postgres
```

### 3. Setup Secrets

```bash
cp .env.example .env

# Generate required secrets:
for var in POSTGRES_PASSWORD REPLICATION_PASSWORD PGBOUNCER_AUTH_PASSWORD PGBOUNCER_ADMIN_PASSWORD MONITOR_PASSWORD BACKUP_CIPHER_PASS; do
  sed -i "s|^${var}=.*|${var}=$(openssl rand -hex 24)|" .env
done
```

### 4. Pull and Start Services

```bash
# Pull the latest prebuilt images from Docker Hub (instant)
docker compose pull

# Launch in background
docker compose up -d
```

---

## Docker Hub Prebuilt Images vs Local Building

By default, `docker-compose.yml` points to prebuilt multi-arch images on Docker Hub:

```yaml
image: ${POSTGRES_IMAGE:-andreastuko/vps-postgres:17}
image: ${PGBOUNCER_IMAGE:-andreastuko/vps-pgbouncer:1}
```

* **Production (Recommended):**
  Running `docker compose pull && docker compose up -d` pulls the images directly from Docker Hub. Deployments finish in seconds with virtually zero CPU or memory footprint on the VPS.
* **Local Source Build:**
  If you customize Dockerfiles or entrypoint scripts, you can build locally on the host by passing `--build`:

  ```bash
  docker compose up -d --build
  ```

---

## Configuring Remote S3 Backups

pgBackRest supports dual-repository backup (Repo 1 = local volume, Repo 2 = S3 bucket). This provides instant local restores with the safety of offsite replication.

To activate S3 backups, fill in the following keys in `.env`:

```env
BACKUP_S3_BUCKET=my-pgbackrest-bucket
BACKUP_S3_ENDPOINT=s3.eu-central-1.amazonaws.com
BACKUP_S3_REGION=eu-central-1
BACKUP_S3_KEY=AKIA...
BACKUP_S3_KEY_SECRET=...
BACKUP_S3_URI_STYLE=host
BACKUP_S3_PATH=/pgbackrest
```

The backup agent will automatically verify the remote bucket, replicate WAL segments, and sync scheduled backups to the cloud.

---

## High Availability & Streaming Replica Setup

### Same Host Replica

To run a streaming replica on the same VPS:

1. In `.env`:

   ```env
   COMPOSE_PROFILES=replica
   REPLICA_SLOT=replica1
   ```

2. Start the replica:

   ```bash
   docker compose up -d
   ```

### Cross-VPS Replica (Recommended for Disaster Recovery)

1. On **VPS 1 (Primary)**:
   * Allow the Replica VPS IP in `PG_ALLOWED_CIDRS` in `.env`.
   * Ensure port 5432 is reachable from the Replica VPS IP.
2. On **VPS 2 (Replica)**:
   * In `.env`, set:

     ```env
     COMPOSE_PROFILES=replica
     PRIMARY_HOST=203.0.113.10   # IP or hostname of VPS 1
     REPLICATION_PASSWORD=<same_password_as_vps_1>
     REPLICA_SLOT=replica1
     ```

   * Start only the replica:

     ```bash
     docker compose up -d postgres-replica
     ```

---

## Post-Deployment Verification

Run the built-in health inspection:

```bash
docker compose exec postgres-primary pg-status
```

Verify WAL archiving:

```bash
docker compose exec postgres-primary psql -U postgres -c "SELECT pg_switch_wal();"
docker compose exec postgres-primary psql -U postgres -c "SELECT * FROM pg_stat_archiver;"
```

Run an on-demand full backup test:

```bash
docker compose exec postgres-primary pg-backup full
```
