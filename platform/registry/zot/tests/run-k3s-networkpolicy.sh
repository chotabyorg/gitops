#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
CONTAINER="zot-networkpolicy-k3s"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.35.5-k3s1}"
KUBECONFIG_FILE="${RUNNER_TEMP:-/tmp}/zot-k3s.yaml"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  rm -f "${KUBECONFIG_FILE}"
}
trap cleanup EXIT

docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
docker run --privileged --detach --name "${CONTAINER}" \
  --publish 6446:6443 \
  "${K3S_IMAGE}" server \
  --disable=traefik \
  --disable=servicelb \
  --flannel-backend=host-gw \
  --write-kubeconfig-mode=644 >/dev/null

for _ in {1..90}; do
  if docker exec "${CONTAINER}" kubectl get nodes >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec "${CONTAINER}" kubectl get nodes >/dev/null
docker cp "${CONTAINER}:/etc/rancher/k3s/k3s.yaml" "${KUBECONFIG_FILE}"
sed -i 's#https://127.0.0.1:6443#https://127.0.0.1:6446#' "${KUBECONFIG_FILE}"
export KUBECONFIG="${KUBECONFIG_FILE}"

kubectl wait --for=condition=Ready node --all --timeout=120s
for _ in {1..60}; do
  if kubectl -n kube-system get deployment coredns >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl -n kube-system rollout status deployment/coredns --timeout=120s
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace np-forbidden --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_ROOT}/platform/registry/zot/zot-network-policy.yaml.template"

kubectl -n registry apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: zot-synthetic
  labels:
    app.kubernetes.io/name: zot
    app.kubernetes.io/component: registry
spec:
  containers:
    - name: server
      image: busybox:1.36.1
      command: ["sh", "-ec", "mkdir -p /www; printf synthetic-zot > /www/index.html; httpd -f -p 5000 -h /www"]
      ports:
        - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: zot-synthetic
spec:
  selector:
    app.kubernetes.io/name: zot
    app.kubernetes.io/component: registry
  ports:
    - port: 5000
      targetPort: 5000
YAML

kubectl -n kube-system run traefik-synthetic --image=busybox:1.36.1 \
  --labels='app.kubernetes.io/name=traefik' --command -- sleep 300
kubectl -n np-forbidden run forbidden-synthetic --image=busybox:1.36.1 \
  --labels='app=forbidden' --command -- sleep 300
kubectl wait --for=condition=Ready pod/zot-synthetic -n registry --timeout=120s
kubectl wait --for=condition=Ready pod/traefik-synthetic -n kube-system --timeout=120s
kubectl wait --for=condition=Ready pod/forbidden-synthetic -n np-forbidden --timeout=120s

kubectl exec -n kube-system traefik-synthetic -- \
  wget -q -T 8 -O - http://zot-synthetic.registry.svc.cluster.local:5000/ | grep -Fx synthetic-zot
if kubectl exec -n np-forbidden forbidden-synthetic -- \
  wget -q -T 8 -O - http://zot-synthetic.registry.svc.cluster.local:5000/ >/dev/null 2>&1; then
  echo "expected forbidden Zot ingress to be denied" >&2
  exit 1
fi

kubectl exec -n registry zot-synthetic -- nslookup kubernetes.default.svc.cluster.local
if kubectl exec -n registry zot-synthetic -- nc -z -w 3 kubernetes.default.svc 443 >/dev/null 2>&1; then
  echo "expected unnecessary Zot egress to the Kubernetes API Service to be denied" >&2
  exit 1
fi

echo "networkpolicy_controller=k3s-embedded-kube-router"
echo "networkpolicy_enforcement=PASS"
