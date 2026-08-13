#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

def documents(path)
  YAML.load_stream(File.read(path)).compact
rescue Psych::Exception => e
  abort "YAML parse failed for #{path}: #{e.message}"
end

def walk(value, &block)
  yield value
  case value
  when Hash
    value.each_value { |child| walk(child, &block) }
  when Array
    value.each { |child| walk(child, &block) }
  end
end

def rbac_inventory(docs, path)
  File.open(path, "w") do |out|
    docs.select { |doc| %w[ClusterRole ClusterRoleBinding Role RoleBinding].include?(doc["kind"]) }.each do |doc|
      metadata = doc.fetch("metadata", {})
      role_ref = doc.fetch("roleRef", {})
      subjects = doc.fetch("subjects", []).map { |s| "#{s["kind"]}:#{s["namespace"]}/#{s["name"]}" }.join(",")
      rules = doc.fetch("rules", []).map do |rule|
        resources = Array(rule["resources"]).join(",")
        verbs = Array(rule["verbs"]).join(",")
        api_groups = Array(rule["apiGroups"]).join(",")
        "#{api_groups}|#{resources}|#{verbs}"
      end.join(";")
      out.puts [
        doc["kind"],
        metadata["name"],
        "namespace=#{metadata["namespace"] || "<cluster>"}",
        "role=#{role_ref["kind"]}:#{role_ref["name"]}",
        "subjects=#{subjects}",
        "rules=#{rules}"
      ].join("\t")
    end
  end
end

def find_doc(docs, kind, name)
  docs.find { |doc| doc["kind"] == kind && doc.dig("metadata", "name") == name }
end

before_path, after_path, objectstore_path, policy_path, output_dir = ARGV
abort "usage: inspect-render.rb BEFORE AFTER OBJECTSTORE NETWORK_POLICY OUTPUT_DIR" unless output_dir

before = documents(before_path)
after = documents(after_path)
objectstore = documents(objectstore_path)
policies = documents(policy_path)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

rbac_inventory(before, File.join(output_dir, "rbac-before.txt"))
rbac_inventory(after, File.join(output_dir, "rbac-after.txt"))

before_binding = find_doc(before, "ClusterRoleBinding", "aistor-object-store-certificate-management")
abort "RED: before render did not contain the expected certificate-management binding" unless before_binding
abort "GREEN contract failure: certificate-management binding remains after optOut" if find_doc(after, "ClusterRoleBinding", "aistor-object-store-certificate-management")

certificate_role = find_doc(after, "ClusterRole", "aistor-certificate-management")
abort "GREEN contract failure: chart no longer renders the auditable certificate role" unless certificate_role
effective_certificate_binding = after.any? do |doc|
  doc["kind"] == "ClusterRoleBinding" && doc.dig("roleRef", "name") == "aistor-certificate-management"
end
abort "GREEN contract failure: certificate-management role is still effectively bound" if effective_certificate_binding

%w[aistor-object-store-cluster aistor-object-store-webhook-cluster].each do |name|
  abort "GREEN contract failure: missing required cluster binding #{name}" unless find_doc(after, "ClusterRoleBinding", name)
end

token_role = find_doc(after, "ClusterRole", "aistor-tokenreview")
abort "GREEN contract failure: TokenReview exception was not rendered" unless token_role
abort "GREEN contract failure: tokenreview role lost tokenreviews/create" unless token_role.fetch("rules", []).any? { |r| r["apiGroups"] == ["authentication.k8s.io"] && r["resources"] == ["tokenreviews"] && r["verbs"] == ["create"] }

operator = find_doc(after, "Deployment", "object-store-operator")
abort "GREEN contract failure: operator Deployment missing" unless operator
operator_env = operator.dig("spec", "template", "spec", "containers", 0, "env") || []
env = operator_env.to_h { |entry| [entry["name"], entry["value"]] }
abort "GREEN contract failure: WATCHED_NAMESPACES is not prod" unless env["WATCHED_NAMESPACES"] == "prod"
abort "GREEN contract failure: TOKEN_VALIDATION is not TokenReview" unless env["TOKEN_VALIDATION"] == "TokenReview"
abort "GREEN contract failure: operator autocert is not disabled" unless env["OPERATOR_AUTO_CERT_DISABLED"] == "on"
abort "GREEN contract failure: custom operator TLS Secret is not wired" unless env["OPERATOR_CUSTOM_TLS_SECRET_NAME"] == "object-store-operator-tls"

webhook = find_doc(after, "Deployment", "object-store-webhook")
abort "GREEN contract failure: admission webhook Deployment missing" unless webhook
webhook_env = webhook.dig("spec", "template", "spec", "containers", 0, "env") || []
webhook_env_map = webhook_env.to_h { |entry| [entry["name"], entry["value"]] }
abort "GREEN contract failure: custom admission webhook TLS Secret is not wired" unless webhook_env_map["WEBHOOK_CUSTOM_TLS_SECRET_NAME"] == "object-store-webhook-tls"
webhook_config = find_doc(after, "MutatingWebhookConfiguration", "object-store-operator-webhook")
abort "GREEN contract failure: webhook configuration missing" unless webhook_config
ca_bundle = webhook_config.dig("webhooks", 0, "clientConfig", "caBundle")
abort "GREEN contract failure: webhook caBundle is empty" if ca_bundle.to_s.empty?

