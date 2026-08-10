# AIStor GREEN runtime draft

This directory is an intentionally inert runtime-implementation scaffold for
GitOps #44. It is not referenced by
`services/repetly/prod/kustomization.yaml`, contains no Argo Application or
Helm release object, and must not be applied directly. The current BLUE
Deployment, Service, PVC, rollback patch, and storage-disabled boundary remain
unchanged.

## Intended production shape

- BLUE remains `repetly-minio` with the existing OSS PVC and rollback path.
- GREEN is an official AIStor Operator `ObjectStore` on a separate PVC.
- AIStor Free is single-node only. `servers: 1` is fixed; `volumesPerServer`
  and PVC `size` are deliberately unresolved until the read-only production
  preflight proves dataset size, filesystem usage, StorageClass behavior, and
  headroom. The template values must not be deployed until those placeholders
  are replaced and independently reviewed.
- The GREEN S3 Service remains private/ClusterIP until the reviewed endpoint
  cutover. TLS, NetworkPolicy, resources, probes, PVC protection, and the
  separate license Secret are mandatory.
- `MINIO_API_AUTO_BUMP=off` is mandatory at first GREEN start.

## Pinned vendor chart inputs

These are the exact public Helm packages inspected for this Draft on
2026-08-10. They are not yet approved for production activation and still
require rendered-image digest review against the target cluster.

| Chart | Version | Package SHA-256 |
| --- | --- | --- |
| `aistor-operator` | `5.11.3` | `da7ee3ba290939a5279a76b1dd8ec7717207c00e6ffbd7cb110178a7dc8af590` |
| `aistor-objectstore` | `1.0.17` | `a19401ab94da86f34eb5f1a53ea6502ed364bc139a60fac22042a4e192aeb304` |

Official package URLs:

- <https://helm.min.io/helm-releases/aistor-operator-5.11.3.tgz>
- <https://helm.min.io/helm-releases/aistor-objectstore-1.0.17.tgz>
- <https://helm.min.io/index.yaml>

The server candidate remains the reviewed immutable digest from PR #45:

```text
quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1
```

Before activation, render both charts with the target values, enumerate every
image, resolve every image to an immutable digest, scan each image, and attach
the result to the implementation PR. Do not rely on chart default tags.

## Admin-client gate

The server image's `/usr/bin/mc` is forbidden for all production bootstrap,
license, probe, lifecycle, admin, background, or troubleshooting work. The
currently published stable AIStor Client
`quay.io/minio/aistor/mc:RELEASE.2026-07-24T01-15-12Z` is pinned and scanned,
but is not eligible because it contains `grpc-go v1.81.1` (fixed `1.82.1`).

No admin Job, lifecycle hook, or reconciliation manifest is included until an
official client with `grpc-go >= 1.82.1` and zero HIGH/CRITICAL findings is
available and pinned by digest. The current BLUE `minio/mc` bootstrap hook must
not be reused for GREEN.

## Required gates before this scaffold can become active

1. Complete the production read-only preflight from
   `MINIO_RUNTIME_REMEDIATION.md`; never commit secret values.
2. Replace both value placeholders with an owner-reviewed capacity and
   StorageClass decision. Do not reuse `repetly-minio-data`.
3. Provide a separately sealed license Secret and object-store config Secret.
4. Select and scan an eligible separate admin client; add only its immutable
   image digest to the future admin Job/reconciliation package.
5. Render the exact chart versions and all dependent images; verify CRDs,
   RBAC, TLS, NetworkPolicy, probes, resources, PVC finalizers, and Service
   selectors in a disposable lower environment.
6. Keep this directory absent from the active production Kustomization until a
   separate owner-approved activation PR. Migration remains BLUE/GREEN:
   preflight → GREEN provision → initial reconcile → write freeze/final delta →
   Service to GREEN → bake. Rollback after GREEN writes is freeze →
   reverse-sync GREEN → BLUE → reconcile → `Service → BLUE` before writes
   reopen.

No production cluster, PVC, license, Service, IAM, or storage data is touched
by this Draft.
