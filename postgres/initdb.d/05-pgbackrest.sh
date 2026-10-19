#!/usr/bin/env bash
# First-init only (runs against docker-entrypoint's temporary server).
# Creating the stanza here means archive_command works from the very first WAL segment.
set -Eeuo pipefail
[[ "${BACKUP_ENABLED:-yes}" == yes ]] || exit 0
pgbackrest --stanza=main stanza-create
