#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="${SCRIPT_DIR}/../retention-preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "${PREFLIGHT}" ]] || fail "retention dry-run entrypoint is missing or not executable"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
inventory="${tmp_dir}/inventory.tsv"
safe_plan="${tmp_dir}/safe-plan.tsv"
unsafe_plan="${tmp_dir}/unsafe-plan.tsv"
dump_only_plan="${tmp_dir}/dump-only-plan.tsv"
marker_only_plan="${tmp_dir}/marker-only-plan.tsv"
mismatched_plan="${tmp_dir}/mismatched-plan.tsv"

printf '%s\n' \
  $'postgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump\tversion-old\tpostgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump.complete.json\tmarker-version-old\t20260601T000000Z\teligible' \
  $'postgres/production/repetly/repetly/20260701T000000Z-v1-prisma-b.dump\tversion-latest\tpostgres/production/repetly/repetly/20260701T000000Z-v1-prisma-b.dump.complete.json\tmarker-version-latest\t20260701T000000Z\teligible' \
  $'postgres/production/repetly/repetly/20260615T000000Z-v1-prisma-c.dump\tversion-restored\tpostgres/production/repetly/repetly/20260615T000000Z-v1-prisma-c.dump.complete.json\tmarker-version-restored\t20260615T000000Z\trestore-verified' \
  $'postgres/production/repetly/repetly/20260620T000000Z-v1-prisma-d.dump\tversion-pinned\tpostgres/production/repetly/repetly/20260620T000000Z-v1-prisma-d.dump.complete.json\tmarker-version-pinned\t20260620T000000Z\tpinned-75' \
  >"${inventory}"
printf '%s\n' \
  $'postgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump\tversion-old\tpostgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump.complete.json\tmarker-version-old' \
  >"${safe_plan}"
printf '%s\n' \
  $'postgres/production/repetly/repetly/20260701T000000Z-v1-prisma-b.dump\tversion-latest\tpostgres/production/repetly/repetly/20260701T000000Z-v1-prisma-b.dump.complete.json\tmarker-version-latest' \
  >"${unsafe_plan}"
printf '%s\n' \
  $'postgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump\tversion-old' \
  >"${dump_only_plan}"
printf '%s\n' \
  $'postgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump.complete.json\tmarker-version-old' \
  >"${marker_only_plan}"
printf '%s\n' \
  $'postgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump\tversion-old\tpostgres/production/repetly/repetly/20260601T000000Z-v1-prisma-a.dump.complete.json\tmarker-version-latest' \
  >"${mismatched_plan}"

output="$(${PREFLIGHT} --dry-run "${inventory}" "${safe_plan}")" \
  || fail "a plan deleting only an old eligible backup must be previewable"
grep -Fq 'retention status=dry-run candidates=1 protected=3' <<<"${output}" \
  || fail "dry-run must emit only aggregate retention evidence"

if "${PREFLIGHT}" --dry-run "${inventory}" "${unsafe_plan}" >/dev/null 2>&1; then
  fail "retention must preserve the most recent eligible backup"
fi

for rejected_plan in "${dump_only_plan}" "${marker_only_plan}" "${mismatched_plan}"; do
  if "${PREFLIGHT}" --dry-run "${inventory}" "${rejected_plan}" >/dev/null 2>&1; then
    fail "retention must reject a dump-only, marker-only, or mismatched pair proposal"
  fi
done

printf 'PASS: retention preview preserves complete dump-marker pairs and protected backups\n'
