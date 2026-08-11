# Dedicated Zot registry scaffold

Status: **owner-approved conditional production path — inert Draft scaffold**.

Tracked by GitOps issue #47, `[P0] Add immutable private OCI registry for
AIStor runtime`. This platform dependency is intentionally separate from
AIStor GREEN and Repetly storage. The directory is not referenced by the
active ArgoCD `ApplicationSet`, any service overlay, or an active Kustomize
root. All resource files are `.template` files and cannot be applied as-is.

## Decision

Primary candidate: **Zot v2.1.20**, released 2026-08-04.

Pinned multi-architecture candidate index:

```text
ghcr.io/project-zot/zot@sha256:542e25be4d32e7879c0cfad93492a93c81b1e059cbd2d30d485d4bd567318234
```

Platform manifests:

```text
linux/amd64:   sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5
linux/arm64/v8: sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6
```

This is an architecture candidate, not production approval. Harbor remains
the alternative if the platform requires an organization-wide registry
service, richer governance/UI, central audit/search, or broader
replication/scanning workflows.

## Owner-approved P0 shape

- Namespace: `registry`; Zot: one replica, independent RWO PVC, `local-path`,
  `10Gi`.
- Endpoint: `registry.chota.by` through Traefik `websecure` and ACME resolver
  `le`; Traefik terminates the public certificate and forwards HTTP to the
  private Zot ClusterIP Service.
- Publisher: `zot-publisher`, read/create only. Puller: `aistor-puller`, read
  only. Break-glass: `zot-break-glass`, out-of-band and never a workload
  credential. Auth Secret: `registry/zot-registry-auth`, key `htpasswd`.
- AIStor puller Secret: `prod/aistor-zot-puller`, key `.dockerconfigjson`,
  separate from publisher auth.
- Node/containerd path: HTTPS `registry.chota.by` → Traefik → Zot Service
  `registry/zot-registry:5000`. Zot bootstraps from the exact public GHCR
  amd64 digest, avoiding circular image-pull dependency.

DNS, ACME issuance, Secret delivery, and the first mirror remain rollout
prerequisites. This PR creates none of them.

## Hard boundaries

- Registry storage must be independent of current BLUE MinIO, future GREEN
  AIStor, and every Repetly storage bucket.
- The read-only production preflight is now recorded. It found only the
  existing node-local `local-path` StorageClass and no current registry DNS or
  route. The owner explicitly approved this single-node P0 shape with
  deterministic rehydration; replicated/multi-node storage is follow-up debt.
- Production rollout requires a separate approval and a new review of the
  rendered manifests.
- No active workload, Argo Application, service Kustomization, image reference,
  Secret, PVC, or Ingress is changed by this scaffold.

## Production read-only preflight — 2026-08-11

Production is a single-node amd64 k3s `v1.35.5+k3s1` cluster with 4 CPU and
about 7.75Gi allocatable memory. The existing BLUE MinIO uses a separate 10Gi
RWO `local-path` PVC; the bucket inventory is one object / 356134 bytes and the
node filesystem has 116G free. Storage remains disabled because the Repetly
S3 environment entries are blank. There is no existing registry namespace or
`registry.chota.by` DNS/route. K3s embedded NetworkPolicy enforcement is
enabled; no registry or `prod` policy objects exist yet. Traefik already runs
ACME HTTP-challenge with `certResolver: le` on `websecure` routes.

These facts are documented in
[`PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md`](./PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md).
They narrow the design, but do not approve a node-local single-replica
registry without an owner-approved backup/restore plan and a proven kubelet
image-pull path.

## Production design ledger

| Contract | Current production-specific value | Readiness |
| --- | --- | --- |
| Node/platform | one `linux/amd64` k3s node | Resolved |
| Zot image | `ghcr.io/project-zot/zot@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5` | Exact amd64 candidate; GitHub x64 acceptance remains |
| Namespace | `registry` | Resolved in inert templates; creation is rollout-time |
| Registry storage | `local-path`, node-local, reclaim `Delete` | Owner-approved P0; replicated storage is follow-up debt |
| Registry PVC size | `10Gi` | Resolved; exact active footprint is 145455137 compressed bytes |
| Resources | requests `100m/256Mi`, limits `250m/384Mi` | Resolved conservative single-node budget |
| Endpoint | `registry.chota.by` → Traefik `websecure` → `registry/zot-registry:5000` | Resolved rollout contract; DNS/ACME prerequisite |
| TLS/trust | Traefik ACME `certResolver: le`; Zot backend is ClusterIP HTTP | Resolved preferred model; no containerd CA file when public trust works |
| NetworkPolicy | embedded kube-router enabled; Traefik ingress and CoreDNS egress selectors rendered | Resolved selectors; route rollout must verify enforcement |
| Auth model | publisher `read/create`; puller `read`; break-glass admin separate; anonymous deny | Contract resolved; identity names and Secret delivery remain out-of-band |
| Backup/RPO/RTO | deterministic rehydration from exact digest ledger; target RPO 24h/RTO 2h | Resolved P0; off-host snapshot is follow-up debt |
| Availability | one replica is the only viable current shape on one node | Owner-approved conditional P0; cached pulls may continue during outage |

This ledger deliberately leaves unresolved values fail-closed rather than
inventing production infrastructure. The exact evidence and owner actions are
in [`PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md`](./PRODUCTION_PREFLIGHT_ACCESS_2026-08-11.md)
and [`backup-restore-runbook.md`](./backup-restore-runbook.md).

## Identity contract

| Identity | Allowed | Forbidden | Use |
| --- | --- | --- | --- |
| Publisher | `read`, `create` | `update`, `delete` | Owner-controlled mirror job only; never a workload credential |
| Production puller | `read` | `create`, `update`, `delete` | Dedicated Kubernetes `imagePullSecret` |
| Break-glass admin | Explicit admin actions | Normal CI/workload use | Separate owner-controlled credential; mandatory audit |
| Anonymous | Nothing | Pull and all writes | Denied |

The registry ACL must enforce the publisher `read/create` boundary. A unique
tag convention alone is insufficient. The release invariant is:

```text
official source digest == private registry destination digest == production Pod imageID
```

Any mismatch is a blocker and fails closed.

## Security and operations contract

The final rendered deployment must prove:

- TLS with an approved CA/trust path and private-only access;
- repository-specific ACLs and NetworkPolicy, plus the node-level path needed
  for kubelet image pulls;
- non-root execution, read-only root filesystem where compatible, dropped
  capabilities, `seccompProfile: RuntimeDefault`, and no service-account token;
- CPU/memory requests and limits, startup/readiness/liveness probes, and a
  dedicated PVC;
- exact registry image digest, HIGH/CRITICAL scan result, and available
  SBOM/source evidence;
- backup/restore runbook with owner, retention, RPO/RTO, and tested recovery;
- documented outage behavior: cached running Pods may continue, while a new
  pull or reschedule can fail when the registry is unavailable;
- HA decision deferred until the production node topology and current
  single-replica requirement are known.

The template files in this directory are design inputs only. Before activation,
the exact Zot version must be validated against the rendered config schema and
the selected Kubernetes security context.

### Scanner status and exploitability disposition

The pinned Trivy v0.72.0 image was used against both v2.1.20 platform
manifests on 2026-08-11. Both scans returned Debian 13.6 with zero HIGH or
CRITICAL OS findings and one HIGH in the bundled Zot Go binary:

```text
CVE-2026-71556 — github.com/go-git/go-git/v5 v5.19.1
fixed version: 5.19.2
CRITICAL: 0
```

Scanner status: **Trivy 0 Critical / 1 High**. The finding remains visible and
is not suppressed. Per the owner security disposition, it is **not a
production activation blocker while the approved runtime/security contract is
unchanged**. The v2.1.18 image used by the historical disposable proof had
five HIGH findings and is not substituted for this v2.1.20 acceptance. The
exact scan evidence and commands are in
[`ZOT_IMAGE_SCAN_2026-08-11.md`](./ZOT_IMAGE_SCAN_2026-08-11.md).

The separate reachability review verdict is **NOT USED BY APPROVED REGISTRY
RUNTIME**: the cited go-git module is indirect/module metadata only in the
reviewed Zot source and exact amd64 binary, with no runtime Worktree path
identified. This does not suppress the Trivy finding. A new official Zot
release carrying `go-git >=5.19.2` is preferred when available; if future
configuration adds Git/worktree functionality, this disposition is invalid
and the finding must be re-reviewed. See
[`ZOT_REACHABILITY_2026-08-11.md`](./ZOT_REACHABILITY_2026-08-11.md).

The exact v2.1.20 Docker-level disposable contract passed locally; evidence is
in [`ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md`](./ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md).
The rendered Kubernetes rehearsal also passed locally in an arm64 kind cluster;
evidence is in
[`ZOT_K8S_KIND_ACCEPTANCE_2026-08-11.md`](./ZOT_K8S_KIND_ACCEPTANCE_2026-08-11.md).
The required amd64 follow-up is isolated in
`.github/workflows/zot-amd64-acceptance.yaml` on `ubuntu-24.04`, with a
disposable kind cluster, synthetic credentials/certificates, and no production
access or secrets. The previous local attempt was architecture-invalid and is
retained as negative evidence; see
[`ZOT_AMD64_K8S_ACCEPTANCE_2026-08-11.md`](./ZOT_AMD64_K8S_ACCEPTANCE_2026-08-11.md).
The local rehearsals use synthetic values and do not
approve production selectors, storage, TLS, image-pull reachability, or
resources.

The multi-architecture index is documented for candidate selection only.
Production is amd64, so the final workload must use the exact child digest
`sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`.
The abbreviated Kubernetes acceptance and final Pod `imageID` equality are
recorded by that workflow before Ready for Review.

## Required disposable/lower-environment acceptance

1. Publisher creates a unique content-identifying tag.
2. Resolve, inspect, and scan the destination; compare it with the official
   source digest.
3. Publisher retry to the same tag fails.
4. Publisher delete fails.
5. Puller can pull and cannot create/update/delete.
6. Anonymous pull fails.
7. Zot restart preserves the tag and digest.
8. Registry PVC restart/rebind preserves the tag and digest.
9. TLS, NetworkPolicy, probes, resource limits, and security context are
   observed in the rendered workload.

All acceptance failures are **BLOCKER**. Use pinned Skopeo or an equivalent
digest-preserving tool; reject a Docker rebuild/push that changes the manifest
digest.

## Production rollout sequence

1. Create `registry` and the out-of-band `zot-registry-auth` Secret; never
   store credentials in Git.
2. Publish DNS `registry.chota.by` to `153.80.244.178`, wait for public DNS,
   and let Traefik ACME `le` obtain the certificate.
3. Verify node/containerd HTTPS pull through Traefik. If public trust is not
   available, stop and add an explicit `registries.yaml`/CA contract.
4. Mirror the exact AIStor amd64 OCI artifacts with digest preservation and
   create `aistor-minio-e8394b040720`.
5. Create `prod/aistor-zot-puller` and only then render the inert AIStor
   template under its separate approval.

## References

- [GitOps issue #47](https://github.com/chotabyorg/gitops/issues/47)
- [AIStor Draft PR #46](https://github.com/chotabyorg/gitops/pull/46)
- [Registry architecture audit](../../../services/repetly/prod/operations/aistor-green/REGISTRY_ARCHITECTURE_AUDIT_2026-08-11.md)
- [Disposable fallback evidence](../../../services/repetly/prod/operations/aistor-green/PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md)
- [Zot authentication and authorization](https://zotregistry.dev/v2.1.18/articles/authn-authz/)
- [Zot immutable tags](https://zotregistry.dev/v2.1.18/articles/immutable-tags/)
- [Harbor tag immutability](https://goharbor.io/docs/2.0.0/working-with-projects/working-with-images/create-tag-immutability-rules/)
