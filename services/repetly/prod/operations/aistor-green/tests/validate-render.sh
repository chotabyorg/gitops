#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_BIN="${HELM_BIN:-helm}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/artifacts/aistor-green}"
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
KEEP_WORK_DIR="${KEEP_WORK_DIR:-false}"

OPERATOR_URL="https://helm.min.io/helm-releases/aistor-operator-5.11.3.tgz"
OPERATOR_SHA256="da7ee3ba290939a5279a76b1dd8ec7717207c00e6ffbd7cb110178a7dc8af590"
OBJECTSTORE_URL="https://helm.min.io/helm-releases/aistor-objectstore-1.0.17.tgz"
OBJECTSTORE_SHA256="a19401ab94da86f34eb5f1a53ea6502ed364bc139a60fac22042a4e192aeb304"

cleanup() {
  if [[ "${KEEP_WORK_DIR}" != "true" ]]; then
    rm -rf "${WORK_DIR}"
  else
    echo "work_dir=${WORK_DIR}"
  fi
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"

download_verified() {
  local url="$1" expected="$2" destination="$3"
  curl --fail --silent --show-error --location "${url}" --output "${destination}"
  printf '%s  %s\n' "${expected}" "${destination}" | sha256sum --check --status
}

OPERATOR_CHART="${OPERATOR_CHART:-${WORK_DIR}/aistor-operator-5.11.3.tgz}"
OBJECTSTORE_CHART="${OBJECTSTORE_CHART:-${WORK_DIR}/aistor-objectstore-1.0.17.tgz}"
[[ -f "${OPERATOR_CHART}" ]] || download_verified "${OPERATOR_URL}" "${OPERATOR_SHA256}" "${OPERATOR_CHART}"
[[ -f "${OBJECTSTORE_CHART}" ]] || download_verified "${OBJECTSTORE_URL}" "${OBJECTSTORE_SHA256}" "${OBJECTSTORE_CHART}"

SYNTHETIC_CA="Y2lfc3ludGhldGljX2NhX2J1bmRsZQ=="
cat > "${WORK_DIR}/synthetic-values.yaml" <<EOF
operators:
  object-store:
    webhook:
      caBundle: "${SYNTHETIC_CA}"
EOF

"${HELM_BIN}" version --short
"${HELM_BIN}" template aistor "${OPERATOR_CHART}" \
  --namespace prod \
  --values "${ROOT_DIR}/aistor-operator-values.yaml.template" \
  --values "${WORK_DIR}/synthetic-values.yaml" \
  --include-crds > "${WORK_DIR}/operator-after.yaml"

"${HELM_BIN}" template aistor "${OPERATOR_CHART}" \
  --namespace prod \
  --values "${ROOT_DIR}/aistor-operator-values.yaml.template" \
  --values "${WORK_DIR}/synthetic-values.yaml" \
  --set global.operator.optOutAutomaticCertificates=false \
  --include-crds > "${WORK_DIR}/operator-before.yaml"

"${HELM_BIN}" template repetly-aistor-green "${OBJECTSTORE_CHART}" \
  --namespace prod \
  --values "${ROOT_DIR}/aistor-objectstore-values.yaml.template" \
  --include-crds > "${WORK_DIR}/objectstore.yaml"

ruby "${ROOT_DIR}/tests/inspect-render.rb" \
  "${WORK_DIR}/operator-before.yaml" \
  "${WORK_DIR}/operator-after.yaml" \
  "${WORK_DIR}/objectstore.yaml" \
  "${ROOT_DIR}/network-policy.yaml.template" \
  "${OUTPUT_DIR}"

diff -u "${OUTPUT_DIR}/rbac-before.txt" "${OUTPUT_DIR}/rbac-after.txt" > "${OUTPUT_DIR}/rbac-before-after.diff" || true
cp "${WORK_DIR}/operator-after.yaml" "${OUTPUT_DIR}/operator-rendered.yaml"
cp "${WORK_DIR}/objectstore.yaml" "${OUTPUT_DIR}/objectstore-rendered.yaml"
echo "validation=PASS"
