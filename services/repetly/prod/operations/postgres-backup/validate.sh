#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
EXPECTED_ACTIVE_SHA="${EXPECTED_ACTIVE_SHA:-}"

fail() {
  printf 'validation failed: %s\n' "$1" >&2
  exit 1
}

for command in kubectl grep; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing command: ${command}"
done

required_files=(
  "${SCRIPT_DIR}/RUNBOOK.md"
  "${SCRIPT_DIR}/kustomization.yaml"
  "${SCRIPT_DIR}/backup/kustomization.yaml"
  "${SCRIPT_DIR}/restore/kustomization.yaml"
  "${SCRIPT_DIR}/role/postgres-backup-role.sql"
  "${SCRIPT_DIR}/storage/STORAGE_CONTRACT.md"
  "${SCRIPT_DIR}/restore/reader-policy.template.json"
  "${SCRIPT_DIR}/tests/test-package-contract.sh"
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || fail "missing required file: ${file#"${PROD_DIR}/"}"
done

if grep -Eq 'operations/postgres-backup|postgres-backup' "${PROD_DIR}/kustomization.yaml"; then
  fail "backup tooling is referenced by the active production overlay"
fi

if command -v sha256sum >/dev/null 2>&1; then
  active_sha="$(kubectl kustomize "${PROD_DIR}" | sha256sum | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  active_sha="$(kubectl kustomize "${PROD_DIR}" | shasum -a 256 | awk '{print $1}')"
else
  fail 'missing SHA-256 command'
fi
if [[ -n "${EXPECTED_ACTIVE_SHA}" && "${active_sha}" != "${EXPECTED_ACTIVE_SHA}" ]]; then
  fail "active production render changed"
fi

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT
kubectl kustomize "${SCRIPT_DIR}" >"${rendered}" || fail "operations render failed"
kubectl create cronjob repetly-postgres-backup-dry-run \
  --image=example.invalid/inert:never --schedule='0 0 * * *' \
  --dry-run=client -o yaml >/dev/null || fail "CronJob client dry-run failed"
kubectl create job repetly-postgres-restore-dry-run \
  --image=example.invalid/inert:never --dry-run=client -o yaml >/dev/null \
  || fail "Job client dry-run failed"

while IFS= read -r script; do
  bash -n "${script}" || fail "Bash syntax failed: ${script#"${SCRIPT_DIR}/"}"
done < <(find "${SCRIPT_DIR}" -type f -name '*.sh' ! -name 'verify-application.sh' -print)
sh -n "${SCRIPT_DIR}/restore/verify-application.sh" \
  || fail 'POSIX shell syntax failed: restore/verify-application.sh'

"${SCRIPT_DIR}/backup/tests/test-backup-script.sh"
"${SCRIPT_DIR}/storage/tests/test-retention-preflight.sh"
"${SCRIPT_DIR}/restore/test_restore_runner.sh"
"${SCRIPT_DIR}/restore/test_restore_contract.sh"
"${SCRIPT_DIR}/tests/test-package-contract.sh"

printf 'PASS: inert PostgreSQL backup/restore tooling preserves active production render sha256=%s\n' \
  "${active_sha}"
