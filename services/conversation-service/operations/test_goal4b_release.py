"""Offline production-render regression checks for the DARK Goal4B foundation.

Requires kubectl's embedded Kustomize and PyYAML, as does validate.py. This suite
does not contact Kubernetes, decrypt credentials, or establish activation approval.
GOAL4B_RELEASE_ROOT may point at another checkout for a before-fix regression run.
"""

import json
import os
from pathlib import Path
import subprocess
import unittest

import yaml


REPO = Path(os.environ.get("GOAL4B_RELEASE_ROOT", Path(__file__).resolve().parents[3]))
WEBSITE_SELECTOR = {"matchLabels": {"app": "conversation-service", "component": "worker"}}
TELEGRAM_SELECTOR = {
    "matchLabels": {"app": "conversation-service", "component": "telegram-worker"}
}
CONVERSATION_IMAGE = (
    "ghcr.io/chotabyorg/conversation-service:"
    "d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3@"
    "sha256:a37fc3344e78664fe861a793393e8dbbe0cdf1268e376965a7a3038ce9274a38"
)
TELEGRAM_IMAGE = (
    "ghcr.io/chotabyorg/telegram-gateway-service:4ee10d9@"
    "sha256:c59533541dd0147feea4fe26e94cbbf67977c6a99f19c5076bc225355d294f7a"
)


def matches(selector, labels):
    """Kubernetes LabelSelector semantics, including set-based requirements."""
    if any(labels.get(key) != value for key, value in selector.get("matchLabels", {}).items()):
        return False
    for requirement in selector.get("matchExpressions", []):
        key, operator = requirement["key"], requirement["operator"]
        values = requirement.get("values", [])
        if operator == "In":
            accepted = key in labels and labels[key] in values
        elif operator == "NotIn":
            accepted = key not in labels or labels[key] not in values
        elif operator == "Exists":
            accepted = key in labels
        elif operator == "DoesNotExist":
            accepted = key not in labels
        else:
            raise AssertionError("Unsupported Kubernetes selector operator")
        if not accepted:
            return False
    return True


