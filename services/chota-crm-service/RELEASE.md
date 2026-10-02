# ChotaCRM v0.1 reviewed deployment candidate

Prepared 2026-09-30 UTC / 2026-10-01 Minsk. Implementation evidence only: **deployment review, merge, production pull/readiness, live backup and product acceptance remain pending**. No manifests have been applied by this preparation.

## Exact provenance

GitOps branch `codex/chotacrm-v01` was fetched/rebased from original2bd115f onto current main **3b44e639a11e399c95fda1c0a1d76b3609486a42** before editing. The four intervening Atlas commits are preserved. The original GitOps checkout/branch is untouched.

| Component | Merged source / review basis | Pinned image or configuration |
| --- | --- | --- |
| CRM backend | PR1 `e0127c7d98014e122b78e84684a938db1294e4db`, tree-identical reviewed `d6719863` | `ghcr.io/chotabyorg/chota-crm-service@sha256:5480abfddfcc030d17107ba820777ff02467924aaa6472abd3b9c13c412d2df0` |
| CRM frontend FINAL | PR2 `a76dc47beca7f26f51aa65741bf8befc5e13c06c`, tree-identical reviewed `1b87d50e` | `ghcr.io/chotabyorg/chota-crm-web@sha256:76cc7dddd468fe7a11a787ef19f411f46766a8e8a1fb2dfe4bfef8fa11d7c3d9` |
| Existing Agents site SSO | PR57 `1ad8c8676f30410cae8959dcab4ae2f76361630a` | `ghcr.io/chotabyorg/chota-site@sha256:9252a3c0e7f0ae21de9e30492508099b20f9b4dfe612ab1f036fe319685a8e4a` |
| Gateway config | PR31 `7c88977c2c1664a4faf06ee96461fab664714848`, reviewed `a8d4478e` | krakend.json SHA256 `c9913f040992db88d080133360cee2a838cac3cfaca628e4ded2557bdffa0ac3`, exact source copy |
| Existing KrakenD runtime | Existing production2.13.3, no version upgrade | `krakend:2.13.3@sha256:bd392b692271209927da6c62f1b42d7f8f7bd0cd60b00d97c93bb5b8d42b4999` |
| PostgreSQL + backup clients | Official18.6-alpine3.24; same index as independent backup/restore test | `postgres:18.6-alpine3.24@sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873` |

Application publication CI passed: backend36775006654, final frontend36778305977, site36775019328. Gateway main validation36780483429 passed; no gateway image build is needed. Earlier frontend6636dbe3 / digest6c9672 is superseded and must not be deployed. Official PostgreSQL and KrakenD indexes were fetched and confirm linux/amd64 entries; PG amd64 manifest is `sha256:d8703cd7fba306b9fec9268ecedfa8a966846c053036a60e3635791957eb2f66`. Source CI for all four repos does not automatically mutate GitOps for this release.

Existing identity image remains `ghcr.io/chotabyorg/user-service:4b2f90e`, observed digest `sha256:047a7eed5270ac9c6569c765a95cfaf2ad7768a64c43fcccf1978ef128c7e76b`. Only its exact CORS origin list changes to Chota/Agents/CRM. API-host cookies remain host-only, Secure, SameSite=lax; email-verification policy remains false across all products. CORS alignment does not implement identity CSRF enforcement; CRM writes independently enforce exact Origin.

## Rendered inventory

New CRM backend Application: **17 objects**. Deployments `chota-crm-service`, `chota-crm-service-postgres`; two matching ClusterIP Services; PVCs `chota-crm-service-postgres-data` and `chota-crm-service-backups`; SealedSecret `chota-crm-service-secret`; NetworkPolicies `chota-crm-service-api`, `chota-crm-service-postgres`, `chota-crm-service-backup`; daily CronJob `chota-crm-service-backup`; initial Job `chota-crm-service-backup-initial-v01`; five hashed ConfigMaps for API, PG, backup environment, migration wrapper and unchanged backup/restore helpers.

New frontend Application: **4 objects** — Deployment, ClusterIP Service, ConfigMap and NetworkPolicy `chota-crm-web` (ConfigMap has hash suffix). New route `crm-chota-by` is added to the existing Traefik Application. Existing site changes its digest only; gateway changes exact config plus pins its existing digest; identity changes origin configuration only. No unrelated service spec, ApplicationSet, shared CI or Atlas file changes.

