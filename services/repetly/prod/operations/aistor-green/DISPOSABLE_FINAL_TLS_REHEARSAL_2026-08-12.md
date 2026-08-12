# Disposable final TLS rehearsal — 2026-08-12

## Result

**PARTIAL — admission webhook runtime proven; licensed ObjectStore runtime not
repeated.**

The exact Operator image/chart admission webhook path is exercised by
`tests/run-webhook-tls-runtime.sh` in disposable embedded k3s. The test uses a
synthetic CA and Secret only, checks HTTPS health, the served certificate
fingerprint/SAN, and a server-side admission request.

The owner-provided AIStor Free license is not available through the current
approved secure path. `gh secret list` exposed no AIStor license secret, and
no license value was read, printed, copied, or committed. The 2026-08-10
licensed rehearsal in README remains historical evidence, not a fresh final
TLS rehearsal.

Consequently, exact generated ObjectStore S3/headless Service names, runtime
server certificate SANs, and the final Traefik SNI are not promoted from a
guess. The rendered candidate still uses S3 port `9000` and
`repetly-aistor-green.prod.svc.cluster.local` only as an inert, pending
ServersTransport contract until exact licensed reconciliation and live
Traefik CRD inspection are available.
