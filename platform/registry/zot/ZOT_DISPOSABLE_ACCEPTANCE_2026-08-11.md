# Zot v2.1.20 disposable acceptance — 2026-08-11

Verdict:

> **LOCAL REGISTRY GATES PASS — PRODUCTION PREFLIGHT REQUIRED**

This is a lower-environment Docker rehearsal only. It did not use Kubernetes,
the production cluster, BLUE MinIO, GREEN AIStor, or Repetly storage.

## Candidate and tooling

- Host architecture: `arm64` / Docker `aarch64`.
- Official Zot image: `ghcr.io/project-zot/zot@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`.
- Multi-architecture index:
  `sha256:542e25be4d32e7879c0cfad93492a93c81b1e059cbd2d30d485d4bd567318234`.
- Local Docker image ID: `sha256:22462b7c31a805ea133fd6a17b2e92a663620029ec03b2e1d04aa1ae4d3c45cb`.
- Skopeo: `1.22.2`, official image digest
  `quay.io/skopeo/stable@sha256:c7d3c512612f52805023cd38351081dad7e2729fc13d14b701e47c7c8bdd6615`.
- Source artifact:
  `docker.io/library/busybox@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662`.
- Different overwrite source:
  `docker.io/library/busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0`.
- Destination endpoint: disposable TLS-only Zot on `localhost:5500`.
- Registry data: independent Docker volume `zot-v2120-data`.

## Identity and ACL results

| Identity/action | Result | Evidence |
| --- | --- | --- |
| Publisher read existing tag | PASS | Skopeo inspect returned the source digest |
| Publisher create unique tag | PASS | `create-unique-v2120` created |
| Publisher update existing tag | DENY | Different source manifest returned `requested access to the resource is denied` |
| Publisher delete | DENY | Skopeo delete returned `requested access to the resource is denied` |
| Puller read | PASS | Skopeo inspect returned the source digest |
| Puller create | DENY | New-tag copy returned `requested access to the resource is denied` |
| Puller update | DENY | Existing-tag copy returned `requested access to the resource is denied` |
| Puller delete | DENY | Skopeo delete returned `requested access to the resource is denied` |
| Anonymous pull | DENY | Skopeo inspect returned `authentication required` / HTTP 401 |
| Publisher outside `aistor/**` | DENY | Skopeo inspect returned `requested access to the resource is denied` |

Break-glass credentials were not used in the normal test flow.

## Digest and immutability results

The digest-preserving Skopeo copy used `--all`:

```text
source busybox index          sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
destination immutable-v2120   sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
destination create-unique-v2120  sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
```

The retry with the different `busybox` manifest failed, publisher delete
failed, and resolving `immutable-v2120` afterwards still returned the source
digest. No Docker rebuild or repack was used.

## Persistence and restore

- Zot restart: tag and digest remained unchanged; puller access returned HTTP
  200.
- Container/pod recreation on the same data volume: tag and digest remained
  unchanged; publisher access returned HTTP 200; UID/security settings were
  reapplied.
- Backup: the disposable volume was archived to `zot-data.tgz`; backup SHA256
  was `eb3300a38da3e40e489535e1afd161b7009b3bb3930a5fc52d2252887eb4168f`.
- Restore: the disposable volume was destroyed, recreated, restored, and
  started with the exact Zot image. Tag and digest remained unchanged; puller
  read succeeded; anonymous pull remained denied; publisher overwrite/delete
  remained denied.

## TLS and network controls

- TLS was enabled with the disposable self-signed certificate.
- A client trusting that certificate received HTTP 200 with publisher or
  puller credentials.
- The same trusted client without credentials received HTTP 401.
- The Docker harness has no Kubernetes NetworkPolicy engine. The scaffold
  NetworkPolicy remains fail-closed with production selectors as placeholders;
  namespace selectors, DNS egress, and node/kubelet image-pull paths require
  the approved production read-only preflight and rendered lower-environment
  Kubernetes validation. No production selector was guessed.

## Security context and resources

The running disposable container was observed with:

```text
UID/GID:                  1000/1000
read-only rootfs:         true
allowPrivilegeEscalation: no-new-privileges=true
effective capabilities:   0000000000000000
seccomp:                  2 (official Moby default profile)
writable paths:           registry data volume and /tmp tmpfs only
config/auth/TLS mounts:   read-only
```

The container started, served the registry, restarted, and recovered under
these settings. A lower-environment snapshot after restore observed about
`0.60%` CPU and `53.33 MiB` of `3.827 GiB` (`1.36%`) memory. These are not
production sizing values. Docker image metadata has no built-in healthcheck;
the `/v2/` TLS/auth response was used as the local probe equivalent. The
Kubernetes readiness/liveness probes still require rendered Kubernetes
validation after preflight.

## Fresh local review

| Category | Result |
| --- | --- |
| BLOCKER | None in the local registry scope |
| IMPORTANT | None in the local registry scope |
| MINOR | Zot logs a generated random `hashKey` because the disposable config does not enable UI/session flows; decide on a persistent value if those flows are activated |
| TECH DEBT | Validate Kubernetes NetworkPolicy selectors, kubelet path, probes, resource values, StorageClass/PVC, TLS hostname, and backup owner/RPO/RTO after preflight |

The local review covers the Zot config, ACL, digest immutability, independent
storage, TLS, Docker security context, restart/restore behavior, vulnerability
disposition, inert GitOps paths, and workflow. The local acceptance does not
approve production or resolve production-specific placeholders.

## Final local gate

**LOCAL REGISTRY GATES PASS — PRODUCTION PREFLIGHT REQUIRED**.

The remaining production activation blockers are production-specific facts and
rendered Kubernetes verification: approved read-only cluster identity, node
architecture/topology, independent StorageClass/PVC, TLS/Ingress, exact
NetworkPolicy selectors and kubelet path, resource values, backup/restore owner
and RPO/RTO, and final Pod imageID equality. If future Zot configuration adds
Git/worktree functionality, the owner reachability disposition must be
reopened immediately.
