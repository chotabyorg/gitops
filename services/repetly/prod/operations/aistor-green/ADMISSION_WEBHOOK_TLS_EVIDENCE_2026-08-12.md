# Admission webhook TLS evidence — 2026-08-12

## Disposition

`WEBHOOK_CUSTOM_TLS_SECRET_NAME=object-store-webhook-tls` is retained. It is
not accepted merely because Helm copied an environment variable. The exact
chart package, exact Operator image, rendered objects, and a disposable
runtime test all support the contract.

## Primary evidence

- Exact Operator chart: `aistor-operator` `5.11.3`, SHA-256
  `da7ee3ba290939a5279a76b1dd8ec7717207c00e6ffbd7cb110178a7dc8af590`.
- Its `values.yaml` documents `WEBHOOK_CUSTOM_TLS_SECRET_NAME` under
  `operators.object-store.webhook.extraEnv` and requires `caBundle` when a
  custom serving certificate is selected.
- Its `_helpers.tpl` detects the exact variable and disables the OpenShift
  service-CA/autocert wiring when the custom certificate path is selected.
- Exact rendered chart objects are:
  - `Deployment/prod/object-store-webhook`, image
    `quay.io/minio/aistor/operator@sha256:b88e5cf563406719f67028a52fef9dac4049e555f44e263267c30a069d1d8166`;
  - env `WEBHOOK_CUSTOM_TLS_SECRET_NAME=object-store-webhook-tls`;
  - Pod `automountServiceAccountToken: true`, so the webhook can read its
    namespace Secret through the chart-rendered Role;
  - no arbitrary TLS bypass, container port `8443`, and HTTPS `/healthz`
    readiness/liveness probes;
  - `Service/prod/object-store-webhook` TCP `8443`;
  - `MutatingWebhookConfiguration/object-store-operator-webhook` with
    HTTPS `/mutate`, `failurePolicy: Fail`, and the supplied CA bundle.
- The exact image binary is the OCI layer payload SHA-256
  `e7785c9ec7dfdcc79a3317d9445e880423348d72e94cbd232b703171dae47c21`.
  Byte-level inspection contains all of:
  `WEBHOOK_CUSTOM_TLS_SECRET_NAME`, `OPERATOR_CUSTOM_TLS_SECRET_NAME`, and
  `OPERATOR_AUTO_CERT_DISABLED`, plus the admission webhook and certificate
  handling strings.

## Runtime proof

`tests/run-webhook-tls-runtime.sh` runs in disposable embedded-k3s only. It
creates a short-lived CA and serving Secret, applies the exact rendered
webhook Deployment/image, verifies HTTPS `/healthz` with the CA, compares the
served certificate fingerprint to the Secret certificate, verifies the
service DNS SAN, and sends a server-side dry-run Pod admission request through
the `failurePolicy: Fail` webhook.

The current GitHub Actions run is the authoritative execution record. No
production namespace, Secret, certificate, webhook, or admission request is
touched.

## Boundary

The owner-provided AIStor Free license is not available through the current
approved secure path: the repository has no AIStor license secret, and no
license bytes were read or searched for. Therefore the separate full licensed
ObjectStore TLS rehearsal is not claimed as current evidence. The historical
licensed rehearsal remains historical; its generated ObjectStore Service and
certificate SANs must not be silently promoted beyond what was recorded.
