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

### Rendered chart audit — 2026-08-10

The archives were rendered locally with Helm 3.17.3 using these exact values.
Neither archive contains `values.schema.json`; the Operator archive embeds six
CRDs as templates and the ObjectStore archive relies on the Operator CRD:

- `adminjobs.aistor.min.io`
- `aihubs.aistor.min.io`
- `objectstores.aistor.min.io`
- `policybindings.sts.min.io`
- `prompts.aistor.min.io`
- `warps.aistor.min.io`

The ObjectStore render is structurally correct for the intended contract:
`repository: quay.io/minio/aistor/minio@sha256` plus `digest:` renders as
`quay.io/minio/aistor/minio@sha256:<digest>`; `configuration.name` points to
`repetly-aistor-green-env`, `servers: 1` is present, PVC protection is true,
both services are `ClusterIP`, automatic certificates are enabled, and
`MINIO_API_AUTO_BUMP=off` is present. The capacity and StorageClass values are
deliberately invalid placeholders until preflight replaces them.

The Operator chart's exact default image inventory is an activation gate, not
an approval:

| Role | Rendered/default reference | Current status |
| --- | --- | --- |
| ObjectStore CR server override | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` | Exact reviewed digest; scan/evidence recorded in PR #45. |
| Operator controller + webhook | `quay.io/minio/aistor/operator:RELEASE.2026-07-21T22-41-48Z` | Floating tag; resolve digest and scan before activation. |
| Operator ObjectStore ConfigMap defaults | `minwall:RELEASE.2026-05-21T06-25-56Z`, `kes:RELEASE.2026-07-30T10-52-13Z`, `kes-sidecar:RELEASE.2026-07-14T22-03-37Z`, `minio:RELEASE.2026-08-07T18-34-35Z`, `minio-sidecar:RELEASE.2026-07-14T22-07-12Z` | Chart-configured tags; usage is conditional, the CR server digest overrides `minio`, and every dependency still requires digest resolution and scan. |
| AdminJob client | `quay.io/minio/aistor/mc:RELEASE.2026-07-24T01-15-12Z` | **Blocked**: grpc-go `v1.81.1`, fixed `1.82.1`; AdminJob controller is disabled in this scaffold. |
| Optional AIHub/Prompt/Warp | `quay.io/minio/aistor/aihub:RELEASE.2025-12-11T18-08-15Z`, `quay.io/minio/aistor/prompt:RELEASE.2025-01-17T21-55-43Z`, `quay.io/minio/aistor/warp:v1.5.0` | Disabled here; no activation without a separate owner decision and image review. |

With `operators.adminjob.disabled: true`, the rendered Operator release has no
AdminJob controller Deployment or `adminjob-operator` ConfigMap, so the
ineligible `mc` path is not activated. The AdminJob CRD remains chart-owned
metadata; it must not receive an AdminJob resource until the client gate is
closed. If AdminJob is enabled later, its `mc` image must be explicitly
overridden to a separately pinned, scanned, eligible client.

The chart's default Operator security context renders non-root UID/GID 1000,
`allowPrivilegeEscalation: false`, all capabilities dropped, and
`RuntimeDefault`; this is retained for the Operator. ObjectStore pod security,
NetworkPolicy, resource limits, probes, and external TLS trust still require a
separate owner-reviewed values decision. The Operator chart renders its own
Operator/webhook Services and MutatingWebhookConfiguration; the ObjectStore
Services remain private `ClusterIP` resources owned by the ObjectStore
controller.

The chart license contract was verified from the template: `license: ""`
creates no license Secret, while a non-empty value would create
`minio-license` with key `minio.license` in the Operator release namespace.
The draft's out-of-band Secret contract uses that exact name/key, but its
namespace placeholder must be resolved together with the release namespace.
The default empty `global.operator.watchedNamespaces` means cluster-wide
watch/RBAC mode; set an explicit approved namespace scope before activation.

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

The standalone exact-client reachability evidence is intentionally narrower:
the pinned `mc` binary was run as UID 1000 with a read-only root filesystem and
ephemeral `/tmp` against disposable synthetic OSS and AIStor endpoints. Alias,
ready, admin-info, config export, bucket/object operations, mirror, and help
paths completed as one-shot processes where the endpoint supported them; each
sample reported `process_exited=1` and `listener_count=0` while running. The
unlicensed AIStor endpoint correctly rejected readiness/license info. This
proves the approved one-shot boundary has no observed inbound listener or
daemon mode; it does not make the `mc` package clean and does not authorize its
production use while grpc-go remains below the fixed version.

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
