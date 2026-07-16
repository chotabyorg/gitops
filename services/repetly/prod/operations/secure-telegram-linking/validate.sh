#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../../../.." && pwd)"
REPETLY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROD_DIR="${REPETLY_DIR}/prod"
STOP_DIR="${SCRIPT_DIR}/stop"
MIGRATE_DIR="${SCRIPT_DIR}/migrate"
RESUME_CLOSED_DIR="${SCRIPT_DIR}/resume-closed"
GUARD="${SCRIPT_DIR}/sql-boolean-guard.sh"
RELEASE_PATCH="${SCRIPT_DIR}/release-identity-patch.yaml"

EXPECTED_COMMIT="6cb8a891911d1c194ff7792790689d882b69cf0e"
EXPECTED_SHORT="${EXPECTED_COMMIT:0:7}"
EXPECTED_JOB_PREFIX="repetly-telegram-linking-migrate-${EXPECTED_SHORT}"
IMAGE_REPOSITORY="ghcr.io/chotabyorg/repetly"
ZERO_DIGEST="sha256:0000000000000000000000000000000000000000000000000000000000000000"
TEST_CURRENT_DIGEST="sha256:1111111111111111111111111111111111111111111111111111111111111111"
TEST_TARGET_DIGEST="sha256:2222222222222222222222222222222222222222222222222222222222222222"

MODE="inert"
EXECUTION_STAGE=""
if [[ "$#" -eq 2 && "$1" == "--execution-stage" ]]; then
  MODE="execution"
  EXECUTION_STAGE="$2"
  case "${EXECUTION_STAGE}" in
    STOP | MIGRATE | RESUME-CLOSED | OPEN) ;;
    *)
      printf 'usage: %s [--execution-stage STOP|MIGRATE|RESUME-CLOSED|OPEN]\n' \
        "${0##*/}" >&2
      exit 64
      ;;
  esac
elif [[ "$#" -ne 0 ]]; then
  printf 'usage: %s [--execution-stage STOP|MIGRATE|RESUME-CLOSED|OPEN]\n' \
    "${0##*/}" >&2
  exit 64
fi

fail() {
  printf 'validation failed: %s\n' "$1" >&2
  exit 1
}

for command in kubectl git awk grep mktemp env cp mkdir mv rm sort tar ruby wc; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing command: ${command}"
done

