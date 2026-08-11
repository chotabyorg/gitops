# Dedicated Zot registry scaffold

Status: **inert Draft scaffold — not a production deployment**.

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

## Hard boundaries

- Registry storage must be independent of current BLUE MinIO, future GREEN
  AIStor, and every Repetly storage bucket.
- StorageClass, PVC size, registry namespace, internal endpoint, and TLS
  hostname remain `REPLACE_WITH_...` fail-closed placeholders until the
  authorized production read-only preflight provides exact facts.
- Production rollout requires a separate approval and a new review of the
  rendered manifests.
- No active workload, Argo Application, service Kustomization, image reference,
  Secret, PVC, or Ingress is changed by this scaffold.

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

### Current image security gate

The pinned Trivy v0.72.0 image was used against both v2.1.20 platform
manifests on 2026-08-11. Both scans returned Debian 13.6 with zero HIGH or
CRITICAL OS findings and one HIGH in the bundled Zot Go binary:

```text
CVE-2026-71556 — github.com/go-git/go-git/v5 v5.19.1
fixed version: 5.19.2
CRITICAL: 0
```

This remains a **BLOCKER** for production activation because a fixed version
is available. The v2.1.18 image used by the disposable proof had five HIGH
findings and is not the production candidate. The exact scan evidence and
commands are in [`ZOT_IMAGE_SCAN_2026-08-11.md`](./ZOT_IMAGE_SCAN_2026-08-11.md).
Do not deploy v2.1.20 until a patched official image is scanned clean or the
owner explicitly accepts the residual risk in a separate approval.

The separate reachability review verdict is **NOT USED BY APPROVED REGISTRY
RUNTIME**: the cited go-git module is indirect/module metadata only in the
reviewed Zot source and exact amd64 binary, with no runtime Worktree path
identified. This does not suppress the Trivy finding or clear the image gate;
see [`ZOT_REACHABILITY_2026-08-11.md`](./ZOT_REACHABILITY_2026-08-11.md).

The multi-architecture index is documented for candidate selection only. The
final rendered workload must use the exact platform manifest digest selected
after node architecture preflight so that the Pod `imageID` can satisfy the
release invariant.

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

All failures are **BLOCKER**. Use pinned Skopeo or an equivalent
digest-preserving tool; reject a Docker rebuild/push that changes the manifest
digest.

## References

- [GitOps issue #47](https://github.com/chotabyorg/gitops/issues/47)
- [AIStor Draft PR #46](https://github.com/chotabyorg/gitops/pull/46)
- [Registry architecture audit](../../../services/repetly/prod/operations/aistor-green/REGISTRY_ARCHITECTURE_AUDIT_2026-08-11.md)
- [Disposable fallback evidence](../../../services/repetly/prod/operations/aistor-green/PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md)
- [Zot authentication and authorization](https://zotregistry.dev/v2.1.18/articles/authn-authz/)
- [Zot immutable tags](https://zotregistry.dev/v2.1.18/articles/immutable-tags/)
- [Harbor tag immutability](https://goharbor.io/docs/2.0.0/working-with-projects/working-with-images/create-tag-immutability-rules/)