store = objectstore.find { |doc| doc["kind"] == "ObjectStore" }
abort "GREEN contract failure: ObjectStore render missing" unless store
spec = store.fetch("spec")
pool = spec.fetch("pools").fetch(0)
abort "GREEN contract failure: ObjectStore image is not the approved immutable Zot tag" unless spec["image"] == "registry.chota.by/aistor/minio:aistor-minio-e8394b040720"
abort "GREEN contract failure: imagePullSecret missing" unless spec.dig("imagePullSecret", "name") == "aistor-zot-puller"
abort "GREEN contract failure: single-node pool contract changed" unless pool["servers"] == 1 && pool["volumesPerServer"] == 1
abort "GREEN contract failure: storage contract changed" unless pool.dig("volumeClaimTemplate", "spec", "storageClassName") == "local-path" && pool.dig("volumeClaimTemplate", "spec", "resources", "requests", "storage") == "10Gi"
abort "GREEN contract failure: amd64 node selector missing" unless pool.dig("nodeSelector", "kubernetes.io/arch") == "amd64"
abort "GREEN contract failure: server TLS is not custom/OOB" unless spec.dig("certificates", "disableAutoCert") == true && spec.dig("certificates", "server", 0, "name") == "repetly-aistor-green-tls"
abort "GREEN contract failure: MINIO_API_AUTO_BUMP is not off" unless Array(spec["env"]).any? { |entry| entry["name"] == "MINIO_API_AUTO_BUMP" && entry["value"] == "off" }

policy = policies.find { |doc| doc.dig("metadata", "name") == "repetly-aistor-green" }
abort "GREEN contract failure: ObjectStore NetworkPolicy missing" unless policy
ingress = Array(policy.dig("spec", "ingress"))
traefik_rule = ingress.any? do |rule|
  Array(rule["from"]).any? do |source|
    source.dig("namespaceSelector", "matchLabels", "kubernetes.io/metadata.name") == "kube-system" && source.dig("podSelector", "matchLabels", "app.kubernetes.io/name") == "traefik"
  end
end
abort "GREEN contract failure: final public S3 path is not allowed from the Traefik contract" unless traefik_rule
abort "GREEN contract failure: direct Repetly/scanner ingress remains after public endpoint decision" if ingress.any? { |rule| rule.to_s.include?("repetly-file-scanner") || rule.to_s.include?("\"app\"=>\"repetly\"") }

images = []
walk(after) { |value| images << value if value.is_a?(String) && (value.include?("/aistor/") || value.include?("quay.io/minio")) }
floating = images.uniq.reject { |image| image.include?("@sha256:") || image == "registry.chota.by/aistor/minio:aistor-minio-e8394b040720" }
abort "GREEN contract failure: floating/unapproved rendered images: #{floating.join(", ")}" unless floating.empty?

File.write(File.join(output_dir, "render-summary.md"), <<~MARKDOWN)
  # AIStor GREEN rendered contract

  - Operator chart: `aistor-operator` 5.11.3
  - ObjectStore chart: `aistor-objectstore` 1.0.17
  - Namespace/watch: `prod`
  - Certificate-management ClusterRoleBinding: absent after `optOutAutomaticCertificates: true`
  - Token validation: `TokenReview` (explicit bounded cluster-wide exception)
  - Operator upgrade TLS: custom `object-store-operator-tls`
  - Admission webhook TLS: custom `object-store-webhook-tls` with out-of-band CA bundle
  - ObjectStore server TLS: custom `repetly-aistor-green-tls`
  - S3 image: immutable Zot content tag `aistor-minio-e8394b040720`
  - S3 endpoint: `https://repetly-storage.chota.by` through Traefik
  - NetworkPolicy public ingress: kube-system Traefik label contract only

  ## Combined candidate scheduler budget

  | Metric | Existing recorded requests/limits | Added Zot + Operator + webhook + GREEN + sidecar | Combined recorded total |
  | --- | ---: | ---: | ---: |
  | CPU requests | 300m | 1050m | 1350m |
  | Memory requests | 396Mi | 1568Mi | 1964Mi |
  | Ephemeral requests | not recorded | 1000Mi (Operator + webhook) | not determinable |
  | CPU limits | 1 CPU | 2350m | 3350m |
  | Memory limits | 1194Mi | 2536Mi | 3730Mi |
  | Ephemeral limits | not recorded | 1000Mi (Operator + webhook) | not determinable |

  Kubernetes schedules an init container using the maximum of init-container
  requests and the app-container sum; `sidecar-init` is not double-counted
  when its request matches the sidecar contract.
MARKDOWN

puts "rendered_contract=PASS"
puts "rbac_before=#{File.join(output_dir, "rbac-before.txt")}"
puts "rbac_after=#{File.join(output_dir, "rbac-after.txt")}"
puts "render_summary=#{File.join(output_dir, "render-summary.md")}"
