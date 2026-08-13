#!/usr/bin/env bash
set -Eeuo pipefail

RENDERED_OPERATOR="${1:?usage: $0 /path/to/operator-rendered.yaml}"
CONTAINER="aistor-webhook-tls-k3s"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.35.5-k3s1@sha256:2074403abe1bded11ef3dde09d457e13be8e0b64c218b1c4f8269b4565cfbc65}"
KUBECONFIG_FILE="${RUNNER_TEMP:-/tmp}/aistor-webhook-tls-k3s.yaml"
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/aistor-webhook-tls.XXXXXX")"

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  rm -f "${KUBECONFIG_FILE}"
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

[[ -s "${RENDERED_OPERATOR}" ]]

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${WORK_DIR}/ca.key" \
  -out "${WORK_DIR}/ca.crt" \
  -days 1 \
  -subj "/CN=AIStor disposable webhook test CA" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes \
  -keyout "${WORK_DIR}/webhook.key" \
  -out "${WORK_DIR}/webhook.csr" \
  -subj "/CN=object-store-webhook.prod.svc.cluster.local" >/dev/null 2>&1
cat > "${WORK_DIR}/webhook.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:object-store-webhook,DNS:object-store-webhook.prod.svc,DNS:object-store-webhook.prod.svc.cluster.local
EOF
openssl x509 -req \
  -in "${WORK_DIR}/webhook.csr" \
  -CA "${WORK_DIR}/ca.crt" \
  -CAkey "${WORK_DIR}/ca.key" \
  -CAcreateserial \
  -out "${WORK_DIR}/webhook.crt" \
  -days 1 \
  -extfile "${WORK_DIR}/webhook.ext" >/dev/null 2>&1

docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
docker run --privileged --detach --name "${CONTAINER}" \
  --publish 6447:6443 \
  "${K3S_IMAGE}" server \
  --disable=traefik \
  --disable=servicelb \
  --flannel-backend=host-gw \
  --write-kubeconfig-mode=644 >/dev/null

for _ in {1..90}; do
  if docker exec "${CONTAINER}" kubectl get nodes --no-headers 2>/dev/null | grep -q .; then
    break
  fi
  sleep 2
done
docker exec "${CONTAINER}" kubectl get nodes --no-headers | grep -q .
docker cp "${CONTAINER}:/etc/rancher/k3s/k3s.yaml" "${KUBECONFIG_FILE}"
sed -i 's#https://127.0.0.1:6443#https://127.0.0.1:6447#' "${KUBECONFIG_FILE}"
export KUBECONFIG="${KUBECONFIG_FILE}"

kubectl wait --for=condition=Ready node --all --timeout=120s
for _ in {1..60}; do
  if kubectl -n kube-system get deployment coredns --no-headers 2>/dev/null | grep -q .; then
    break
  fi
  sleep 2
done
kubectl -n kube-system rollout status deployment/coredns --timeout=120s

kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
kubectl -n prod create secret docker-registry aistor-zot-puller \
  --docker-server=registry.invalid \
  --docker-username=disposable \
  --docker-password=disposable \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n prod create secret tls object-store-webhook-tls \
  --cert="${WORK_DIR}/webhook.crt" \
  --key="${WORK_DIR}/webhook.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${RENDERED_OPERATOR}"
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: aistor.min.io/v1
kind: ObjectStore
metadata:
  name: repetly-aistor-green
  namespace: prod
spec:
  pools:
    - name: pool-0
      servers: 1
      volumesPerServer: 1
      volumeClaimTemplate:
        metadata:
          name: data
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: local-path
          resources:
            requests:
              storage: 1Gi
YAML
CA_BUNDLE="$(base64 -w0 < "${WORK_DIR}/ca.crt")"
kubectl patch mutatingwebhookconfiguration object-store-operator-webhook \
  --type=json \
  --patch="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]" >/dev/null

kubectl -n prod rollout status deployment/object-store-webhook --timeout=180s
kubectl -n prod get deployment/object-store-webhook service/object-store-webhook

kubectl -n prod port-forward service/object-store-webhook 18443:8443 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
for _ in {1..30}; do
  if curl --silent --fail --cacert "${WORK_DIR}/ca.crt" \
      --resolve object-store-webhook.prod.svc.cluster.local:18443:127.0.0.1 \
      "https://object-store-webhook.prod.svc.cluster.local:18443/healthz" \
      >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl --silent --fail --show-error --cacert "${WORK_DIR}/ca.crt" \
  --resolve object-store-webhook.prod.svc.cluster.local:18443:127.0.0.1 \
  "https://object-store-webhook.prod.svc.cluster.local:18443/healthz" \
  | grep -F 'ok'

EXPECTED_FINGERPRINT="$(openssl x509 -in "${WORK_DIR}/webhook.crt" -noout -fingerprint -sha256)"
ACTUAL_FINGERPRINT="$(openssl s_client -connect 127.0.0.1:18443 \
  -servername object-store-webhook.prod.svc.cluster.local \
  -CAfile "${WORK_DIR}/ca.crt" -verify_return_error </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256)"
[[ "${ACTUAL_FINGERPRINT}" == "${EXPECTED_FINGERPRINT}" ]]
openssl x509 -in "${WORK_DIR}/webhook.crt" -noout -text \
  | grep -F 'DNS:object-store-webhook.prod.svc.cluster.local' >/dev/null

cat <<'YAML' | kubectl apply --dry-run=server -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: admission-tls-synthetic
  namespace: prod
  labels:
    aistor.min.io/objectStore: repetly-aistor-green
    aistor.min.io/spreadZoneAware: "true"
    v1.min.io/pool: pool-0
spec:
  containers:
    - name: pause
      image: busybox:1.36.1
      command: ["sh", "-c", "sleep 5"]
YAML

echo "admission_webhook_image=quay.io/minio/aistor/operator@sha256:b88e5cf563406719f67028a52fef9dac4049e555f44e263267c30a069d1d8166"
echo "admission_webhook_custom_tls=PASS"
echo "admission_webhook_https_healthz=PASS"
echo "admission_webhook_certificate_fingerprint=PASS"
echo "admission_webhook_server_side_request=PASS"
