#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOB_FILE="${SCRIPT_DIR}/restore-job.yaml"
CONTRACT_FILE="${SCRIPT_DIR}/restore-contract.yaml"
KUSTOMIZATION_FILE="${SCRIPT_DIR}/kustomization.yaml"

fail() {
  printf 'restore contract test failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "${JOB_FILE}" ]] || fail "restore Job manifest is missing"
[[ -f "${CONTRACT_FILE}" ]] || fail "immutable restore contract is missing"
[[ -f "${KUSTOMIZATION_FILE}" ]] || fail "restore Kustomization is missing"
[[ -x "${SCRIPT_DIR}/verify-application.sh" ]] || fail "application verification script is missing or not executable"
[[ -f "${SCRIPT_DIR}/restore-verify.sql" ]] || fail "aggregate structural verification SQL is missing"

ruby -ryaml - "${JOB_FILE}" "${CONTRACT_FILE}" "${KUSTOMIZATION_FILE}" <<'RUBY'
job = YAML.load_file(ARGV.fetch(0))
contract = YAML.load_file(ARGV.fetch(1))
kustomization = YAML.load_file(ARGV.fetch(2))
abort "expected a batch/v1 Job" unless job.fetch("apiVersion") == "batch/v1" && job.fetch("kind") == "Job"
abort "restore reference contract must be an immutable ConfigMap" unless contract.fetch("apiVersion") == "v1" && contract.fetch("kind") == "ConfigMap" && contract["immutable"] == true
abort "restore reference contract must be a template until an execution PR pins it" unless contract.dig("metadata", "name") == "repetly-postgres-restore-contract-template"
%w[backup-reference backup-version-id completion-reference completion-version-id format-version storage-approved-fqdn].each do |key|
  abort "restore contract misses #{key}" unless contract.fetch("data", {}).key?(key)
end
abort "checksum must be authoritative in the completion marker, not a mutable sidecar object" if contract.fetch("data", {}).key?("backup-sha256")
pod_spec = job.fetch("spec").fetch("template").fetch("spec")
contract_volume = pod_spec.fetch("volumes", []).find { |volume| volume["name"] == "restore-contract" }
abort "restore Job must mount the immutable reference contract" unless contract_volume.dig("configMap", "name") == "repetly-postgres-restore-contract-template"
sidecar = pod_spec.fetch("initContainers").find { |container| container["name"] == "restore-postgres" }
abort "native PostgreSQL sidecar is missing" unless sidecar
abort "PostgreSQL sidecar must use restartPolicy Always" unless sidecar["restartPolicy"] == "Always"
args = sidecar.fetch("args", []).join(" ")
abort "PostgreSQL sidecar must bind only 127.0.0.1:55432" unless args.include?("listen_addresses=127.0.0.1") && args.include?("port=55432")
abort "custom socket args break the official PostgreSQL initialization entrypoint" if args.include?("unix_socket_directories")
socket_volume = pod_spec.fetch("volumes", []).find { |volume| volume["name"] == "restore-socket" }
abort "PostgreSQL sidecar needs an ephemeral default socket directory" unless socket_volume.dig("emptyDir", "medium") == "Memory"
socket_mount = sidecar.fetch("volumeMounts", []).find { |mount| mount["name"] == "restore-socket" }
abort "PostgreSQL default socket directory must be writable with a read-only root" unless socket_mount && socket_mount["mountPath"] == "/var/run/postgresql"
env = sidecar.fetch("env", []).to_h { |entry| [entry.fetch("name"), entry["value"]] }
abort "restore target must be the fixed non-production database" unless env["POSTGRES_DB"] == "repetly_restore_drill"
abort "restore target must use a dedicated local-only role" unless env["POSTGRES_USER"] == "restore_drill"
abort "restore target may use trust only inside its localhost-only ephemeral sidecar" unless env["POSTGRES_HOST_AUTH_METHOD"] == "trust"
abort "target sidecar must not receive a Secret" if sidecar.key?("envFrom") || sidecar.fetch("env", []).any? { |entry| entry.key?("valueFrom") }
abort "restore Job must not use a service-account token" unless pod_spec["automountServiceAccountToken"] == false
abort "restore Job must use the RuntimeDefault seccomp profile" unless pod_spec.dig("securityContext", "seccompProfile", "type") == "RuntimeDefault"
abort "restore Job must run non-root" unless pod_spec.dig("securityContext", "runAsNonRoot") == true
abort "restore Job requires a bounded deadline" unless job.dig("spec", "activeDeadlineSeconds").is_a?(Integer) && job.dig("spec", "activeDeadlineSeconds") > 0
containers = pod_spec.fetch("initContainers") + pod_spec.fetch("containers")
containers.each do |container|
  security = container.fetch("securityContext", {})
  abort "#{container.fetch("name")} allows privilege escalation" unless security["allowPrivilegeEscalation"] == false
  abort "#{container.fetch("name")} root filesystem is writable" unless security["readOnlyRootFilesystem"] == true
  abort "#{container.fetch("name")} does not drop every capability" unless security.dig("capabilities", "drop") == ["ALL"]
  resources = container.fetch("resources", {})
  abort "#{container.fetch("name")} lacks resource requests" unless resources.fetch("requests", {}).key?("cpu") && resources.fetch("requests", {}).key?("memory")
  abort "#{container.fetch("name")} lacks resource limits" unless resources.fetch("limits", {}).key?("cpu") && resources.fetch("limits", {}).key?("memory")
end
init_names = pod_spec.fetch("initContainers").map { |container| container.fetch("name") }
%w[restore-postgres download-backup restore-database structural-verification application-verification].each do |name|
  abort "restore Job misses #{name}" unless init_names.include?(name)
end
abort "restore Job must have one completion container" unless pod_spec.fetch("containers").map { |container| container.fetch("name") } == ["completion"]
download = pod_spec.fetch("initContainers").find { |container| container["name"] == "download-backup" }
secret_names = download.fetch("env", []).map { |entry| entry.dig("valueFrom", "secretKeyRef", "name") }.compact.uniq
abort "only the download stage may receive the restore-reader Secret" unless secret_names == ["repetly-postgres-backup-s3-reader"]
abort "restore Job must never receive the production database Secret" if YAML.dump(job).include?("repetly-secret")
app = pod_spec.fetch("initContainers").find { |container| container["name"] == "application-verification" }
zero_digest = "sha256:" + ("0" * 64)
abort "application verification must use the exact digest-pinned Repetly image sentinel" unless app.fetch("image") == "ghcr.io/chotabyorg/repetly@#{zero_digest}"
abort "all operation images must remain fail-closed sentinels until an execution PR pins approved digests" unless containers.all? { |container| container.fetch("image").end_with?("@#{zero_digest}") }
abort "restore Kustomization must not create a Service or PVC" if kustomization.fetch("resources", []).any? { |resource| resource.match?(/service|pvc/i) }

sql = File.read(File.join(File.dirname(ARGV.fetch(0)), "restore-verify.sql"))
required_sql = {
  "exact public-table count" => /41 AS expected_count/,
  "exact foreign-key count" => /95 AS expected_count/,
  "exact completed Prisma migration count" => /25 AS expected_count/,
  "current secure Telegram migration" => /20260714184000_telegram_active_token_unique_index/,
  "minimum ready index count" => /100 AS minimum_count/,
  "strict table-count verdict" => /table_count_state\.table_count = table_count_state\.expected_count/,
  "strict foreign-key verdict" => /foreign_key_state\.foreign_key_count = foreign_key_state\.expected_count/,
  "strict migration verdict" => /migration_state\.total_count = migration_state\.expected_count/,
  "required secure migration verdict" => /migration_state\.required_migration_count = 1/,
  "ready-index verdict" => /index_state\.ready_valid_count >= index_state\.minimum_count/
}
required_sql.each do |description, pattern|
  abort "restore SQL lacks #{description}" unless sql.match?(pattern)
end
abort "restore SQL must reject invalid or unready indexes directly" unless sql.match?(/indisvalid AND index_state\.indisready/)
puts "PASS: isolated restore target, stages, and hardened Job contract"
RUBY
