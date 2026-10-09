"""Behavior-focused render failures for approved temporary boundaries."""

import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location("goal4a_canary_validate",Path(__file__).with_name("validate.py"))
validate=importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate)


class RenderBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="goal4a-render-tests-") as directory:
            cls.documents=validate.render(validate.fixture_tree(Path(directory)))

    def changed(self,kind,name):
        docs=copy.deepcopy(self.documents)
        resource=next(d for d in docs if d["kind"]==kind and d["metadata"]["name"]==name)
        return docs,resource

    def test_complete_fixture_is_only_render_proof(self):
        self.assertEqual(validate.validate(self.documents,fixture=True)["status"],"PASS_RENDER_ONLY_FIXTURE")
        with self.assertRaisesRegex(ValueError,"FIXTURE_NOT_RELEASE"):
            validate.validate(self.documents)

    def test_normal_business_secret_or_direct_app_bind_is_rejected(self):
        docs,dep=self.changed("Deployment","ai-agent-service-goal4a-canary")
        app=dep["spec"]["template"]["spec"]["containers"][0]
        app["envFrom"].append({"secretRef":{"name":"ai-agent-secret"}})
        with self.assertRaisesRegex(ValueError,"BROAD_SECRET_ENV"):
            validate.validate(docs,fixture=True)
        docs,dep=self.changed("Deployment","ai-agent-service-goal4a-canary")
        dep["spec"]["template"]["spec"]["containers"][0]["command"][3]="0.0.0.0"
        with self.assertRaisesRegex(ValueError,"LOOPBACK_NO_ACCESS_LOG"):
            validate.validate(docs,fixture=True)

    def test_public_service_and_direct_internet_egress_are_rejected(self):
        docs,svc=self.changed("Service","ai-agent-service-goal4a-canary")
        svc["spec"]["type"]="NodePort"
        with self.assertRaisesRegex(ValueError,"PRIVATE_SERVICE_ONLY"):
            validate.validate(docs,fixture=True)
        docs,policy=self.changed("NetworkPolicy","goal4a-ai-canary")
        policy["spec"]["egress"].append({"to":[{"ipBlock":{"cidr":"0.0.0.0/0"}}],"ports":[{"port":443,"protocol":"TCP"}]})
        with self.assertRaisesRegex(ValueError,"CANARY_ROLE_EGRESS_BOUNDARY"):
            validate.validate(docs,fixture=True)

    def test_role_job_cannot_receive_decryption_key_or_recreate_as_hook(self):
        docs,job=self.changed("Job","goal4a-ai-readonly-provision-v1")
        job["spec"]["template"]["spec"]["containers"][0]["env"].append({"name":"ENCRYPTION_KEY","valueFrom":{"secretKeyRef":{"name":"ai-agent-secret","key":"ENCRYPTION_KEY"}}})
        with self.assertRaisesRegex(ValueError,"PRIVILEGED_JOB_SECRET_SCOPE"):
            validate.validate(docs,fixture=True)
        docs,job=self.changed("Job","goal4a-ai-readonly-provision-v1")
        job["metadata"]["annotations"]["argocd.argoproj.io/hook"]="PostSync"
        with self.assertRaisesRegex(ValueError,"FINITE_ORDINARY_JOB"):
            validate.validate(docs,fixture=True)

    def test_temporary_credentials_cannot_be_clusterwide_or_retained(self):
        docs,seal=self.changed("SealedSecret","ai-goal4a-managed-secret")
        seal["metadata"]["annotations"]["sealedsecrets.bitnami.com/cluster-wide"]="true"
        with self.assertRaisesRegex(ValueError,"STRICT_PRUNABLE_SEAL"):
            validate.validate(docs,fixture=True)
        docs,seal=self.changed("SealedSecret","ai-goal4a-readonly-secret")
        seal["metadata"]["annotations"]["argocd.argoproj.io/sync-options"]="Prune=false,Delete=false"
        with self.assertRaisesRegex(ValueError,"STRICT_PRUNABLE_SEAL"):
            validate.validate(docs,fixture=True)


if __name__=="__main__":
    unittest.main(verbosity=2)
