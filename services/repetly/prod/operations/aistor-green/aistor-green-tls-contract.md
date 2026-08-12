# AIStor GREEN TLS contract — 2026-08-12

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
- `repetly-aistor-green-tls` must cover the generated API and headless Service
  DNS names plus any StatefulSet peer names required by the exact licensed
  reconciliation. The proposed Traefik `ServersTransport` uses
  `repetly-aistor-green.prod.svc.cluster.local` as `serverName` only as an
  inert candidate; it is not promoted to a verified final SNI.
- The external certificate for `repetly-storage.chota.by` remains Traefik
  ACME/publicly trusted. No `insecureSkipVerify` or process-wide TLS bypass is
  permitted.
- Rotation must update the OOB Secret/CA material, verify the generated
  `<objectstore>-generated` mount Secret refresh, then validate the public
  S3 health path and a presigned browser URL before cutover.

The exact Traefik version, CRD support for `ServersTransport.rootCAsSecrets`,
generated Service name/port, licensed server SANs, and production Pod labels
still require a fresh read-only/owned disposable check. SSH to the supplied
host timed out on 2026-08-12 and no current owner license was available;
this contract therefore does not clear the production activation gate.
