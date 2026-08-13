# AIStor GREEN TLS contract — 2026-08-13

This is an inert, production-specific contract. It does not create a Secret,
Certificate, Service, IngressRoute, or NetworkPolicy in the active
Kustomization.

## Three separate TLS concerns

| Concern | In-cluster object | Trust owner | Git contract |
| --- | --- | --- | --- |
| Operator upgrade webhook (port 4221) | `object-store-operator-tls` | AIStor server trusts issuer CA through `aistor-operator-ca` | `OPERATOR_AUTO_CERT_DISABLED="on"` and `OPERATOR_CUSTOM_TLS_SECRET_NAME=object-store-operator-tls` |
| AIStor server/internal TLS (port 9000) | `repetly-aistor-green-tls` | Traefik trusts `repetly-aistor-green-ca`; AIStor uses `certificates.server` | `disableAutoCert: true`, one OOB `kubernetes.io/tls` Secret |
| Public S3 endpoint | `repetly-storage.chota.by` on Traefik `websecure` | Browser and Repetly trust public ACME certificate | Existing hostname remains stable; BLUE owns it before cutover, GREEN after sign-off |

The admission webhook is a fourth, distinct Kubernetes control-plane endpoint:
its serving Secret is `object-store-webhook-tls`, and its issuing CA is supplied
to the chart as `caBundle` only during the final out-of-band render. The exact
chart/image/runtime proof is recorded in
`ADMISSION_WEBHOOK_TLS_EVIDENCE_2026-08-12.md`; the placeholder in values is
intentionally not deployable.

## SAN and rotation contract

- `object-store-operator-tls` must cover `object-store-operator`,
  `object-store-operator.prod.svc`, and
  `object-store-operator.prod.svc.cluster.local`.
- `object-store-webhook-tls` must cover `object-store-webhook`,
  `object-store-webhook.prod.svc`, and
  `object-store-webhook.prod.svc.cluster.local`.
- `repetly-aistor-green-tls` must cover the generated S3 Service DNS name
  `minio.prod.svc.cluster.local`, the ObjectStore/headless Service DNS names,
  and the StatefulSet peer names required by the exact licensed
  reconciliation. The verified Traefik `ServersTransport` therefore uses
  `minio.prod.svc.cluster.local` as `serverName`.
- The previously proposed candidate
  `repetly-aistor-green.prod.svc.cluster.local` is also present in the
  disposable certificate SAN set and passes the same TLS check, but it is not
  the selected backend SNI because the generated S3 Service is `minio`.
- The external certificate for `repetly-storage.chota.by` remains Traefik
  ACME/publicly trusted. No `insecureSkipVerify` or process-wide TLS bypass is
  permitted.
- Rotation must update the OOB Secret/CA material, verify the generated
  `<objectstore>-generated` mount Secret refresh, then validate the public
  S3 health path and a presigned browser URL before cutover.

## Evidence status — 2026-08-13

The exact licensed disposable rehearsal and the fresh production read-only
snapshot are recorded in
[`DISPOSABLE_FINAL_TLS_REHEARSAL_2026-08-13.md`](./DISPOSABLE_FINAL_TLS_REHEARSAL_2026-08-13.md)
and
[`PRODUCTION_READONLY_RECHECK_2026-08-13.md`](./PRODUCTION_READONLY_RECHECK_2026-08-13.md).

The disposable ObjectStore `1.0.17` generated `Service/minio` as `443/TCP`
with `targetPort: 9000`, plus the headless Service on `9000/TCP` and
`4444/TCP`. Its sidecar command contained
`-servername minio.prod.svc.cluster.local`. With the OOB server Secret and CA
mounted, ObjectStore reached `Initialized`, both MinIO containers reached
`Ready`, and HTTPS `/minio/health/live` returned HTTP 200 with SNI verification.

The live production Traefik CRD serves/stores `v1alpha1` and supports
`spec.rootCAs` with a Secret string reference; `rootCAsSecrets` remains in the
schema only as a deprecated field. The contract now uses `rootCAs` and the
`repetly-aistor-green-ca` Secret whose `ca.crt` key is already defined in the
OOB template.

These checks clear the stale SSH/license evidence gate, but do not authorize
production mutation or BLUE/GREEN cutover. The active production route still
targets BLUE `repetly-minio:9000`; GREEN remains an inert scaffold pending an
explicit reviewed activation.
