# Production read-only recheck — 2026-08-13

## Result

**FRESH READ-ONLY SNAPSHOT — no production mutation performed.** The supplied
owner SSH key authenticated successfully after host-key verification. The
owner-provided license was used only in the disposable rehearsal; no key,
passphrase, license bytes, or production Secret material is recorded here.

## Identity and platform

- Host: `chota.by`, Ubuntu `22.04.5 LTS`, kernel `5.15.0-187-generic`.
- Kubernetes: k3s `v1.35.5+k3s1`, Linux `amd64`; one Ready node
  `chota.by`, InternalIP `153.80.244.178`.
- Container runtime: `containerd://2.2.3-k3s1`.
- The verified SSH host-key fingerprint was
  `SHA256:Bg2duS3bgB7X/VJepynEEdmfOthhAfwNAqBirmSPwQg`.

## Traefik and current route

- Deployment image: `rancher/mirrored-library-traefik:3.6.13`.
- Running image ID:
  `docker.io/rancher/mirrored-library-traefik@sha256:34d5089d0b414945342848518b383f11f5b3a645504ed87b77ffeb9d683d0e48`.
- Live Pod labels include `app.kubernetes.io/name=traefik` and the
  `kube-system` namespace label is the standard
  `kubernetes.io/metadata.name=kube-system`.
- The Deployment enables `kubernetescrd`, `kubernetesingress`, and
  `websecure.http.tls=true`; no insecure TLS bypass flag was present.
- Live `ServersTransport` CRD version `v1alpha1` is served and stored. Its
  schema supports `spec.rootCAs` with a Secret string reference and the
  certificate keys `tls.ca` or `ca.crt`. The legacy `rootCAsSecrets` field is
  present only as deprecated schema support.
- The current `prod/repetly-storage-chota-by` IngressRoute remains unchanged:
  `Host(repetly-storage.chota.by)` on `websecure` targets BLUE
  `Service/repetly-minio:9000` and has no GREEN transport.
- Traefik Service is `LoadBalancer` with ClusterIP `10.43.237.166`, external
  IP `153.80.244.178`, and ports `80:31520/TCP`, `443:31900/TCP`.

## CoreDNS, labels, and NetworkPolicy enforcement

- CoreDNS Deployment/Pod labels match the draft policy contract:
  `k8s-app=kube-dns` and `kubernetes.io/name=CoreDNS`.
- `Service/kube-dns` is `10.43.0.10` on `53/UDP`, `53/TCP`, and `9153/TCP`.
- Production currently has no AIStor/`prod` NetworkPolicy; only existing
  Argo CD policies were listed. No policy was applied during this recheck.
- `k3s` is active and iptables contains active kube-router
  `KUBE-ROUTER-INPUT/FORWARD/OUTPUT` and `KUBE-NWPLCY-*` chains with policy
  counters. This confirms enforcement is available for the inert policy
  template.
- Existing Repetly API Pods use `app=repetly`; no scanner Pod was present in
  the read-only Pod inventory. The GREEN policy intentionally does not grant
  direct Repetly/scanner ingress.

## Capacity and current usage

- Node allocatable: `4 CPU`, `8127796Ki` memory, `200693717859` bytes
  ephemeral storage, `110` Pods.
- Current scheduled aggregate: `300m` CPU requests / `1 CPU` limits;
  `396Mi` memory requests / `1194Mi` limits; `0` ephemeral-storage requests
  or limits.
- Node conditions were all healthy: `MemoryPressure=False`,
  `DiskPressure=False`, `PIDPressure=False`.
- Fresh usage: `523m` CPU (`13%`) and `5652Mi` memory (`71%`). The memory
  observation is a rollout-monitoring concern, not a scheduler rejection.
- Highest current memory consumers included document-service `365Mi`,
  rag-service `346Mi`, Repetly `226Mi`, and Argo CD application-controller
  `185Mi`; Traefik remained a small consumer at about `49Mi` in the captured
  inventory.
- The rendered GREEN+Operator+webhook+Zot candidate adds `1050m` CPU and
  `1568Mi` memory requests, for a recorded combined request baseline of
  `1350m` CPU and `1964Mi` memory. Ephemeral storage remains a separate
  rollout observation because the existing workloads declare none.

## Mutation boundary

This snapshot used only SSH identity/read commands, Kubernetes `get`/
`describe`/`top`, `systemctl is-active`, and `iptables-save`. No production
`apply`, `create`, `patch`, `delete`, `exec`, rollout, route change, Secret
change, or BLUE/GREEN cutover was performed.

TokenReview remains the owner-approved production P0. OIDC/JWKS remains
future RBAC-hardening technical debt and is not reopened by this recheck.
