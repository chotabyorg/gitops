#!/usr/bin/env bash
# Validates a lifecycle-admin deletion proposal. It never calls storage APIs and
# intentionally supports dry-run only; the backup writer has no Delete grant.
set -euo pipefail

fail() {
  printf 'retention status=blocked reason=%s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'usage: %s --dry-run INVENTORY.tsv PLAN.tsv\n' "${0##*/}" >&2
  exit 64
}

valid_dump_key() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*\.dump$ ]] &&
    [[ "$1" != /* ]] && [[ "$1" != *..* ]] && [[ "$1" != *//* ]]
}

valid_version() {
  [[ "$1" =~ ^[A-Za-z0-9._+=/-]+$ ]] && [[ "${#1}" -le 1024 ]]
}

valid_timestamp() {
  [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

[[ "$#" -eq 3 && "$1" == '--dry-run' ]] || usage
inventory="$2"
plan="$3"
[[ -r "${inventory}" && -r "${plan}" ]] || fail 'inventory-or-plan-unreadable'

latest_eligible_timestamp=''
latest_eligible_pair=''
protected=0
inventory_rows=0
inventory_pairs="$(mktemp)"
trap 'rm -f "${inventory_pairs}"' EXIT

while IFS=$'\t' read -r dump_key dump_version marker_key marker_version timestamp state extra || [[ -n "${dump_key:-}" ]]; do
  [[ -z "${extra:-}" && -n "${dump_key:-}" && -n "${dump_version:-}" && -n "${marker_key:-}" && -n "${marker_version:-}" && -n "${timestamp:-}" && -n "${state:-}" ]] \
    || fail 'invalid-inventory-record'
  valid_dump_key "${dump_key}" || fail 'unsafe-inventory-dump-key'
  [[ "${marker_key}" == "${dump_key}.complete.json" ]] || fail 'inventory-marker-does-not-bind-dump'
  valid_version "${dump_version}" || fail 'unsafe-inventory-dump-version'
  valid_version "${marker_version}" || fail 'unsafe-inventory-marker-version'
  valid_timestamp "${timestamp}" || fail 'unsafe-inventory-timestamp'
  case "${state}" in
    eligible | restore-verified | pinned-75) ;;
    *) fail 'invalid-inventory-state' ;;
  esac
  pair="${dump_key}"$'\t'"${dump_version}"$'\t'"${marker_key}"$'\t'"${marker_version}"
  grep -Fqx "${pair}" "${inventory_pairs}" && fail 'duplicate-inventory-pair'
  printf '%s\n' "${pair}" >>"${inventory_pairs}"
  inventory_rows=$((inventory_rows + 1))
  if [[ "${state}" == 'eligible' ]] && { [[ -z "${latest_eligible_timestamp}" ]] || [[ "${timestamp}" > "${latest_eligible_timestamp}" ]]; }; then
    latest_eligible_timestamp="${timestamp}"
    latest_eligible_pair="${pair}"
  fi
done <"${inventory}"

[[ "${inventory_rows}" -gt 0 && -n "${latest_eligible_pair}" ]] \
  || fail 'no-eligible-complete-backup'

while IFS=$'\t' read -r dump_key dump_version marker_key marker_version timestamp state extra || [[ -n "${dump_key:-}" ]]; do
  pair="${dump_key}"$'\t'"${dump_version}"$'\t'"${marker_key}"$'\t'"${marker_version}"
  if [[ "${pair}" == "${latest_eligible_pair}" || \
        "${state}" == 'restore-verified' || "${state}" == 'pinned-75' ]]; then
    protected=$((protected + 1))
  fi
done <"${inventory}"

candidates=0
seen_file="$(mktemp)"
trap 'rm -f "${inventory_pairs}" "${seen_file}"' EXIT
while IFS=$'\t' read -r dump_key dump_version marker_key marker_version extra || [[ -n "${dump_key:-}" ]]; do
  [[ -z "${extra:-}" && -n "${dump_key:-}" && -n "${dump_version:-}" && -n "${marker_key:-}" && -n "${marker_version:-}" ]] \
    || fail 'invalid-plan-record'
  valid_dump_key "${dump_key}" || fail 'unsafe-plan-dump-key'
  [[ "${marker_key}" == "${dump_key}.complete.json" ]] || fail 'plan-marker-does-not-bind-dump'
  valid_version "${dump_version}" || fail 'unsafe-plan-dump-version'
  valid_version "${marker_version}" || fail 'unsafe-plan-marker-version'
  pair="${dump_key}"$'\t'"${dump_version}"$'\t'"${marker_key}"$'\t'"${marker_version}"
  grep -Fqx "${pair}" "${seen_file}" && fail 'duplicate-plan-record'
  printf '%s\n' "${pair}" >>"${seen_file}"

  matches="$(grep -F "${pair}"$'\t' "${inventory}" || true)"
  [[ "$(printf '%s\n' "${matches}" | grep -c .)" -eq 1 ]] || fail 'plan-object-not-in-inventory'
  IFS=$'\t' read -r _ _ _ _ _ state <<<"${matches}"
  [[ "${pair}" != "${latest_eligible_pair}" ]] || fail 'cannot-delete-latest-eligible-backup'
  [[ "${state}" != 'restore-verified' ]] || fail 'cannot-delete-restore-verified-backup'
  [[ "${state}" != 'pinned-75' ]] || fail 'cannot-delete-issue-75-pinned-backup'
  candidates=$((candidates + 1))
done <"${plan}"

printf 'retention status=dry-run candidates=%s protected=%s inventory=%s\n' \
  "${candidates}" "${protected}" "${inventory_rows}"
