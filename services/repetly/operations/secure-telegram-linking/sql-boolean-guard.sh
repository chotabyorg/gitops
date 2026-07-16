#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s QUERY_FILE\n' "${0##*/}" >&2
  exit 64
fi

query_file="$1"
[[ -r "${query_file}" ]] || {
  printf 'SQL guard failed: query file is not readable\n' >&2
  exit 66
}

if [[ -n "${DATABASE_URL+x}" ]]; then
  printf 'SQL guard failed: DATABASE_URL is not accepted; inject libpq connection environment separately\n' >&2
  exit 64
fi

if [[ -z "${PGSERVICE:-}" ]] \
  && { [[ -z "${PGHOST:-}" ]] || [[ -z "${PGDATABASE:-}" ]] || [[ -z "${PGUSER:-}" ]]; }; then
  printf 'SQL guard failed: inject PGSERVICE or PGHOST/PGDATABASE/PGUSER\n' >&2
  exit 64
fi

command -v psql >/dev/null 2>&1 || {
  printf 'SQL guard failed: psql is unavailable\n' >&2
  exit 69
}

if ! query_output="$(
  psql \
    -X \
    --quiet \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --field-separator '|' \
    --file "${query_file}" \
    2>/dev/null
)"; then
  printf 'SQL guard failed: query execution failed\n' >&2
  exit 1
fi

verdict="$(
  printf '%s\n' "${query_output}" \
    | sed '/^[[:space:]]*$/d' \
    | tail -n 1 \
    | awk -F '|' '{ print $NF }'
)"

case "${verdict}" in
  t | true | 1)
    printf 'SQL guard passed\n'
    ;;
  *)
    printf 'SQL guard failed: aggregate safety verdict was not true\n' >&2
    exit 1
    ;;
esac