required_files=(
  "${SCRIPT_DIR}/RUNBOOK.md"
  "${SCRIPT_DIR}/postflight.sql"
  "${GUARD}"
  "${STOP_DIR}/replicas-zero-patch.yaml"
  "${STOP_DIR}/service-traffic-closed-patch.yaml"
  "${MIGRATE_DIR}/migration-job.yaml"
  "${RESUME_CLOSED_DIR}/service-traffic-closed-patch.yaml"
  "${RELEASE_PATCH}"
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || fail "missing required file: ${file#"${REPO_ROOT}/"}"
done

[[ -x "${GUARD}" ]] || fail "SQL boolean guard is not executable"

read_job_identity() {
  local file="$1"

  ruby -ryaml - "${file}" "${EXPECTED_JOB_PREFIX}" <<'RUBY'
file, prefix = ARGV
document = YAML.load_file(file)
metadata = document.fetch("metadata")
name = metadata.fetch("name").to_s
attempt = metadata.fetch("annotations").fetch(
  "repetly.chota.by/migration-attempt"
).to_s
match = /\A#{Regexp.escape(prefix)}-a([1-9][0-9]*)\z/.match(name)
abort "unsafe release-specific migration Job name" unless match
abort "migration attempt annotation does not match Job-name suffix" \
  unless attempt == match[1]
puts "#{name}|#{attempt}"
RUBY
}

if ! job_identity="$(read_job_identity "${MIGRATE_DIR}/migration-job.yaml" 2>/dev/null)"; then
  fail "migration Job name and attempt annotation must form one safe release-specific identity"
fi
EXPECTED_JOB="${job_identity%%|*}"
EXPECTED_ATTEMPT="${job_identity##*|}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

next_attempt="$(ruby -e 'puts Integer(ARGV.fetch(0), 10) + 1' "${EXPECTED_ATTEMPT}")"
retry_job="${tmp_dir}/retry-migration-job.yaml"
ruby -ryaml - \
  "${MIGRATE_DIR}/migration-job.yaml" \
  "${retry_job}" \
  "${EXPECTED_JOB_PREFIX}" \
  "${next_attempt}" <<'RUBY'
source, destination, prefix, attempt = ARGV
document = YAML.load_file(source)
metadata = document.fetch("metadata")
metadata["name"] = "#{prefix}-a#{attempt}"
metadata.fetch("annotations")["repetly.chota.by/migration-attempt"] = attempt
File.write(destination, YAML.dump(document))
RUBY
retry_identity="$(read_job_identity "${retry_job}")" \
  || fail "validator rejected an atomically renamed release-specific retry Job"
RETRY_JOB="${retry_identity%%|*}"
RETRY_ATTEMPT="${retry_identity##*|}"
[[ "${RETRY_JOB}" != "${EXPECTED_JOB}" ]] \
  || fail "retry simulation reused the prior migration Job name"

append_list_entry() {
  local file="$1"
  local list_name="$2"
  local entry="$3"
  local next_file="${file}.next"

  awk -v list_name="${list_name}" -v entry="${entry}" '
    $0 == list_name ":" && !inserted {
      print
      print entry
      inserted = 1
      next
    }
    { print }
    END {
      if (!inserted) {
        exit 1
      }
    }
  ' "${file}" >"${next_file}" \
    || fail "could not add ${list_name} entry to temporary active kustomization"
  mv "${next_file}" "${file}"
}

pin_repetly_digest() {
  local file="$1"
  local digest="$2"
  local next_file="${file}.next"

  awk -v digest="${digest}" '
    function emit_digest() {
      if (in_repetly && !wrote_digest) {
        print "    digest: \"" digest "\""
        wrote_digest = 1
      }
    }
    /^images:$/ {
      in_images = 1
      print
      next
    }
    in_images && /^  - name: / {
      emit_digest()
      in_repetly = ($0 == "  - name: repetly")
      if (in_repetly) {
        found_repetly = 1
      }
      wrote_digest = 0
      print
      next
    }
    in_images && in_repetly && /^    (newTag|digest):/ {
      if (!wrote_digest) {
        print "    digest: \"" digest "\""
        wrote_digest = 1
      }
      next
    }
    in_images && /^[^ ]/ {
      emit_digest()
      in_images = 0
      in_repetly = 0
    }
    { print }
    END {
      emit_digest()
      if (!found_repetly) {
        exit 1
      }
    }
  ' "${file}" >"${next_file}" \
    || fail "could not pin the Repetly image digest in temporary active kustomization"
  mv "${next_file}" "${file}"
}

replace_zero_digest() {
  local file="$1"
  local digest="$2"
  local next_file="${file}.next"

  awk -v zero="${ZERO_DIGEST}" -v digest="${digest}" '
    {
      gsub(zero, digest)
      print
    }
  ' "${file}" >"${next_file}"
  mv "${next_file}" "${file}"
}

render_origin_main_baseline() {
  local checkout_root="${tmp_dir}/origin-main"

  mkdir -p "${checkout_root}"
  git -C "${REPO_ROOT}" archive origin/main -- \
    services/repetly/base services/repetly/prod \
    | tar -x -C "${checkout_root}"
  kubectl kustomize \
    "${checkout_root}/services/repetly/prod" \
    >"${tmp_dir}/origin-main.yaml"
}

validate_render_contract_raw() {
  local baseline="$1"
  local render="$2"
  local stage="$3"
  local expected_digest="$4"
  local expected_job="${5:-${EXPECTED_JOB}}"
  local expected_attempt="${6:-${EXPECTED_ATTEMPT}}"

  ruby -ryaml -rset - "${baseline}" "${render}" "${stage}" "${expected_digest}" \
    "${EXPECTED_COMMIT}" "${expected_job}" "${expected_attempt}" \
    "${IMAGE_REPOSITORY}" "${EXPECTED_JOB_PREFIX}" <<'RUBY'
baseline_path, render_path, stage, digest, commit, expected_job,
  expected_attempt, repository, expected_job_prefix = ARGV
expected_image = "#{repository}@#{digest}"
maintenance_key = "repetly.chota.by/maintenance-gate"
release_digest_key = "repetly.chota.by/application-image-digest"
release_commit_key = "repetly.chota.by/application-commit"
operation_key = "repetly.chota.by/operation"
operation_value = "secure-telegram-linking-migration"
attempt_key = "repetly.chota.by/migration-attempt"

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def resource_key(document)
  metadata = document.fetch("metadata")
  [
    document.fetch("apiVersion"),
    document.fetch("kind"),
    metadata.fetch("namespace", ""),
    metadata.fetch("name")
  ]
end

def load_inventory(path)
  inventory = {}
  YAML.load_stream(File.read(path)).compact.each do |document|
    raise "#{path}: every YAML document must be a mapping" unless document.is_a?(Hash)

    key = resource_key(document)
    raise "#{path}: duplicate resource #{key.join("/")}" if inventory.key?(key)

    inventory[key] = document
  end
  raise "#{path}: render is empty" if inventory.empty?

  inventory
end

def secure_migration_jobs!(
  inventory,
  path,
  expected_job_prefix,
  operation_key,
  operation_value,
  attempt_key
)
  jobs = inventory.each_with_object([]) do |(key, document), matches|
    next unless document["kind"] == "Job"

    metadata = document.fetch("metadata")
    annotations = metadata.fetch("annotations", {})
    next unless annotations[operation_key] == operation_value

    name = metadata.fetch("name").to_s
    attempt = annotations.fetch(attempt_key, "").to_s
    match = /\A#{Regexp.escape(expected_job_prefix)}-a([1-9][0-9]*)\z/.match(name)
    raise "#{path}: secure-linking Job has the wrong release prefix or attempt suffix" \
      unless match
    raise "#{path}: secure-linking Job name and attempt annotation differ" \
      unless attempt == match[1]

    matches << [key, document, Integer(attempt, 10)]
  end

  raise "#{path}: multiple secure-linking migration Jobs are forbidden" \
    if jobs.length > 1

  jobs
end

def exact_keys!(mapping, expected, path)
  raise "#{path} must be a mapping" unless mapping.is_a?(Hash)

  actual = mapping.keys.sort
  wanted = expected.sort
  return if actual == wanted

  raise "#{path} keys differ: expected #{wanted.inspect}, got #{actual.inspect}"
end

def assert_equal!(actual, expected, path)
  return if actual == expected

  raise "#{path} differs from the authorized stage contract"
end

def fetch_named!(items, name, path)
  raise "#{path} must be an array" unless items.is_a?(Array)

  matches = items.select { |item| item.is_a?(Hash) && item["name"] == name }
  raise "#{path} must contain exactly one #{name}" unless matches.length == 1

  matches.first
end

def validate_migration_job!(
  job,
  expected_job,
  expected_attempt,
  expected_image,
  digest,
  commit,
  maintenance_key
)
  exact_keys!(job, %w[apiVersion kind metadata spec], "migration Job")
  assert_equal!(job["apiVersion"], "batch/v1", "migration Job apiVersion")
  assert_equal!(job["kind"], "Job", "migration Job kind")

  metadata = job.fetch("metadata")
  exact_keys!(metadata, %w[annotations name namespace], "migration Job metadata")
  assert_equal!(metadata["name"], expected_job, "migration Job name")
  assert_equal!(metadata["namespace"], "prod", "migration Job namespace")
  expected_annotations = {
    "argocd.argoproj.io/sync-wave" => "3",
    "repetly.chota.by/operation" => "secure-telegram-linking-migration",
    "repetly.chota.by/migration-attempt" => expected_attempt,
    "repetly.chota.by/application-commit" => commit,
    "repetly.chota.by/application-image-digest" => digest
  }
  assert_equal!(
    metadata["annotations"],
    expected_annotations,
    "migration Job annotations (hooks and TTL are forbidden)"
  )

  spec = job.fetch("spec")
  exact_keys!(
    spec,
    %w[activeDeadlineSeconds backoffLimit template],
    "migration Job spec"
  )
  assert_equal!(spec["activeDeadlineSeconds"], 900, "migration Job deadline")
  assert_equal!(spec["backoffLimit"], 0, "migration Job backoffLimit")

  template = spec.fetch("template")
  exact_keys!(template, %w[metadata spec], "migration Job pod template")
  template_metadata = template.fetch("metadata")
  exact_keys!(template_metadata, %w[labels], "migration Job pod metadata")
  assert_equal!(
    template_metadata["labels"],
    { "app" => "repetly", "component" => "migration" },
    "migration Job pod labels"
  )
  raise "maintenance gate must not appear on migration pod labels" \
    if template_metadata["labels"].key?(maintenance_key)

  pod_spec = template.fetch("spec")
  exact_keys!(
    pod_spec,
    %w[
      automountServiceAccountToken containers imagePullSecrets restartPolicy
      securityContext volumes
    ],
    "migration Job pod spec"
  )
  assert_equal!(
    pod_spec["automountServiceAccountToken"],
    false,
    "migration Job service-account token mount"
  )
  assert_equal!(
    pod_spec["imagePullSecrets"],
    [{ "name" => "ghcr-pull-secret" }],
    "migration Job imagePullSecrets"
  )
  assert_equal!(pod_spec["restartPolicy"], "Never", "migration Job restartPolicy")
  assert_equal!(
    pod_spec["securityContext"],
    {
      "runAsNonRoot" => true,
      "runAsUser" => 1000,
      "runAsGroup" => 1000,
      "seccompProfile" => { "type" => "RuntimeDefault" }
    },
    "migration Job pod securityContext"
  )
  assert_equal!(
    pod_spec["volumes"],
    [{ "name" => "tmp", "emptyDir" => { "sizeLimit" => "16Mi" } }],
    "migration Job writable volume"
  )

  containers = pod_spec.fetch("containers")
  raise "migration Job must contain exactly one container" \
    unless containers.is_a?(Array) && containers.length == 1

  container = containers.first
  exact_keys!(
    container,
    %w[
      command env image imagePullPolicy name resources securityContext
      volumeMounts
    ],
    "migration Job container"
  )
  assert_equal!(container["name"], "migrate", "migration Job container name")
  assert_equal!(container["image"], expected_image, "migration Job image")
  assert_equal!(
    container["imagePullPolicy"],
    "Always",
    "migration Job imagePullPolicy"
  )
  assert_equal!(
    container["command"],
    ["node", "node_modules/prisma/build/index.js", "migrate", "deploy"],
    "migration Job command"
  )
  assert_equal!(
    container["env"],
    [
      { "name" => "HOME", "value" => "/tmp" },
      {
        "name" => "DATABASE_URL",
        "valueFrom" => {
          "secretKeyRef" => {
            "name" => "repetly-secret",
            "key" => "DATABASE_URL"
          }
        }
      }
    ],
    "migration Job environment (envFrom and extra Secret keys are forbidden)"
  )
  assert_equal!(
    container["resources"],
    {
      "requests" => { "cpu" => "50m", "memory" => "64Mi" },
      "limits" => { "cpu" => "500m", "memory" => "512Mi" }
    },
    "migration Job resources"
  )
  assert_equal!(
    container["securityContext"],
    {
      "allowPrivilegeEscalation" => false,
      "capabilities" => { "drop" => ["ALL"] },
      "readOnlyRootFilesystem" => true
    },
    "migration Job container securityContext"
  )
  assert_equal!(
    container["volumeMounts"],
    [{ "name" => "tmp", "mountPath" => "/tmp" }],
    "migration Job volumeMounts"
  )
end

baseline = load_inventory(baseline_path)
render = load_inventory(render_path)
service_key = ["v1", "Service", "prod", "repetly"]
deployment_key = ["apps/v1", "Deployment", "prod", "repetly"]
job_key = ["batch/v1", "Job", "prod", expected_job]
expected_job_match =
  /\A#{Regexp.escape(expected_job_prefix)}-a([1-9][0-9]*)\z/.match(expected_job)
raise "expected migration Job has the wrong release prefix or attempt suffix" \
  unless expected_job_match
raise "expected migration Job name and attempt annotation differ" \
  unless expected_attempt == expected_job_match[1]

baseline_secure_jobs = secure_migration_jobs!(
  baseline,
  baseline_path,
  expected_job_prefix,
  operation_key,
  operation_value,
  attempt_key
)
render_secure_jobs = secure_migration_jobs!(
  render,
  render_path,
  expected_job_prefix,
  operation_key,
  operation_value,
  attempt_key
)
prior_job = baseline_secure_jobs.first

baseline_service = baseline.fetch(service_key) {
  raise "baseline is missing Service/prod/repetly"
}
baseline_deployment = baseline.fetch(deployment_key) {
  raise "baseline is missing Deployment/prod/repetly"
}

expected_keys = baseline.keys.to_set
expected_keys.delete(prior_job[0]) if prior_job
if stage == "MIGRATE"
  if prior_job
    raise "retry migration attempt must increment the prior attempt by exactly one" \
      unless Integer(expected_attempt, 10) == prior_job[2] + 1
  else
    raise "initial migration attempt must be a1" \
      unless Integer(expected_attempt, 10) == 1
  end
  raise "MIGRATE must render exactly one secure-linking migration Job" \
    unless render_secure_jobs.length == 1 && render_secure_jobs.first[0] == job_key
  expected_keys.add(job_key)
else
  raise "#{stage} must not render a secure-linking migration Job" \
    unless render_secure_jobs.empty?
end
actual_keys = render.keys.to_set
unless actual_keys == expected_keys
  missing = (expected_keys - actual_keys).map { |key| key.join("/") }.sort
  unexpected = (actual_keys - expected_keys).map { |key| key.join("/") }.sort
  raise(
    "resource inventory differs; missing=#{missing.inspect}, " \
    "unexpected=#{unexpected.inspect}"
  )
end

authorized_keys = [service_key, deployment_key, job_key]
authorized_keys << prior_job[0] if prior_job
(expected_keys - authorized_keys).each do |key|
  assert_equal!(
    render.fetch(key),
    baseline.fetch(key),
    "non-Repetly resource #{key.join("/")}"
  )
end

expected_service = deep_copy(baseline_service)
expected_selector = { "app" => "repetly", "component" => "api" }
if %w[STOP MIGRATE RESUME-CLOSED].include?(stage)
  expected_selector[maintenance_key] = "closed"
end
expected_service.fetch("spec")["selector"] = expected_selector
assert_equal!(
  render.fetch(service_key),
  expected_service,
  "Service/prod/repetly"
)

expected_deployment = deep_copy(baseline_deployment)
expected_deployment.fetch("spec")["replicas"] = %w[STOP MIGRATE].include?(stage) ? 0 : 1
pod_template = expected_deployment.dig("spec", "template")
raise "baseline Repetly Deployment lacks pod template" unless pod_template.is_a?(Hash)
pod_labels = pod_template.dig("metadata", "labels")
raise "baseline Repetly Deployment lacks pod labels" unless pod_labels.is_a?(Hash)
pod_labels.delete(maintenance_key)

pod_spec = pod_template.fetch("spec")
fetch_named!(
  pod_spec.fetch("initContainers"),
  "repetly-migrations",
  "Repetly initContainers"
)["image"] = expected_image
fetch_named!(
  pod_spec.fetch("containers"),
  "repetly",
  "Repetly containers"
)["image"] = expected_image

deployment_annotations =
  (expected_deployment.dig("metadata", "annotations") || {}).dup
deployment_annotations.delete(release_digest_key)
deployment_annotations.delete(release_commit_key)
unless stage == "STOP"
  deployment_annotations[release_digest_key] = digest
  deployment_annotations[release_commit_key] = commit
end
expected_deployment.fetch("metadata")["annotations"] = deployment_annotations

actual_pod_labels = render.fetch(deployment_key).dig(
  "spec", "template", "metadata", "labels"
)
raise "maintenance gate must not appear on Repetly pod labels" \
  if actual_pod_labels.is_a?(Hash) && actual_pod_labels.key?(maintenance_key)
assert_equal!(
  render.fetch(deployment_key),
  expected_deployment,
  "Deployment/prod/repetly"
)

if stage == "MIGRATE"
  validate_migration_job!(
    render.fetch(job_key),
    expected_job,
    expected_attempt,
    expected_image,
    digest,
    commit,
    maintenance_key
  )
end
RUBY
}

validate_render_contract() {
  local baseline="$1"
  local render="$2"
  local stage="$3"
  local expected_digest="$4"

  validate_render_contract_raw \
    "${baseline}" "${render}" "${stage}" "${expected_digest}" \
    || fail "${stage} render changed resource inventory or violated its structural contract"
}

mutate_render_for_negative_test() {
  local source="$1"
  local destination="$2"
  local mutation="$3"
  local source_job="${4:-${EXPECTED_JOB}}"
  local replacement_job="${5:-}"
  local replacement_attempt="${6:-}"

  ruby -ryaml - \
    "${source}" \
    "${destination}" \
    "${mutation}" \
    "${source_job}" \
    "${replacement_job}" \
    "${replacement_attempt}" <<'RUBY'
source, destination, mutation, source_job, replacement_job,
  replacement_attempt = ARGV
documents = YAML.load_stream(File.read(source)).compact

case mutation
when "remove-critical-resource"
  documents.reject! do |document|
    document["kind"] == "PersistentVolumeClaim" &&
      document.dig("metadata", "name") == "repetly-postgres-data"
  end
when "wrong-service-selector"
  service = documents.find do |document|
    document["kind"] == "Service" &&
      document.dig("metadata", "name") == "repetly"
  end
  raise "negative test could not find Repetly Service" unless service
  service.fetch("spec").fetch("selector").delete("component")
when "unsafe-job"
  job = documents.find do |document|
    document["kind"] == "Job" &&
      document.dig("metadata", "name") == source_job
  end
  raise "negative test could not find migration Job" unless job
  job.fetch("metadata").fetch("annotations")["argocd.argoproj.io/hook"] = "Sync"
  job.fetch("spec")["ttlSecondsAfterFinished"] = 30
  job.dig("spec", "template", "spec", "containers").first["command"] = [
    "sh", "-c", "npx prisma migrate deploy"
  ]
when "retry-job-identity"
  job = documents.find do |document|
    document["kind"] == "Job" &&
      document.dig("metadata", "name") == source_job
  end
  raise "retry simulation could not find migration Job" unless job
  raise "retry simulation requires a replacement identity" \
    if replacement_job.empty? || replacement_attempt.empty?
  job.fetch("metadata")["name"] = replacement_job
  job.fetch("metadata").fetch("annotations")[
    "repetly.chota.by/migration-attempt"
  ] = replacement_attempt
when "duplicate-secure-job"
  job = documents.find do |document|
    document["kind"] == "Job" &&
      document.dig("metadata", "name") == source_job
  end
  raise "duplicate simulation could not find migration Job" unless job
  raise "duplicate simulation requires a replacement identity" \
    if replacement_job.empty? || replacement_attempt.empty?
  duplicate = Marshal.load(Marshal.dump(job))
  duplicate.fetch("metadata")["name"] = replacement_job
  duplicate.fetch("metadata").fetch("annotations")[
    "repetly.chota.by/migration-attempt"
  ] = replacement_attempt
  documents << duplicate
when "mismatched-job-identity"
  job = documents.find do |document|
    document["kind"] == "Job" &&
      document.dig("metadata", "name") == source_job
  end
  raise "mismatch simulation could not find migration Job" unless job
  raise "mismatch simulation requires a replacement attempt" \
    if replacement_attempt.empty?
  job.fetch("metadata").fetch("annotations")[
    "repetly.chota.by/migration-attempt"
  ] = replacement_attempt
else
  raise "unknown negative-test mutation: #{mutation}"
end

File.write(
  destination,
  documents.map { |document| YAML.dump(document) }.join
)
RUBY
}

prepare_inert_stage() {
  local stage="$1"
  local stage_root="${tmp_dir}/states/${stage}/repetly"
  local stage_prod="${stage_root}/prod"
  local stage_kustomization="${stage_prod}/kustomization.yaml"
  local digest="${TEST_TARGET_DIGEST}"

  mkdir -p "${stage_root}"
  cp -R "${REPETLY_DIR}/base" "${stage_root}/base"
  cp -R "${PROD_DIR}" "${stage_prod}"

  if [[ "${stage}" == "stop" ]]; then
    digest="${TEST_CURRENT_DIGEST}"
  fi
  pin_repetly_digest "${stage_kustomization}" "${digest}"

  case "${stage}" in
    stop)
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/stop/service-traffic-closed-patch.yaml'
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/stop/replicas-zero-patch.yaml'
      ;;
    migrate)
      replace_zero_digest \
        "${stage_prod}/operations/secure-telegram-linking/migrate/migration-job.yaml" \
        "${digest}"
      replace_zero_digest \
        "${stage_prod}/operations/secure-telegram-linking/release-identity-patch.yaml" \
        "${digest}"
      append_list_entry "${stage_kustomization}" resources \
        '  - operations/secure-telegram-linking/migrate/migration-job.yaml'
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/release-identity-patch.yaml'
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/stop/service-traffic-closed-patch.yaml'
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/stop/replicas-zero-patch.yaml'
      ;;
    resume-closed)
      replace_zero_digest \
        "${stage_prod}/operations/secure-telegram-linking/release-identity-patch.yaml" \
        "${digest}"
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/release-identity-patch.yaml'
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/resume-closed/service-traffic-closed-patch.yaml'
      ;;
    open)
      replace_zero_digest \
        "${stage_prod}/operations/secure-telegram-linking/release-identity-patch.yaml" \
        "${digest}"
      append_list_entry "${stage_kustomization}" patches \
        '  - path: operations/secure-telegram-linking/release-identity-patch.yaml'
      ;;
    *)
      fail "unknown inert stage: ${stage}"
      ;;
  esac

  kubectl kustomize "${stage_prod}" >"${tmp_dir}/${stage}.yaml"
}

