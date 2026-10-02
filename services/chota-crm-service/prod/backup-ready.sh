#!/bin/sh
# GitOps startup guard. Keep the reviewed archive helper unchanged.
set -eu

echo 'CRM backup waiting for database readiness'
attempt=1
while [ "$attempt" -le 30 ]; do
  # Bound DNS/connect stalls too; BusyBox timeout is in the pinned PG18 image.
  # pg_isready is a reachability gate, not proof of authentication or a backup.
  if timeout -k 1 3 pg_isready -q -t 2 >/dev/null 2>&1; then
    echo 'CRM backup database ready'
    exec sh "$(dirname "$0")/backup.sh"
  fi
  if [ "$attempt" -eq 30 ]; then
    echo 'CRM backup database readiness timed out' >&2
    exit 1
  fi
  sleep 2
  attempt=$((attempt + 1))
done
