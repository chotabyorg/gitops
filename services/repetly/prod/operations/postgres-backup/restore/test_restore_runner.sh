#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/restore.sh"

fail() {
  printf 'restore runner test failed: %s\n' "$1" >&2
  exit 1
}

[[ -x "${RUNNER}" ]] || fail "restore runner is missing or not executable"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
contract_dir="${tmp_dir}/contract"
work_dir="${tmp_dir}/work"
bin_dir="${tmp_dir}/bin"
mkdir -p "${contract_dir}" "${work_dir}" "${bin_dir}"

reference='s3://repetly-backup-drills/postgres/production/repetly/repetly/20260720T120000Z-v1-prisma-01234567-89ab-cdef-0123-456789abcdef.dump'
checksum='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
printf '%s\n' "${reference}" >"${contract_dir}/backup-reference"
printf '%s\n' 'version-00000000000000000001' >"${contract_dir}/backup-version-id"
printf '%s\n' "${reference}.complete.json" >"${contract_dir}/completion-reference"
printf '%s\n' 'version-00000000000000000002' >"${contract_dir}/completion-version-id"
printf '%s\n' 'v1' >"${contract_dir}/format-version"
printf '%s\n' 'backup-storage.example.test' >"${contract_dir}/storage-approved-fqdn"

cat >"${bin_dir}/aws" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${TEST_STORAGE_FAILURE:-}" = '1' ]; then
  exit 1
fi
destination="${!#}"
[ -n "${destination}" ] || exit 64
case "${destination}" in
  *.dump) printf '%s' archive >"${destination}" ;;
  *.complete.json) printf '%s\n' "${TEST_MARKER}" >"${destination}" ;;
  *) exit 64 ;;
esac
SH
cat >"${bin_dir}/sha256sum" <<'SH'
#!/usr/bin/env sh
printf '%s  %s\n' "${TEST_HASH}" "$1"
SH
cat >"${bin_dir}/jq" <<'SH'
#!/usr/bin/env sh
# The runner owns the exact jq predicate; this fake returns the marker facts.
printf '%s\n' "${TEST_MARKER_FACTS}"
SH
cat >"${bin_dir}/pg_isready" <<'SH'
#!/usr/bin/env bash
set -eu
for name in DATABASE_URL PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGOPTIONS PGCONNECT_TIMEOUT PGSSLMODE PGSSLROOTCERT; do
  [ -z "${!name:-}" ] || exit 70
done
exit 0
SH
cat >"${bin_dir}/pg_restore" <<'SH'
#!/usr/bin/env bash
set -eu
for name in DATABASE_URL PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGOPTIONS PGCONNECT_TIMEOUT PGSSLMODE PGSSLROOTCERT; do
  [ -z "${!name:-}" ] || exit 70
done
if [ "${1:-}" = '--list' ]; then
  exit 0
fi
printf '%s\n' "$*" >>"${TEST_DB_CALL_LOG:?}"
SH
cat >"${bin_dir}/psql" <<'SH'
#!/usr/bin/env bash
set -eu
for name in DATABASE_URL PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGOPTIONS PGCONNECT_TIMEOUT PGSSLMODE PGSSLROOTCERT; do
  [ -z "${!name:-}" ] || exit 70
done
printf '%s\n' "$*" >>"${TEST_DB_CALL_LOG:?}"
SH
chmod +x "${bin_dir}/aws" "${bin_dir}/sha256sum" "${bin_dir}/jq"
chmod +x "${bin_dir}/pg_isready" "${bin_dir}/pg_restore" "${bin_dir}/psql"

runner=("${RUNNER}")
if [[ "${TRACE_RESTORE_TEST:-}" == "1" ]]; then
  runner=(bash -x "${RUNNER}")