if [[ "${MODE}" == "inert" ]]; then
  if grep -Eq 'operations/secure-telegram-linking|telegram-linking-migrate|maintenance-gate' \
    "${PROD_DIR}/kustomization.yaml"; then
    fail "active production kustomization references an operational resource"
  fi

  if ! git -C "${REPO_ROOT}" diff --quiet origin/main -- \
    services/repetly/prod \
    ':(exclude)services/repetly/prod/operations/**'; then
    fail "active production overlay differs from origin/main outside inert operations"
  fi

  grep -Fq "image: ${IMAGE_REPOSITORY}@${ZERO_DIGEST}" \
    "${MIGRATE_DIR}/migration-job.yaml" \
    || fail "inert migration Job must use the fail-closed zero-digest sentinel"
  [[ "$(grep -Fc "repetly.chota.by/application-image-digest: ${ZERO_DIGEST}" \
    "${MIGRATE_DIR}/migration-job.yaml")" == "1" ]] \
    || fail "inert migration Job annotation must use the zero-digest sentinel"
  [[ "$(grep -Fc "repetly.chota.by/application-image-digest: ${ZERO_DIGEST}" \
    "${RELEASE_PATCH}")" == "1" ]] \
    || fail "inert release patch must use the zero-digest sentinel"

  kubectl kustomize "${PROD_DIR}" >"${tmp_dir}/prod.yaml"
  prepare_inert_stage stop
  prepare_inert_stage migrate
  prepare_inert_stage resume-closed
  prepare_inert_stage open
