# AIStor GREEN production read-only facts — 2026-08-11

Result: **FACTS COLLECTED — OWNER-APPROVED CONDITIONAL GREEN P0 CONTRACT**.

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
- No production Zot/Harbor registry, `registry` namespace, or
  `registry.chota.by` DNS/route currently exists. The selected rollout model
  is Traefik `websecure`/ACME `le` to a private Zot ClusterIP.
- K3s embedded kube-router NetworkPolicy enforcement is enabled: the service
  has no `--disable-network-policy`, and `KUBE-NWPLCY-*`/`KUBE-ROUTER-*`
  chains with `kube-router netpol` rules are present. No registry/`prod`
  policy objects exist yet.
- AIStor auto-generated internal TLS is the selected private ClusterIP client
  path; its service DNS/trust must be included in the first rendered rollout
  review. External registry TLS is Traefik ACME, not a Zot Pod Secret.

## Resolved P0 values

- GREEN is `servers: 1`, `volumesPerServer: 1`, one independent `10Gi`
  `local-path` RWO PVC. BLUE is untouched; replicated storage is follow-up
  technical debt.
- Main runtime image is `registry.chota.by/aistor/minio:aistor-minio-e8394b040720`
  with source amd64 digest `sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`.
  `prod/aistor-zot-puller` key `.dockerconfigjson` is the dedicated pull-only
  contract.
- Conservative resources are MinIO requests `500m/768Mi`, limits `1 CPU/1Gi`;
  sidecar `50m/32Mi` → `100m/128Mi`; Operator/webhook requests
  `200m/256Mi/500Mi ephemeral`, limits `500m/256Mi/500Mi ephemeral`.
- Current point-in-time **observed usage** was 312m CPU (7%) and 5671Mi memory
  (71%) of 4 CPU/8127796Ki allocatable; this is not scheduler headroom.
  Separately recorded scheduled requests/limits are 300m/1 CPU and
  396Mi/1194Mi. The proposed candidate budget and rollout floor are defined in
  `RESOURCE_AND_ROLLOUT_CONTRACT_2026-08-12.md`.
- No existing Velero/restic/off-host backup path was found. P0 DR is
  deterministic rehydration from the exact digest ledger, target RPO 24h/RTO
  2h; off-host snapshots are follow-up work.

## Read-only IAM observations

- The current BLUE bootstrap policy and application identity are
  `repetly-homework` scoped with `GetObject`, `PutObject`, and `DeleteObject`.
- Anonymous bucket listing and anonymous root listing both returned `403`.
- No credentials or Secret data is recorded here.

## Readiness decision

The facts resolve the production architecture boundary to `amd64`, the
owner-approved single-node/local-path shape, GREEN `10Gi`, resources,
NetworkPolicy controller/selectors, Zot pull model, and RPO/RTO. The native
image parser is a vendor limitation, not a production BLOCKER while the
immutable Zot fallback passes its acceptance invariant. PR #46 remains inert
until the separate x64 Zot acceptance and final rendered review pass; issue
#44 remains In Progress and production was not mutated.
