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

if [[ -z "${APP_DB_SCHEMA:-}" ]]; then
  printf 'SQL guard failed: APP_DB_SCHEMA is required\n' >&2
  exit 64
fi

if [[ ! "${APP_DB_SCHEMA}" =~ ^[a-z_][a-z0-9_]*$ ]] \
  || [[ "${APP_DB_SCHEMA}" == pg_* ]] \
  || [[ "${APP_DB_SCHEMA}" == "information_schema" ]]; then
  printf 'SQL guard failed: APP_DB_SCHEMA must be a safe application-schema identifier\n' >&2
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

psql_options=(
  -X
  --quiet
  --tuples-only
  --no-align
  --set ON_ERROR_STOP=1
  --set "app_schema=${APP_DB_SCHEMA}"
)
schema_pgoptions="-c search_path=${APP_DB_SCHEMA},pg_catalog"

if ! schema_output="$(
  PGOPTIONS="${schema_pgoptions}" \
    psql \
    "${psql_options[@]}" \
    --command \
    "SELECT current_schema() = '${APP_DB_SCHEMA}' AND to_regnamespace('${APP_DB_SCHEMA}') IS NOT NULL;" \
    2>/dev/null
)"; then
  printf 'SQL guard failed: application schema verification failed\n' >&2
  exit 1
fi

schema_verdict="$(
  printf '%s\n' "${schema_output}" \
    | awk 'NF { print }'
)"
if [[ "${schema_verdict}" != "t" ]]; then
  printf 'SQL guard failed: application schema is missing or not active\n' >&2
  exit 1
fi

if ! query_output="$(
  PGOPTIONS="${schema_pgoptions}" \
    psql \
    "${psql_options[@]}" \
    --field-separator '|' \
    --file "${query_file}" \
    2>/dev/null
)"; then
  printf 'SQL guard failed: query execution failed\n' >&2
  exit 1
fi

nonblank_row_count="$(
  printf '%s\n' "${query_output}" \
    | awk 'NF { count += 1 } END { print count + 0 }'
)"

if [[ "${nonblank_row_count}" != "1" ]]; then
  printf 'SQL guard failed: query must return exactly one aggregate row\n' >&2
  exit 1
fi

verdict="$(
  printf '%s\n' "${query_output}" \
    | awk -F '|' 'NF { print $NF }'
)"

if [[ "${verdict}" != "t" ]]; then
  printf 'SQL guard failed: aggregate safety verdict was not canonical true\n' >&2
  exit 1
fi

printf 'SQL guard passed\n'
