"""Render and offline regression checks for bounded Goal4A release contracts."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("goal4a_validate", Path(__file__).with_name("validate.py"))
validate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate)


class WebsiteRoutingStageTests(unittest.TestCase):
    def setUp(self):
        identity = json.loads((validate.SERVICE / "release" / "activation" / "routing-candidate.json").read_text())
        integration = identity["integration_id"]
        self.guard = {integration: identity["expected_agent_id"]}
        self.cohort = {integration: {
            "expected_agent_id": identity["expected_agent_id"],
            "mode": "SESSION_ALLOWLIST",
            "session_ids": [identity["technical_session_id"]],
        }}

    @staticmethod
    def documents(config):
        return [{"kind": "ConfigMap", "metadata": {"name": "website-gateway-config-test"}, "data": config}]

    def check(self, config, stage):
        validate.check_website(self.documents(config), stage)

    def test_dark_accepts_missing_or_explicit_empty_fields(self):
        for config in ({}, {"MANAGED_WEBSITE_GUARDED_INTEGRATIONS": "{}"},
                       {"MANAGED_WEBSITE_COHORTS": "{}"},
                       {"MANAGED_WEBSITE_GUARDED_INTEGRATIONS": "{}", "MANAGED_WEBSITE_COHORTS": "{}"}):
            with self.subTest(config=config):
                self.check(config, "dark")

    def test_dark_rejects_explicit_nonempty_guards_and_cohorts(self):
        for config, code in (
            ({"MANAGED_WEBSITE_GUARDED_INTEGRATIONS": json.dumps(self.guard)}, "RETAINED_GUARD_SCOPE"),
            ({"MANAGED_WEBSITE_COHORTS": json.dumps(self.cohort)}, "EXACT_TECHNICAL_COHORT_ONLY"),
        ):
            with self.subTest(code=code):
                with self.assertRaisesRegex(ValueError, f"^{code}$"):
                    self.check(config, "dark")

    def test_later_stages_require_both_explicit_fields(self):
        for stage in ("guarded", "worker", "canary", "rollback"):
            complete = {
                "MANAGED_WEBSITE_GUARDED_INTEGRATIONS": json.dumps(self.guard),
                "MANAGED_WEBSITE_COHORTS": json.dumps(self.cohort if stage == "canary" else {}),
            }
            for missing in (("MANAGED_WEBSITE_GUARDED_INTEGRATIONS",), ("MANAGED_WEBSITE_COHORTS",),
                            ("MANAGED_WEBSITE_GUARDED_INTEGRATIONS", "MANAGED_WEBSITE_COHORTS")):
                with self.subTest(stage=stage, missing=missing):
                    config = {key: value for key, value in complete.items() if key not in missing}
                    with self.assertRaisesRegex(ValueError, "^WEBSITE_ROUTING_FIELDS_REQUIRED$"):
                        self.check(config, stage)

    def test_later_stages_accept_exact_explicit_configuration(self):
        for stage in ("guarded", "worker", "canary", "rollback"):
            with self.subTest(stage=stage):
                self.check({
                    "MANAGED_WEBSITE_GUARDED_INTEGRATIONS": json.dumps(self.guard),
                    "MANAGED_WEBSITE_COHORTS": json.dumps(self.cohort if stage == "canary" else {}),
                }, stage)

    def test_later_stages_reject_removed_or_unrelated_guard(self):
        for stage in ("guarded", "worker", "canary", "rollback"):
            for guard in ({}, {**self.guard, "unrelated-integration": "unrelated-agent"}):
                with self.subTest(stage=stage, guard=guard):
                    with self.assertRaisesRegex(ValueError, "^RETAINED_GUARD_SCOPE$"):
                        self.check({
                            "MANAGED_WEBSITE_GUARDED_INTEGRATIONS": json.dumps(guard),
                            "MANAGED_WEBSITE_COHORTS": json.dumps(self.cohort if stage == "canary" else {}),
                        }, stage)

    def test_canary_rejects_integration_wide_cohort(self):
        cohort = copy.deepcopy(self.cohort)
        next(iter(cohort.values()))["mode"] = "INTEGRATION_ALL"
        with self.assertRaisesRegex(ValueError, "^EXACT_TECHNICAL_COHORT_ONLY$"):
            self.check({
                "MANAGED_WEBSITE_GUARDED_INTEGRATIONS": json.dumps(self.guard),
                "MANAGED_WEBSITE_COHORTS": json.dumps(cohort),
                }, "canary")


class PostgresStorageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rendered = validate.render(validate.REPO, "conversation-service")

    def setUp(self):
        self.documents = copy.deepcopy(self.rendered)
        deployments = {item["metadata"]["name"]: item for item in self.documents if item["kind"] == "Deployment"}
        self.postgres = deployments["conversation-service-postgres"]
        self.api = deployments["conversation-service"]
        self.pod = self.postgres["spec"]["template"]["spec"]
        self.container = self.pod["containers"][0]
        self.mount = next(item for item in self.container["volumeMounts"] if item["name"] == "postgres-data")

    def check(self):
        validate.check_postgres_storage(self.documents)

    def test_rendered_release_puts_pgdata_on_retained_pvc(self):
        self.check()

    def test_parent_mount_leaves_image_volume_uncovered(self):
        self.mount["mountPath"] = "/var/lib/postgresql"
        with self.assertRaisesRegex(ValueError, "^POSTGRES_IMAGE_VOLUME_MOUNT_REQUIRED$"):
            self.check()

    def test_subpath_or_readonly_mount_cannot_substitute_for_volume_root(self):
        for field, value in (("subPath", "data"), ("subPathExpr", "$(POD_NAME)"), ("readOnly", True)):
            with self.subTest(field=field):
                self.mount[field] = value
                with self.assertRaisesRegex(ValueError, "^POSTGRES_IMAGE_VOLUME_MOUNT_REQUIRED$"):
                    self.check()
                del self.mount[field]

    def test_pgdata_outside_retained_mount_is_rejected(self):
        config_name = self.container["envFrom"][0]["configMapRef"]["name"]
        config = next(item["data"] for item in self.documents if item["kind"] == "ConfigMap" and
                      item["metadata"]["name"] == config_name)
        config["PGDATA"] = "/var/lib/postgresql/pgdata"
        with self.assertRaisesRegex(ValueError, "^POSTGRES_PGDATA_ON_PVC_REQUIRED$"):
            self.check()

    def test_changed_pvc_reference_is_rejected(self):
        volume = next(item for item in self.pod["volumes"] if "persistentVolumeClaim" in item)
        volume["persistentVolumeClaim"]["claimName"] = "unrelated-data"
        with self.assertRaisesRegex(ValueError, "^POSTGRES_RETAINED_PVC_REQUIRED$"):
            self.check()

    def test_nonmatching_filesystem_group_is_rejected(self):
        self.pod["securityContext"]["fsGroup"] = 10001
        with self.assertRaisesRegex(ValueError, "^POSTGRES_PVC_OWNERSHIP_REQUIRED$"):
            self.check()

    def test_api_reinitialization_after_database_rollout_is_required(self):
        self.api["spec"]["template"]["metadata"]["annotations"].pop("goal4a.chota.by/postgres-storage-layout")
        with self.assertRaisesRegex(ValueError, "^STORAGE_API_REINITIALIZATION_REQUIRED$"):
            self.check()

    def test_api_migration_cannot_precede_database_wave(self):
        self.api["metadata"]["annotations"]["argocd.argoproj.io/sync-wave"] = "0"
        with self.assertRaisesRegex(ValueError, "^STORAGE_MIGRATION_WAVE_ORDER_REQUIRED$"):
            self.check()


if __name__ == "__main__":
    unittest.main()
