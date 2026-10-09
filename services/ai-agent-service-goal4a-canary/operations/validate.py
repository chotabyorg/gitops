"""Render-only validation for the NEW temporary AI topology, never live clearance."""

import argparse
import ipaddress
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import yaml

SERVICE = Path(__file__).resolve().parents[1]
AI_IMAGE = "ghcr.io/chotabyorg/ai-agent-service@sha256:5eba680cf018acf0f8062bbc1b0909e8c09ff157795e5a7f79ac4232a863ef4c"
NGINX_IMAGE = "docker.io/library/nginx@sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe"
PULL_SECRET = "ghcr-pull-secret"


def require(condition, code):
    if not condition:
        raise ValueError(code)


def properties(path):
    return dict(line.split("=",1) for line in path.read_text().splitlines() if line and not line.startswith("#"))


def fixture_tree(target):
    shutil.copytree(SERVICE / "base", target / "base")
    prod = target / "prod"
    prod.mkdir()
    for src,dest in (("config.properties","config.properties"),("guard.conf","guard.conf"),
                      ("kustomization.yaml.template","kustomization.yaml")):
        shutil.copy2(SERVICE/"release"/src,prod/dest)
    for src,dest in (("relay.conf.template","relay.conf"),("relay-network-policy.yaml.template","relay-network-policy.yaml")):
        (prod/dest).write_text((SERVICE/"release"/src).read_text().replace("${OPENROUTER_IPV4}","192.0.2.1"))
    shutil.copy2(SERVICE/"operations/role.py",prod/"role.py")
    (prod/"release-inputs.json").write_text('{"fixture":true}\n')
    for prefix,name,key in (("readonly","ai-goal4a-readonly-secret","POSTGRES_PASSWORD"),
                            ("managed","ai-goal4a-managed-secret","MANAGED_AI_AUTH_PRINCIPALS")):
        (prod/f"{prefix}-sealed-secret.yaml").write_text(yaml.safe_dump({
            "apiVersion":"bitnami.com/v1alpha1","kind":"SealedSecret",
            "metadata":{"name":name,"namespace":"prod","annotations":{
                "argocd.argoproj.io/sync-wave":"-6","goal4a.chota.by/fixture":"true"}},
            "spec":{"encryptedData":{key:"AgSYNTHETIC_SCHEMA_ONLY"},"template":{
                "metadata":{"name":name,"namespace":"prod"},"type":"Opaque"}}},sort_keys=False))
    return prod


def render(path):
    result=subprocess.run(["kubectl","kustomize",str(path)],capture_output=True,text=True)
    require(result.returncode==0,"RENDER_FAILED")
    return [v for v in yaml.safe_load_all(result.stdout) if v]


