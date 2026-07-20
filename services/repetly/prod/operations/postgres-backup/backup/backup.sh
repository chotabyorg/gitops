#!/usr/bin/env bash
# Logical PostgreSQL backup entrypoint. It never accepts object-key fragments from
# callers: the key is derived from validated, non-secret configuration only.
set -euo pipefail

umask 077

usage() {
  printf 'usage: %s --dump-only|--upload-only|--run\n' "${0##*/}" >&2
  exit 64
}

fail() {
  printf 'backup status=failed reason=%s\n' "$1" >&2
  exit 1
}

require() {
  [[ -n "${!1:-}" ]] || fail "missing-${1,,}"
}

valid_component() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9.-]{0,63}$ ]] && [[ "$1" != *..* ]]
}

valid_prefix() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._/-]{0,127}$ ]] &&
    [[ "$1" != /* ]] && [[ "$1" != */ ]] && [[ "$1" != *..* ]] &&
    [[ "$1" != *//* ]]
}

valid_timestamp() {
  [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

endpoint_host() {
  local endpoint="$1"
  endpoint="${endpoint#https://}"
  printf '%s' "${endpoint%%:*}"
}

valid_fqdn() {
  local host="$1"
  [[ "${host}" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1
  ! is_ipv4_literal "${host}" || return 1
  case "${host}" in
    *.svc | *.svc.cluster.local | *.cluster.local | *.local | *.internal) return 1 ;;
  esac
}

is_ipv4_literal() {
  local host="$1" octet
  local -a octets
  IFS='.' read -r -a octets <<<"${host}"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "${octet}" =~ ^[0-9]{1,3}$ ]] && ((10#${octet} <= 255)) || return 1
  done
}

is_local_or_reserved_ipv4() {
  local host="$1" first second
  is_ipv4_literal "${host}" || return 1
  IFS='.' read -r first second _ <<<"${host}"
  ((first == 0 || first == 10 || first == 127)) && return 0
  ((first == 169 && second == 254)) && return 0
  ((first == 172 && second >= 16 && second <= 31)) && return 0
  ((first == 192 && second == 168)) && return 0
  ((first == 100 && second >= 64 && second <= 127)) && return 0
  return 1
}

valid_storage_endpoint() {
  local endpoint="$1" host
  [[ "${endpoint}" =~ ^https://[a-z0-9][a-z0-9.-]*[a-z0-9](:[0-9]{1,5})?$ ]] || return 1
  host="$(endpoint_host "${endpoint}")"
  if [[ "${BACKUP_ENVIRONMENT}" == test && \
    "${BACKUP_ALLOW_LOCAL_TEST_STORAGE:-}" == 1 && \
    "${BACKUP_LOCAL_TEST_STORAGE_APPROVED:-}" == 1 ]]; then
    [[ "${host}" == localhost ]] || is_local_or_reserved_ipv4 "${host}" || return 1
    return 0
  fi
  valid_fqdn "${host}" || return 1
  [[ -n "${S3_APPROVED_FQDN:-}" ]] || return 1
  valid_fqdn "${S3_APPROVED_FQDN}" || return 1
  [[ "${host}" == "${S3_APPROVED_FQDN}" ]]
}

database_ca_path='/var/run/repetly-backup-db-ca/ca.crt'

validate_database_tls() {
  [[ "${PGSSLMODE:-}" == verify-full ]] || fail 'database-tls-verify-full-required'
  [[ "${PGSSLROOTCERT:-}" == "${database_ca_path}" ]] || fail 'database-tls-root-cert-required'
}

clean_backup_libpq() {
  env -u DATABASE_URL -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE \
    -u PGPASSFILE -u PGOPTIONS -u PGCONNECT_TIMEOUT "$@"
}

require_pg_dump_major_18() {
  local version
  version="$(pg_dump --version 2>/dev/null)" || fail 'pg-dump-major-18-required'
  [[ "${version}" =~ ^pg_dump\ \(PostgreSQL\)\ 18(\.[0-9]+)?$ ]] \
    || fail 'pg-dump-major-18-required'
}

validate_environment() {
  local name
  for name in BACKUP_ENVIRONMENT BACKUP_APPLICATION PGDATABASE \
    BACKUP_FORMAT_VERSION BACKUP_SCHEMA_REVISION BACKUP_RUN_ID S3_BUCKET S3_PREFIX \
    AWS_DEFAULT_REGION S3_ENDPOINT; do
    require "${name}"
  done

  for name in BACKUP_ENVIRONMENT BACKUP_APPLICATION PGDATABASE \
    BACKUP_FORMAT_VERSION BACKUP_SCHEMA_REVISION BACKUP_RUN_ID AWS_DEFAULT_REGION; do
    valid_component "${!name}" || fail "unsafe-${name,,}"
  done
  valid_prefix "${S3_PREFIX}" || fail 'unsafe-s3-prefix'
  if ! [[ "${S3_BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] ||
    [[ "${S3_BUCKET}" == *..* ]]; then
    fail 'unsafe-s3-bucket'
  fi
  valid_storage_endpoint "${S3_ENDPOINT}" || fail 's3-endpoint-must-be-approved-off-cluster-fqdn'
}

object_key_for() {
  local timestamp="$1"
  valid_timestamp "${timestamp}" || fail 'unsafe-utc-timestamp'
  printf '%s/%s/%s/%s/%s-%s-%s-%s.dump' \
    "${S3_PREFIX}" "${BACKUP_ENVIRONMENT}" "${BACKUP_APPLICATION}" \
    "${PGDATABASE}" "${timestamp}" "${BACKUP_FORMAT_VERSION}" \
    "${BACKUP_SCHEMA_REVISION}" "${BACKUP_RUN_ID}"
}

metadata_value() {
  local name="$1"
  local matches
  matches="$(grep -E "^${name}=" "${metadata_file}" || true)"
  [[ "$(printf '%s\n' "${matches}" | grep -c .)" -eq 1 ]] || fail "invalid-metadata-${name}"
  printf '%s' "${matches#*=}"
}

validate_version_id() {
  [[ "$1" =~ ^[A-Za-z0-9._+=/-]+$ ]] &&
    [[ "${#1}" -le 1024 ]] && [[ "$1" != None ]]
}

read_storage_head() {
  local key="$1"
  aws s3api head-object --bucket "${S3_BUCKET}" --key "${key}" \
    --endpoint-url "${S3_ENDPOINT}" \
    --query '[VersionId, ServerSideEncryption]' --output text 2>/dev/null
}

validate_storage_head() {
  local facts="$1" expected_version="$2" expected_encryption="$3"
  local version encryption extra
  IFS=$'\t' read -r version encryption extra <<<"${facts}"
  [[ -z "${extra:-}" ]] || return 1
  validate_version_id "${version}" || return 1
  [[ "${version}" == "${expected_version}" ]] || return 1
  [[ "${encryption}" == "${expected_encryption}" ]]
}

mode="${1:-}"
case "${mode}" in
  --dump-only | --upload-only | --run) ;;
  *) usage ;;
esac

validate_environment
if [[ "${mode}" == --dump-only || "${mode}" == --run ]]; then
  require PGHOST
  require PGPORT
  require PGUSER
  require PGPASSWORD
  validate_database_tls
fi
storage_encryption="${S3_SERVER_SIDE_ENCRYPTION:-AES256}"
case "${storage_encryption}" in
  AES256) ;;
  none)
    [[ "${BACKUP_ENVIRONMENT}" == test &&
      "${BACKUP_ALLOW_UNENCRYPTED_TEST_STORAGE:-}" == 1 ]] ||
      fail 'storage-encryption-required'
    ;;
  *) fail 'unsupported-storage-encryption' ;;
esac
for command in aws date grep pg_dump sha256sum wc; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing-command-${command}"
done
if [[ "${mode}" == --dump-only || "${mode}" == --run ]]; then
  require_pg_dump_major_18
fi

work_dir="${BACKUP_WORKDIR:-}"
created_work_dir=0
if [[ -z "${work_dir}" ]]; then
  work_dir="$(mktemp -d)"
  created_work_dir=1
fi
mkdir -p "${work_dir}"
dump_file="${work_dir}/backup.dump"
metadata_file="${work_dir}/backup.meta"
marker_file="${work_dir}/backup.complete.json"
keep_intermediate_files=0

cleanup() {
  local exit_code="$?"
  if [[ "${keep_intermediate_files}" -eq 1 && "${exit_code}" -eq 0 ]]; then
    exit "${exit_code}"
  fi
  rm -f "${dump_file}" "${metadata_file}" "${marker_file}"
  if [[ "${created_work_dir}" -eq 1 ]]; then
    rmdir "${work_dir}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

dump_archive() {
  local timestamp key checksum size_bytes
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  key="$(object_key_for "${timestamp}")"

  # pg_dump custom format is already compressed where useful; do not wrap gzip.
  clean_backup_libpq pg_dump --format=custom --file "${dump_file}" "${PGDATABASE}" \
    >/dev/null 2>&1 || fail 'pg-dump-failed'
  [[ -s "${dump_file}" ]] || fail 'empty-backup-archive'
  checksum="$(sha256sum "${dump_file}" | awk '{print $1}')"
  [[ "${checksum}" =~ ^[a-f0-9]{64}$ ]] || fail 'invalid-backup-checksum'
  size_bytes="$(wc -c <"${dump_file}" | tr -d '[:space:]')"
  [[ "${size_bytes}" =~ ^[1-9][0-9]*$ ]] || fail 'invalid-backup-size'

  {
    printf 'timestamp=%s\n' "${timestamp}"
    printf 'object_key=%s\n' "${key}"
    printf 'sha256=%s\n' "${checksum}"
    printf 'size_bytes=%s\n' "${size_bytes}"
  } >"${metadata_file}"
}

upload_archive() {
  local timestamp key checksum size_bytes expected_key object_uri version marker_key marker_version head_facts expected_encryption
  local -a upload_encryption_args marker_encryption_args
  [[ -s "${dump_file}" ]] || fail 'missing-backup-archive'
  [[ -f "${metadata_file}" ]] || fail 'missing-backup-metadata'

  timestamp="$(metadata_value timestamp)"
  key="$(metadata_value object_key)"
  checksum="$(metadata_value sha256)"
  size_bytes="$(metadata_value size_bytes)"
  expected_key="$(object_key_for "${timestamp}")"
  [[ "${key}" == "${expected_key}" ]] || fail 'metadata-object-key-mismatch'
  [[ "${checksum}" =~ ^[a-f0-9]{64}$ ]] || fail 'invalid-metadata-checksum'
  [[ "${size_bytes}" =~ ^[1-9][0-9]*$ ]] || fail 'invalid-metadata-size'
  [[ "$(sha256sum "${dump_file}" | awk '{print $1}')" == "${checksum}" ]] \
    || fail 'backup-checksum-mismatch'
  [[ "$(wc -c <"${dump_file}" | tr -d '[:space:]')" == "${size_bytes}" ]] \
    || fail 'backup-size-mismatch'

  object_uri="s3://${S3_BUCKET}/${key}"
  upload_encryption_args=()
  marker_encryption_args=()
  if [[ "${storage_encryption}" == AES256 ]]; then
    upload_encryption_args=(--sse AES256)
    marker_encryption_args=(--server-side-encryption AES256)
    expected_encryption=AES256
  else
    expected_encryption=None
  fi

  aws s3 cp "${dump_file}" "${object_uri}" \
    --endpoint-url "${S3_ENDPOINT}" --only-show-errors "${upload_encryption_args[@]}" \
    >/dev/null 2>&1 || fail 'archive-upload-failed'
  head_facts="$(read_storage_head "${key}")" \
    || fail 'uploaded-object-verification-failed'
  IFS=$'\t' read -r version _ <<<"${head_facts}"
  validate_version_id "${version}" || fail 'storage-versioning-required'
  validate_storage_head "${head_facts}" "${version}" "${expected_encryption}" \
    || fail 'archive-storage-encryption-unverified'

  marker_key="${key}.complete.json"
  printf '{"status":"complete","format_version":"%s","object_key":"%s","object_version":"%s","sha256":"%s","size_bytes":%s,"created_at":"%s"}\n' \
    "${BACKUP_FORMAT_VERSION}" "${key}" "${version}" "${checksum}" "${size_bytes}" "${timestamp}" >"${marker_file}"
  marker_version="$(aws s3api put-object --bucket "${S3_BUCKET}" --key "${marker_key}" \
    --body "${marker_file}" --endpoint-url "${S3_ENDPOINT}" "${marker_encryption_args[@]}" \
    --query VersionId --output text 2>/dev/null)" || fail 'completion-marker-upload-failed'
  validate_version_id "${marker_version}" || fail 'storage-versioning-required'
  head_facts="$(read_storage_head "${marker_key}")" \
    || fail 'completion-marker-verification-failed'
  validate_storage_head "${head_facts}" "${marker_version}" "${expected_encryption}" \
    || fail 'completion-marker-storage-encryption-unverified'

  printf 'backup status=success timestamp=%s reference=%s object_version=%s marker_version=%s size_bytes=%s sha256=%s checksum=verified\n' \
    "${timestamp}" "${object_uri}" "${version}" "${marker_version}" \
    "${size_bytes}" "${checksum}"
}

case "${mode}" in
  --dump-only)
    dump_archive
    keep_intermediate_files=1
    printf 'backup status=dumped timestamp=%s\n' "$(metadata_value timestamp)"
    ;;
  --upload-only)
    upload_archive
    ;;
  --run)
    dump_archive
    upload_archive
    ;;
esac
