# Disposable final TLS rehearsal — 2026-08-13

## Result

**PASS for the licensed disposable ObjectStore/TLS contract; production was
not touched.** The exact Operator chart `5.11.3` and ObjectStore chart `1.0.17`
were reconciled in a temporary embedded k3s cluster with the owner-provided
AIStor license. The license was supplied to a disposable-only
`minio-license` Secret and was never printed, decoded, copied into GitHub, or
committed.

The local disposable node was native `linux/arm64`; the production node and
Git contract remain `linux/amd64`. This lower-environment run proves the
multiarch runtime shape and exact TLS/SNI behavior, while the amd64 Operator,
webhook, render, and NetworkPolicy checks remain covered by the current PR CI.
No production image selector or digest was changed for this rehearsal.

## Exact reconciled runtime

- ObjectStore: `prod/repetly-aistor-green`, chart `aistor-objectstore 1.0.17`.
- Operator: `aistor-operator 5.11.3`, with custom Operator/webhook TLS and the
  owner-approved `TokenReview` mode.
- Main MinIO container: public release tag
  `quay.io/minio/aistor/minio:RELEASE.2026-08-07T18-34-35Z` used only for the
  disposable pull; the production scaffold remains the immutable Zot content
  tag required by PR #46.
- Sidecar: `quay.io/minio/aistor/minio-sidecar@sha256:560e204d8fbd05d095719a39af0db36e177829528d80366962d1bc22102c9b57`.
- The reconciled StatefulSet was `repetly-aistor-green-pool-0`, with Pod
  `repetly-aistor-green-pool-0-0`, one `10Gi` `local-path` PVC, and `minio` plus
  `sidecar` containers.

## Generated Services and ports

The ObjectStore generated these exact Services:

| Service | Type | Port | Target/role |
| --- | --- | ---: | --- |
| `minio` | ClusterIP | `443/TCP` | `targetPort: 9000`, S3 API |
| `repetly-aistor-green-console` | ClusterIP | `9443/TCP` | Console |
| `repetly-aistor-green-hl` | Headless | `9000/TCP`, `4444/TCP` | API and sidecar/headless traffic |

The sidecar command in the actual Pod included:
`-servername minio.prod.svc.cluster.local` and called the local MinIO HTTPS
cluster-read endpoint. This is the observed final backend SNI, not a guessed
name derived from the CR.

## Certificate SAN and HTTPS evidence

The disposable OOB server certificate had subject `CN=repetly-aistor-green`
and issuer `CN=AIStor disposable rehearsal CA`. Its SANs included:

- `minio`, `minio.prod.svc`, `minio.prod.svc.cluster.local`;
- `repetly-aistor-green`, `repetly-aistor-green.prod.svc`,
  `repetly-aistor-green.prod.svc.cluster.local`;
- `repetly-aistor-green-console` and its `prod.svc` and
  `prod.svc.cluster.local` names;
- the generated headless, pool, and peer names, including
  `repetly-aistor-green-pool-0-0.repetly-aistor-green-hl.prod.svc.cluster.local`.

Therefore the earlier candidate
`repetly-aistor-green.prod.svc.cluster.local` is confirmed in the certificate,
but the selected Traefik SNI is the exact generated S3 Service name
`minio.prod.svc.cluster.local`.

Observed runtime results after the OOB TLS Secret refresh:

- ObjectStore status: `Initialized`, setup `100`.
- Pod status: `2/2 Running`; MinIO and sidecar both `Ready`.
- `https://minio.prod.svc.cluster.local/minio/health/live` through the
  disposable `Service/minio:443`: HTTP `200`, CA verification code `0 (ok)`.
- The candidate SNI `repetly-aistor-green.prod.svc.cluster.local` against the
  same Service: HTTP `200`, CA verification code `0 (ok)`.
- No `insecureSkipVerify` or process-wide TLS bypass was used.

The first sidecar readiness failure exposed that its actual SNI was `minio`;
the disposable-only OOB certificate was rotated to include the exact Service
SAN, after which the runtime reached `Initialized`. This is why the Git
contract now names `minio:443`, `targetPort:9000`, and
`minio.prod.svc.cluster.local` explicitly.

## Boundary

All namespaces, Secrets, PVCs, Services, Pods, port-forwards, and certificate
material in this rehearsal were disposable. The production cluster received
no apply/create/patch/delete/exec operation and no route or Secret mutation.
