# Contributing to VPS Postgres Setup

Thank you for contributing to this project!

## 📌 Architecture & Design Principles

1. **Declarative & Reproducible:**
   - Configuration is strictly environment-variable driven (no hidden state files).
   - Any tunable should be configurable via `.env` with sane production defaults.
2. **Containerized & Stateless Host:**
   - The primary stack runs via Docker Compose and prebuilt Docker Hub images.
   - Host systems should not require package installations other than Docker and Docker Compose.
3. **Safety & Zero Data Loss:**
   - WAL archiving must remain functional at all times.
   - Passwords must never be exposed in unescaped SQL strings or process tables.
   - Containers run with least privileges (`read_only` filesystems and `cap_drop: ALL` where possible).

---

## 🛠 Development & Testing Workflow

### 1. Requirements

- Docker & Docker Compose
- `bash`

### 2. Linting & Validation

Before submitting a PR, make sure the Compose syntax is valid:

```bash
POSTGRES_PASSWORD=x REPLICATION_PASSWORD=x PGBOUNCER_AUTH_PASSWORD=x \
PGBOUNCER_ADMIN_PASSWORD=x MONITOR_PASSWORD=x BACKUP_CIPHER_PASS=x \
docker compose --profile replica --profile monitoring config -q
```

Validate all bash scripts syntax:

```bash
bash -n postgres/entrypoint.sh postgres/bin/* postgres/initdb.d/*.sh pgbouncer/entrypoint.sh scripts/*.sh
```

### 3. Running the Smoke Test Suite

The repository includes an end-to-end integration test in `scripts/smoke-test.sh`:

```bash
# Generates a temporary test environment and verifies:
# 1. Primary container boot
# 2. PgBouncer auth_query SCRAM authentication
# 3. WAL archiving and initial pgBackRest backup
# 4. Streaming replica synchronization
./scripts/smoke-test.sh
```

---

## 📦 Docker Images & Releases

Multi-architecture images (`linux/amd64`, `linux/arm64`) are built and published automatically by GitHub Actions in `.github/workflows/publish.yml` upon push to `main` or release tag:

- `andreastuko/vps-postgres:17`
- `andreastuko/vps-pgbouncer:1`

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.
