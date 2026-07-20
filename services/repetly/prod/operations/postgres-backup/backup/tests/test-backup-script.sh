#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKUP_SCRIPT="${BACKUP_DIR}/backup.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "${BACKUP_SCRIPT}" ]] || fail "backup public entrypoint is missing or not executable"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_bin="${tmp_dir}/bin"
mkdir -p "${fake_bin}" "${tmp_dir}/work"

cat >"${fake_bin}/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '-u +%Y%m%dT%H%M%SZ' ]] || exit 64
printf '%s\n' "${FAKE_UTC_TIMESTAMP:?}"
EOF

cat >"${fake_bin}/pg_dump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '--version' ]]; then
  printf '%s\n' "${PG_DUMP_VERSION:-pg_dump (PostgreSQL) 18.0}"
  exit 0
fi
[[ "${PG_DUMP_EXIT:-0}" == 0 ]] || exit "${PG_DUMP_EXIT}"
[[ "$1" == '--format=custom' ]] || exit 65
[[ "$2" == '--file' ]] || exit 65
printf 'custom-format-archive\n' >"$3"
EOF

cat >"${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWS_CALL_LOG:?}"

case "$1 $2" in
  's3 cp')
    [[ "${AWS_FAIL_UPLOAD:-0}" == 0 ]] || exit 42
    ;;
  's3api head-object')
    [[ "${AWS_FAIL_HEAD:-0}" == 0 ]] || exit 43
    query=''
    for ((index = 1; index <= $#; index += 1)); do
      if [[ "${!index}" == '--query' ]]; then
        next_index=$((index + 1))
        query="${!next_index}"
        break
      fi
    done
    if [[ "${query}" == *ServerSideEncryption* ]]; then
      if [[ "$*" == *'.complete.json'* ]]; then
        printf '%s\t%s\n' 'version-marker-1' "${AWS_MARKER_SSE:-AES256}"
      else
        printf '%s\t%s\n' 'version-backup-1' "${AWS_ARCHIVE_SSE:-AES256}"
      fi
    else
      printf 'version-backup-1\n'
    fi
    ;;
  's3api put-object')
    [[ "${AWS_FAIL_MARKER:-0}" == 0 ]] || exit 44
    for ((index = 1; index <= $#; index += 1)); do
      if [[ "${!index}" == '--body' ]]; then
        next_index=$((index + 1))
        cp "${!next_index}" "${AWS_MARKER_CAPTURE:?}"
        break
      fi
    done
    printf 'version-marker-1\n'
    ;;
  *) exit 66 ;;
esac
EOF

chmod +x "${fake_bin}/date" "${fake_bin}/pg_dump" "${fake_bin}/aws"

run_backup() {
  PATH="${fake_bin}:${PATH}" \
  FAKE_UTC_TIMESTAMP="${1}" \
  BACKUP_RUN_ID="${2:-podabc123}" \
  AWS_CALL_LOG="${tmp_dir}/aws-${1}.log" \
  AWS_MARKER_CAPTURE="${tmp_dir}/marker-${1}.json" \
  BACKUP_WORKDIR="${tmp_dir}/work" \
  BACKUP_ENVIRONMENT=production \
  BACKUP_APPLICATION=repetly \
  PGDATABASE=repetly \
  PGHOST=postgres.production.example.invalid \
  PGPORT=5432 \
  PGUSER=repetly_backup \
  PGPASSWORD=test-only-password \
  BACKUP_FORMAT_VERSION=v1 \
  BACKUP_SCHEMA_REVISION=prisma \
  PGSSLMODE="${BACKUP_TEST_PGSSLMODE:-verify-full}" \
  PGSSLROOTCERT="${BACKUP_TEST_PGSSLROOTCERT:-/var/run/repetly-backup-db-ca/ca.crt}" \
  S3_ENDPOINT=https://storage.example.invalid \
  S3_APPROVED_FQDN=storage.example.invalid \
  S3_BUCKET=repetly-backups \
  S3_PREFIX=postgres \
  AWS_DEFAULT_REGION=us-east-1 \
  "${BACKUP_SCRIPT}" --run
}

run_phase() {
  local mode="$1"
  local timestamp="$2"
  local run_id="$3"
  local work_dir="$4"
  local call_log="$5"
  PATH="${fake_bin}:${PATH}" \
  FAKE_UTC_TIMESTAMP="${timestamp}" \
  AWS_CALL_LOG="${call_log}" \
  AWS_MARKER_CAPTURE="${call_log}.marker" \
  BACKUP_WORKDIR="${work_dir}" \
  BACKUP_ENVIRONMENT=production \
  BACKUP_APPLICATION=repetly \
  PGDATABASE=repetly \
  PGHOST=postgres.production.example.invalid \
  PGPORT=5432 \
  PGUSER=repetly_backup \
  PGPASSWORD=test-only-password \
  BACKUP_FORMAT_VERSION=v1 \
  BACKUP_SCHEMA_REVISION=prisma \
  BACKUP_RUN_ID="${run_id}" \
  PGSSLMODE="${BACKUP_TEST_PGSSLMODE:-verify-full}" \
  PGSSLROOTCERT="${BACKUP_TEST_PGSSLROOTCERT:-/var/run/repetly-backup-db-ca/ca.crt}" \
  S3_ENDPOINT=https://storage.example.invalid \
  S3_APPROVED_FQDN=storage.example.invalid \
  S3_BUCKET=repetly-backups \
  S3_PREFIX=postgres \
  AWS_DEFAULT_REGION=us-east-1 \
  "${BACKUP_SCRIPT}" "${mode}"
}

output="$(run_backup 20260720T120000Z podabc123)" || fail "a valid backup must succeed"
expected_key='postgres/production/repetly/repetly/20260720T120000Z-v1-prisma-podabc123.dump'
grep -Fq "reference=s3://repetly-backups/${expected_key}" <<<"${output}" \
  || fail "success output must expose a sanitized immutable backup reference"
grep -Fq 'status=success' <<<"${output}" || fail "success output must be explicit"
grep -Fq 'object_version=version-backup-1' <<<"${output}" \
  || fail "success evidence must pin the immutable archive version"
grep -Fq 'marker_version=version-marker-1' <<<"${output}" \
  || fail "success evidence must pin the completion-marker version"

call_log="${tmp_dir}/aws-20260720T120000Z.log"
[[ "$(wc -l <"${call_log}")" -eq 4 ]] || fail "backup must upload, verify encryption, write one marker, then read it"
sed -n '1p' "${call_log}" | grep -Fq "s3 cp ${tmp_dir}/work/backup.dump s3://repetly-backups/${expected_key}" \
  || fail "the completed custom archive must upload before marker work"
sed -n '2p' "${call_log}" | grep -Fq "s3api head-object --bucket repetly-backups --key ${expected_key}" \
  || fail "the uploaded archive must have a versioned immutable and encrypted reference"
sed -n '3p' "${call_log}" | grep -Fq "s3api put-object --bucket repetly-backups --key ${expected_key}.complete.json" \
  || fail "completion marker must be the final storage write"
sed -n '4p' "${call_log}" | grep -Fq "s3api head-object --bucket repetly-backups --key ${expected_key}.complete.json" \
  || fail "only a read-only marker head may follow the final completion-marker write"
tail -n '+4' "${call_log}" | grep -Eq 's3 cp|s3api put-object' \
  && fail "no storage write may follow the completion marker"
ruby -rjson - "${tmp_dir}/marker-20260720T120000Z.json" <<'RUBY'
marker = JSON.parse(File.read(ARGV.fetch(0)))
expected = %w[status format_version object_key object_version sha256 size_bytes created_at]
abort "unexpected marker fields" unless marker.keys.sort == expected.sort
abort "marker not complete" unless marker.fetch("status") == "complete"
abort "format mismatch" unless marker.fetch("format_version") == "v1"
abort "wrong key" unless marker.fetch("object_key").end_with?(".dump")
abort "unsafe checksum" unless marker.fetch("sha256").match?(/\A[a-f0-9]{64}\z/)
abort "invalid size" unless marker.fetch("size_bytes").is_a?(Integer) && marker.fetch("size_bytes").positive?
RUBY

if PATH="${fake_bin}:${PATH}" \
  FAKE_UTC_TIMESTAMP=20260720T120001Z \
  AWS_CALL_LOG="${tmp_dir}/unsafe-endpoint.log" \
  BACKUP_WORKDIR="${tmp_dir}/work" \
  BACKUP_ENVIRONMENT=production \
  BACKUP_APPLICATION=repetly \
  PGDATABASE=repetly \
  BACKUP_FORMAT_VERSION=v1 \
  BACKUP_SCHEMA_REVISION=prisma \
  BACKUP_RUN_ID=podabc124 \
  S3_ENDPOINT=https://127.0.0.1 \
  S3_APPROVED_FQDN=storage.example.invalid \
  S3_BUCKET=repetly-backups \
  S3_PREFIX=postgres \
  AWS_DEFAULT_REGION=us-east-1 \
  "${BACKUP_SCRIPT}" --run >/dev/null 2>&1; then
  fail "a loopback storage endpoint must be rejected before dump or upload"
fi
[[ ! -e "${tmp_dir}/unsafe-endpoint.log" ]] \
  || fail "a rejected endpoint must not reach storage commands"

assert_rejected_production_endpoint() {
  local endpoint="$1"
  local label="$2"
  local call_log="${tmp_dir}/rejected-${label}.log"
  local approved_fqdn="${endpoint#https://}"
  approved_fqdn="${approved_fqdn%%:*}"
  if PATH="${fake_bin}:${PATH}" \
    FAKE_UTC_TIMESTAMP=20260720T120001Z \
    AWS_CALL_LOG="${call_log}" \
    BACKUP_WORKDIR="${tmp_dir}/work" \
    BACKUP_ENVIRONMENT=production \
    BACKUP_APPLICATION=repetly \
    PGDATABASE=repetly \
    BACKUP_FORMAT_VERSION=v1 \
    BACKUP_SCHEMA_REVISION=prisma \
    BACKUP_RUN_ID=podabc124 \
    S3_ENDPOINT="${endpoint}" \
    S3_APPROVED_FQDN="${approved_fqdn}" \
    S3_BUCKET=repetly-backups \
    S3_PREFIX=postgres \
    AWS_DEFAULT_REGION=us-east-1 \
    "${BACKUP_SCRIPT}" --run >/dev/null 2>&1; then
    fail "production endpoint ${endpoint} must be rejected"
  fi
  [[ ! -e "${call_log}" ]] || fail "rejected ${label} endpoint must not reach storage commands"
}

assert_rejected_production_endpoint 'https://backup.svc' 'service-suffix'
assert_rejected_production_endpoint 'https://backup.svc.cluster.local' 'service-cluster-suffix'
assert_rejected_production_endpoint 'https://backup.cluster.local' 'cluster-suffix'
assert_rejected_production_endpoint 'https://backup.local' 'local-suffix'
assert_rejected_production_endpoint 'https://backup.internal' 'internal-suffix'
assert_rejected_production_endpoint 'https://10.10.0.8' 'private-10'
assert_rejected_production_endpoint 'https://172.16.0.8' 'private-172'
assert_rejected_production_endpoint 'https://192.168.0.8' 'private-192'

local_test_output="$(PATH="${fake_bin}:${PATH}" \
  FAKE_UTC_TIMESTAMP=20260720T120001Z \
  AWS_CALL_LOG="${tmp_dir}/local-test.log" \
  AWS_MARKER_CAPTURE="${tmp_dir}/local-test.marker" \
  BACKUP_WORKDIR="${tmp_dir}/local-test-work" \
  BACKUP_ENVIRONMENT=test \
  BACKUP_APPLICATION=repetly \
  PGDATABASE=repetly \
  PGHOST=postgres.test.example.invalid \
  PGPORT=5432 \
  PGUSER=repetly_backup \
  PGPASSWORD=test-only-password \
  PGSSLMODE=verify-full \
  PGSSLROOTCERT=/var/run/repetly-backup-db-ca/ca.crt \
  BACKUP_FORMAT_VERSION=v1 \
  BACKUP_SCHEMA_REVISION=prisma \
  BACKUP_RUN_ID=localtest \
  S3_ENDPOINT=https://127.0.0.1 \
  BACKUP_ALLOW_LOCAL_TEST_STORAGE=1 \
  BACKUP_LOCAL_TEST_STORAGE_APPROVED=1 \
  S3_BUCKET=repetly-backups \
  S3_PREFIX=postgres \
  AWS_DEFAULT_REGION=us-east-1 \
  "${BACKUP_SCRIPT}" --run)" || fail "both explicit gates may allow local storage only in test"
grep -Fq 'status=success' <<<"${local_test_output}" \
  || fail "the double-gated local test path must still prove full backup success"

if S3_SERVER_SIDE_ENCRYPTION=none run_backup 20260720T120001Z noencryption \
  >/dev/null 2>&1; then
  fail "production backup must reject disabled storage encryption"
fi
[[ ! -e "${tmp_dir}/aws-20260720T120001Z.log" ]] \
  || fail "disabled production encryption must be rejected before storage use"

tls_failure_log="${tmp_dir}/tls-failure.log"
tls_failure_output=''
if tls_failure_output="$(BACKUP_TEST_PGSSLMODE=require run_phase --run 20260720T120001Z tlsfail \
  "${tmp_dir}/tls-failure-work" "${tls_failure_log}" 2>&1)"; then
  fail "a backup must reject a database TLS mode other than verify-full"
fi
[[ "${tls_failure_output}" == 'backup status=failed reason=database-tls-verify-full-required' ]] \
  || fail "a wrong database TLS mode must fail with a sanitized TLS reason"
[[ ! -e "${tls_failure_log}" ]] || fail "a TLS-rejected dump must not reach storage"

version_failure_log="${tmp_dir}/version-failure.log"
version_failure_output=''
if version_failure_output="$(PG_DUMP_VERSION='pg_dump (PostgreSQL) 17.5' run_phase --run 20260720T120001Z oldclient \
  "${tmp_dir}/version-failure-work" "${version_failure_log}" 2>&1)"; then
  fail "a pg_dump major version other than 18 must fail before database or storage work"
fi
[[ "${version_failure_output}" == 'backup status=failed reason=pg-dump-major-18-required' ]] \
  || fail "an unsupported pg_dump major must emit a sanitized preflight reason"
[[ ! -e "${version_failure_log}" ]] || fail "an unsupported pg_dump major must not reach storage"

if PATH="${fake_bin}:${PATH}" \
  FAKE_UTC_TIMESTAMP=20260720T120002Z \
  AWS_CALL_LOG="${tmp_dir}/unsafe-key.log" \
  AWS_MARKER_CAPTURE="${tmp_dir}/unsafe-key.marker" \
  BACKUP_WORKDIR="${tmp_dir}/work" \
  BACKUP_ENVIRONMENT=production \
  BACKUP_APPLICATION=repetly \
  PGDATABASE=repetly \
  BACKUP_FORMAT_VERSION=v1 \
  BACKUP_SCHEMA_REVISION=prisma \
  BACKUP_RUN_ID=podabc125 \
  S3_ENDPOINT=https://storage.example.invalid \
  S3_APPROVED_FQDN=storage.example.invalid \
  S3_BUCKET=repetly-backups \
  S3_PREFIX=../escape \
  AWS_DEFAULT_REGION=us-east-1 \
  "${BACKUP_SCRIPT}" --run >/dev/null 2>&1; then
  fail "object-key traversal must be rejected before dump or upload"
fi
[[ ! -e "${tmp_dir}/unsafe-key.log" ]] \
  || fail "a rejected object key must not reach storage commands"

first_repeat="$(run_backup 20260720T120100Z manualaaa)" \
  || fail "the first same-second backup must succeed"
second_repeat="$(run_backup 20260720T120100Z manualbbb)" \
  || fail "a repeat backup must succeed with a different immutable object key"
grep -Fq '20260720T120100Z-v1-prisma-manualaaa.dump' <<<"${first_repeat}" \
  || fail "the first backup must bind its pod-derived run identifier into the key"
grep -Fq '20260720T120100Z-v1-prisma-manualbbb.dump' <<<"${second_repeat}" \
  || fail "a repeat must not overwrite the first same-second backup key"

split_work="${tmp_dir}/split-work"
mkdir -p "${split_work}"
run_phase --dump-only 20260720T120200Z splitpod1 "${split_work}" "${tmp_dir}/split.log" \
  >/dev/null || fail "the dump phase must prepare an archive for the uploader"
[[ ! -e "${tmp_dir}/split.log" ]] || fail "the DB-only dump phase must not reach storage"
split_output="$(run_phase --upload-only 20260720T120200Z splitpod1 "${split_work}" "${tmp_dir}/split.log")" \
  || fail "the storage-only upload phase must consume the completed archive"
grep -Fq 'status=success' <<<"${split_output}" \
  || fail "the upload phase must report success only after its completion marker"

upload_failure_log="${tmp_dir}/upload-failure.log"
upload_failure_output=''
if upload_failure_output="$(AWS_FAIL_UPLOAD=1 run_phase --run 20260720T120300Z uploadfail \
  "${tmp_dir}/upload-failure-work" "${upload_failure_log}" 2>&1)"; then
  fail "a denied or partial object upload must fail the backup"
fi
[[ "${upload_failure_output}" == 'backup status=failed reason=archive-upload-failed' ]] \
  || fail "storage denial must emit only a sanitized reason"
[[ "$(wc -l <"${upload_failure_log}")" -eq 1 ]] \
  || fail "a failed archive upload must not verify or mark a backup complete"
! grep -Fq 'put-object' "${upload_failure_log}" \
  || fail "a partial upload must never create a completion marker"

head_failure_log="${tmp_dir}/head-failure.log"
head_failure_output=''
if head_failure_output="$(AWS_FAIL_HEAD=1 run_phase --run 20260720T120301Z headfail \
  "${tmp_dir}/head-failure-work" "${head_failure_log}" 2>&1)"; then
  fail "an object without verified versioning must fail the backup"
fi
[[ "${head_failure_output}" == 'backup status=failed reason=uploaded-object-verification-failed' ]] \
  || fail "versioning failure must emit only a sanitized reason"
! grep -Fq 'put-object' "${head_failure_log}" \
  || fail "an unversioned object must never receive a completion marker"

marker_failure_output=''
if marker_failure_output="$(AWS_FAIL_MARKER=1 run_phase --run 20260720T120302Z markerfail \
  "${tmp_dir}/marker-failure-work" "${tmp_dir}/marker-failure.log" 2>&1)"; then
  fail "a failed completion-marker write must fail the backup"
fi
[[ "${marker_failure_output}" == 'backup status=failed reason=completion-marker-upload-failed' ]] \
  || fail "marker failure must emit only a sanitized reason"

ignored_sse_log="${tmp_dir}/ignored-sse.log"
ignored_sse_output=''
if ignored_sse_output="$(AWS_ARCHIVE_SSE=None run_phase --run 20260720T120303Z ignoredsse \
  "${tmp_dir}/ignored-sse-work" "${ignored_sse_log}" 2>&1)"; then
  fail "a storage provider that ignores archive SSE must fail before the completion marker"
fi
[[ "${ignored_sse_output}" == 'backup status=failed reason=archive-storage-encryption-unverified' ]] \
  || fail "ignored archive SSE must emit a sanitized encryption-verification reason"
! grep -Fq 'put-object' "${ignored_sse_log}" \
  || fail "an archive without reported encryption must never receive a completion marker"

marker_sse_log="${tmp_dir}/marker-sse.log"
marker_sse_output=''
if marker_sse_output="$(AWS_MARKER_SSE=None run_phase --run 20260720T120304Z markersse \
  "${tmp_dir}/marker-sse-work" "${marker_sse_log}" 2>&1)"; then
  fail "a storage provider that ignores marker SSE must fail after its read-only verification"
fi
[[ "${marker_sse_output}" == 'backup status=failed reason=completion-marker-storage-encryption-unverified' ]] \
  || fail "ignored marker SSE must emit a sanitized encryption-verification reason"
[[ "$(wc -l <"${marker_sse_log}")" -eq 4 ]] \
  || fail "marker encryption verification must head the marker exactly once after writing it"
sed -n '3p' "${marker_sse_log}" | grep -Fq 's3api put-object' \
  || fail "the marker must be written before its encryption verification"
sed -n '4p' "${marker_sse_log}" | grep -Fq 's3api head-object' \
  || fail "only a marker head may occur after the marker write"

db_failure_log="${tmp_dir}/db-failure.log"
db_failure_output=''
if db_failure_output="$(PG_DUMP_EXIT=2 run_phase --run 20260720T120400Z dbfailpod \
  "${tmp_dir}/db-failure-work" "${db_failure_log}" 2>&1)"; then
  fail "wrong database credentials must fail before storage use"
fi
[[ "${db_failure_output}" == 'backup status=failed reason=pg-dump-failed' ]] \
  || fail "database failures must emit only a sanitized reason"
[[ ! -e "${db_failure_log}" ]] \
  || fail "a failed database dump must not upload an object or marker"

missing_work="${tmp_dir}/missing-work"
mkdir -p "${missing_work}"
missing_log="${tmp_dir}/missing-object.log"
if run_phase --upload-only 20260720T120500Z missingpod "${missing_work}" "${missing_log}" \
  >/dev/null 2>&1; then
  fail "a missing archive must not be treated as a successful backup"
fi
[[ ! -e "${missing_log}" ]] \
  || fail "a missing archive must not reach storage"

tampered_work="${tmp_dir}/tampered-work"
mkdir -p "${tampered_work}"
run_phase --dump-only 20260720T120600Z tamperpod "${tampered_work}" "${tmp_dir}/tampered.log" \
  >/dev/null || fail "the checksum test needs a completed dump phase"
printf 'tampered\n' >>"${tampered_work}/backup.dump"
if run_phase --upload-only 20260720T120600Z tamperpod "${tampered_work}" "${tmp_dir}/tampered.log" \
  >/dev/null 2>&1; then
  fail "a checksum mismatch must prevent upload and completion"
fi
[[ ! -e "${tmp_dir}/tampered.log" ]] \
  || fail "a checksum mismatch must not reach storage"

printf 'PASS: custom archive uploads before its versioned completion marker\n'
