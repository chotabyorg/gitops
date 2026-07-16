#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd)"
PROD_DIR="${REPO_ROOT}/services/repetly/prod"
STOP_DIR="${SCRIPT_DIR}/stop"
MIGRATE_DIR="${SCRIPT_DIR}/migrate"
RESUME_CLOSED_DIR="${SCRIPT_DIR}/resume-closed"
OPEN_DIR="${SCRIPT_DIR}/open"
GUARD="${SCRIPT_DIR}/sql-boolean-guard.sh"

EXPECTED_COMMIT="6cb8a891911d1c194ff7792790689d882b69cf0e"
EXPECTED_TAG="${EXPECTED_COMMIT:0:7}"
EXPECTED_IMAGE="ghcr.io/chotabyorg/repetly:${EXPECTED_TAG}"
EXPECTED_JOB="repetly-telegram-linking-migrate-${EXPECTED_TAG}"

fail() {
  printf 'validation failed: %s\n' "$1" >&2
  exit 1
}

for command in kubectl git awk grep sed tail mktemp cmp env; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing command: ${command}"
done

required_files=(
  "${SCRIPT_DIR}/RUNBOOK.md"
  "${SCRIPT_DIR}/postflight.sql"
  "${GUARD}"
  "${STOP_DIR}/kustomization.yaml"
  "${STOP_DIR}/replicas-zero-patch.yaml"
  "${STOP_DIR}/service-traffic-closed-patch.yaml"
  "${MIGRATE_DIR}/kustomization.yaml"
  "${MIGRATE_DIR}/migration-job.yaml"
  "${MIGRATE_DIR}/replicas-zero-patch.yaml"
  "${MIGRATE_DIR}/service-traffic-closed-patch.yaml"
  "${RESUME_CLOSED_DIR}/kustomization.yaml"
  "${RESUME_CLOSED_DIR}/service-traffic-closed-patch.yaml"
  "${OPEN_DIR}/kustomization.yaml"
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || fail "missing required file: ${file#"${REPO_ROOT}/"}"
done

[[ -x "${GUARD}" ]] || fail "SQL boolean guard is not executable"

if grep -Eq 'operations/secure-telegram-linking|telegram-linking-migrate|maintenance-gate' \
  "${PROD_DIR}/kustomization.yaml"; then
  fail "active production kustomization references an operational resource"
fi

if ! git -C "${REPO_ROOT}" diff --quiet origin/main -- services/repetly/prod; then
  fail "active production overlay differs from origin/main"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

kubectl kustomize "${PROD_DIR}" >"${tmp_dir}/prod.yaml"
kubectl kustomize "${STOP_DIR}" >"${tmp_dir}/stop.yaml"
kubectl kustomize "${MIGRATE_DIR}" >"${tmp_dir}/migrate.yaml"
kubectl kustomize "${RESUME_CLOSED_DIR}" >"${tmp_dir}/resume-closed.yaml"
kubectl kustomize "${OPEN_DIR}" >"${tmp_dir}/open.yaml"

replicas_for_repetly() {
  awk '
    /^kind: Deployment$/ { in_deployment = 1; name = ""; next }
    /^kind: / { in_deployment = 0 }
    in_deployment && /^  name: repetly$/ { name = "repetly" }
    in_deployment && name == "repetly" && /^  replicas: / {
      print $2
      exit
    }
  ' "$1"
}

deployment_image_for_repetly() {
  awk '
    /^kind: Deployment$/ { in_deployment = 1; name = ""; next }
    /^kind: / { in_deployment = 0 }
    in_deployment && /^  name: repetly$/ { name = "repetly" }
    in_deployment && name == "repetly" && /^        image: / {
      print $2
      exit
    }
  ' "$1"
}

migration_job_image() {
  awk -v expected_job="${EXPECTED_JOB}" '
    /^kind: Job$/ { in_job = 1; name = ""; next }
    /^kind: / { in_job = 0 }
    in_job && $1 == "name:" && $2 == expected_job { name = expected_job }
    in_job && name == expected_job && /^        image: / {
      print $2
      exit
    }
  ' "$1"
}

resource_namespace() {
  awk -v expected_kind="$1" -v expected_name="$2" '
    function emit() {
      if (kind == expected_kind && name == expected_name) {
        print namespace
        found = 1
        exit
      }
    }
    /^---$/ { emit(); kind = ""; name = ""; namespace = ""; next }
    /^kind: / { kind = $2; next }
    /^  name: / && name == "" { name = $2; next }
    /^  namespace: / && namespace == "" { namespace = $2; next }
    END {
      if (!found && kind == expected_kind && name == expected_name) {
        print namespace
      }
    }
  ' "$3"
}

[[ "$(replicas_for_repetly "${tmp_dir}/prod.yaml")" == "1" ]] \
  || fail "active production render must retain one replica"
[[ "$(replicas_for_repetly "${tmp_dir}/stop.yaml")" == "0" ]] \
  || fail "STOP render must scale Repetly to zero"
[[ "$(replicas_for_repetly "${tmp_dir}/migrate.yaml")" == "0" ]] \
  || fail "MIGRATE render must keep Repetly at zero"
[[ "$(replicas_for_repetly "${tmp_dir}/resume-closed.yaml")" == "1" ]] \
  || fail "RESUME-CLOSED render must restore one replica"
[[ "$(replicas_for_repetly "${tmp_dir}/open.yaml")" == "1" ]] \
  || fail "OPEN render must retain one replica"

for stage in stop migrate resume-closed; do
  gate_count="$(grep -c 'repetly.chota.by/maintenance-gate: closed' \
    "${tmp_dir}/${stage}.yaml" || true)"
  [[ "${gate_count}" == "1" ]] \
    || fail "${stage} must render exactly one non-matching Service traffic gate"
done
if grep -q 'repetly.chota.by/maintenance-gate: closed' "${tmp_dir}/open.yaml"; then
  fail "OPEN render must remove the Service traffic gate"
fi

job_count="$(grep -c '^kind: Job$' "${tmp_dir}/migrate.yaml" || true)"
[[ "${job_count}" == "2" ]] \
  || fail "MIGRATE render must contain the existing bootstrap Job and one migration Job"
grep -q "^  name: ${EXPECTED_JOB}$" "${tmp_dir}/migrate.yaml" \
  || fail "migration Job name must match the reviewed release tag"
grep -q "repetly.chota.by/application-commit: ${EXPECTED_COMMIT}$" \
  "${tmp_dir}/migrate.yaml" \
  || fail "migration Job must record the exact reviewed application commit"
grep -q "repetly.chota.by/application-image: ${EXPECTED_IMAGE}$" \
  "${tmp_dir}/migrate.yaml" \
  || fail "migration Job must record the exact reviewed application image"
[[ "$(resource_namespace Job "${EXPECTED_JOB}" "${tmp_dir}/migrate.yaml")" == "prod" ]] \
  || fail "migration Job must render in namespace prod"
[[ "$(resource_namespace Service repetly "${tmp_dir}/migrate.yaml")" == "prod" ]] \
  || fail "Repetly Service must render in namespace prod"

if grep -Eq 'argocd.argoproj.io/hook:|ttlSecondsAfterFinished:' \
  "${MIGRATE_DIR}/migration-job.yaml"; then
  fail "migration Job must be ordinary and retained for evidence"
fi
grep -q '^  backoffLimit: 0$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job retries must be disabled"
grep -q '^  activeDeadlineSeconds: ' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job requires a bounded deadline"
grep -q '^      restartPolicy: Never$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job restart policy must be Never"
grep -q '^      automountServiceAccountToken: false$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job must not mount a service-account token"
[[ "$(grep -c 'secretKeyRef:' "${MIGRATE_DIR}/migration-job.yaml")" == "1" ]] \
  || fail "migration Job must reference exactly one Secret key"
grep -Eq '^[[:space:]]+key: DATABASE_URL$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job must reference only the existing DATABASE_URL key"
grep -q '^            readOnlyRootFilesystem: true$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job root filesystem must be read-only"
grep -q '^              mountPath: /tmp$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job requires a bounded writable /tmp"

migration_image="$(migration_job_image "${tmp_dir}/migrate.yaml")"
[[ "${migration_image}" == "${EXPECTED_IMAGE}" ]] \
  || fail "migration Job must render the exact reviewed image"
for stage in migrate resume-closed open; do
  [[ "$(deployment_image_for_repetly "${tmp_dir}/${stage}.yaml")" == "${EXPECTED_IMAGE}" ]] \
    || fail "${stage} Deployment must render the exact reviewed image"
done
[[ "${migration_image}" == "$(deployment_image_for_repetly "${tmp_dir}/migrate.yaml")" ]] \
  || fail "migration Job and Deployment images must match"
[[ "${EXPECTED_TAG}" != "latest" && "${EXPECTED_TAG}" != "main" ]] \
  || fail "mutable application image tags are forbidden"

if grep -REq '(postgres(ql)?://[^[:space:]]+:[^[:space:]]+@|BEGIN (RSA |OPENSSH )?PRIVATE KEY|TELEGRAM_BOT_TOKEN[[:space:]]*:[[:space:]]*[^$])' \
  "${SCRIPT_DIR}"; then
  fail "possible plaintext secret in operational assets"
fi

psql() {
  local argument
  for argument in "$@"; do
    [[ "${argument}" != *"://"* ]] \
      || return 90
  done
  printf '%s\n' "${FAKE_PSQL_RESULT:-f}"
}
export -f psql

if DATABASE_URL='postgresql://redacted-host/redacted-db?schema=public' \
  PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-prisma-url.out" 2>"${tmp_dir}/guard-prisma-url.err"; then
  fail "boolean guard accepted Prisma DATABASE_URL"
fi

if env -u DATABASE_URL PGSERVICE='validator' FAKE_PSQL_RESULT='7|f' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-false.out" 2>"${tmp_dir}/guard-false.err"; then
  fail "boolean guard accepted a false verdict"
fi
if grep -q '7' "${tmp_dir}/guard-false.out" "${tmp_dir}/guard-false.err"; then
  fail "boolean guard leaked query output on failure"
fi
env -u DATABASE_URL PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-true.out" 2>"${tmp_dir}/guard-true.err" \
  || fail "boolean guard rejected a true verdict"

printf 'PASS: inert STOP/MIGRATE/RESUME-CLOSED/OPEN dry-renders and guard simulations\n'