def validate(documents, fixture=False):
    require(all(d["metadata"].get("namespace")=="prod" for d in documents),"WRONG_NAMESPACE")
    require(all(d["kind"] in {"Deployment","Service","Job","ConfigMap","NetworkPolicy","SealedSecret"} for d in documents),"PUBLIC_OR_PLAINTEXT_RESOURCE")
    indexed={(d["kind"],d["metadata"]["name"]):d for d in documents}
    require(len(indexed)==len(documents),"DUPLICATE_RESOURCE")
    deps={d["metadata"]["name"]:d for d in documents if d["kind"]=="Deployment"}
    require(set(deps)=={"ai-agent-service-goal4a-canary","ai-agent-service-goal4a-llm-relay"},"DEPLOYMENT_SCOPE")
    jobs=[d for d in documents if d["kind"]=="Job"]
    require(len(jobs)==1 and jobs[0]["metadata"]["name"]=="goal4a-ai-readonly-provision-v2" and
            jobs[0]["spec"]["backoffLimit"]==0 and jobs[0]["spec"]["activeDeadlineSeconds"]==240 and
            "ttlSecondsAfterFinished" not in jobs[0]["spec"] and
            not any("hook" in key.lower() for key in jobs[0]["metadata"].get("annotations",{})),"FINITE_ORDINARY_JOB")
    configs={d["metadata"]["name"]:d["data"] for d in documents if d["kind"]=="ConfigMap"}
    seals={d["metadata"]["name"]:d for d in documents if d["kind"]=="SealedSecret"}
    require(set(seals)=={"ai-goal4a-readonly-secret","ai-goal4a-managed-secret"},"TEMPORARY_SECRET_SCOPE")
    for name,seal in seals.items():
        require(seal["spec"]["template"]["metadata"]["name"]==name and
                seal["spec"]["template"]["metadata"]["namespace"]=="prod" and
                seal["metadata"].get("annotations",{}).get("argocd.argoproj.io/sync-options","")=="" and
                not any(key in seal["metadata"].get("annotations",{}) for key in
                        ("sealedsecrets.bitnami.com/cluster-wide","sealedsecrets.bitnami.com/namespace-wide")),"STRICT_PRUNABLE_SEAL")
        require(fixture or ("goal4a.chota.by/fixture" not in seal["metadata"].get("annotations",{}) and
                all("SYNTHETIC" not in value for value in seal["spec"]["encryptedData"].values())),"FIXTURE_NOT_RELEASE")
        expected_key="POSTGRES_PASSWORD" if name=="ai-goal4a-readonly-secret" else "MANAGED_AI_AUTH_PRINCIPALS"
        require(set(seal["spec"]["encryptedData"])=={expected_key},"SECRET_KEY_SCOPE")
    all_pods=[d["spec"]["template"]["spec"] for d in list(deps.values())+jobs]
    for pod in all_pods:
        containers=pod.get("initContainers",[])+pod["containers"]
        expected_pull=[{"name":PULL_SECRET}] if any(c["image"]==AI_IMAGE for c in containers) else []
        require(pod.get("imagePullSecrets",[])==expected_pull,"EXACT_KUBELET_PULL_SECRET")
        require(PULL_SECRET not in json.dumps({key:pod.get(key,[]) for key in
                ("containers","initContainers","volumes")}),"REGISTRY_CREDENTIAL_IN_CONTAINER")
        require(not any(e["name"] in {"DOCKER_CONFIG","DOCKER_AUTH_CONFIG","REGISTRY_AUTH_FILE"}
                for c in containers for e in c.get("env",[])),"REGISTRY_CREDENTIAL_IN_CONTAINER")
        require(pod.get("automountServiceAccountToken") is False and not any(pod.get(k) for k in
                ("hostNetwork","hostPID","hostIPC","serviceAccountName")),"HOST_OR_API_AUTHORITY")
        require(pod["nodeSelector"]=={"kubernetes.io/hostname":"chota.by","kubernetes.io/arch":"amd64"},"PINNED_CACHE_NODE")
        require(pod["securityContext"]["runAsNonRoot"] is True and
                pod["securityContext"]["seccompProfile"]=={"type":"RuntimeDefault"},"POD_HARDENING")
        require(all(set(v)<= {"name","configMap","emptyDir"} and not v.get("hostPath") for v in pod["volumes"]),"SECRET_OR_HOST_MOUNT")
        for container in pod.get("initContainers",[])+pod["containers"]:
            require(container["image"] in {AI_IMAGE,NGINX_IMAGE} and container["imagePullPolicy"]=="IfNotPresent","EXACT_IMMUTABLE_IMAGE")
            s=container["securityContext"]
            require(s["allowPrivilegeEscalation"] is False and s["readOnlyRootFilesystem"] is True and
                    s["capabilities"]=={"drop":["ALL"]} and set(container["resources"])=={"requests","limits"},"CONTAINER_HARDENING")
            require(all("secretRef" not in ref for ref in container.get("envFrom",[])),"BROAD_SECRET_ENV")
            require(not any("hostPort" in port for port in container.get("ports",[])),"HOST_PORT")
            for ref in container.get("envFrom",[]):
                require(ref["configMapRef"]["name"] in configs,"MISSING_CONFIG")
    api=deps["ai-agent-service-goal4a-canary"]["spec"]["template"]["spec"]
    app=next(c for c in api["containers"] if c["name"]=="ai-agent-service")
    require(app["command"]==["uvicorn","main:app","--host","127.0.0.1","--port","8000","--no-access-log"],"LOOPBACK_NO_ACCESS_LOG")
    require({e["name"]:e["valueFrom"]["secretKeyRef"] for e in app["env"]}=={
        "POSTGRES_PASSWORD":{"name":"ai-goal4a-readonly-secret","key":"POSTGRES_PASSWORD"},
        "ENCRYPTION_KEY":{"name":"ai-agent-secret","key":"ENCRYPTION_KEY"},
        "MANAGED_AI_AUTH_PRINCIPALS":{"name":"ai-goal4a-managed-secret","key":"MANAGED_AI_AUTH_PRINCIPALS"}},"APP_SECRET_BARRIER")
    config=configs[app["envFrom"][0]["configMapRef"]["name"]]
    require(config==properties(SERVICE/"release/config.properties"),"EMPTY_RUNTIME_CONFIG")
    init=api["initContainers"]
    require(len(init)==1 and init[0]["command"]==["python","-I","-B","/operations/role.py","verify"] and
            len(init[0]["env"])==1 and init[0]["env"][0]["valueFrom"]["secretKeyRef"]=={
                "name":"ai-goal4a-readonly-secret","key":"POSTGRES_PASSWORD"},"READONLY_NO_MIGRATION")
    job=jobs[0]["spec"]["template"]["spec"]["containers"][0]
    require(job["command"]==["python","-I","-B","/operations/role.py","provision"] and
            {e["name"] for e in job["env"]}=={"POSTGRES_HOST","POSTGRES_PORT","ADMIN_POSTGRES_PASSWORD","POSTGRES_PASSWORD"} and
            next(e for e in job["env"] if e["name"]=="ADMIN_POSTGRES_PASSWORD")["valueFrom"]["secretKeyRef"]=={
                "name":"ai-agent-secret","key":"POSTGRES_PASSWORD"},"PRIVILEGED_JOB_SECRET_SCOPE")
    services=[d for d in documents if d["kind"]=="Service"]
    require(len(services)==2,"PRIVATE_SERVICE_COUNT")
    for svc in services:
        require(svc["spec"]["type"]=="ClusterIP" and not svc["spec"].get("externalIPs") and
                len(svc["spec"]["ports"])==1 and svc["spec"]["ports"][0]["port"]==8080 and
                "nodePort" not in svc["spec"]["ports"][0],"PRIVATE_SERVICE_ONLY")
        selected=[dep for dep in deps.values() if all(dep["spec"]["template"]["metadata"]["labels"].get(k)==v
                  for k,v in svc["spec"]["selector"].items())]
        require(len(selected)==1,"DISJOINT_SELECTORS")
    policies={d["metadata"]["name"]:d["spec"] for d in documents if d["kind"]=="NetworkPolicy"}
    require(set(policies)=={"goal4a-ai-canary","goal4a-ai-role-lifecycle","goal4a-ai-llm-relay"},"ALL_POLICIES_REQUIRED")
    base_policies={d["metadata"]["name"]:d["spec"] for d in yaml.safe_load_all((SERVICE/"base/network-policies.yaml").read_text())}
    require(all(policies[name]==spec for name,spec in base_policies.items()),"CANARY_ROLE_EGRESS_BOUNDARY")
    relay_policy=policies["goal4a-ai-llm-relay"]
    ip=ipaddress.ip_network(relay_policy["egress"][0]["to"][0]["ipBlock"]["cidr"])
    require(ip.version==4 and ip.prefixlen==32 and (fixture or ip.network_address.is_global),"FIXED_PUBLIC_IPV4_REQUIRED")
    expected=yaml.safe_load((SERVICE/"release/relay-network-policy.yaml.template").read_text().replace("${OPENROUTER_IPV4}",str(ip.network_address)))["spec"]
    require(relay_policy==expected,"FIXED_RELAY_POLICY")
    guard=next(c["nginx.conf"] for c in configs.values() if c.get("nginx.conf")== (SERVICE/"release/guard.conf").read_text())
    require(guard== (SERVICE/"release/guard.conf").read_text(),"GUARD_CONFIG")
    relay=(SERVICE/"release/relay.conf.template").read_text().replace("${OPENROUTER_IPV4}",str(ip.network_address))
    require(sum(c.get("nginx.conf")==relay for c in configs.values())==1,"FIXED_RELAY_CONFIG")
    operations=next(c for c in configs.values() if "role.py" in c)
    require(operations["role.py"]==(SERVICE/"operations/role.py").read_text(),"EXACT_LIFECYCLE_CODE")
    release=json.loads(operations["release-inputs.json"])
    require(fixture or release.get("fixture") is not True,"FIXTURE_INPUTS_NOT_RELEASE")
    if not fixture:
        import role
        with tempfile.NamedTemporaryFile(mode="w",suffix=".json") as handle:
            json.dump(release,handle); handle.flush(); role.inputs(handle.name)
    return {"status":"PASS_RENDER_ONLY_FIXTURE" if fixture else "PASS_RENDER_ONLY_MATERIALIZED",
            "resources":len(documents),"native_release_clearance":False}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--fixture",action="store_true")
    parser.add_argument("--prod",type=Path,default=SERVICE/"prod")
    args=parser.parse_args()
    if args.fixture:
        with tempfile.TemporaryDirectory(prefix="goal4a-canary-render-") as path:
            print(json.dumps(validate(render(fixture_tree(Path(path))),fixture=True)))
    else:
        print(json.dumps(validate(render(args.prod))))


if __name__=="__main__":
    main()
