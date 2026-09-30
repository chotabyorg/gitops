#!/bin/sh
# Temporary in-pod PostgreSQL only: Unix socket, no Service, no production secret.
set -eu
umask 077
: "${RESTORE_FILE:?Choose a completed timestamp archive in the read-only backup mount}"
case "$RESTORE_FILE" in /backups/chotacrm-????????T??????Z.dump) ;; *) echo 'Refusing unexpected backup path' >&2; exit 1 ;; esac
[ -f "$RESTORE_FILE" ] && [ ! -L "$RESTORE_FILE" ] || { echo 'Completed archive missing' >&2; exit 1; }
export PGDATA=/var/lib/postgresql/18/restore-check
export PGHOST=/var/run/postgresql PGUSER=crm_restore PGDATABASE=crm_restore_verification
cleanup() {
  pg_ctl -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM
initdb -D "$PGDATA" -U "$PGUSER" --auth-local=trust --auth-host=reject >/dev/null 2>&1
pg_ctl -D "$PGDATA" -o '-c listen_addresses= -c shared_buffers=32MB -c max_connections=10 -c log_min_error_statement=panic' -w -t 60 start >/dev/null 2>&1
# The unchanged reviewed helper creates a new disposable database and validates it.
if ! sh /opt/restore/restore-check.sh >/tmp/restore-result 2>/dev/null; then
  echo 'CRM disposable restore verification failed' >&2
  exit 1
fi
cat /tmp/restore-result
# Drop only our temporary database on this pod's Unix socket, never a TCP source.
dropdb --if-exists "$PGDATABASE"
[ "$(psql -X -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname='crm_restore_verification'")" = 0 ]
echo 'CRM disposable database removed; backup volume remained read-only'
