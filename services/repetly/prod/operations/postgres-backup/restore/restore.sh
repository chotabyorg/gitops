#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'restore-drill status=FAIL stage=%s\n' "${stage:-unknown}" >&2
  exit 1
}

if [[ "$#" -ne 5 || "$1" != "--contract-dir" || "$3" != "--work-dir" ]]; then
  printf 'usage: %s --contract-dir DIRECTORY --work-dir DIRECTORY download|restore|verify\n' "${0##*/}" >&2
  exit 64
fi

contract_dir="$2"
work_dir="$4"
stage="$5"
case "${stage}" in
  download | restore | verify) ;;
  *)
  printf 'usage: %s --contract-dir DIRECTORY --work-dir DIRECTORY download|restore|verify\n' "${0##*/}" >&2
  exit 64
  ;;
esac

read_contract_value() {
  local name="$1"
  local file="${contract_dir}/${name}"
  local value

  [[ -f "${file}" && ! -L "${file}" && -s "${file}" ]] || fail
  value="$(<"${file}")"
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || fail
  printf '%s' "${value}"
}

contains_placeholder() {
  local value="$1"
  [[ "${value}" == *REPLACE* || "${value}" == *replace-before-execution* \
    || "${value}" == *template* || "${value}" == *placeholder* ]]
}

valid_version_id() {
  [[ "$1" =~ ^[A-Za-z0-9._+=/-]+$ ]] &&
    [[ "${#1}" -le 1024 ]] && [[ "$1" != None ]]
}

