# Review of `setup-postgres17-enterprise.sh`

Findings from reading the original script line by line, and how this project resolves each one.
Severity: **B** = breaks the run, **S** = security, **D** = data-loss / recoverability risk, **O** = operational.

## Breaks the run

| # | Issue | Fix here |
|---|-------|----------|
| 1 **B** | `postgresql-contrib-17` doesn't exist (contrib is part of `postgresql-17` since v10) → `apt-get` fails under `set -e`. | Official image already includes contrib. |
| 2 **B** | `save_state` expands variables that are unset when a feature is disabled (`SSL_CERT_FILE`, `S3_BUCKET`, `REPLICATION_SLOTS`, `PGBOUNCER_*`…) → `set -u` aborts. | No state file; configuration is env-only. |
| 3 **B** | `apply_configuration` only *reloads*. `listen_addresses`, `port`, `max_connections`, `shared_buffers`, `archive_mode`, `max_wal_senders`, `max_replication_slots` need a **restart**; then `pg_isready -p $DB_PORT` fails on a port change and the script exits. | Config is rendered before the server starts. |
| 4 **B** | SSL dir is `chmod 700` owned by root, only the files are chowned → `postgres` can't traverse it, server won't start with `ssl=on`. | Certs live in a postgres-owned dir. |
| 5 **B** | `sed 's/^#*ssl.*/ssl = on/'` and `'s/^#*autovacuum.*/autovacuum = on/'` rewrite **every** line starting with `ssl…` / `autovacuum…` (cert paths, ciphers, all autovacuum tunables) into duplicates. Similar greedy patterns for `port`, `log_*`. | Static `postgresql.conf` + one generated include; no `sed` on configs. |
| 6 **B** | `log_destination=csvlog` + `log_filename=*.log`; `log_directory='log'` is relative to PGDATA, so `pg-logs.sh` and Fail2Ban read an empty `/var/log/postgresql`. | Logs go to stderr → `docker logs` / Dokploy / Coolify log viewer. |
| 7 **B** | `ls ….{sql,custom}` in `pg-restore.sh` fails under `pipefail` when one extension has no match. | Restore via pgBackRest. |

## Security

| # | Issue | Fix here |
|---|-------|----------|
| 8 **S** | `eval "${varname}='${answer}'"` and `source $STATE_FILE`: command injection from any prompt answer / tampered state file. | No `eval`, no sourced state. |
| 9 **S** | Superuser `postgres` and the replication role may log in remotely from every allowed IP, `listen_addresses` defaults to `0.0.0.0`. | `hba` rejects remote `postgres`/`replicator` for normal DBs, requires `hostssl` + SCRAM, 5432 is never published. |
| 10 **S** | `ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'` enables 3DES; no minimum TLS version; clients not forced onto TLS. | TLS ≥ 1.2, no 3DES/MD5, `hostnossl` rejected. |
| 11 **S** | User passwords interpolated into SQL strings and visible in `ps`; `'` in a password breaks or injects. | `psql -v` + `format('%L')`, identifiers validated and `%I`-quoted. |
| 12 **S** | Fail2Ban on Postgres sees the PgBouncer/loopback address for every client, so five bad logins **bans 127.0.0.1** (and the jail file also redefines `[sshd]`). | Dropped. Use provider firewall + `hostssl` CIDR allow-list. |
| 13 **S** | `ufw --force reset` wipes existing rules and a wrong `SSH_PORT` locks you out; Docker would bypass UFW anyway. | Firewalling is the host/provider's job; ports bind to loopback by default. |

## Data safety / recoverability

| # | Issue | Fix here |
|---|-------|----------|
| 14 **D** | "HA" isn't implemented: no replication role, no slots, no standby, no failover — only `wal_level` flags. | Real streaming replica with a physical slot (`replica` profile) + documented promotion. |
| 15 **D** | Backups are `pg_dump` only: no PITR, RPO = backup interval. pgBackRest is installed and never used. | pgBackRest: continuous WAL archiving, weekly full / daily diff, retention, zstd, AES-256 encryption. |
| 16 **D** | `archive_command` copies WAL to a directory **on the same disk**, never prunes it (disk fills), and `aws s3 cp` runs as `postgres` without credentials. | Archive to pgBackRest repos (local volume + optional S3), async queue with a cap. |
| 17 **D** | `BACKUP_*`/`S3_BUCKET` are shell variables, not present in cron's environment → retention falls back to defaults and **S3 upload never runs**. `aws s3 sync --delete` also propagates local deletions. | Scheduler inherits container env; pgBackRest manages retention per repo. |
| 18 **D** | Hand-rolled PgBouncer SCRAM "hash" (`sha256(password+user)`) is not a valid SCRAM verifier → nobody can log in through the pooler. | `auth_user` + `auth_query` against a `SECURITY DEFINER` function. |
| 19 **D** | No backup verification, no alerting; `pg_dump` of `postgres` DB skipped. | `pgbackrest check` at start, exit codes surfaced in logs, CI restore test recommended (see README). |
| 20 **D** | Replication slots with no `max_slot_wal_keep_size`: a dead standby fills the primary's disk. | Capped (`PG_MAX_SLOT_WAL_KEEP_SIZE`). |

## Operational

| # | Issue | Fix here |
|---|-------|----------|
| 21 **O** | PgBouncer: `server_reset_query = DISCARD ALL` in transaction mode (wasteful), `max_db_connections` = full `max_connections` (starves admin/replication), no `ignore_startup_parameters` (JDBC/Prisma fail), no prepared-statement support, no admin user, userlist owned by wrong user. | Correct defaults, `max_prepared_statements`, admin user, headroom. |
| 22 **O** | Extensions installed (`pgaudit`, `pg_stat_kcache`, `pg_cron`, `partman`) but never in `shared_preload_libraries`/`CREATE EXTENSION` → dead weight. | `pg_stat_statements` + `pgaudit` loaded and configured; add others on purpose. |
| 23 **O** | `autovacuum_naptime=10s`, `log_autovacuum_min_duration=0`, `log_temp_files=0`, `track_functions=all`: noisy/costly. Weekly `VACUUM ANALYZE` of everything is redundant; `VACUUM FULL` helper takes exclusive locks. | Sane thresholds, autovacuum does its job. |
| 24 **O** | Monitoring = 8 `sudo psql` forks every 5 min writing 288 YAML files/day nobody reads. | `postgres_exporter` (profile `monitoring`) for Prometheus/Grafana. |
| 25 **O** | `work_mem` auto-calc divides by `max_connections` only; memory settings ignore containers/cgroups. | Explicit env values with documented rules of thumb. |
| 26 **O** | Fully interactive (`read -p`), can't run unattended or from CI/GitOps. | 100 % declarative. |
| 27 **O** | `pg-status.sh` joins `pg_locks.relation::regclass` across databases (errors), `max(state)` is meaningless. | Rewritten `pg-status`. |

## What is intentionally *not* solved

* **Automatic failover.** Real HA needs a consensus layer (Patroni + etcd/Consul) and ≥ 3 nodes. A single VPS cannot be highly available; the replica here protects against disk/corruption problems and gives you a fast manual promotion, not host-failure tolerance.
* **Off-site backups require your S3-compatible bucket.** The local repo shares a failure domain with the database.
