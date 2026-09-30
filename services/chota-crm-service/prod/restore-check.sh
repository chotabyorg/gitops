#!/bin/sh
# A separate disposable database ONLY. Never restores over the configured source DB.
set -eu
: "${PGHOST:?PGHOST required}"
: "${PGDATABASE:?PGDATABASE must name a disposable restore database}"
: "${PGUSER:?PGUSER required}"
: "${RESTORE_FILE:?RESTORE_FILE required}"
case "$PGDATABASE" in crm_restore_*) ;; *) echo 'Refusing non-disposable target database name' >&2; exit 1 ;; esac
[ -f "$RESTORE_FILE" ] || { echo 'Dump file missing' >&2; exit 1; }
# createdb must succeed; an existing target is refused rather than overwritten.
createdb "$PGDATABASE"
pg_restore --exit-on-error --single-transaction --no-owner --no-privileges --dbname="$PGDATABASE" "$RESTORE_FILE"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
 IF (SELECT version_num FROM alembic_version) <> '0001_crm' THEN RAISE EXCEPTION 'Unexpected schema'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='bookings_resource_no_overlap') THEN RAISE EXCEPTION 'Missing booking constraint'; END IF;
 IF EXISTS (SELECT 1 FROM customers c LEFT JOIN workspaces w ON w.id=c.workspace_id WHERE w.id IS NULL) THEN RAISE EXCEPTION 'Orphan customer'; END IF;
 IF EXISTS (SELECT 1 FROM bookings a JOIN bookings b ON a.id < b.id AND a.workspace_id=b.workspace_id AND a.resource_id=b.resource_id AND a.status='CONFIRMED' AND b.status='CONFIRMED' AND tstzrange(a.start_at,a.end_at,'[)') && tstzrange(b.start_at,b.end_at,'[)')) THEN RAISE EXCEPTION 'Overlapping confirmed bookings'; END IF;
END $$;
SELECT 'workspaces' AS entity, count(*) FROM workspaces
UNION ALL SELECT 'customers',count(*) FROM customers
UNION ALL SELECT 'offerings',count(*) FROM offerings
UNION ALL SELECT 'bookings',count(*) FROM bookings
UNION ALL SELECT 'deals',count(*) FROM deals
UNION ALL SELECT 'timeline_events',count(*) FROM timeline_events
UNION ALL SELECT 'audit_events',count(*) FROM audit_events;
SQL
# Leave cleanup explicit so a failed verification can be inspected safely.
echo 'Restore verification complete; remove the disposable database after recording counts'
