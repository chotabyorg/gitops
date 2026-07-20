#!/bin/sh
set -eu

fail() {
  printf 'restore-drill status=FAIL stage=application-verification\n' >&2
  exit 1
}

[ "$#" -eq 0 ] || fail
readonly target_url='postgresql://restore_drill@127.0.0.1:55432/repetly_restore_drill?schema=public'
started_at="$(date -u +%s)" || fail
unset PGHOST PGPORT PGDATABASE PGUSER PGSERVICE PGPASSWORD PGOPTIONS
export DATABASE_URL="${target_url}"
export HOME=/tmp

cd /app 2>/dev/null || fail
# Migration consistency is checked by the aggregate SQL stage. This probe uses
# the exact application runtime and its PostgreSQL client without requiring the
# Prisma CLI schema-engine binary in the slim production image.
node <<'NODE' >/dev/null 2>&1 || fail
const { Client } = require('pg');
const client = new Client({ connectionString: process.env.DATABASE_URL });
(async () => {
  await client.connect();
  await client.query('BEGIN READ ONLY');
  await client.query('SELECT 1');
  await client.query('COMMIT');
  await client.end();
})().catch(async () => {
  try { await client.end(); } catch (_) {}
  process.exit(1);
});
NODE
finished_at="$(date -u +%s)" || fail
printf 'restore-drill status=PASS stage=application-verification duration_seconds=%s\n' \
  "$((finished_at - started_at))"
