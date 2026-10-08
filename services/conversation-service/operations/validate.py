"""Render-only Goal4A release checks; fixtures never establish release readiness."""

import argparse
import copy
import json
from pathlib import Path
import re
import shutil
from string import Template
import subprocess
import tempfile

import yaml

SERVICE = Path(__file__).resolve().parents[1]
REPO = SERVICE.parents[1]
SERVICES = ("conversation-service", "website-gateway-service", "ai-agent-service", "control-plane-service")
DIGEST = re.compile(r"sha256:[0-9a-f]{64}$")
FULL_SHA = re.compile(r"[0-9a-f]{40}$")


def require(condition, code):
    if not condition:
        raise ValueError(code)


def properties(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines()
                if line and not line.startswith("#"))


def fixture_seal(template, path):
    source = yaml.safe_load(template.read_text())
    metadata = copy.deepcopy(source["metadata"])
    metadata.setdefault("annotations", {})["goal4a.chota.by/fixture"] = "true"
    document = {
        "apiVersion": "bitnami.com/v1alpha1", "kind": "SealedSecret", "metadata": metadata,
        "spec": {
            "encryptedData": {key: "AgSYNTHETICSCHEMAFIXTUREONLY" for key in source["stringData"]},
            "template": {"metadata": copy.deepcopy(source["metadata"]), "type": "Opaque"},
        },
    }
    path.write_text(yaml.safe_dump(document, sort_keys=False))


def fixture_tree(target):
    for name in SERVICES[1:]:
        shutil.copytree(REPO / "services" / name, target / "services" / name)
    destination = target / "services" / "conversation-service"
    shutil.copytree(SERVICE / "base", destination / "base")
    prod = destination / "prod"
    prod.mkdir()
    dark = SERVICE / "release" / "dark"
    for name in ("config.properties", "worker.properties", "postgres.properties", "migrate.py"):
        shutil.copy2(dark / name, prod / name)
    mapping = {
        "CONVERSATION_SOURCE_SHA": "a" * 40, "CONVERSATION_IMAGE_DIGEST": "sha256:" + "a" * 64,
        "POSTGRES_16_ALPINE_TAG": "16-alpine", "POSTGRES_16_ALPINE_DIGEST": "sha256:" + "b" * 64,
    }
    (prod / "kustomization.yaml").write_text(Template(
        (dark / "kustomization.yaml.template").read_text()).substitute(mapping))
    for prefix in ("database", "principals", "managed-ai"):
        fixture_seal(dark / f"{prefix}-secrets.yaml.template", prod / f"{prefix}-sealed-secret.yaml")
    for lane, service_name in (("website", SERVICES[1]), ("ai", SERVICES[2]), ("control-plane", SERVICES[3])):
        overlay = target / "services" / service_name / "prod"
        patch = "goal4a-deployment-patch.yaml"
        shutil.copy2(SERVICE / "release" / lane / "deployment-patch.yaml.template", overlay / patch)
        manifest = yaml.safe_load((overlay / "kustomization.yaml").read_text())
        manifest.setdefault("patches", []).append({"path": patch})
        if lane != "control-plane":
            fixture_seal(SERVICE / "release" / lane / "secrets.yaml.template", overlay / "goal4a-sealed-secret.yaml")
            manifest["resources"].append("goal4a-sealed-secret.yaml")
        (overlay / "kustomization.yaml").write_text(yaml.safe_dump(manifest, sort_keys=False))
    website = target / "services" / SERVICES[1] / "prod" / "config.properties"
    website.write_text(website.read_text().rstrip() + "\n" +
                       (SERVICE / "release" / "website" / "default-legacy-config.properties").read_text())


def render(root, service):
    result = subprocess.run(["kubectl", "kustomize", str(root / "services" / service / "prod")],
                            capture_output=True, text=True, check=False)
    require(result.returncode == 0, "RENDER_FAILED")
    documents = [item for item in yaml.safe_load_all(result.stdout) if item]
    require(all(item["metadata"].get("namespace") == "prod" for item in documents), "WRONG_NAMESPACE")
    require(all(item["kind"] != "Secret" for item in documents), "PLAINTEXT_SECRET_RESOURCE")
    identities = [(item["kind"], item["metadata"]["name"]) for item in documents]
    require(len(identities) == len(set(identities)), "DUPLICATE_RESOURCE")
    return documents


