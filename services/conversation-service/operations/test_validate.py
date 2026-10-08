"""Offline checks for stage-specific Website routing validation."""

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


if __name__ == "__main__":
    unittest.main()