else
  render_origin_main_baseline
  kubectl kustomize "${PROD_DIR}" >"${tmp_dir}/execution.yaml"
fi

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

deployment_images_for_repetly() {
  awk '
    /^kind: Deployment$/ { in_deployment = 1; name = ""; next }
    /^kind: / { in_deployment = 0 }
    in_deployment && /^  name: repetly$/ { name = "repetly" }
    in_deployment && name == "repetly" && /^        image: / {
      print $2
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

is_valid_nonzero_digest_image() {
  local image="$1"
  local digest

  case "${image}" in
    "${IMAGE_REPOSITORY}@sha256:"*) ;;
    *) return 1 ;;
  esac

  digest="${image#*@}"
  [[ "${digest}" != "${ZERO_DIGEST}" ]] \
    && printf '%s\n' "${digest}" | grep -Eq '^sha256:[0-9a-f]{64}$'
}

validate_deployment_images() {
  local stage="$1"
  local render="$2"
  local expected_image="$3"
  local images
  local image_count
  local unique_count
  local image

  images="$(deployment_images_for_repetly "${render}")"
  image_count="$(printf '%s\n' "${images}" | awk 'NF { count += 1 } END { print count + 0 }')"
  [[ "${image_count}" == "2" ]] \
    || fail "${stage} must render both Repetly Deployment containers"

  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    is_valid_nonzero_digest_image "${image}" \
      || fail "${stage} contains a tag-only, malformed, or zero-digest Deployment image"
    [[ "${image}" == "${expected_image}" ]] \
      || fail "${stage} Deployment containers must use the expected immutable digest"
  done <<EOF
${images}
EOF

  unique_count="$(
    printf '%s\n' "${images}" \
      | awk 'NF' \
      | sort -u \
      | wc -l \
      | awk '{ print $1 }'
  )"
  [[ "${unique_count}" == "1" ]] \
    || fail "${stage} Deployment init and application container digests differ"
}