def check_conversation(documents, root, stage, fixture):
    deployments = {item["metadata"]["name"]: item for item in documents if item["kind"] == "Deployment"}
    api = deployments["conversation-service"]
    worker = deployments["conversation-service-worker"]
    postgres = deployments["conversation-service-postgres"]
    require(set(deployments) == {"conversation-service", "conversation-service-worker", "conversation-service-postgres"}, "UNEXPECTED_DEPLOYMENT")
    require(api["spec"]["replicas"] == postgres["spec"]["replicas"] == 1, "API_PG_REPLICA_SCOPE")
    require(worker["spec"]["replicas"] == (1 if stage in {"worker", "canary", "rollback"} else 0), "WORKER_STAGE")
    images = []
    for item in deployments.values():
        require(item["spec"]["strategy"]["type"] == "Recreate", "SERIAL_ROLLOUT_REQUIRED")
        pod = item["spec"]["template"]["spec"]
        require(pod.get("automountServiceAccountToken") is False, "SERVICE_ACCOUNT_TOKEN")
        require(not pod.get("hostNetwork") and not pod.get("hostPID") and not pod.get("hostIPC"), "HOST_NAMESPACE")
        require(pod["securityContext"]["runAsNonRoot"] is True, "ROOT_PROCESS")
        require(pod["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault", "SECCOMP")
        for container in pod.get("initContainers", []) + pod["containers"]:
            security = container["securityContext"]
            require(security["allowPrivilegeEscalation"] is False and security["readOnlyRootFilesystem"] is True
                    and security["capabilities"]["drop"] == ["ALL"], "CONTAINER_HARDENING")
            require(set(container["resources"]) == {"requests", "limits"}, "RESOURCES")
            images.append(container["image"])
            require(not any("hostPort" in port for port in container.get("ports", [])), "PUBLIC_HOST_PORT")
        for container in pod["containers"]:
            require(all(probe in container for probe in ("startupProbe", "livenessProbe", "readinessProbe")), "PROBES")
    require(all("@" in image and DIGEST.fullmatch(image.rsplit("@", 1)[1]) for image in images), "IMMUTABLE_IMAGE_REQUIRED")
    app_images = [image for image in images if "conversation-service" in image]
    require(len(set(app_images)) == 1 and FULL_SHA.fullmatch(app_images[0].split("@", 1)[0].rsplit(":", 1)[1]), "SAME_FULL_SHA_IMAGE_REQUIRED")
    require(":16" in postgres["spec"]["template"]["spec"]["containers"][0]["image"], "PG16_REQUIRED")
    require(api["spec"]["template"]["spec"]["securityContext"]["runAsUser"] == 10001 and
            worker["spec"]["template"]["spec"]["securityContext"]["runAsUser"] == 10001 and
            postgres["spec"]["template"]["spec"]["securityContext"]["runAsUser"] == 70, "IMAGE_UID_REQUIRED")
    init = api["spec"]["template"]["spec"]["initContainers"]
    require(len(init) == 1 and init[0]["command"] == ["python", "/migration/migrate.py"]
            and not worker["spec"]["template"]["spec"].get("initContainers"), "SINGLE_MIGRATION_AUTHORITY")
    require(api["spec"]["template"]["spec"]["containers"][0]["command"][-1] == "--no-access-log"
            and worker["spec"]["template"]["spec"]["containers"][0]["command"] == ["python", "worker.py"], "SOURCE_COMMANDS")
    require(all(item["kind"] in {"Deployment", "Service", "PersistentVolumeClaim", "ConfigMap", "SealedSecret", "NetworkPolicy"} for item in documents), "PUBLIC_OR_UNEXPECTED_RESOURCE")
    for item in documents:
        if item["kind"] == "Service":
            require(item["spec"]["type"] == "ClusterIP" and not item["spec"].get("externalIPs")
                    and all("nodePort" not in port for port in item["spec"]["ports"]), "PUBLIC_SERVICE")
            selector = item["spec"]["selector"]
            selected = [dep for dep in deployments.values() if all(
                dep["spec"]["template"]["metadata"]["labels"].get(key) == value for key, value in selector.items())]
            require(len(selected) == 1, "OVERLAPPING_SERVICE_SELECTOR")
        if item["kind"] in {"PersistentVolumeClaim", "SealedSecret"}:
            require(item["metadata"]["annotations"].get("argocd.argoproj.io/sync-options") == "Prune=false,Delete=false", "RETENTION")
        if item["kind"] == "SealedSecret":
            require(item["spec"]["template"]["metadata"]["name"] == item["metadata"]["name"]
                    and item["spec"]["template"]["metadata"]["namespace"] == "prod", "STRICT_SEAL_SCOPE")
            require(fixture or ("goal4a.chota.by/fixture" not in item["metadata"].get("annotations", {}) and
                    all("FIXTURE" not in value for value in item["spec"]["encryptedData"].values())), "SYNTHETIC_SEAL_BLOCKED")
    for dep in deployments.values():
        for container in dep["spec"]["template"]["spec"].get("initContainers", []) + dep["spec"]["template"]["spec"]["containers"]:
            for env in container.get("env", []):
                reference = env.get("valueFrom", {}).get("secretKeyRef")
                if reference:
                    seal = next((item for item in documents if item["kind"] == "SealedSecret" and
                                 item["metadata"]["name"] == reference["name"]), None)
                    require(seal is not None and reference["key"] in seal["spec"]["encryptedData"], "MISSING_SEALED_KEY")
            for reference in container.get("envFrom", []):
                config_ref = reference.get("configMapRef")
                if config_ref:
                    require(any(item["kind"] == "ConfigMap" and item["metadata"]["name"] == config_ref["name"]
                                for item in documents), "MISSING_CONFIG_REF")
    policies = {item["metadata"]["name"]: item["spec"] for item in documents if item["kind"] == "NetworkPolicy"}
    require(set(policies) == {"conversation-service-api", "conversation-service-worker", "conversation-service-postgres"}, "POLICIES_REQUIRED")
    require(policies["conversation-service-api"]["ingress"] == [{"from": [{"podSelector": {"matchLabels": {"app": "website-gateway-service"}}}], "ports": [{"protocol": "TCP", "port": 8000}]}], "API_INGRESS_BOUNDARY")
    require(policies["conversation-service-worker"]["ingress"] == [] and
            policies["conversation-service-postgres"]["egress"] == [], "WORKER_PG_BOUNDARY")
    postgres_ingress = policies["conversation-service-postgres"]["ingress"]
    require(postgres_ingress == [{"from": [
        {"podSelector": {"matchLabels": {"app": "conversation-service", "component": "api"}}},
        {"podSelector": {"matchLabels": {"app": "conversation-service", "component": "worker"}}}],
        "ports": [{"protocol": "TCP", "port": 5432}]}], "DATABASE_INGRESS_BOUNDARY")
    for name, policy in policies.items():
        require(policy["policyTypes"] == ["Ingress", "Egress"], "BOTH_POLICY_DIRECTIONS")
        require(policy["podSelector"]["matchLabels"] == {"app": "conversation-service", "component": name.rsplit("-", 1)[1]}, "POLICY_SELECTORS")
        for rule in policy.get("egress", []):
            for peer in rule["to"]:
                labels = peer.get("podSelector", {}).get("matchLabels", {})
                allowed = labels in ({"app": "conversation-service", "component": "postgres"}, {"app": "ai-agent-service", "component": "api"})
                dns = labels == {"k8s-app": "kube-dns"} and peer.get("namespaceSelector", {}).get("matchLabels") == {"kubernetes.io/metadata.name": "kube-system"}
                require(allowed or dns, "EGRESS_BOUNDARY")
                expected_ports = ([{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}] if dns else
                                  [{"protocol": "TCP", "port": 8000 if labels.get("app") == "ai-agent-service" else 5432}])
                require(rule["ports"] == expected_ports, "EGRESS_PORT_SCOPE")
    config = properties(root / "services" / SERVICES[0] / "prod" / "config.properties")
    work = properties(root / "services" / SERVICES[0] / "prod" / "worker.properties")
    require(config["WEBSITE_WORKER_ENABLED"] == "false", "API_PROCESSING_DISABLED")
    require(work["WEBSITE_WORKER_ENABLED"] == ("true" if stage in {"worker", "canary", "rollback"} else "false"), "WORKER_ENABLE_STAGE")
    bindings = json.loads(config["WEBSITE_BINDINGS"])
    identity = json.loads((SERVICE / "release" / "activation" / "routing-candidate.json").read_text())
    expected = [{"owner_id": identity["owner_id"], "integration_id": identity["integration_id"], "agent_id": identity["expected_agent_id"]}]
    require(bindings == ([] if stage == "dark" else expected), "EXACT_PROCESSING_SCOPE")


def check_website(documents, stage):
    config = next(item["data"] for item in documents if item["kind"] == "ConfigMap" and
                  item["metadata"]["name"].startswith("website-gateway-config-"))
    if stage != "dark":
        require(all(key in config for key in (
            "MANAGED_WEBSITE_GUARDED_INTEGRATIONS", "MANAGED_WEBSITE_COHORTS")),
            "WEBSITE_ROUTING_FIELDS_REQUIRED")
    # Dark precedes Website deployment; absent fields retain its legacy defaults.
    guards = json.loads(config.get("MANAGED_WEBSITE_GUARDED_INTEGRATIONS", "{}"))
    cohorts = json.loads(config.get("MANAGED_WEBSITE_COHORTS", "{}"))
    identity = json.loads((SERVICE / "release" / "activation" / "routing-candidate.json").read_text())
    integration = identity["integration_id"]
    expected_guard = {integration: identity["expected_agent_id"]}
    require(guards == ({} if stage == "dark" else expected_guard), "RETAINED_GUARD_SCOPE")
    expected_cohort = {integration: {"expected_agent_id": identity["expected_agent_id"], "mode": "SESSION_ALLOWLIST", "session_ids": [identity["technical_session_id"]]}}
    require(cohorts == (expected_cohort if stage == "canary" else {}), "EXACT_TECHNICAL_COHORT_ONLY")


def verify(root, stage, fixture, approval_record=None):
    if stage == "canary":
        require(approval_record is not None, "CANARY_APPROVAL_RECORD_REQUIRED")
        approval = json.loads(approval_record.read_text())
        identity = json.loads((SERVICE / "release" / "activation" / "routing-candidate.json").read_text())
        require(all(approval.get(key) is True for key in (
            "credential_binding_verified", "credential_logging_verified", "smoke_safety_approved",
            "exact_release_review_clean")), "CANARY_GATES_UNRESOLVED")
        require(all(approval.get(key) == identity[key] for key in (
            "owner_id", "integration_id", "expected_agent_id", "technical_session_id")), "CANARY_APPROVAL_SCOPE")
    rendered = {service: render(root, service) for service in SERVICES}
    check_conversation(rendered[SERVICES[0]], root, stage, fixture)
    check_website(rendered[SERVICES[1]], stage)
    ai = next(item for item in rendered[SERVICES[2]] if item["kind"] == "Deployment" and item["metadata"]["name"] == SERVICES[2])
    pod = ai["spec"]["template"]["spec"]
    require(any(container["name"] == "business-tls-client" for container in pod["containers"]), "AI_BUSINESS_SIDECAR_RETAINED")
    require(any(item["metadata"]["name"] == "ai-agent-mcp-credentials-backfill" for item in rendered[SERVICES[2]] if item["kind"] == "Job"), "AI_HOOK_RETAINED")
    for service in SERVICES:
        print(f"Rendered and checked {service}: {len(rendered[service])} resources")
    print("Fixture schema/render checks only; no real image or seal readiness." if fixture else
          "Source render checks passed; cryptographic/runtime/release gates remain separate.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", action="store_true")
    parser.add_argument("--stage", choices=("dark", "guarded", "worker", "canary", "rollback"), default="dark")
    parser.add_argument("--root", type=Path, default=REPO)
    parser.add_argument("--approval-record", type=Path)
    args = parser.parse_args()
    if args.fixture:
        require(args.stage == "dark", "FIXTURE_DARK_ONLY")
        with tempfile.TemporaryDirectory(prefix="goal4a-render-") as directory:
            target = Path(directory)
            fixture_tree(target)
            verify(target, args.stage, True)
    else:
        verify(args.root, args.stage, False, args.approval_record)


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(f"Goal4A validation blocked: {error}")
        raise SystemExit(1) from None
    except Exception:
        print("Goal4A validation blocked: incomplete or invalid release inputs")
        raise SystemExit(1) from None