endpoint_host() {
  local endpoint="$1"
  endpoint="${endpoint#https://}"
  printf '%s' "${endpoint%%:*}"
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

valid_fqdn() {
  local host="$1"
  [[ "${host}" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1
  ! is_ipv4_literal "${host}" || return 1
  case "${host}" in
    *.svc | *.svc.cluster.local | *.cluster.local | *.local | *.internal) return 1 ;;
  esac
}

valid_storage_endpoint() {
  local endpoint="$1" approved_fqdn="$2" host
  [[ "${endpoint}" =~ ^https://[a-z0-9][a-z0-9.-]*[a-z0-9](:[0-9]{1,5})?$ ]] || return 1
  host="$(endpoint_host "${endpoint}")"
  valid_fqdn "${host}" && valid_fqdn "${approved_fqdn}" && [[ "${host}" == "${approved_fqdn}" ]]
}

clean_local_libpq() {
  env -u DATABASE_URL -u PGHOST -u PGHOSTADDR -u PGPORT -u PGDATABASE \
    -u PGUSER -u PGSERVICE -u PGSERVICEFILE -u PGPASSWORD -u PGPASSFILE \
    -u PGOPTIONS -u PGCONNECT_TIMEOUT -u PGSSLMODE -u PGSSLROOTCERT \
    -u PGSSLCRL -u PGSSLCERT -u PGSSLKEY "$@"
}

reference="$(read_contract_value backup-reference)"
backup_version="$(read_contract_value backup-version-id)"
completion_reference="$(read_contract_value completion-reference)"
completion_version="$(read_contract_value completion-version-id)"
format_version="$(read_contract_value format-version)"
storage_approved_fqdn="$(read_contract_value storage-approved-fqdn)"

[[ "${reference}" =~ ^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/[a-z0-9][a-z0-9._/-]{0,127}/production/repetly/repetly/[0-9]{8}T[0-9]{6}Z-v1-prisma-[a-f0-9-]{8,64}\.dump$ ]] || fail
[[ "${reference}" != *.invalid/* ]] || fail
contains_placeholder "${reference}" && fail
valid_version_id "${backup_version}" || fail
contains_placeholder "${backup_version}" && fail
[[ "${completion_reference}" == "${reference}.complete.json" ]] || fail
valid_version_id "${completion_version}" || fail
contains_placeholder "${completion_version}" && fail
[[ "${format_version}" == "v1" ]] || fail
contains_placeholder "${storage_approved_fqdn}" && fail
valid_fqdn "${storage_approved_fqdn}" || fail

reference_path="${reference#s3://}"
bucket="${reference_path%%/*}"
object_key="${reference_path#*/}"
[[ -n "${bucket}" && -n "${object_key}" ]] || fail
[[ "${object_key}" != *..* && "${object_key}" != *//* ]] || fail

command -v aws >/dev/null 2>&1 || fail
command -v sha256sum >/dev/null 2>&1 || fail
command -v jq >/dev/null 2>&1 || fail
command -v wc >/dev/null 2>&1 || fail
command -v tr >/dev/null 2>&1 || fail

umask 077
[[ ! -L "${work_dir}" ]] || fail
mkdir -p "${work_dir}" 2>/dev/null || fail
[[ -d "${work_dir}" && ! -L "${work_dir}" ]] || fail

archive_path="${work_dir}/backup.dump"
marker_path="${work_dir}/backup.dump.complete.json"

storage_get() {
  local object_reference="$1"
  local version_id="$2"
  local destination="$3"
  local object_path object_bucket object_key

  object_path="${object_reference#s3://}"
  object_bucket="${object_path%%/*}"
  object_key="${object_path#*/}"
  [[ "${object_bucket}" == "${bucket}" && -n "${object_key}" ]] || fail
  valid_storage_endpoint "${S3_ENDPOINT:-}" "${storage_approved_fqdn}" || fail
  aws s3api get-object --bucket "${object_bucket}" --key "${object_key}" \
    --version-id "${version_id}" --endpoint-url "${S3_ENDPOINT}" \
    --no-cli-pager "${destination}" >/dev/null 2>&1 || fail
}

if [[ "${stage}" == "restore" ]]; then
  command -v pg_isready >/dev/null 2>&1 || fail
  command -v pg_restore >/dev/null 2>&1 || fail
  command -v psql >/dev/null 2>&1 || fail
  [[ -s "${archive_path}" && ! -L "${archive_path}" ]] || fail
  for ((attempt = 0; attempt < 60; attempt += 1)); do
    if clean_local_libpq pg_isready --host=127.0.0.1 --port=55432 --username=restore_drill \
      --dbname=repetly_restore_drill >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  clean_local_libpq pg_isready --host=127.0.0.1 --port=55432 --username=restore_drill \
    --dbname=repetly_restore_drill >/dev/null 2>&1 || fail
  clean_local_libpq pg_restore --list "${archive_path}" >/dev/null 2>&1 || fail
  clean_local_libpq pg_restore --host=127.0.0.1 --port=55432 --username=restore_drill \
      --dbname=repetly_restore_drill --single-transaction --exit-on-error \
      --no-owner --no-privileges "${archive_path}" >/dev/null 2>&1 || fail
  # Refresh only planner aggregates in the ephemeral target. Verification uses
  # these estimates and never emits per-table or row data.
  clean_local_libpq psql --host=127.0.0.1 --port=55432 --username=restore_drill \
      --dbname=repetly_restore_drill --no-password --quiet \
      --set ON_ERROR_STOP=1 --command='ANALYZE' >/dev/null 2>&1 || fail
  printf 'restore-drill status=PASS stage=restore duration_seconds=%s\n' "${SECONDS}"
  exit 0
fi

if [[ "${stage}" == "verify" ]]; then
  command -v psql >/dev/null 2>&1 || fail
  [[ -r /scripts/restore-verify.sql ]] || fail
  verification_output="$(clean_local_libpq psql --host=127.0.0.1 --port=55432 --username=restore_drill \
      --dbname=repetly_restore_drill --no-password --quiet --tuples-only --no-align \
      --set ON_ERROR_STOP=1 --file /scripts/restore-verify.sql 2>/dev/null)" || fail
  verification_rows="$(printf '%s\n' "${verification_output}" | awk 'NF { count += 1 } END { print count + 0 }')"
  verification_verdict="$(printf '%s\n' "${verification_output}" | awk -F '|' 'NF { print $NF }')"
  [[ "${verification_rows}" == "1" && "${verification_verdict}" == "t" ]] || fail
  printf 'restore-drill status=PASS stage=structural-verification duration_seconds=%s\n' "${SECONDS}"
  exit 0
fi

rm -f -- "${archive_path}" "${marker_path}" 2>/dev/null || fail

# The completion marker is intentionally fetched last. It binds the exact
# immutable dump version and checksum, so partial uploads are never restored.
storage_get "${reference}" "${backup_version}" "${archive_path}"
[[ -s "${archive_path}" && ! -L "${archive_path}" ]] || fail
storage_get "${completion_reference}" "${completion_version}" "${marker_path}"
[[ -s "${marker_path}" && ! -L "${marker_path}" ]] || fail
marker_facts="$(jq -er --arg object_key "${object_key}" --arg version "${backup_version}" \
  --arg format "${format_version}" '
  if (
    type == "object"
    and (keys | sort == ["created_at", "format_version", "object_key", "object_version", "sha256", "size_bytes", "status"])
    and .status == "complete"
    and .object_key == $object_key
    and .object_version == $version
    and .format_version == $format
    and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
    and .sha256 != "0000000000000000000000000000000000000000000000000000000000000000"
    and (.size_bytes | type == "number" and floor == . and . > 0)
    and (.created_at | type == "string" and test("^[0-9]{8}T[0-9]{6}Z$"))
  ) then
    [.object_version, .sha256, (.size_bytes | tostring), .format_version, .object_key] | join("|")
  else
    error("invalid completion marker")
  end
' "${marker_path}" 2>/dev/null)" || fail
IFS='|' read -r marker_version marker_checksum marker_size marker_format marker_key marker_extra <<<"${marker_facts}"
[[ -z "${marker_extra:-}" && -n "${marker_key:-}" ]] || fail
[[ "${marker_version}" == "${backup_version}" ]] || fail
[[ "${marker_format}" == "${format_version}" ]] || fail
[[ "${marker_key}" == "${object_key}" ]] || fail
actual_checksum="$(sha256sum "${archive_path}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
actual_size="$(wc -c <"${archive_path}" | tr -d '[:space:]')"
[[ "${actual_checksum}" == "${marker_checksum}" ]] || fail
[[ "${actual_size}" == "${marker_size}" ]] || fail

printf 'restore-drill status=PASS stage=download duration_seconds=%s\n' "${SECONDS}"
