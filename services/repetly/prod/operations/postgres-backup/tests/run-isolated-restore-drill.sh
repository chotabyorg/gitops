#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable CI-only DB+files drill. It never uses production credentials,
# production endpoints, or application data.
PG_IMAGE="postgres:18@sha256:d93de42662696f278fb34354b06fdaa90ad7ca3106d6f72fbd01d16da006d2cf"
MINIO_IMAGE="minio/minio:latest@sha256:a1a8bd4ac40ad7881a245bab97323e18f971e4d4cba2c2007ec1bedd21cbaba2"
WORK="$PWD/.restore-drill"
REPORT_DIR="$PWD/artifacts/restore-drill"
SOURCE="repetly-drill-source"
RESTORE="repetly-drill-restore"
MINIO="repetly-drill-minio"
BUCKET="repetly-backup-drill"
ACCESS_KEY="repetly-drill-writer"
SECRET_KEY="repetly-drill-writer-secret"
DB_PASSWORD="repetly-drill-db-password"
RUN_ID="${GITHUB_RUN_ID:-local}"

rm -rf "$WORK"
mkdir -p "$WORK" "$REPORT_DIR"
rm -f "$REPORT_DIR"/*
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cleanup() {
  code="$?"
  docker rm -f "$SOURCE" "$RESTORE" "$MINIO" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  exit "$code"
}
trap cleanup EXIT
fail() {
  printf 'restore-drill status=FAIL stage=%s\n' "$1" >&2
  exit 1
}
for command in aws docker jq openssl sha256sum; do
  command -v "$command" >/dev/null 2>&1 || fail "missing-$command"
done

docker run -d --name "$MINIO" -p 9000:9000 \
  -e MINIO_ROOT_USER="$ACCESS_KEY" \
  -e MINIO_ROOT_PASSWORD="$SECRET_KEY" \
  "$MINIO_IMAGE" server /data --address :9000 >/dev/null
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_DEFAULT_REGION=us-east-1
for attempt in $(seq 1 60); do
  if aws --endpoint-url http://127.0.0.1:9000 s3api list-buckets >/dev/null 2>&1; then break; fi
  sleep 2
done
aws --endpoint-url http://127.0.0.1:9000 s3api list-buckets >/dev/null 2>&1 || fail minio-start
aws --endpoint-url http://127.0.0.1:9000 s3api create-bucket --bucket "$BUCKET" >/dev/null
aws --endpoint-url http://127.0.0.1:9000 s3api put-bucket-versioning \
  --bucket "$BUCKET" --versioning-configuration Status=Enabled

docker run -d --name "$SOURCE" -p 55431:5432 \
  -e POSTGRES_USER=drill \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -e POSTGRES_DB=repetly \
  "$PG_IMAGE" >/dev/null
for attempt in $(seq 1 60); do
  if docker exec "$SOURCE" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec "$SOURCE" pg_isready -U postgres >/dev/null 2>&1 || fail source-start
docker exec -e PGPASSWORD="$DB_PASSWORD" "$SOURCE" \
  psql -U drill -d repetly -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE drill_documents (id integer PRIMARY KEY, payload text NOT NULL);
   INSERT INTO drill_documents VALUES (1, 'QA-DRILL-A'), (2, 'QA-DRILL-B');" >/dev/null

fixture_started="$(date +%s)"
printf 'QA-DRILL-FILE\n' > "$WORK/fixture.txt"
fixture_sha="$(sha256sum "$WORK/fixture.txt" | awk '{print $1}')"
file_key="files/$RUN_ID/fixture.txt"
object_key="postgres/production/repetly/$RUN_ID.dump"

docker exec "$SOURCE" pg_dump -U drill -d repetly --format=custom > "$WORK/backup.dump"
[ -s "$WORK/backup.dump" ] || fail empty-dump
archive_sha="$(sha256sum "$WORK/backup.dump" | awk '{print $1}')"
archive_size="$(wc -c < "$WORK/backup.dump" | tr -d '[:space:]')"
aws --endpoint-url http://127.0.0.1:9000 s3api put-object \
  --bucket "$BUCKET" --key "$object_key" --body "$WORK/backup.dump" \
  --server-side-encryption AES256 >/dev/null
archive_version="$(aws --endpoint-url http://127.0.0.1:9000 s3api head-object \
  --bucket "$BUCKET" --key "$object_key" --query VersionId --output text)"
marker_key="$object_key.complete.json"
jq -n --arg key "$object_key" --arg version "$archive_version" \
  --arg sha "$archive_sha" --argjson size "$archive_size" \
  '{status:"complete",object_key:$key,object_version:$version,sha256:$sha,size_bytes:$size}' \
  > "$WORK/marker.json"
aws --endpoint-url http://127.0.0.1:9000 s3api put-object \
  --bucket "$BUCKET" --key "$marker_key" --body "$WORK/marker.json" \
  --server-side-encryption AES256 >/dev/null
marker_version="$(aws --endpoint-url http://127.0.0.1:9000 s3api head-object \
  --bucket "$BUCKET" --key "$marker_key" --query VersionId --output text)"
aws --endpoint-url http://127.0.0.1:9000 s3api put-object \
  --bucket "$BUCKET" --key "$file_key" --body "$WORK/fixture.txt" \
  --server-side-encryption AES256 >/dev/null
file_version="$(aws --endpoint-url http://127.0.0.1:9000 s3api head-object \
  --bucket "$BUCKET" --key "$file_key" --query VersionId --output text)"
backup_finished="$(date +%s)"

docker run -d --name "$RESTORE" -p 55432:5432 \
  -e POSTGRES_USER=restore_drill \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -e POSTGRES_DB=repetly_restore_drill \
  "$PG_IMAGE" >/dev/null
for attempt in $(seq 1 60); do
  if docker exec "$RESTORE" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec "$RESTORE" pg_isready -U postgres >/dev/null 2>&1 || fail restore-start

restore_started="$(date +%s)"
aws --endpoint-url http://127.0.0.1:9000 s3api get-object \
  --bucket "$BUCKET" --key "$object_key" --version-id "$archive_version" \
  "$WORK/restored.dump" >/dev/null
aws --endpoint-url http://127.0.0.1:9000 s3api get-object \
  --bucket "$BUCKET" --key "$file_key" --version-id "$file_version" \
  "$WORK/restored-file.txt" >/dev/null
restored_archive_sha="$(sha256sum "$WORK/restored.dump" | awk '{print $1}')"
restored_file_sha="$(sha256sum "$WORK/restored-file.txt" | awk '{print $1}')"
[ "$restored_archive_sha" = "$archive_sha" ] || fail archive-checksum
[ "$restored_file_sha" = "$fixture_sha" ] || fail file-checksum

docker cp "$WORK/restored.dump" "$RESTORE:/tmp/restored.dump" >/dev/null
docker exec -e PGPASSWORD="$DB_PASSWORD" "$RESTORE" \
  pg_restore --dbname=repetly_restore_drill --single-transaction \
  --exit-on-error --no-owner --no-privileges /tmp/restored.dump >/dev/null
db_facts="$(docker exec -e PGPASSWORD="$DB_PASSWORD" "$RESTORE" \
  psql -U restore_drill -d repetly_restore_drill -At -c \
  "SELECT count(*)::text || '|' || string_agg(payload, ',' ORDER BY id)
   FROM public.drill_documents;")"
[ "$db_facts" = "2|QA-DRILL-A,QA-DRILL-B" ] || fail database-verification
restore_finished="$(date +%s)"
rpo_seconds="$((backup_finished - fixture_started))"
rto_seconds="$((restore_finished - restore_started))"
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg run_id "$RUN_ID" \
  --arg started_at "$started_at" \
  --arg finished_at "$finished_at" \
  --arg object_key "$object_key" \
  --arg archive_version "$archive_version" \
  --arg marker_version "$marker_version" \
  --arg archive_sha "$archive_sha" \
  --arg fixture_sha "$fixture_sha" \
  --arg restored_file_sha "$restored_file_sha" \
  --argjson archive_size "$archive_size" \
  --argjson rpo_seconds "$rpo_seconds" \
  --argjson rto_seconds "$rto_seconds" \
  '{
    status:"PASS",
    run_id:$run_id,
    started_at:$started_at,
    finished_at:$finished_at,
    database_restore:"PASS",
    files_restore:"PASS",
    archive_checksum_verified:($archive_sha == $archive_sha),
    file_checksum_match:($fixture_sha == $restored_file_sha),
    archive:{object_key:$object_key,version:$archive_version,size_bytes:$archive_size,sha256:$archive_sha},
    completion_marker_version:$marker_version,
    measured_rpo_seconds:$rpo_seconds,
    measured_rto_seconds:$rto_seconds
  }' > "$REPORT_DIR/report.json"
sha256sum "$REPORT_DIR/report.json" > "$REPORT_DIR/checksum-manifest.txt"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out "$REPORT_DIR/ephemeral-signing-key.pem" >/dev/null 2>&1
openssl rsa -in "$REPORT_DIR/ephemeral-signing-key.pem" -pubout \
  -out "$REPORT_DIR/ephemeral-signing-public.pem" >/dev/null 2>&1
openssl dgst -sha256 -sign "$REPORT_DIR/ephemeral-signing-key.pem" \
  -out "$REPORT_DIR/report.json.sig" "$REPORT_DIR/report.json"
rm -f "$REPORT_DIR/ephemeral-signing-key.pem"
printf 'restore-drill status=PASS database=PASS files=PASS rpo_seconds=%s rto_seconds=%s\n' \
  "$rpo_seconds" "$rto_seconds"