validate_stage_render() {
  local stage="$1"
  local render="$2"
  local baseline="$3"
  local expected_digest="$4"
  local expected_image="${IMAGE_REPOSITORY}@${expected_digest}"
  local expected_replicas="1"
  local expected_release_count="1"
  local release_digest_count
  local release_commit_count
  local migration_image

  case "${stage}" in
    STOP)
      expected_replicas="0"
      expected_release_count="0"
      ;;
    MIGRATE)
      expected_replicas="0"
      ;;
    RESUME-CLOSED) ;;
    OPEN) ;;
    *)
      fail "unknown stage contract: ${stage}"
      ;;
  esac

  validate_render_contract \
    "${baseline}" "${render}" "${stage}" "${expected_digest}"

  [[ "$(replicas_for_repetly "${render}")" == "${expected_replicas}" ]] \
    || fail "${stage} rendered an unexpected Repetly replica count"

  validate_deployment_images "${stage}" "${render}" "${expected_image}"

  release_digest_count="$(
    grep -Fc "repetly.chota.by/application-image-digest: ${expected_digest}" \
      "${render}" || true
  )"
  release_commit_count="$(
    grep -Fc "repetly.chota.by/application-commit: ${EXPECTED_COMMIT}" \
      "${render}" || true
  )"

  if [[ "${stage}" == "MIGRATE" ]]; then
    [[ "$(grep -c '^kind: Job$' "${render}" || true)" == "2" ]] \
      || fail "MIGRATE must contain the existing MinIO hook and one migration Job"
    [[ "$(grep -c "^  name: ${EXPECTED_JOB}$" "${render}" || true)" == "1" ]] \
      || fail "MIGRATE must render exactly one release-specific migration Job"
    [[ "${release_digest_count}" == "2" ]] \
      || fail "MIGRATE Job and Deployment must record the exact same digest"
    [[ "${release_commit_count}" == "2" ]] \
      || fail "MIGRATE Job and Deployment must record the reviewed commit"
    grep -q "^  name: ${EXPECTED_JOB}$" "${render}" \
      || fail "MIGRATE must render the release-specific migration Job"
    migration_image="$(migration_job_image "${render}")"
    is_valid_nonzero_digest_image "${migration_image}" \
      || fail "MIGRATE contains a tag-only, malformed, or zero-digest Job image"
    [[ "${migration_image}" == "${expected_image}" ]] \
      || fail "MIGRATE Job and Deployment digests differ"
    [[ "$(resource_namespace Job "${EXPECTED_JOB}" "${render}")" == "prod" ]] \
      || fail "migration Job must render in namespace prod"
  else
    if grep -q "^  name: ${EXPECTED_JOB}$" "${render}"; then
      fail "${stage} must not render the migration Job"
    fi
    [[ "${release_digest_count}" == "${expected_release_count}" ]] \
      || fail "${stage} rendered an unexpected release-digest annotation count"
    [[ "${release_commit_count}" == "${expected_release_count}" ]] \
      || fail "${stage} rendered an unexpected release-commit annotation count"
  fi

  [[ "$(resource_namespace Service repetly "${render}")" == "prod" ]] \
    || fail "Repetly Service must render in namespace prod"
}