fi
object_key="${reference#s3://repetly-backup-drills/}"
marker="{\"status\":\"complete\",\"format_version\":\"v1\",\"object_key\":\"${object_key}\",\"object_version\":\"version-00000000000000000001\",\"sha256\":\"${checksum}\",\"size_bytes\":7,\"created_at\":\"20260720T120000Z\"}"
marker_facts="version-00000000000000000001|${checksum}|7|v1|${object_key}"
run_download() {
  PATH="${bin_dir}:${PATH}" S3_ENDPOINT="${TEST_S3_ENDPOINT:-https://backup-storage.example.test}" TEST_HASH="${checksum}" TEST_MARKER="${marker}" \
    TEST_MARKER_FACTS="${marker_facts}" TEST_STORAGE_FAILURE="${TEST_STORAGE_FAILURE:-}" \
    "${runner[@]}" --contract-dir "${contract_dir}" --work-dir "${work_dir}" download
}
assert_sanitized_failure() {
  local description="$1"
  local output
  if output="$(run_download 2>&1)"; then
    fail "${description} must fail closed"
  fi
  [[ "${output}" == 'restore-drill status=FAIL stage=download' ]] \
    || fail "${description} must emit only a sanitized failure"
  [[ "${output}" != *"${reference}"* ]] || fail "${description} leaked a backup reference"
}

if ! output="$(run_download 2>&1)"; then
  printf '%s\n' "${output}" >&2
  fail "a valid immutable contract must download, checksum, and mark the archive ready"
fi
[[ "${output}" =~ ^restore-drill\ status=PASS\ stage=download\ duration_seconds=[0-9]+$ ]] \
  || fail "download success output must stay sanitized"
[[ -s "${work_dir}/backup.dump" ]] || fail "download must leave a non-empty local archive"

# Marker checksum is authoritative. A mismatch rejects a corrupt archive before
# any restore stage can start, without leaking its reference.
marker_facts="version-00000000000000000001|ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff|7|v1|${object_key}"
assert_sanitized_failure 'checksum mismatch'
marker_facts="version-00000000000000000001|${checksum}|7|v1|${object_key}"

TEST_STORAGE_FAILURE=1
assert_sanitized_failure 'missing or denied storage object'
unset TEST_STORAGE_FAILURE

TEST_S3_ENDPOINT='https://backup.svc'
assert_sanitized_failure 'in-cluster service endpoint'
TEST_S3_ENDPOINT='https://10.10.0.8'
assert_sanitized_failure 'private IPv4 endpoint'
TEST_S3_ENDPOINT='https://172.16.0.8'
assert_sanitized_failure 'private 172.16/12 IPv4 endpoint'
TEST_S3_ENDPOINT='https://192.168.0.8'
assert_sanitized_failure 'private 192.168/16 IPv4 endpoint'
unset TEST_S3_ENDPOINT

printf '%s\n' 's3://repetly-backup-drills/postgres/production/repetly/repetly/20260720T120000Z-v1-prisma-01234567-89ab-cdef-0123-456789abcdef.dump/../unsafe' >"${contract_dir}/backup-reference"
assert_sanitized_failure 'unsafe object key'
printf '%s\n' "${reference}" >"${contract_dir}/backup-reference"

if ! output="$(run_download 2>&1)"; then
  printf '%s\n' "${output}" >&2
  fail "a second isolated download must remain repeatable"
fi

db_call_log="${tmp_dir}/database-calls.log"
restore_output="$(PATH="${bin_dir}:${PATH}" TEST_DB_CALL_LOG="${db_call_log}" \
  PGDATABASE=postgres PGHOST=production.invalid PGHOSTADDR=10.0.0.9 \
  PGSERVICE=hostile-service PGSERVICEFILE=/tmp/hostile-service.conf \
  PGPASSWORD=must-not-propagate PGPASSFILE=/tmp/hostile-passfile \
  PGOPTIONS='-c role=postgres' PGCONNECT_TIMEOUT=1 PGSSLMODE=disable \
  PGSSLROOTCERT=/tmp/hostile-ca.pem \
  DATABASE_URL='postgresql://production.invalid/repetly' \
  "${RUNNER}" --contract-dir "${contract_dir}" --work-dir "${work_dir}" restore 2>&1)" \
  || fail 'hostile production/system database environment must not control restore target'
[[ "${restore_output}" =~ ^restore-drill\ status=PASS\ stage=restore\ duration_seconds=[0-9]+$ ]] \
  || fail 'restore success output must stay sanitized'
grep -Fq -- '--dbname=repetly_restore_drill' "${db_call_log}" \
  || fail 'restore and ANALYZE must use only the fixed isolated target'
if grep -Eq -- '--dbname=(postgres|repetly)([[:space:]]|$)' "${db_call_log}"; then
  fail 'production or system database target reached a restore command'
fi

printf '%s\n' 'PASS: immutable download, failure simulation, and sanitized logging contract'
