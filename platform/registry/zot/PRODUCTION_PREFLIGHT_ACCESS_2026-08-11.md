# Production read-only preflight result — 2026-08-11

Result: **FACTS COLLECTED — ACTIVATION BLOCKED BY UNRESOLVED PLATFORM
CONTRACTS**.

The authorized SSH path reached the production k3s host and only read-only
commands were run. No Kubernetes or MinIO mutation, Argo sync, Helm action,
S3 write, migration, cutover, or Secret value read was performed.

## Cluster and node

| Fact | Observed value |
| --- | --- |
| Host | `chota.by` / Ubuntu 22.04.5 LTS |
| Kubernetes | k3s `v1.35.5+k3s1`, context `default`, API `127.0.0.1:6443` |
| Nodes | one Ready control-plane node, `chota.by` |
| Architecture | `linux/amd64` |
| Allocatable | 4 CPU, `8127796Ki` memory, 110 Pods |
| Pressure | memory, disk, and PID pressure all false |
| Argo revision | `repetly-prod` Healthy/Synced at `3c9af25cef...` |

The node is a single failure domain. No second production node, HA storage
backend, or cross-node replication path was observed.

## BLUE MinIO and storage

| Fact | Observed value |
| --- | --- |
| Namespace / Deployment | `prod/repetly-minio`, 1 replica, `Recreate` |
| Current image | `minio/minio:RELEASE.2025-09-07T16-13-09Z` |
| Running imageID | `docker.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` |
| BLUE PVC | `repetly-minio-data`, Bound, RWO, 10Gi |
| StorageClass | `local-path` only; PV is node-local, reclaim `Delete` |
| Dataset inventory | bucket `repetly-homework`, 1 object, 356134 bytes, no incomplete multipart uploads |
| Host filesystem | 197G total, 116G free, 39% used |
| App storage env | `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` have no value/valueFrom; storage remains disabled |

The GREEN AIStor and Zot data paths must use separate PVCs and must not reuse
the BLUE PVC, BLUE MinIO path, GREEN bucket, or Repetly bucket.

## Registry and network path

- No production Zot/Harbor registry, registry namespace, private registry DNS
  name, TLS Secret, private CA, or containerd registry trust configuration was
  observed.
- `prod` has no NetworkPolicy. Existing policies are limited to ArgoCD
  namespaces; an enforcing CNI for the production path was not evidenced.
- The current storage API is public through Traefik at
  `repetly-storage.chota.by` and routes to BLUE MinIO. This is not an approved
  private registry endpoint.
- The only production StorageClass is node-local `local-path`; selecting it
  for a registry PVC requires explicit owner approval for durability and
  restore risk.

## Argo and safety boundary

`repetly-prod` is automated with prune/self-heal and tracks
`services/repetly/prod`. The current active Kustomization does not reference
the inert AIStor or Zot templates. No production registry, ObjectStore, PVC,
Secret, Service, image reference, IAM value, or NetworkPolicy was created or
changed.

## Remaining blockers before Ready for Review

1. Provide an approved private registry endpoint, DNS, TLS/CA trust path, and
   publisher/puller Secret contracts for kubelet image pulls.
2. Approve the dedicated registry namespace, `local-path` durability tradeoff,
   PVC sizes/resources, and the backup/restore owner, retention, RPO, and RTO.
3. Render exact production NetworkPolicy selectors and prove enforcement and
   the node/container-runtime image-pull path.
4. Run the required amd64 Kubernetes acceptance. The local host is arm64;
   amd64 kind/k3s emulation could not provide a real amd64 node, so the exact
   acceptance remains an explicit blocker. See
   [`ZOT_AMD64_K8S_ACCEPTANCE_2026-08-11.md`](./ZOT_AMD64_K8S_ACCEPTANCE_2026-08-11.md).

No kubeconfig, token, certificate, password, access-key value, or Secret value
is stored in this repository or in the evidence.