The active six overlays (CRM API, CRM web, site, gateway, identity, routes) render **52 objects total** including unchanged objects. Inert `operations/restore` renders3 temporary diagnostic objects and is outside every active Kustomization; its archive placeholder intentionally prevents execution until an operator selects a completed backup.

## Live baseline and capacity

Read-only SSH on September30: single Ready k3s1.35.5 node, 4CPU, allocatable8127796Ki (7937Mi), working memory6250Mi/78%, CPU817m/20%. Disk `/var/lib/rancher/k3s/storage` has90Gi free of197Gi. All22 Argo Applications Synced/Healthy at main3b44e639; ArgoCD3.3.9. StorageClass `local-path`: Delete reclaim, WaitForFirstConsumer, no expansion. No production NetworkPolicies preexist. Confirmed labels: gateway `app=chota-gateway`; identity `app=user-service,component=api`; CoreDNS `k8s-app=kube-dns` in kube-system; Traefik `app.kubernetes.io/name=traefik,app.kubernetes.io/instance=traefik-kube-system` in kube-system.

| New workload | CPU request / limit | Memory request / limit |
| --- | --- | --- |
| API or migration init (sequential) | 100m / 500m | 128Mi / 256Mi |
| CRM web | 50m / 500m | 128Mi / 256Mi |
| PostgreSQL | 100m / 500m | 128Mi / 384Mi |
| Each backup Job | 50m / 250m | 32Mi / 128Mi |
| Temporary restore drill, run separately | 50m / 500m | 64Mi / 256Mi |

CRM steady limits896Mi, scheduled-backup peak1024Mi; initial/manual overlap with scheduled backup can reach1152Mi. Requests are384Mi steady /416Mi with one backup. CRM API/web maxSurge0 and PG Recreate add no duplicate CRM replica. Existing site/gateway/identity retain their established rolling strategy; their old pods measured140/26/77Mi, so concurrent old/new overlap adds approximately243Mi at baseline (not a guaranteed bound: those inherited workloads have no limits). Initial worst-case sum of new limits plus that measured overlap is1395Mi against1687Mi observed headroom. This is tight enough to require immediate before/after rollout observation; do not run restore/load tests concurrently with initial convergence. Actual new local idle API68.8Mi, frontend54.6Mi and PG20.81Mi are smoke observations, not load capacity claims. Most preexisting workloads omit reservations; scheduler requests alone cannot prove free memory.

