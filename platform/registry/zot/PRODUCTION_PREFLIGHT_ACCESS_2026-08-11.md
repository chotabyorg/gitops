# Production read-only preflight result — 2026-08-11

Result: **FACTS COLLECTED — OWNER-APPROVED CONDITIONAL P0 CONTRACT RECORDED**.

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

- No production Zot/Harbor registry, `registry` namespace, or
  `registry.chota.by` DNS/route currently exists.
- K3s runs embedded kube-router NetworkPolicy enforcement: `k3s` has no
  `--disable-network-policy`, and `iptables-save`/`nft` contain
  `KUBE-NWPLCY-*` and `KUBE-ROUTER-*` chains with `kube-router netpol` rules.
  The controller is **ENABLED**. No registry/`prod` policy objects exist yet.
- The current storage API is public through Traefik at
  `repetly-storage.chota.by` and routes to BLUE MinIO. This is not an approved
  private registry endpoint.
- The only production StorageClass is node-local `local-path`; the owner
  approved it for this P0 with one independent `10Gi` PVC per workload.
  Replicated/multi-node durability is follow-up technical debt.

## Argo and safety boundary

`repetly-prod` is automated with prune/self-heal and tracks
`services/repetly/prod`. The current active Kustomization does not reference
the inert AIStor or Zot templates. No production registry, ObjectStore, PVC,
Secret, Service, image reference, IAM value, or NetworkPolicy was created or
changed.

## Resolved rollout contracts

- Zot: namespace `registry`, one replica, independent `10Gi` `local-path` RWO
  PVC, exact amd64 image digest, requests `100m/256Mi`, limits `250m/384Mi`.
- Hostname/TLS: `registry.chota.by` → Traefik `websecure`/ACME `le` → Zot
  ClusterIP `registry/zot-registry:5000`; Zot auth denies anonymous access.
  DNS and certificate issuance are rollout prerequisites only.
- Pull path: node containerd uses HTTPS to the public hostname; Zot itself is
  pulled from exact public GHCR digest. AIStor main image uses
  `prod/aistor-zot-puller` (`.dockerconfigjson`); publisher is separate.
- Backup: no existing backup controller/path was found. P0 RPO is 24h and RTO
  is 2h via deterministic rehydration from the reviewed digest ledger;
  off-host snapshots remain follow-up work.

## Remaining gates before Ready for Review

1. Publish DNS and obtain/verify the Traefik ACME certificate; no production
   DNS or ingress mutation is authorized in this execution.
2. Run the GitHub-hosted x64 Kubernetes acceptance and record its run,
   sanitized evidence, exact Pod imageID, and PVC persistence.

No kubeconfig, token, certificate, password, access-key value, or Secret value
is stored in this repository or in the evidence.