for invalid_image in \
  "${IMAGE_REPOSITORY}:6cb8a89" \
  "${IMAGE_REPOSITORY}:latest" \
  "${IMAGE_REPOSITORY}:main" \
  "${IMAGE_REPOSITORY}:6cb8a89@${TEST_TARGET_DIGEST}" \
  "${IMAGE_REPOSITORY}@${ZERO_DIGEST}" \
  "${IMAGE_REPOSITORY}@sha256:not-a-digest"; do
  if is_valid_nonzero_digest_image "${invalid_image}"; then
    fail "immutable-image validator accepted tag-only, mutable, mixed, zero, or malformed input"
  fi
done
is_valid_nonzero_digest_image "${IMAGE_REPOSITORY}@${TEST_TARGET_DIGEST}" \
  || fail "immutable-image validator rejected a canonical nonzero digest"

if [[ "${MODE}" == "inert" ]]; then
  [[ "$(replicas_for_repetly "${tmp_dir}/prod.yaml")" == "1" ]] \
    || fail "active production render must retain one replica"
  if grep -Eq "${EXPECTED_JOB}|repetly.chota.by/maintenance-gate: closed" \
    "${tmp_dir}/prod.yaml"; then
    fail "inert active production render unexpectedly contains maintenance resources"
  fi

  validate_stage_render \
    STOP "${tmp_dir}/stop.yaml" "${tmp_dir}/prod.yaml" "${TEST_CURRENT_DIGEST}"
  validate_stage_render \
    MIGRATE "${tmp_dir}/migrate.yaml" "${tmp_dir}/prod.yaml" "${TEST_TARGET_DIGEST}"
  validate_stage_render RESUME-CLOSED \
    "${tmp_dir}/resume-closed.yaml" "${tmp_dir}/prod.yaml" "${TEST_TARGET_DIGEST}"
  validate_stage_render \
    OPEN "${tmp_dir}/open.yaml" "${tmp_dir}/prod.yaml" "${TEST_TARGET_DIGEST}"

  mutate_render_for_negative_test \
    "${tmp_dir}/stop.yaml" \
    "${tmp_dir}/negative-missing-resource.yaml" \
    remove-critical-resource
  if validate_render_contract_raw \
    "${tmp_dir}/prod.yaml" \
    "${tmp_dir}/negative-missing-resource.yaml" \
    STOP \
    "${TEST_CURRENT_DIGEST}" \
    >/dev/null 2>&1; then
    fail "resource-inventory validator accepted a pruned PostgreSQL PVC"
  fi

  mutate_render_for_negative_test \
    "${tmp_dir}/stop.yaml" \
    "${tmp_dir}/negative-service-selector.yaml" \
    wrong-service-selector
  if validate_render_contract_raw \
    "${tmp_dir}/prod.yaml" \
    "${tmp_dir}/negative-service-selector.yaml" \
    STOP \
    "${TEST_CURRENT_DIGEST}" \
    >/dev/null 2>&1; then
    fail "Service validator accepted a missing component selector"
  fi

  mutate_render_for_negative_test \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-unsafe-job.yaml" \
    unsafe-job
  if validate_render_contract_raw \
    "${tmp_dir}/prod.yaml" \
    "${tmp_dir}/negative-unsafe-job.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    >/dev/null 2>&1; then
    fail "migration Job validator accepted a hook, TTL, or shell command"
  fi

  mutate_render_for_negative_test \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/retry-migrate.yaml" \
    retry-job-identity \
    "${EXPECTED_JOB}" \
    "${RETRY_JOB}" \
    "${RETRY_ATTEMPT}"
  validate_render_contract_raw \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/retry-migrate.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    "${RETRY_JOB}" \
    "${RETRY_ATTEMPT}" \
    || fail "validator rejected an exact aN to a(N+1) migration Job replacement"

  skipped_attempt="$(
    ruby -e 'puts Integer(ARGV.fetch(0), 10) + 2' "${EXPECTED_ATTEMPT}"
  )"
  skipped_job="${EXPECTED_JOB_PREFIX}-a${skipped_attempt}"
  mutate_render_for_negative_test \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-skipped-retry.yaml" \
    retry-job-identity \
    "${EXPECTED_JOB}" \
    "${skipped_job}" \
    "${skipped_attempt}"
  if validate_render_contract_raw \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-skipped-retry.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    "${skipped_job}" \
    "${skipped_attempt}" \
    >/dev/null 2>&1; then
    fail "retry validator accepted a skipped migration attempt"
  fi

  mutate_render_for_negative_test \
    "${tmp_dir}/retry-migrate.yaml" \
    "${tmp_dir}/negative-duplicate-retry.yaml" \
    duplicate-secure-job \
    "${RETRY_JOB}" \
    "${EXPECTED_JOB}" \
    "${EXPECTED_ATTEMPT}"
  if validate_render_contract_raw \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-duplicate-retry.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    "${RETRY_JOB}" \
    "${RETRY_ATTEMPT}" \
    >/dev/null 2>&1; then
    fail "retry validator accepted old and new secure-linking Jobs together"
  fi

  mutate_render_for_negative_test \
    "${tmp_dir}/retry-migrate.yaml" \
    "${tmp_dir}/negative-mismatched-retry.yaml" \
    mismatched-job-identity \
    "${RETRY_JOB}" \
    "" \
    "${skipped_attempt}"
  if validate_render_contract_raw \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-mismatched-retry.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    "${RETRY_JOB}" \
    "${RETRY_ATTEMPT}" \
    >/dev/null 2>&1; then
    fail "retry validator accepted a Job-name/attempt mismatch"
  fi

  wrong_prefix_job="repetly-telegram-linking-migrate-deadbee-a${RETRY_ATTEMPT}"
  mutate_render_for_negative_test \
    "${tmp_dir}/retry-migrate.yaml" \
    "${tmp_dir}/negative-wrong-prefix-retry.yaml" \
    retry-job-identity \
    "${RETRY_JOB}" \
    "${wrong_prefix_job}" \
    "${RETRY_ATTEMPT}"
  if validate_render_contract_raw \
    "${tmp_dir}/migrate.yaml" \
    "${tmp_dir}/negative-wrong-prefix-retry.yaml" \
    MIGRATE \
    "${TEST_TARGET_DIGEST}" \
    "${RETRY_JOB}" \
    "${RETRY_ATTEMPT}" \
    >/dev/null 2>&1; then
    fail "retry validator accepted a secure-linking Job for the wrong release"
  fi
