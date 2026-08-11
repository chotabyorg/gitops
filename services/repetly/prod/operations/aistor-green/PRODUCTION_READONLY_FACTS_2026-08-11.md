# AIStor GREEN production read-only facts — 2026-08-11

Result: **FACTS COLLECTED — GREEN ACTIVATION REMAINS BLOCKED**.

The production k3s host was accessed through the authorized SSH path. Only
read-only Kubernetes, filesystem, Argo, and MinIO inventory/identity checks
were run. No apply/create/patch/delete/replace/scale/restart, Helm mutation,
Argo sync, S3 write, migration, cutover, IAM change, or Secret value read was
performed.

## Cluster and active GitOps state

| Fact | Observed value |
| --- | --- |
| Host / OS | `chota.by`, Ubuntu 22.04.5 LTS |
| Kubernetes | k3s `v1.35.5+k3s1`, context `default` |
| Topology | one Ready control-plane node, `chota.by`, `linux/amd64` |
| Allocatable | 4 CPU, `8127796Ki` memory, 110 Pods |
| Pressure | memory, disk, and PID pressure false |
| Argo | `repetly-prod` Healthy/Synced at revision `3c9af25cef...`; automated prune/self-heal |
| Active storage | BLUE `repetly-minio` only; AIStor/Zot templates are not referenced |

## BLUE storage baseline

| Fact | Observed value |
| --- | --- |
| Deployment | `prod/repetly-minio`, 1 replica, `Recreate` |
| Current image | `minio/minio:RELEASE.2025-09-07T16-13-09Z` |
| Running imageID | `docker.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` |
| PVC | `repetly-minio-data`, Bound, RWO, 10Gi, `local-path` |
| PV | node-local, reclaim `Delete`; only StorageClass is `local-path` |
| Inventory | `repetly-homework`: 1 object, 356134 bytes, no incomplete multipart uploads |
| Host filesystem | 197G total, 116G free, 39% used |
| Repetly storage gate | S3 access-key/secret env entries have no value/valueFrom, so storage is disabled |

The measured dataset is small, but it does not by itself establish a
production capacity policy, backup target, restore window, or migration
headroom. GREEN must use a new PVC and must never reuse the BLUE PVC, its local
path, or the Repetly bucket.

## Network, TLS, and registry facts

- The only production StorageClass is node-local `local-path`; no separate
  durable/replicated storage backend was observed.
- The current storage hostname `repetly-storage.chota.by` is a public Traefik
  route to BLUE MinIO. It is not a private Zot/AIStor endpoint.
- No production Zot/Harbor registry, registry DNS name, private CA, or
  containerd registry trust configuration was observed.
- No NetworkPolicy exists in `prod`; existing policies are in ArgoCD
  namespaces. An enforcing CNI for the GREEN client/admin path was not
  evidenced.
- AIStor auto-generated internal TLS must not be treated as a client trust
  contract until the service DNS names and trust distribution are reviewed.

## Read-only IAM observations

- The current BLUE bootstrap policy and application identity are
  `repetly-homework` scoped with `GetObject`, `PutObject`, and `DeleteObject`.
- Anonymous bucket listing and anonymous root listing both returned `403`.
- No credentials or Secret data is recorded here.

## Readiness decision

The facts resolve the production architecture boundary to `amd64`, a single
server, and `volumesPerServer: 1` for the AIStor Free design. They do not
resolve the GREEN PVC size, owner-approved use of node-local storage,
production resource values, private registry pull path, exact NetworkPolicy
selectors/enforcement, backup/restore owner/RPO/RTO, or the vendor image-parser
blocker. PR #46 therefore remains Draft and issue #44 remains In Progress.
