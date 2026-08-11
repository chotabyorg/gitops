# Zot v2.1.20 Kubernetes kind acceptance — 2026-08-11

Verdict:

> **LOCAL REGISTRY GATES PASS — PRODUCTION PREFLIGHT REQUIRED**

This is a disposable Kubernetes rehearsal only. It used a single-node kind
cluster and synthetic namespace, TLS, authentication, resource, and network
values. It did not use the production cluster, BLUE MinIO, GREEN AIStor,
Repetly storage, or the SSH credentials supplied for production access.

## Candidate and cluster

- Host and disposable node architecture: `arm64`.
- kind: `v0.32.0`; Kubernetes node: `v1.36.1`.
- CNI/NetworkPolicy engine: Calico `v3.32.1`; kind's default CNI was disabled
  so the NetworkPolicy checks exercised an enforcing CNI.
- Zot image:
  `ghcr.io/project-zot/zot@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`.
- Pod `imageID` before and after recreation matched the exact arm64 digest
  above. The local image ID was
  `sha256:22462b7c31a805ea133fd6a17b2e92a663620029ec03b2e1d04aa1ae4d3c45cb`.
- Workload shape: rendered StatefulSet, Service, ConfigMap, two Secrets, a
  `1Gi` RWO PVC, and a dedicated NetworkPolicy in namespace
  `zot-disposable`.

All values in this rehearsal were synthetic. The tracked manifests remain
`.template` files with fail-closed production placeholders.

## Probe contract

The rendered Pod used HTTPS probes on the named `https` port:

| Probe | Endpoint | Period | Timeout | Failure threshold | Result |
| --- | --- | ---: | ---: | ---: | --- |
| Startup | `/startupz` | 5s | 3s | 24 | PASS; startup completed without a restart loop |
| Readiness | `/readyz` | 5s | 3s | 6 | PASS; allowed client received HTTP 200 / `ok` |
| Liveness | `/livez` | 10s | 3s | 6 | PASS; direct and kubelet requests returned HTTP 200 |

Zot logs showed successful `/startupz`, `/readyz`, and `/livez` requests. No
`/v2/` health probe was used.

## Kubernetes security evidence

The actual Pod spec and process were checked, not only the source template:

- `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000`.
- `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and
  `seccompProfile.type: RuntimeDefault`.
- The running process reported UID/GID `1000/1000`, `NoNewPrivs=1`, zero
  permitted/effective/bounding capabilities, and active seccomp.
- `readOnlyRootFilesystem: true`.
- `/etc/zot/config`, `/etc/zot/auth`, and `/etc/zot/tls` were not writable.
  `/tmp` and the PVC-backed `/var/lib/zot` were writable.
- `automountServiceAccountToken: false`; the Pod had no service-account token
  volume.

The first Kubernetes render exposed an important compatibility issue: the
exact Zot image metadata runs as root, so `runAsNonRoot` alone produced
`CreateContainerConfigError`. Adding the explicit UID/GID and fsGroup above
resolved the issue; the recreated Pod started and became Ready under the
same hardened contract.

## Digest and ACL results

Skopeo `1.22.2` copied the source with `--all` and preserved the manifest
digest:

```text
source busybox index       sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
destination tag            sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
```

| Identity/action | Result |
| --- | --- |
| Publisher create tag | PASS |
| Publisher retry/update existing tag | DENY; destination manifest upload returned `requested access to the resource is denied` |
| Publisher delete | DENY |
| Puller read | PASS; inspect returned the source digest |
| Puller create | DENY |
| Anonymous read | DENY; `authentication required` |

The ACL remained enforced after Pod recreation on the same PVC. No break-glass
credential was used.

## NetworkPolicy behavior

The disposable policy used:

- ingress from a synthetic namespace label `zot-network-access=allowed`;
- a synthetic kind node CIDR only for kubelet probe reachability; and
- `egress: []`.

Observed behavior:

- `zot-allowed` health request: HTTP 200 / `ok` — PASS.
- `zot-forbidden` health request: timeout — PASS for deny.
- Egress from the Zot Pod to the Kubernetes API ClusterIP: timeout — PASS for
  unnecessary-egress deny.

The namespace label and node CIDR are disposable test values. They are not
production selectors. A production NetworkPolicy must be rendered only after
the approved preflight identifies the exact publisher/puller namespaces and
the node/container-runtime image-pull path. NamespaceSelector rules do not
prove kubelet connectivity.

## Availability, liveness, and PVC persistence

### Temporary unavailability and recovery

The disposable StatefulSet was scaled to zero. The Service then had no
endpoints and the allowed client received connection refused. Scaling back to
one recreated the workload and StatefulSet rollout completed with Ready=true.

### Liveness failure and recovery

The Zot process was stopped inside the disposable node/container namespace.
Kubelet recorded `/livez` timeout, set the Pod Ready condition to false, and
emitted `Container zot failed liveness probe, will be restarted`. The
container restarted with `restartCount=1`, then startup/readiness recovered to
Ready=true. The final recreated container had `restartCount=0` and the exact
Zot imageID.

### Persistence

Before scale-to-zero, the Pod used a PVC with UID
`fdb93ab0-2637-4021-b9bc-2c8f0c1b2d9f` and volume
`pvc-fdb93ab0-2637-4021-b9bc-2c8f0c1b2d9f`. After the Pod was deleted and
recreated, the Pod UID changed, while the PVC UID and volume remained the
same. The `aistor/test:kind-v2120` tag still resolved to
`sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662`,
and puller read plus publisher overwrite/delete denial remained unchanged.

## Architecture boundary and remaining gates

This rehearsal is arm64. If production nodes are amd64, the final workload
must use the scanned amd64 manifest digest
`sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`
and repeat the abbreviated Kubernetes acceptance (probes, ACL, overwrite
deny, persistence, and Pod imageID) before Ready for Review.

Production activation still requires facts unavailable in this workspace:

- approved read-only Kubernetes context and cluster identity;
- node architecture/topology and kubelet/container-runtime pull path;
- independent production StorageClass/PVC sizing and registry namespace;
- approved TLS hostname/CA/trust path and private endpoint reachability;
- exact publisher/puller NetworkPolicy selectors and necessary DNS/egress;
- production resource values and backup/restore owner, retention, RPO/RTO;
- final production Pod imageID equality with the approved scanned digest.

No production kubeconfig was present (`current-context` unset and no contexts
returned), so no SSH bypass or production API call was attempted.

The Docker-level acceptance remains in
[`ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md`](./ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md).
The production access boundary remains in
[`PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md`](./PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md).