else
  execution_image="$(
    deployment_images_for_repetly "${tmp_dir}/execution.yaml" \
      | awk 'NF { print; exit }'
  )"
  is_valid_nonzero_digest_image "${execution_image}" \
    || fail "${EXECUTION_STAGE} active Deployment must use a nonzero digest without a tag"
  execution_digest="${execution_image#*@}"
  validate_stage_render \
    "${EXECUTION_STAGE}" \
    "${tmp_dir}/execution.yaml" \
    "${tmp_dir}/origin-main.yaml" \
    "${execution_digest}"
fi

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
grep -q '^          imagePullPolicy: Always$' "${MIGRATE_DIR}/migration-job.yaml" \
  || fail "migration Job must always resolve its reviewed digest"
[[ "$(grep -Fc "repetly.chota.by/application-commit: ${EXPECTED_COMMIT}" \
  "${MIGRATE_DIR}/migration-job.yaml")" == "1" ]] \
  || fail "migration Job must record the reviewed application commit"
[[ "$(grep -Fc "repetly.chota.by/application-commit: ${EXPECTED_COMMIT}" \
  "${RELEASE_PATCH}")" == "1" ]] \
  || fail "release patch must record the reviewed application commit"

grep -q 'argocd.argoproj.io/hook: Sync' \
  "${PROD_DIR}/minio-bootstrap-job.yaml" \
  || fail "existing MinIO bootstrap must remain a Sync hook"
grep -q 'argocd.argoproj.io/sync-wave: "1"' \
  "${PROD_DIR}/minio-bootstrap-job.yaml" \
  || fail "existing MinIO bootstrap must remain at sync wave 1"
grep -q 'argocd.argoproj.io/sync-wave: "2"' \
  "${PROD_DIR}/repetly-deployment-wave-patch.yaml" \
  || fail "Repetly Deployment must remain at sync wave 2"
