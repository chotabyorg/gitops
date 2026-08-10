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

The Operator chart's exact rendered dependency inventory is an activation
gate, not an approval:

| Role | Rendered/default reference | Current status |
| --- | --- | --- |
| ObjectStore CR server override | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` (`linux/amd64`) | Exact reviewed digest; direct scan `0 CRITICAL / 2 HIGH`, dispositions recorded in merged PR #45. |
| Operator controller + webhook | manifest `quay.io/minio/aistor/operator@sha256:50bd6c34a1d2e811cc881116dc3fcce210e2f5fc2276a3933d8cacf71b39d68a`; amd64 `sha256:b88e5cf563406719f67028a52fef9dac4049e555f44e263267c30a069d1d8166`, arm64 `sha256:d49c60db8ac8e2ae0b38fb5b20a16c1c765449fa0c0aee1cea4054b31c7e35d3` | Immutable; direct Trivy `0 CRITICAL / 1 HIGH` (`libacl` and `grpc-go v1.82.0`, fixed `1.82.1`). **Activation blocker.** |
| ObjectStore ConfigMap: minwall | manifest `quay.io/minio/aistor/minwall@sha256:cc74fc5d90115670a40df54459b7feaeb1c340af98866324b26a71ce2e77dc4d`; amd64 `sha256:0f831ea63e6269540f96b312020e1759ab2cd9218ef9c08c108756a54a4ccb99`, arm64 `sha256:b12f90900c7b5dfc532c4f48020a95d76b6c568092018fc702be963765d9b1c0` | Immutable; direct Trivy `0 CRITICAL / 18 HIGH` across `x/crypto`, `x/net`, `x/text`, and Go stdlib. **Activation blocker.** |
| ObjectStore ConfigMap: KES | manifest `quay.io/minio/aistor/kes@sha256:115f6b2bc586a9fc88ddb1342ead4a5df546dd719757bb5f1a411862688f6f21`; amd64 `sha256:7872b91e8cdd580f6eb7ef9d3608e54d228f10199acb83e3e69994ad80ace93e`, arm64 `sha256:dccb7efb1b579cd75d526c5a18ce2d554e8436a27a34fde4e9c1223c52a147f7` | Immutable; direct Trivy `0 CRITICAL / 0 HIGH`. KES is conditional; current ObjectStore values do not enable KES configuration. |
| ObjectStore ConfigMap: KES sidecar | manifest `quay.io/minio/aistor/kes-sidecar@sha256:e7070a20d8dbfce6608a5b7db9afc7bc43f239001680e141b423d7376fd3d473`; amd64 `sha256:fe0b7980565240ca415b8edb403b0361a17ff5f93e6e3b6774c0d1505096b57b`, arm64 `sha256:dde96b3d711cc80b9a5f9f3c6ab291c330a2a3797be5ceb8f164bf0a6cdfe621` | Immutable; direct Trivy `0 CRITICAL / 1 HIGH` (`CVE-2026-54369`, `libacl`). Conditional; **activation blocker if enabled**. |
| ObjectStore ConfigMap: MinIO sidecar | manifest `quay.io/minio/aistor/minio-sidecar@sha256:1cf294b61514a46786d4233e7f4ea66fe179dbb996114fc7af33d3e023961ebc`; amd64 `sha256:560e204d8fbd05d095719a39af0db36e177829528d80366962d1bc22102c9b57`, arm64 `sha256:dba488d488be201923b62859ed8f6c66e9cef79d1e0f488139b4b59763ce9558` | Immutable; direct Trivy `0 CRITICAL / 1 HIGH` (`CVE-2026-54369`, `libacl`). **Activation blocker.** |
| AdminJob client | `quay.io/minio/aistor/mc@sha256:132c8d47976ca9d60b8af26c77bb96d29ed6ae79e6428fa9464cd82803ff2010` | **Not rendered/activated**: AdminJob controller disabled. Owner-accepted only for separate one-shot use; direct Trivy `0 CRITICAL / 1 HIGH`, `grpc-go v1.81.1`. |
| Optional AIHub/Prompt/Warp | `quay.io/minio/aistor/aihub:RELEASE.2025-12-11T18-08-15Z`, `quay.io/minio/aistor/prompt:RELEASE.2025-01-17T21-55-43Z`, `quay.io/minio/aistor/warp:v1.5.0` | Disabled here; no activation without a separate owner decision and image review. |

With `operators.adminjob.disabled: true`, the rendered Operator release has no
AdminJob controller Deployment or `adminjob-operator` ConfigMap, so the
`mc` path is not activated. In this chart version the AdminJob CRD is also not
rendered when the controller is disabled. Future migration/admin work should
use a separate one-shot Job/package; do not enable the Operator AdminJob
subsystem merely because the current `mc` has an owner-accepted narrow-use
disposition.

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
watch/RBAC mode; this Draft now shows the actual chart key and lower-env
rehearsal uses `aistor-green`. The production namespace/scope remains a gate.

All direct scans above used Trivy `0.72.0`, the pinned scanner image, the
public ECR vulnerability database, HIGH/CRITICAL severity, and no
`--ignore-unfixed`. Findings are recorded as blockers or conditional blockers;
no generic suppression was applied.

### Disposable Operator/ObjectStore rehearsal — 2026-08-10

An isolated kind `v0.32.0` cluster was created with pinned node image
`kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95`.
The exact `aistor-operator 5.11.3` and `aistor-objectstore 1.0.17` archives
were installed with digest-pinned rendered images and `adminjob.disabled=true`.
The node was linux/arm64 while the reviewed server image is linux/amd64, so
the successful image start was an emulated lower-env controller-path result,
not a production platform proof.

Passed controller/resource evidence:

- ObjectStore and PolicyBinding CRDs became Established; AdminJob was not
  rendered because the controller was disabled.
- Operator and webhook Deployments were `1/1`, non-root UID/GID 1000 with
  `allowPrivilegeEscalation: false`; `WATCHED_NAMESPACES=aistor-green` was
  present. Webhook Service/MutatingWebhookConfiguration resolved to port 8443.
- ObjectStore reconciliation created the StatefulSet, one RWO `standard` PVC,
  `pvcProtection: true`, private ClusterIP S3/console/headless Services, auto
  TLS Secret, and the exact server/sidecar digests.
- Deleting the ObjectStore removed its workload/Services while the PVC stayed
  `Bound` with `aistor.min.io/pvc-protection` and Kubernetes PVC finalizers.
  Deleting the pod recreated it against the same PVC.
- A lower-env NetworkPolicy model was applied: ObjectStore ingress deny with
  DNS-only egress and webhook ingress only from the disposable kind API/node
  path. It is not a production selector and was deleted with the cluster.

The rehearsal intentionally did **not** claim S3/IAM/readiness success. The
license file path supplied earlier remained a placeholder and no valid local
`minio.license` file was discoverable; only a synthetic disposable Secret was
used, so AIStor correctly reported `license: invalid JWT`, health red, and
denied S3 operations. License material was never read or logged. A valid
disposable license is required to repeat S3/IAM, restart-object persistence,
and application contract checks.

The same lower-env run showed `resources: {}` for the MinIO container and no
explicit MinIO liveness/readiness probes in the current values; only the
sidecar readiness probe was present. This is an implementation blocker: add
owner-reviewed initial requests/limits and probes after lower-env measurement,
then re-run with a valid license. These values must not be treated as
production sizing.

## Admin-client gate

The server image's `/usr/bin/mc` is forbidden for all production bootstrap,
license, probe, lifecycle, admin, background, or troubleshooting work. The
currently published stable AIStor Client
`quay.io/minio/aistor/mc:RELEASE.2026-07-24T01-15-12Z` is pinned and scanned,
but is owner-accepted only for the narrow one-shot administrative/migration
boundary because it contains `grpc-go v1.81.1` (fixed `1.82.1`); it is not
package-clean. A newer clean official client remains preferred.

No AdminJob, lifecycle hook, or reconciliation manifest is included. Future
administrative/migration work should use a separate one-shot package under the
owner boundary; do not enable the Operator AdminJob subsystem. The current
BLUE `minio/mc` bootstrap hook must not be reused for GREEN.

The standalone exact-client reachability evidence is intentionally narrower:
the pinned `mc` binary was run as UID 1000 with a read-only root filesystem and
ephemeral `/tmp` against disposable synthetic OSS and AIStor endpoints. Alias,
ready, admin-info, config export, bucket/object operations, mirror, and help
paths completed as one-shot processes where the endpoint supported them; each
sample reported `process_exited=true` and `listener_count=0` while running;
successful shell exit codes were `0`, while endpoint-specific unsupported or
license-gated checks returned their separately recorded non-zero codes. The
unlicensed AIStor endpoint correctly rejected readiness/license info. This
proves the approved one-shot boundary has no observed inbound listener or
daemon mode; it does not make the `mc` package clean. Re-check the official
release feed and prefer a newer clean client before production migration.

`admin-client-job.yaml.template` is an inert contract only. It encodes the
owner boundary—immutable image, non-root, no token, read-only root, ephemeral
config/tmp, no Service, `restartPolicy: Never`, and TTL cleanup—without adding
an AdminJob CR or activating any production resource. The template must be
replaced or removed during the future migration review; it is not a license to
run generic troubleshooting containers.

## Required gates before this scaffold can become active

1. Complete the production read-only preflight from
   `MINIO_RUNTIME_REMEDIATION.md`; never commit secret values.
2. Replace both value placeholders with an owner-reviewed capacity and
   StorageClass decision. Do not reuse `repetly-minio-data`.
3. Provide a separately sealed license Secret and object-store config Secret.
4. Re-check the official client feed before migration, then use either a newer
   clean client or this owner-accepted client only in a separate immutable
   one-shot Job/package; never enable the Operator AdminJob subsystem.
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