def render(service):
    result = subprocess.run(
        ["kubectl", "kustomize", str(REPO / "services" / service / "prod")],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        # Never include renderer payloads, encrypted data, or configuration values.
        raise AssertionError(f"Production render failed for {service}")
    documents = [item for item in yaml.safe_load_all(result.stdout) if item]
    for document in documents:
        if document["kind"] == "Secret":
            raise AssertionError("Plaintext Secret resource is outside this release")
        if document["kind"] == "SealedSecret":
            # Keep only key names for reference/override checks, never ciphertext.
            document["secret_key_names"] = set(document["spec"].get("encryptedData", {}))
            document.pop("spec")
    return documents


def resource(documents, kind, name):
    return next(item for item in documents
                if item["kind"] == kind and item["metadata"]["name"] == name)


def environment(documents, container):
    configmaps = {d["metadata"]["name"]: d.get("data", {}) for d in documents
                  if d["kind"] == "ConfigMap"}
    secrets = {d["metadata"]["name"]: d["secret_key_names"] for d in documents
               if d["kind"] == "SealedSecret"}
    values = {}
    for source in container.get("envFrom", []):
        prefix = source.get("prefix", "")
        if "configMapRef" in source:
            values.update({prefix + k: v for k, v in
                           configmaps[source["configMapRef"]["name"]].items()})
        if "secretRef" in source:
            values.update({prefix + k: "<secret-reference>" for k in
                           secrets[source["secretRef"]["name"]]})
    for entry in container.get("env", []):
        values[entry["name"]] = entry.get("value", "<secret-reference>")
    return values


class Goal4BProductionRenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conversation = render("conversation-service")
        cls.gateway = render("telegram-gateway-service")
        cls.website = resource(cls.conversation, "Deployment", "conversation-service-worker")
        cls.telegram = resource(cls.conversation, "Deployment", "conversation-service-telegram-worker")

    def test_website_selector_preserved_and_telegram_scope_is_distinct(self):
        self.assertEqual(self.website["spec"]["selector"], WEBSITE_SELECTOR)
        self.assertEqual(self.telegram["spec"]["selector"], TELEGRAM_SELECTOR)

    def test_neither_worker_pod_matches_the_other_deployment_selector(self):
        for owner, other in [(self.website, self.telegram), (self.telegram, self.website)]:
            with self.subTest(owner=owner["metadata"]["name"]):
                self.assertFalse(matches(owner["spec"]["selector"],
                                         other["spec"]["template"]["metadata"]["labels"]))

    def test_deployment_selectors_match_their_own_pod_templates(self):
        for deployment in self.conversation + self.gateway:
            if deployment["kind"] != "Deployment":
                continue
            with self.subTest(deployment=deployment["metadata"]["name"]):
                self.assertEqual(deployment["apiVersion"], "apps/v1")
                selector = deployment["spec"]["selector"]
                self.assertTrue(selector.get("matchLabels") or selector.get("matchExpressions"))
                self.assertTrue(matches(selector,
                                        deployment["spec"]["template"]["metadata"]["labels"]))

    def test_dark_gates_and_goal5_boundary(self):
        self.assertEqual(self.telegram["spec"]["replicas"], 0)
        api = resource(self.conversation, "Deployment", "conversation-service")
        gateway = resource(self.gateway, "Deployment", "telegram-gateway-service")
        api_env = environment(self.conversation, api["spec"]["template"]["spec"]["containers"][0])
        worker_env = environment(self.conversation, self.telegram["spec"]["template"]["spec"]["containers"][0])
        gateway_env = environment(self.gateway, gateway["spec"]["template"]["spec"]["containers"][0])
        self.assertEqual(worker_env["TELEGRAM_WORKER_ENABLED"].lower(), "false")
        self.assertEqual(json.loads(api_env["TELEGRAM_CANARY_INTEGRATION_IDS"]), [])
        self.assertEqual(json.loads(worker_env["TELEGRAM_CANARY_INTEGRATION_IDS"]), [])
        self.assertEqual(json.loads(gateway_env["TELEGRAM_CANARY_INTEGRATION_IDS"]), [])
        self.assertEqual(json.loads(gateway_env["TELEGRAM_MANAGED_BINDINGS"]), [])
        self.assertEqual(gateway_env["CONVERSATION_SERVICE_URL"], "http://conversation-service:8000")
        self.assertNotIn("CONVERSATION_SERVICE_TOKEN", gateway_env)
        self.assertNotIn("TELEGRAM_WORKER_PRINCIPAL_ID", worker_env)
        for documents in [self.conversation, self.gateway]:
            for document in documents:
                if document["kind"] == "Deployment":
                    pod = document["spec"]["template"]["spec"]
                    for container in pod["containers"] + pod.get("initContainers", []):
                        self.assertNotIn("TURN_SETTLING_POLICIES", environment(documents, container))
                if document["kind"] == "ConfigMap":
                    self.assertNotIn("TURN_SETTLING_POLICIES", document.get("data", {}))
                    self.assertFalse(any("TOKEN" in key or "PASSWORD" in key or
                                         "AUTH_PRINCIPALS" in key
                                         for key in document.get("data", {})))

    def test_exact_reviewed_images_and_worker_runtime_contract(self):
        for deployment in self.conversation:
            if deployment["kind"] != "Deployment" or deployment["metadata"]["name"].endswith("postgres"):
                continue
            pod = deployment["spec"]["template"]["spec"]
            for container in pod["containers"] + pod.get("initContainers", []):
                self.assertEqual(container["image"], CONVERSATION_IMAGE)
        gateway = resource(self.gateway, "Deployment", "telegram-gateway-service")
        self.assertEqual(gateway["spec"]["template"]["spec"]["containers"][0]["image"], TELEGRAM_IMAGE)
        pod = self.telegram["spec"]["template"]["spec"]
        container = pod["containers"][0]
        self.assertEqual(container["command"], ["python", "telegram_worker.py"])
        self.assertEqual(container["ports"], [{"name": "health", "containerPort": 8002}])
        self.assertFalse(pod["automountServiceAccountToken"])
        self.assertTrue(pod["securityContext"]["runAsNonRoot"])
        self.assertEqual(pod["securityContext"]["runAsUser"], 10001)
        self.assertEqual(pod["securityContext"]["seccompProfile"], {"type": "RuntimeDefault"})
        self.assertFalse(container["securityContext"]["allowPrivilegeEscalation"])
        self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
        self.assertEqual(container["securityContext"]["capabilities"]["drop"], ["ALL"])
        for probe, path in [("startupProbe", "/health"), ("livenessProbe", "/health"),
                            ("readinessProbe", "/ready")]:
            self.assertEqual(container[probe]["httpGet"], {"path": path, "port": "health"})
        for entry in container["env"]:
            reference = entry["valueFrom"]["secretKeyRef"]
            seal = resource(self.conversation, "SealedSecret", reference["name"])
            self.assertIn(reference["key"], seal["secret_key_names"])

    def test_services_and_network_policies_select_only_intended_components(self):
        website_labels = self.website["spec"]["template"]["metadata"]["labels"]
        telegram_labels = self.telegram["spec"]["template"]["metadata"]["labels"]
        for service in [d for d in self.conversation if d["kind"] == "Service"]:
            selector = {"matchLabels": service["spec"]["selector"]}
            self.assertFalse(matches(selector, website_labels))
            self.assertFalse(matches(selector, telegram_labels))
        website_policy = resource(self.conversation, "NetworkPolicy", "conversation-service-worker")["spec"]
        telegram_policy = resource(self.conversation, "NetworkPolicy", "conversation-service-telegram-worker")["spec"]
        self.assertEqual(website_policy["podSelector"], WEBSITE_SELECTOR)
        self.assertEqual(telegram_policy["podSelector"], TELEGRAM_SELECTOR)
        self.assertFalse(matches(website_policy["podSelector"], telegram_labels))
        self.assertFalse(matches(telegram_policy["podSelector"], website_labels))
        self.assertEqual(telegram_policy["policyTypes"], ["Ingress", "Egress"])
        self.assertEqual(telegram_policy["ingress"], [])
        self.assertEqual(telegram_policy["egress"], website_policy["egress"])
        self.assertEqual(len(telegram_policy["egress"]), 3)
        api = resource(self.conversation, "NetworkPolicy", "conversation-service-api")["spec"]
        self.assertEqual(api["ingress"], [{
            "from": [{"podSelector": {"matchLabels": {"app": "website-gateway-service"}}},
                     {"podSelector": {"matchLabels": {"app": "telegram-gateway-service"}}}],
            "ports": [{"protocol": "TCP", "port": 8000}],
        }])
        postgres = resource(self.conversation, "NetworkPolicy", "conversation-service-postgres")["spec"]
        self.assertEqual(postgres["ingress"], [{
            "from": [{"podSelector": {"matchLabels": {"app": "conversation-service", "component": role}}}
                     for role in ["api", "worker", "telegram-worker"]],
            "ports": [{"protocol": "TCP", "port": 5432}],
        }])


if __name__ == "__main__":
    unittest.main()