if ! grep -q 'planned downtime window' "${SCRIPT_DIR}/RUNBOOK.md" \
  || ! grep -q 'owner must' "${SCRIPT_DIR}/RUNBOOK.md"; then
  fail "runbook must require owner-approved planned downtime"
fi
grep -q 'MinIO hook fails, traffic' "${SCRIPT_DIR}/RUNBOOK.md" \
  || fail "runbook must document the MinIO hook failure boundary"

if grep -REq '(postgres(ql)?://[^[:space:]]+:[^[:space:]]+@|BEGIN (RSA |OPENSSH )?PRIVATE KEY|TELEGRAM_BOT_TOKEN[[:space:]]*:[[:space:]]*[^$])' \
  "${SCRIPT_DIR}"; then
  fail "possible plaintext secret in operational assets"
fi

psql() {
  local argument
  local app_schema=""
  local mode="query"

  for argument in "$@"; do
    [[ "${argument}" != *"://"* ]] \
      || return 90
    case "${argument}" in
      app_schema=*) app_schema="${argument#app_schema=}" ;;
      --command) mode="schema" ;;
    esac
  done

  [[ -n "${app_schema}" ]] || return 91
  [[ "${PGOPTIONS:-}" == "-c search_path=${app_schema},pg_catalog" ]] || return 92

  if [[ "${mode}" == "schema" ]]; then
    if [[ "${FAKE_PSQL_MISSING_SCHEMA:-}" == "${app_schema}" ]]; then
      printf 'f\n'
    else
      printf 't\n'
    fi
    return
  fi

  printf '%s\n' "${FAKE_PSQL_RESULT-f}"
}
export -f psql

if DATABASE_URL='postgresql://redacted-host/redacted-db?schema=public' \
  APP_DB_SCHEMA='reviewed_contract' PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-prisma-url.out" 2>"${tmp_dir}/guard-prisma-url.err"; then
  fail "boolean guard accepted Prisma DATABASE_URL"
fi

if env -u DATABASE_URL -u APP_DB_SCHEMA \
  PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-missing-schema-variable.out" \
  2>"${tmp_dir}/guard-missing-schema-variable.err"; then
  fail "boolean guard accepted a missing APP_DB_SCHEMA"
fi

for invalid_schema in \
  'Public' \
  'public.schema' \
  'public;reset role' \
  'pg_catalog' \
  'pg_reviewed' \
  'information_schema' \
  '-reviewed'; do
  if env -u DATABASE_URL APP_DB_SCHEMA="${invalid_schema}" \
    PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
    "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
    >"${tmp_dir}/guard-invalid-schema.out" \
    2>"${tmp_dir}/guard-invalid-schema.err"; then
    fail "boolean guard accepted an unsafe APP_DB_SCHEMA identifier"
  fi
done

if env -u DATABASE_URL APP_DB_SCHEMA='missing_reviewed_schema' \
  PGSERVICE='validator' FAKE_PSQL_MISSING_SCHEMA='missing_reviewed_schema' \
  FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-nonexistent-schema.out" \
  2>"${tmp_dir}/guard-nonexistent-schema.err"; then
  fail "boolean guard accepted a nonexistent application schema"
fi

if env -u DATABASE_URL APP_DB_SCHEMA='reviewed_contract' \
  PGSERVICE='validator' FAKE_PSQL_RESULT='7|f' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-false.out" 2>"${tmp_dir}/guard-false.err"; then
  fail "boolean guard accepted a false verdict"
fi
if grep -q '7' "${tmp_dir}/guard-false.out" "${tmp_dir}/guard-false.err"; then
  fail "boolean guard leaked query output on failure"
fi
env -u DATABASE_URL APP_DB_SCHEMA='reviewed_contract' \
  PGSERVICE='validator' FAKE_PSQL_RESULT='7|t' \
  "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
  >"${tmp_dir}/guard-true.out" 2>"${tmp_dir}/guard-true.err" \
  || fail "boolean guard rejected a true verdict"

for invalid_result in \
  '' \
  'garbage' \
  '7|1' \
  '7|true' \
  '7|t ' \
  '7|t|garbage' \
  $'7|t\n8|t' \
  $'7|t\ntrailing'; do
  if env -u DATABASE_URL APP_DB_SCHEMA='reviewed_contract' \
    PGSERVICE='validator' FAKE_PSQL_RESULT="${invalid_result}" \
    "${GUARD}" "${SCRIPT_DIR}/postflight.sql" \
    >"${tmp_dir}/guard-invalid.out" 2>"${tmp_dir}/guard-invalid.err"; then
    fail "boolean guard accepted a non-canonical or multirow verdict"
  fi
done

if [[ -n "${VALIDATION_OUTPUT_DIR:-}" ]]; then
  mkdir -p "${VALIDATION_OUTPUT_DIR}"
  if [[ "${MODE}" == "inert" ]]; then
    cp "${tmp_dir}/prod.yaml" "${VALIDATION_OUTPUT_DIR}/prod.yaml"
    cp "${tmp_dir}/stop.yaml" "${VALIDATION_OUTPUT_DIR}/stop.yaml"
    cp "${tmp_dir}/migrate.yaml" "${VALIDATION_OUTPUT_DIR}/migrate.yaml"
    cp "${tmp_dir}/resume-closed.yaml" \
      "${VALIDATION_OUTPUT_DIR}/resume-closed.yaml"
    cp "${tmp_dir}/open.yaml" "${VALIDATION_OUTPUT_DIR}/open.yaml"
  else
    cp "${tmp_dir}/execution.yaml" \
      "${VALIDATION_OUTPUT_DIR}/${EXECUTION_STAGE}.yaml"
  fi
fi

if [[ "${MODE}" == "inert" ]]; then
  printf 'PASS: inert exact-active-prod STOP/MIGRATE/RESUME-CLOSED/OPEN renders and guard simulations\n'
else
  printf 'PASS: exact active production %s contract\n' "${EXECUTION_STAGE}"
fi
