#!/bin/sh
# Run in the pinned PostgreSQL 18 client image. Credentials come only from PG* env.
set -eu
umask 077
: "${PGHOST:?PGHOST required}"
: "${PGDATABASE:?PGDATABASE required}"
: "${PGUSER:?PGUSER required}"
: "${BACKUP_DIR:?Mount a separate backup volume and set BACKUP_DIR}"
[ -d "$BACKUP_DIR" ] || { echo 'Backup volume is not mounted' >&2; exit 1; }
# CronJob must use concurrencyPolicy: Forbid. A failed dump never becomes a completed file.
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_tmp=$(mktemp "$BACKUP_DIR/.chotacrm-partial.XXXXXX")
trap 'rm -f "$backup_tmp"' EXIT HUP INT TERM
pg_dump --format=custom --no-owner --no-privileges --file="$backup_tmp"
pg_restore --list "$backup_tmp" >/dev/null
mv "$backup_tmp" "$BACKUP_DIR/chotacrm-$stamp.dump"
# Retention touches only completed files created by this script, never arbitrary mounts.
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'chotacrm-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z.dump' -mtime +13 -exec rm -f {} \;
echo 'CRM backup completed'