Immediately before merge recheck node working memory/disk/MemoryPressure, active Jobs and rollout overlap. Pause rollout if headroom is materially worse than this baseline, a node is pressured, or unrelated deployments are rolling; adjust only CRM limits/sequence through reviewed GitOps if necessary. After sync watch MemoryPressure/OOMKilled/eviction/restarts and actual pod usage. Use [rollback containment](README.md#rollback) if the node becomes pressured; do not compensate by changing unrelated applications manually.

## Secret preparation

A new48-byte cryptographic random password was generated only in process memory and serialized directly to the official kubeseal stdin. Only strict-scope ciphertext was written to the repository. POSTGRES_PASSWORD and DATABASE_URL contain the same generated credential; no existing Secret data was read. The public certificate was fetched through authenticated SSH using the controller Service proxy, SHA256 fingerprint `40:F4:81:3E:7F:03:6D:82:85:CC:D2:26:5E:D0:32:F6:03:1D:F0:9F:8B:53:39:E7:05:7A:C2:4A:F2:37:5D:A6`, valid2026-09-05 through2036-09-02. Controller0.36.6; temporary official darwin-arm64 kubeseal0.36.6 archive verified SHA256 `bb6a1cdf2f6e2cf034018c83822b27332b1a14691a4c79c7540e679ca20252c0` against the published checksum. No global tool installation.

## Executed preparation checks

- Kustomize v5 renders all22 production service overlays and the route overlay; no object-name or API/PG selector collisions. Static assertions cover immutable images, secret/config name rewriting including Job/CronJob, exact helper/config hashes, probes, private Services, dedicated volumes/retention and bounded backup schedule.
- Cluster kubectl1.35 strict **client-only dry-run** validated all52 active-overlay objects plus3 inert restore objects using the cluster schema. This does not execute admission, controllers, scheduling or image pulls and makes no cluster change.
- Isolated local PG18.6 + tree-identical reviewed backend image verified delayed PostgreSQL startup, two concurrent migrations completing one schema, advisory-lock blocking, hardened rootless/read-only API health/readiness, PG18 mount persistence through restart, separate backup volume, exact helper archive/mode0600, and exact isolated restore helper/cleanup. The operator restore wrapper also passed with no network or secrets, a read-only archive and local Unix-socket DB; its unresolved archive placeholder was independently refused before DB creation. Full synthetic16-table restore/invariant evidence already exists in the independent delivery report; this deployment test used an empty migrated schema.
- Final reviewed frontend1b87d50e (tree-identical to published a76dc47) was built locally and served `/`, `/health`, and `/third-party-notices.txt` with HTTP200 as UID1001, read-only root, no network and a256Mi limit; observed54.6Mi memory. This does not substitute for pulling the published image in production.
- Gateway config byte hash exactly matches the independently reviewed source (57 CRM +71 prior routes). Backup and restore helpers byte-identical to reviewed backend (`6d403b5c…4730` / `19c5e5d0…eee5`). Python/shell syntax and whitespace checks pass.
- No production Secret value or customer data read; no apply, live backup, production auth test or registry credential extraction.

## Required review and rollout sequence

1. Fresh independent Deployment Reviewer inspects this complete immutable GitOps diff, source/image provenance, scripts and results; only CLEAN permits merge. Source reviews do not replace this review.
2. Immediately recheck current main and the LIVE `prod-services` ApplicationSet. It still has `services/*/prod`, excluding only payment-service. The tracked `platform/argocd/prod.yaml` is stale explicit discovery. **Never apply or edit it for this release; never add overlapping standalone Applications.** These complete new directories will be discovered automatically on merge.
3. Confirm actual published images and existing `prod/ghcr-pull-secret`. Its existence/old workloads do not prove new private-package read access. No principal was discovered by decoding it. New CRM pull permission remains **UNVERIFIED** until the approved rollout/pull test; on ErrImagePull inspect safe events and correct package read grants or provision a dedicated sealed pull credential through review. Do not expose registry secrets. No product acceptance until actual Pod imageIDs match the intended manifest/index and both CRM pods run.
4. Merge reviewed GitOps PR; Argo is the only persistent deployment mechanism. Observe generated `chota-crm-service-prod` and `chota-crm-web-prod` ownerReferences to the live ApplicationSet, exact source path/revision, Synced/Healthy, SealedSecret Synced, PVC Bound and PG/API/web Ready. Verify migration container exit0, expected schema/readiness and no restarts/OOMs. Do not print environment/Secret data.
5. Verify network enforcement with approved temporary synthetic probes: gateway can reach CRM, unrelated in-cluster pod cannot reach API/PG, CRM reaches identity/DNS/PG, frontend is reachable by Traefik and cannot egress. Source selectors are verified, but CNI enforcement still needs this runtime check.
6. DNS A `crm.chota.by` →153.80.244.178 was created earlier, DNS-only. Verify current DNS and actual HTTPS certificate/chain/hostname (Traefik resolver `le`, existing HTTP01). Backend has no public Ingress/NodePort. Check approved credentialed CORS, one ACAO header, auth expiry/refresh, and existing Agents behavior.
7. Follow [backup runbook](operations/BACKUP.md): actual initial Job completion, stored archive metadata, scheduled freshness and separately approved disposable restore. Retain original database and both PVCs during any rollback. Same-server failure risk is expressly accepted; off-node storage is not a gate.
8. Fresh production tester runs synthetic business/booking-conflict/tenant-isolation/persistence flow and real browser Agents↔CRM SSO; fresh final reviewer must return PRODUCT ACCEPT. Argo Healthy alone is not acceptance.

Useful primary references: [PG18 mount behavior](https://hub.docker.com/_/postgres#pgdata), [Argo prune/delete protection](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/), [Kubernetes1.35 NetworkPolicy semantics](https://v1-35.docs.kubernetes.io/docs/concepts/services-networking/network-policies/), [kubeseal0.36.6 release/checksums](https://github.com/bitnami/sealed-secrets/releases/tag/v0.36.6). The upstream0.36.6 release notes call some release artifacts incomplete; the exact downloaded client checksum and existing controller version were independently verified.
