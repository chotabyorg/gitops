#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROD_DIR="$(cd -- "${PACKAGE_DIR}/../.." && pwd)"

fail() {
  printf 'package contract test failed: %s\n' "$1" >&2
  exit 1
}

for command in grep kubectl ruby; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing command: ${command}"
done

[[ -f "${PACKAGE_DIR}/restore/reader-policy.template.json" ]] \
  || fail 'restore reader policy template is missing'
[[ -f "${PACKAGE_DIR}/restore/reader-credentials.secret.yaml.template" ]] \
  || fail 'restore reader Secret template is missing'

drill_script="${PACKAGE_DIR}/tests/run-isolated-restore-drill.sh"
grep -Fq 'archive_checksum_verified:($archive_sha == $restored_archive_sha)' "${drill_script}" \
  || fail 'restore drill report must compare the restored archive checksum'
grep -Fq 'openssl dgst -sha256 -verify' "${drill_script}" \
  || fail 'restore drill must verify the detached report signature'
grep -Fq 'signature-verification.txt' "${drill_script}" \
  || fail 'restore drill must publish signature verification evidence'

ruby - "${PACKAGE_DIR}/role/postgres-backup-role.sql" <<'RUBY'
role_sql = File.read(ARGV.fetch(0))
sequence_grants = role_sql.scan(/\bGRANT\b.*?;/mi).select do |grant|
  grant.match?(/\bON\s+(?:ALL\s+)?SEQUENCES\b/i)
end

abort "backup role must define current and future sequence grants" unless sequence_grants.length == 2
abort "backup role sequence grants must be SELECT-only so it cannot call nextval or advance sequence state" unless sequence_grants.all? do |grant|
  grant.gsub(/\s+/, " ").match?(/\AGRANT SELECT ON (?:ALL )?SEQUENCES\b/i)
end
RUBY

grep -Eq '^[[:space:]]*PGDATABASE:[[:space:]]*repetly[[:space:]]*$' \
  "${PACKAGE_DIR}/backup/backup-config.yaml" \
  || fail 'non-secret database name must reach both split backup phases'

if grep -Eq 'operations/postgres-backup|postgres-backup' "${PROD_DIR}/kustomization.yaml"; then
  fail 'the active production overlay references inert operations tooling'
fi

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT
kubectl kustomize "${PACKAGE_DIR}" >"${rendered}" \
  || fail 'operations package does not render'

ruby -ryaml - "${rendered}" "${PACKAGE_DIR}/backup/manual-job.template.yaml" <<'RUBY'
documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
abort "operations package unexpectedly renders a Secret" if documents.any? { |doc| doc["kind"] == "Secret" }
abort "operations package must render one suspended CronJob" unless documents.count { |doc| doc["kind"] == "CronJob" && doc.dig("spec", "suspend") == true } == 1
abort "operations package must render one restore Job" unless documents.count { |doc| doc["kind"] == "Job" } == 1
abort "operations resources must target prod" unless documents.all? { |doc| doc.dig("metadata", "namespace") == "prod" }

images = documents.flat_map do |doc|
  pod = doc.dig("spec", "jobTemplate", "spec", "template", "spec") || doc.dig("spec", "template", "spec") || {}
  Array(pod["initContainers"]) + Array(pod["containers"])
end.map { |container| container["image"] }.compact
sentinel = /@sha256:0{64}\z/
abort "every inert workload image must use an all-zero digest sentinel" unless images.any? && images.all? { |image| image.match?(sentinel) }

backup = documents.find { |doc| doc["kind"] == "CronJob" }
manual = YAML.load_file(ARGV.fetch(1))
[backup.dig("spec", "jobTemplate", "spec", "template", "spec"), manual.dig("spec", "template", "spec")].each do |pod|
  dump = pod.fetch("initContainers").find { |container| container["name"] == "dump" }
  abort "backup dump container is missing" unless dump
  tls = dump.fetch("env", []).to_h { |entry| [entry.fetch("name"), entry["value"]] }
  abort "backup dump must explicitly force verify-full" unless tls["PGSSLMODE"] == "verify-full"
  abort "backup dump must explicitly force the mounted CA path" unless tls["PGSSLROOTCERT"] == "/var/run/repetly-backup-db-ca/ca.crt"
  ca_mount = dump.fetch("volumeMounts").find { |mount| mount["name"] == "database-ca" }
  abort "backup dump must mount the database CA at the forced TLS path" unless ca_mount && ca_mount["mountPath"] == "/var/run/repetly-backup-db-ca" && ca_mount["readOnly"] == true
end

restore = documents.find { |doc| doc["kind"] == "Job" }
pod = restore.fetch("spec").fetch("template").fetch("spec")
abort "restore Job must not expose a Service" if documents.any? { |doc| doc["kind"] == "Service" }
serialized = restore.to_s
abort "restore Job references the production application Secret" if serialized.include?("repetly-secret")
abort "restore Job may reference only its reader Secret" unless serialized.include?("repetly-postgres-backup-s3-reader")
RUBY

ruby -rjson - "${PACKAGE_DIR}/storage/writer-policy.template.json" \
  "${PACKAGE_DIR}/restore/reader-policy.template.json" <<'RUBY'
writer = JSON.parse(File.read(ARGV.fetch(0)))
reader = JSON.parse(File.read(ARGV.fetch(1)))
writer_allowed = writer.fetch("Statement").select { |statement| statement["Effect"] == "Allow" }.flat_map { |statement| Array(statement["Action"]) }
reader_allowed = reader.fetch("Statement").select { |statement| statement["Effect"] == "Allow" }.flat_map { |statement| Array(statement["Action"]) }
abort "backup writer may delete objects" if writer_allowed.any? { |action| action.start_with?("s3:Delete") }
abort "restore reader may mutate objects" if reader_allowed.any? { |action| action.start_with?("s3:Put") || action.start_with?("s3:Delete") }
reader_grants = reader.fetch("Statement").select { |statement| statement["Effect"] == "Allow" }
abort "restore reader must have exactly one versioned grant per approved object" unless reader_grants.length == 2
abort "restore reader may read a mutable object version" unless reader_grants.all? { |statement| statement["Action"] == ["s3:GetObjectVersion"] }
expected_resources = [
  "REPLACE_WITH_BACKUP_BUCKET_ARN/REPLACE_WITH_APPROVED_DUMP_KEY",
  "REPLACE_WITH_BACKUP_BUCKET_ARN/REPLACE_WITH_APPROVED_DUMP_KEY.complete.json"
]
abort "restore reader policy may access an unrelated object key" unless reader_grants.map { |statement| statement["Resource"] }.sort == expected_resources.sort
expected_versions = ["REPLACE_WITH_APPROVED_DUMP_VERSION_ID", "REPLACE_WITH_APPROVED_MARKER_VERSION_ID"]
actual_versions = reader_grants.map { |statement| statement.dig("Condition", "StringEquals", "s3:VersionId") }
abort "restore reader policy must bind each exact object to its exact version" unless actual_versions.sort == expected_versions.sort
RUBY

printf '%s\n' 'PASS: inert package, split identities, and activation blockers are structurally enforced'
