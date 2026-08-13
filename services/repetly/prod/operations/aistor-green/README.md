# AIStor GREEN runtime scaffold

This directory is an intentionally inert runtime-implementation scaffold for
GitOps #44. It is not referenced by
`services/repetly/prod/kustomization.yaml`, contains no Argo Application or
Helm release object, and must not be applied directly. The current BLUE
Deployment, Service, PVC, rollback patch, and storage-disabled boundary remain
unchanged.

## Intended production shape

- BLUE remains `repetly-minio` with the existing OSS PVC and rollback path.
- GREEN is an official AIStor Operator `ObjectStore` on a separate PVC.
- AIStor Free is single-node only: `servers: 1`, `volumesPerServer: 1`,
  independent `10Gi` RWO PVC, and `local-path`. The owner approved this P0
  topology; replicated/multi-node storage is follow-up technical debt.
- The GREEN S3 Service remains ClusterIP behind the existing public
  `repetly-storage.chota.by` route. BLUE owns that route before cutover and
  GREEN owns it only after the reviewed BLUE/GREEN cutover. This is required
  because one `S3_ENDPOINT` is used for server-side calls and browser
  presigned URLs.
- TLS, NetworkPolicy, resources, probes, PVC protection, and the separate
  license Secret are mandatory.
- `MINIO_API_AUTO_BUMP=off` is mandatory at first GREEN start.

The historical production read-only facts are recorded in
[`PRODUCTION_READONLY_FACTS_2026-08-11.md`](./PRODUCTION_READONLY_FACTS_2026-08-11.md).
The fresh owner-authorized recheck is recorded in
[`PRODUCTION_READONLY_RECHECK_2026-08-13.md`](./PRODUCTION_READONLY_RECHECK_2026-08-13.md);
the 2026-08-12 SSH-timeout file is retained as historical evidence.
The target is one amd64 k3s node with 4 CPU and about 7.75Gi allocatable
memory. A historical BLUE inventory recorded one object / 356134 bytes; those
values are evidence of the old snapshot only, not future migration expectations.
The rollout operator must collect a fresh BLUE baseline immediately before
initial copy and again after the write freeze. BLUE uses a separate 10Gi RWO
`local-path` PVC. The selected AIStor image path is the owner-approved
immutable Zot tag at
`registry.chota.by`; K3s embedded NetworkPolicy enforcement is enabled.

## Production design ledger

| Contract | Current production-specific value | Readiness |
| --- | --- | --- |
| ObjectStore/client namespace | `prod`; Operator release/watch scope is `prod` | Resolved for P0; render/RBAC review remains before activation |
| Node/platform | one `linux/amd64` k3s node | Resolved |
| AIStor Free shape | `servers: 1`, `volumesPerServer: 1` | Resolved by topology/product constraint |
| GREEN StorageClass | `local-path`, node-local, reclaim `Delete` | Owner-approved P0; replicated storage is follow-up technical debt |
| GREEN PVC size | `10Gi`, independent from BLUE | Resolved; matches approved single-node capacity baseline |
| Active server image | `registry.chota.by/aistor/minio:aistor-minio-e8394b040720`; source amd64 digest `sha256:e8394b...16a1` | Approved conditional Zot path; source/destination/Pod imageID equality required |
| Operator / sidecar images | exact linux/amd64 child pins in values | Resolved candidates; render/scan evidence remains before activation |
| Resources/probes | MinIO `500m/768Mi` → `1 CPU/1Gi`; sidecar `50m/32Mi` → `100m/128Mi`; Operator/webhook `200m/256Mi/500Mi ephemeral` → `500m/256Mi/500Mi ephemeral` | Fresh node baseline is recorded; rollout still requires live pressure/restart/PVC observation |
| Operator RBAC/TLS | `watchedNamespaces: [prod]`, `optOutAutomaticCertificates: true`, owner-approved TokenReview, OOB Operator/admission TLS | Rendered contract PASS; OIDC is future hardening, production Secret/CA availability remains external |
| AIStor server TLS | `disableAutoCert: true`, OOB `repetly-aistor-green-tls`, Traefik `ServersTransport.rootCAs` with OOB CA and `serverName=minio.prod.svc.cluster.local` | Licensed disposable runtime and live CRD/SAN/SNI checks passed; production route remains BLUE/inert |
| S3/TLS endpoint | `https://repetly-storage.chota.by` → Traefik `websecure` → GREEN Service HTTPS | Public hostname preserved for Repetly and browser presigned URLs; BLUE owns route before cutover |
| NetworkPolicy | Traefik→GREEN public path, Operator→GREEN internal path, CoreDNS/API egress | Live Traefik/CoreDNS labels and kube-router enforcement revalidated read-only |
| License/config/pull/TLS Secrets | `minio-license:minio.license`, `repetly-aistor-green-env:config.env`, `aistor-zot-puller:.dockerconfigjson`, four OOB TLS/CA contracts | Names/keys resolved; values remain out-of-band |
| Migration/rollback | Explicit baseline/copy/reconciliation, write freeze/final delta, health gate, and reverse-sync rollback contract below | Inert; no migration or cutover executed |

## Migration verification and cutover acceptance contract

This is a fail-closed rollout contract. It is documentation only: this inert
scaffold does not copy objects, freeze writes, change the public route, enable
storage, or activate the scanner.

### Pre-migration BLUE baseline

Immediately before the initial copy, the rollout operator must capture a
sanitized BLUE acceptance snapshot containing:

- bucket name;
- exact object count;
- exact total logical bytes;
- the exact set of object keys;
- each object's logical size;
- each object's content-integrity value.

The historical `1` object / `356134` bytes snapshot above must not be used as
the expected rollout value. The current baseline is always collected from BLUE
at the time of the approved migration.

### Content-integrity and reconciliation method

The approved one-shot migration/verification client or process must stream
each BLUE and GREEN object body into a cryptographic SHA-256 calculation. It
must not log object content or persist object bodies merely for verification.
Sanitized evidence may retain only a key-safe identifier, logical size, and
digest. ETag may be recorded as supplemental evidence, but it is never the
sole universal integrity gate because multipart and server-side encryption
semantics can make ETag differ from content MD5.

For every BLUE object, GREEN must contain the same key, logical size, and
SHA-256 content digest. Every reconciliation must report:

- key-set mismatch count;
- size mismatch count;
- integrity mismatch count;
- missing object count;
- unexpected GREEN object count.

Any non-zero mismatch, missing object, or unexpected GREEN object is
`STOP / NO CUTOVER`.

### Initial copy sequence

The approved sequence is:

1. Collect the fresh BLUE pre-copy baseline above.
2. Provision GREEN and prove its runtime health.
3. Perform the initial BLUE → GREEN copy without changing BLUE.
4. Reconcile the complete key set, object count, total logical bytes, per-object
   sizes, and per-object SHA-256 integrity.
5. Stop without route change if any reconciliation result is non-zero.

### Write freeze and final delta

Before final migration, the rollout operator must establish the application
and storage write freeze and prove that no new writes are admitted. Then:

1. Collect a fresh frozen BLUE baseline.
2. Perform the final BLUE → GREEN delta.
3. Repeat the complete key-set, count, byte, per-object size, and SHA-256
   reconciliation.

Final acceptance requires all of the following:

```text
BLUE object count                 == GREEN object count
BLUE total logical bytes          == GREEN total logical bytes
BLUE key set                      == GREEN key set
per-object integrity mismatches  == 0
missing objects                   == 0
unexpected GREEN objects         == 0
```

Any failed equality or non-zero count is `NO ROUTE CUTOVER`.

### GREEN pre-cutover health gate

The migration reconciliation must pass together with these GREEN gates before
the public Traefik backend is changed:

- ObjectStore `status.currentState=Initialized`;
- ObjectStore `status.healthStatus=green`;
- ObjectStore `status.setup=100`;
- every pool reports `PoolCreated` and the expected running server count;
- every expected container is Ready, with no Pending or CrashLoopBackOff and
  no unexpected restart during the reviewed observation window;
- `/minio/health/live`, `/minio/health/ready`, and
  `/minio/health/cluster` each return HTTP 200 over the reviewed verified TLS
  path;
- the production Pod imageID matches the approved official-source digest →
  Zot digest → production imageID invariant;
- the separately approved S3 contract, application IAM contract, and scanner
  IAM contract all pass.

Only after every gate passes may the separately approved rollout switch
`repetly-storage.chota.by` from BLUE to GREEN.

### Sanitized cutover acceptance record

Before cutover, capture a sanitized record containing:

- timestamp;
- BLUE and GREEN object counts;
- BLUE and GREEN total logical bytes;
- key-set, size, integrity, missing-object, and unexpected-object mismatch
  counts;
- GREEN health/status summary;
- exact production GREEN imageID;
- source/Zot digest reconciliation result;
- operator identity performing the gate;
- explicit `PASS`/`FAIL` decision.

The record must contain no Secret values, object contents, credentials,
license bytes, or signed URLs. Cutover requires an explicit `PASS`.

### Storage and scanner activation boundary

Changing the public route to GREEN does not authorize removal of the
storage-disabled rollback patch, application S3 credential activation,
scanner activation, `FILE_SCANNER_URL` activation, or closing #112. After a
GREEN route cutover, storage QA must be performed separately with synthetic QA
data: verify public/presigned S3 flows, expected TLS behavior, and object
read/write behavior; verify scanner integration separately; then obtain an
explicit QA/sign-off. Only a separate activation change may enable production
storage or scanner behavior. #112 remains Ready for Test until that QA/sign-off.

### Rollback and reverse-sync contract

If cutover fails before any accepted GREEN-only production writes, route back
to BLUE, verify BLUE health and data, and reopen writes only after that
verification.

If GREEN accepted writes after cutover, first freeze writes. Reverse-sync
GREEN → BLUE, then repeat the same key-set, count, byte, per-object size, and
per-object SHA-256 integrity reconciliation. Require zero mismatches, missing
objects, and unexpected objects; switch the route to BLUE; verify BLUE health
and the public path; only then reopen writes. Never route to stale BLUE and
reopen writes without successful reconciliation.

The historical sanitized evidence is in
[`PRODUCTION_READONLY_FACTS_2026-08-11.md`](./PRODUCTION_READONLY_FACTS_2026-08-11.md).

The current sanitized production evidence is in
[`PRODUCTION_READONLY_RECHECK_2026-08-13.md`](./PRODUCTION_READONLY_RECHECK_2026-08-13.md).

Fix C rendered/resource evidence is in
[`RESOURCE_AND_ROLLOUT_CONTRACT_2026-08-13.md`](./RESOURCE_AND_ROLLOUT_CONTRACT_2026-08-13.md)
and the TLS separation is in
[`aistor-green-tls-contract.md`](./aistor-green-tls-contract.md).
Admission webhook certificate evidence is in
[`ADMISSION_WEBHOOK_TLS_EVIDENCE_2026-08-12.md`](./ADMISSION_WEBHOOK_TLS_EVIDENCE_2026-08-12.md);
the current licensed disposable rehearsal is in
[`DISPOSABLE_FINAL_TLS_REHEARSAL_2026-08-13.md`](./DISPOSABLE_FINAL_TLS_REHEARSAL_2026-08-13.md).

## Fix C current gate

- `optOutAutomaticCertificates: true` removes the effective
  `aistor-object-store-certificate-management` ClusterRoleBinding. The chart
  still renders the auditable ClusterRole, but no service account receives it.
- TokenReview remains explicit by owner decision as the vendor-supported P0
  contract. The exact remaining cluster-wide exception is
  the vendor `aistor-object-store-cluster` binding (`nodes/get`, CRD `get`,
  and TokenReview binding management) plus the webhook cluster binding
  (`nodes/list`, mutating webhook configuration update).
- OIDC/JWKS is not a P0 gate. It is recorded as future hardening only:
  evaluate OIDC token validation to remove the remaining TokenReview
  cluster-wide RBAC exception.
- The admission webhook remains enabled. It is not disabled to hide RBAC; its
  exact custom serving Secret, CA bundle, and runtime admission proof are a
  separate contract.
- The exact chart render and before/after RBAC inventory are generated by
  `tests/validate-render.sh`. It downloads both chart packages and verifies
  their SHA-256 values before rendering.
- The final public S3 path is represented by
  `repetly-storage-ingressroute.yaml.template` and
  `aistor-servers-transport.yaml.template`; no insecure backend TLS bypass is
  permitted.

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

The complete official index snapshot, including every currently published
Operator/ObjectStore version, publication timestamp, and package SHA-256, is
recorded in [`OFFICIAL_HELM_INDEX_2026-08-11.md`](./OFFICIAL_HELM_INDEX_2026-08-11.md).
The current latest entries are Operator `5.11.3` and ObjectStore `1.0.17`.

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

The rendered chart inventory is not the active inventory. The following is the
licensed kind observation from Deployments, StatefulSets, Pods, initContainers,
containers, Jobs, and DaemonSets. Activation gates apply only to **A**.

### A — ACTIVE/RUNNING

| Runtime object | Exact immutable image | Scan and current disposition |
| --- | --- | --- |
| `object-store-operator` and `object-store-webhook` Deployments/Pods | `quay.io/minio/aistor/operator@sha256:50bd6c34a1d2e811cc881116dc3fcce210e2f5fc2276a3933d8cacf71b39d68a`; amd64 `sha256:b88e5cf563406719f67028a52fef9dac4049e555f44e263267c30a069d1d8166`, arm64 `sha256:d49c60db8ac8e2ae0b38fb5b20a16c1c765449fa0c0aee1cea4054b31c7e35d3` | Trivy `0 CRITICAL / 2 HIGH`: `libacl` and `grpc-go v1.82.0` fixed in `1.82.1`. `libacl`: **NOT USED BY RUNTIME BINARY**. gRPC: **PRESENT BUT VULNERABLE SERVER PATH NOT OBSERVED IN APPROVED RUNTIME**; finding remains visible and must be rechecked on an official fixed operator before activation. |
| `aistor-green-pool-0` StatefulSet/Pod `minio` container | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`; amd64 `sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`, arm64 `sha256:ff8cc4b57bc5259617b206466fa73636a2d862f80791dbed7ae44390acca7cd1` | Trivy `0 CRITICAL / 2 HIGH`: `grpc-go v1.81.1` is present in bundled `/usr/bin/mc`, not the running `minio` process; the owner-accepted one-shot boundary remains in merged PR #45. `CVE-2026-39414` is a scanner mapping mismatch: the official current release is beyond the advisory's affected range. |
| `aistor-green-pool-0` `sidecar` container and `sidecar-init` initContainer | `quay.io/minio/aistor/minio-sidecar@sha256:1cf294b61514a46786d4233e7f4ea66fe179dbb996114fc7af33d3e023961ebc`; amd64 `sha256:560e204d8fbd05d095719a39af0db36e177829528d80366962d1bc22102c9b57`, arm64 `sha256:dba488d488be201923b62859ed8f6c66e9cef79d1e0f488139b4b59763ce9558` | Trivy `0 CRITICAL / 1 HIGH`: `CVE-2026-54369/libacl`. **NOT USED BY RUNTIME BINARY**: no `acl_*` symbols were found in the exact `/sidecar` binary; the container runs UID/GID 1000 with zero effective capabilities, no privilege escalation, and only the `/tmp/minio` emptyDir plus read-only service-account mount. This is not a current activation blocker, but the finding remains visible and the next official fixed sidecar must be repinned/scanned/rehearsed. |

### B — RENDERED BUT NOT INSTANTIATED

| Config-only dependency | Evidence and disposition |
| --- | --- |
| Minwall `quay.io/minio/aistor/minwall@sha256:cc74fc5d90115670a40df54459b7feaeb1c340af98866324b26a71ce2e77dc4d` (amd64 `sha256:0f831ea63e6269540f96b312020e1759ab2cd9218ef9c08c108756a54a4ccb99`, arm64 `sha256:b12f90900c7b5dfc532c4f48020a95d76b6c568092018fc702be963765d9b1c0`) | `object-store-operator` ConfigMap has a `minwall` data key, but there is no Minwall Deployment, StatefulSet, Pod, initContainer, sidecar, Job, or hook. Trivy `0 CRITICAL / 18 HIGH` across x/crypto, x/net, x/text, and Go stdlib: **NOT ACTIVE IN APPROVED CONFIGURATION**; 18 HIGH is not a current activation blocker. Full reachability review is required if it materializes. |
| KES `quay.io/minio/aistor/kes@sha256:115f6b2bc586a9fc88ddb1342ead4a5df546dd719757bb5f1a411862688f6f21` and KES sidecar `quay.io/minio/aistor/kes-sidecar@sha256:e7070a20d8dbfce6608a5b7db9afc7bc43f239001680e141b423d7376fd3d473` | Both appear only as ConfigMap data keys. No KES/KES-sidecar runtime object exists and the current ObjectStore values do not enable KES. KES is `0 CRITICAL / 0 HIGH`; KES sidecar is `0 CRITICAL / 1 HIGH` (`CVE-2026-54369/libacl`). **DISABLED / NOT ACTIVE**; not a current blocker. |

### C — DISABLED/CONDITIONAL

`operators.adminjob.disabled: true` produces no AdminJob CRD, Deployment, Pod,
Job, hook, or active `mc` client. AIHub, Prompt, and Warp are disabled. The
exact owner-accepted `mc` one-shot image remains outside the active inventory:
`quay.io/minio/aistor/mc@sha256:132c8d47976ca9d60b8af26c77bb96d29ed6ae79e6428fa9464cd82803ff2010`,
direct Trivy `0 CRITICAL / 1 HIGH` (`grpc-go v1.81.1`).

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
The out-of-band Secret contract uses that exact name/key and remains out of
band; no license value is committed. The production Operator release/watch
scope is resolved to `prod`. Rendered RBAC/TLS validation has passed, while
production activation remains gated by a separate approved rollout.

All direct scans above used Trivy `0.72.0`, the pinned scanner image, the
public ECR vulnerability database, HIGH/CRITICAL severity, and no
`--ignore-unfixed`. No generic suppression was applied. Only the A inventory
is an activation gate; B/C findings are retained as conditional evidence.

### Official release-feed check — 2026-08-10

The public official Quay tag feed and MinIO download feeds were checked before
disposition. `latest` resolves to the same pinned child digests for Operator,
MinIO sidecar, Minwall, AIStor Client, and server. The official server
`RELEASE.2026-08-07T18-34-35Z` tag resolves to the current amd64 server digest
and arm64 child `sha256:ff8cc4b57bc5259617b206466fa73636a2d862f80791dbed7ae44390acca7cd1`.
The current AIStor Client feed ends at `RELEASE.2026-07-24T01-15-12Z`; the
Minwall feed lists `RELEASE.2026-05-21T06-25-56Z`; and the current Operator and
sidecar tags map to the pinned images. No newer official component with the
required fixes was found, so no unsupported or partial automatic upgrade was
made. Any future component-only replacement must prove chart-supported
override, compatibility, immutable digest, scan, and licensed lower-env PASS.

Checked official endpoints: <https://quay.io/repository/minio/aistor/operator?tab=tags>,
<https://quay.io/repository/minio/aistor/minio-sidecar?tab=tags>,
<https://quay.io/repository/minio/aistor/minwall?tab=tags>,
<https://dl.min.io/aistor/mc/release/notes/>, and
<https://dl.min.io/aistor/minio/release/notes/>.

### Disposable licensed Operator/ObjectStore rehearsal — 2026-08-10

A new isolated kind `v0.32.0` cluster was created with pinned node image
`kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95`.
The exact `aistor-operator 5.11.3` and `aistor-objectstore 1.0.17` archives
were installed with digest-pinned rendered images, a separately mounted valid
license Secret, `MINIO_API_AUTO_BUMP=off`, and `adminjob.disabled=true`. The
license path was checked only for readability/non-empty state; license bytes
were never read, logged, copied into Git, or printed. The node was linux/arm64
while the reviewed server image is linux/amd64, so this is an emulated
lower-env controller/runtime result, not production platform proof.

Licensed PASS evidence:

- The ObjectStore reached `healthStatus=green`, `setup=100`, `Drives Online=1`,
  and the pool was `1/1 Running`. `/minio/health/live`, `/minio/health/ready`,
  and `/minio/health/cluster` each returned HTTP 200 over the generated TLS
  Service. The controller's textual `currentState` remained
  `Waiting for ObjectStore to be healthy` despite green/setup 100. The
  2026-08-11 investigation below records the pre-fallback parser symptom;
  it is not a production BLOCKER once the approved Zot path is used.
- S3 contract: **18/18**. Application IAM: **6/6**. Scanner IAM: **6/6**.
  The exact pinned AIStor `mc` image was used as a disposable client with
  synthetic test identities; no AdminJob or background client was enabled.
- Before and after deleting `aistor-green-pool-0-0`, the same object remained
  readable with the same ETag. The recreated Pod was `Running`, both
  containers were ready, the PVC remained `Bound` at `1Gi`, and its
  `aistor.min.io/pvc-protection` plus Kubernetes finalizers remained present.
- The StatefulSet rendered the exact server image, `minio-sidecar` sidecar, and
  `sidecar-init` image from the A inventory. Operator/webhook Deployments were
  each `1/1`; the Operator watched only `aistor-green` in this rehearsal.

Functional lower-env NetworkPolicy evidence:

- An intended `aistor-client` namespace reached the ObjectStore health path
  through the S3 port and exited `0`.
- An `aistor-forbidden` namespace received the same request and exited `1`.
- ObjectStore ingress was default-deny except the intended namespace/port;
  egress was DNS-only. The webhook allowed only the disposable kind API/node
  path. These selectors and CIDRs are lower-env evidence, not production
  values; the committed NetworkPolicy template remains inert until the
  production namespace, client labels, DNS path, and API-server CIDR are
  reviewed.

Historical resource/probe observation and next contract (2026-08-11):

- Operator and webhook requests rendered as `200m` CPU, `256Mi` memory, and
  `500Mi` ephemeral-storage. The webhook had HTTPS `/healthz` readiness and
  liveness probes; the Operator controller had no probes.
- MinIO and `minio-sidecar` rendered `resources: {}`. MinIO had no explicit
  probes; the sidecar had only HTTP `/ready` readiness on port 4444. The
  evidence-backed probe endpoints for the next lower-env iteration are HTTPS
  port 9000 `/minio/health/live` for startup/liveness and
  `/minio/health/ready` for readiness.
- A non-production starting candidate for owner review is MinIO
  `requests: 500m/1Gi`, `limits: 2 CPU/4Gi`, sidecar `requests: 50m/32Mi`,
  `limits: 100m/128Mi`, startup `30 x 5s`, readiness `6 x 10s`, and liveness
  `3 x 10s`. These numbers are a lower-env contract candidate only, were not
  activated by this Draft, and must not be treated as production sizing.

### Official digest compatibility discovery — 2026-08-11

The official AIStor Object Store Helm documentation explicitly documents the
digest contract used by this Draft:

```yaml
image:
  repository: quay.io/minio/aistor/minio@sha256
  digest: <sha256>
  pullPolicy: IfNotPresent
```

Reference: <https://docs.min.io/aistor/reference/kubernetes/object-store-helm-chart/>.
The current `aistor-objectstore 1.0.17` chart renders that contract to the
exact `ObjectStore.spec.image` tested below. This is therefore not classified
as a Repetly values mistake.

### Minimal immutable-image reproduction matrix — 2026-08-11

Each row used a fresh disposable kind cluster, a licensed single-node
ObjectStore, one minimal PVC, current ObjectStore chart `1.0.17`, and the same
exact AIStor server digest. Case A is the documented digest form; B is a
plain-tag control only; C is a negative `tag@digest` control.

| Operator chart | Case A: documented digest | Case B: plain tag | Case C: tag@digest | Operator restart |
| --- | --- | --- | --- | --- |
| `5.11.3` | `Waiting`, green, setup 100, `PoolCreated/running=1`; `invalid image format` | `Initialized`, green, setup 100, `PoolCreated/running=1`; no parser error | `Waiting`, green, setup 100, `PoolCreated/running=1`; `invalid image format` | Same outcomes |
| `5.11.2` | Same as `5.11.3` | Same as `5.11.3` | Same as `5.11.3` | Same outcomes |
| `5.11.1` | Same as `5.11.3` | Same as `5.11.3` | Same as `5.11.3` | Same outcomes |

The exact CR and generated StatefulSet image strings were recorded for all
cases. Digest cases started the exact server image and reached green/setup100,
`drivesOnline: 1`, and `PoolCreated` with `podStatus.running: 1`, but the
Operator repeatedly logged:

```text
Error extracting tag from current image quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1: invalid image format
```

The `tag@digest` case emitted the same parser error for the combined image
string. The plain-tag control reached `Initialized` in all three chart
releases. The plain tag is not an OCI digest pin and is not an approved
production workaround. Full matrix evidence and the non-secret vendor payload
are in [`VENDOR_DEFECT_REPORT.md`](./VENDOR_DEFECT_REPORT.md).

All three tested 5.11.x charts declare the same Operator `appVersion`
`v20260721224148.0.0` and default Operator release tag. The active matrix
Operator image was pinned to
`quay.io/minio/aistor/operator@sha256:50bd6c34a1d2e811cc881116dc3fcce210e2f5fc2276a3933d8cacf71b39d68a`;
the sidecar and server image digests were unchanged. No tested release was a
security-approved winner, so no downgrade was promoted and no full S3/IAM
rehearsal was repeated for a non-winning candidate.

### Private-registry immutable-tag fallback — owner-approved conditional path — 2026-08-11

The only fallback investigated was an exact OCI mirror into a disposable
registry with TLS, private authentication, restricted push identity, and
registry-enforced `read/create` authorization without `update/delete`. A
Docker-native push was rejected as an integrity path because it converted the
OCI manifest and changed the digest. Pinned Skopeo `--preserve-digests` copied
the reviewed `sha256:e839...` manifest; the destination returned the same
digest, anonymous read returned `401`, and overwrite was denied.

Using the resulting private tag as an ordinary ObjectStore tag, a fresh
licensed Operator `5.11.3` / ObjectStore `1.0.17` rehearsal reached
`Initialized`, green, setup `100`, `1/1 Running`, and Kubelet imageID exactly
equal to the reviewed `sha256:e839...` after Operator and StatefulSet restart.
HTTPS health probes, PVC/object recovery, synthetic S3 CRUD, synthetic
application/scanner IAM, and disposable NetworkPolicy positive/negative tests
passed. The previously accepted full lower-env contract remains S3 `18/18`,
application IAM `6/6`, and scanner IAM `6/6` for the same exact server bytes;
the new tag-specific checks are recorded without claiming a new historical
harness count. Minwall and KES did not materialize in the actual runtime
inventory.

Full evidence, the Docker-format negative control, Trivy result, and current
registry architecture audit are in
[`PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md`](./PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md).
[`REGISTRY_ARCHITECTURE_AUDIT_2026-08-11.md`](./REGISTRY_ARCHITECTURE_AUDIT_2026-08-11.md).
The owner has accepted **`OWNER-APPROVED CONDITIONAL PRODUCTION PATH`** for
the fallback. It is not activated: the recommended architecture is
**`DEPLOY DEDICATED REGISTRY`**, existing GHCR is not accepted without
independent immutable-tag and identity-separation evidence, and the production
read-only facts are now collected. Activation remains conditional on the
rollout-time DNS/ACME/Secret contract, isolated amd64 acceptance, and final
rendered review. The owner-approved single-node storage, PVC sizes, resources,
selectors, and RPO/RTO are resolved for this P0; production remains inert.

The release invariant is:

```text
official source digest == private registry destination digest == production Pod imageID
```

Any mismatch is a blocker and must fail closed. The native direct digest path
is **`PREFERRED — VENDOR LIMITATION — native digest path unavailable; selected
immutable-registry fallback in use`**. The Zot fallback is the approved
conditional production path; a plain mutable public RELEASE tag remains
rejected.

When the vendor fixes the parser, the migration path is: disposable fix
rehearsal; exact Operator/sidecar/server scan; repeat S3/IAM/restart/PVC/
health/NetworkPolicy checks; switch ObjectStore back to the direct vendor
digest; verify Pod `imageID`; then retire the fallback tag through the approved
registry retention/delete process while preserving the evidence.

### CurrentState/status semantics investigation — 2026-08-11

The exact rendered `objectstores.aistor.min.io` CRD from Operator chart
`5.11.3` was inspected, not inferred from printer columns:

- `status.currentState`, `status.pools`, `status.revision`, `status.setup`,
  and `status.syncVersion` are required schema fields. `status.healthStatus`
  is a separate string field.
- The CRD declares no `status.conditions`, no `status.observedGeneration`, and
  no status timestamp/reason/message contract. `metadata.generation` was `1`;
  the runtime status had no observed-generation acknowledgement to use as a
  readiness gate.
- The chart archive contains templates and the CRD, but no Operator source
  code. The exact runtime binary exposed the reconcile log locations used
  below; vendor source was not modified.

The digest-only licensed run was timestamped and repeated:

1. At `2026-08-11T07:46:24Z`, the CR had `generation=1`,
   `currentState=Waiting for ObjectStore to be healthy`, `healthStatus=green`,
   `setup=100`, `drivesOnline=1`, and pool `PoolCreated/running=1`. There were
   no conditions, observedGeneration, reason, message, or status timestamps.
2. Operator logs first recorded `Object store healthy`, then failed the same
   reconcile with `Error extracting tag from current image
   quay.io/minio/aistor/minio@sha256:...: invalid image format`; the error
   repeated on periodic requeues.
3. Restarting the Operator reproduced the error and left the same
   `Waiting...` state. Deleting the ObjectStore Pod recreated it on the same
   Bound PVC, returned `2/2 Running` and `healthStatus=green`, but left the
   state unchanged.
4. A disposable `tag@digest` control also failed the same image parser. A
   clean, separate plain vendor-tag control (`RELEASE.2026-08-07T18-34-35Z`)
   reached `currentState=Initialized`, `healthStatus=green`, `setup=100`, and
   `PoolCreated/running=1` with no image-format error.

Historical pre-fallback disposition: **VENDOR LIMITATION — documented digest
syntax is incompatible with Operator 5.11.3 reconciliation**. The same result
was reproduced with the nearest official 5.11.2 and 5.11.1 charts. The owner
approved the immutable Zot content-tag fallback; a floating or mutable public
tag remains rejected. At that historical point, #46 remained Draft until the
fallback acceptance gates passed. The production read-only preflight is now collected, but the prepared non-secret report
is [`VENDOR_DEFECT_REPORT.md`](./VENDOR_DEFECT_REPORT.md); it has not been
submitted externally.

Authoritative production readiness criteria are all of the following:

- `status.currentState=Initialized` and no current/recent Operator reconcile
  error for the ObjectStore;
- `status.healthStatus=green`, `status.setup=100`, every pool is `PoolCreated`,
  and `podStatus.running` equals the requested server count;
- every active container is Ready with no CrashLoopBackOff/Pending/Crashing
  state and no unexpected restart during the observation window;
- `/minio/health/live`, `/minio/health/ready`, and `/minio/health/cluster`
  return HTTP 200 over the reviewed internal HTTPS path;
- the accepted S3 `18/18`, application IAM `6/6`, and scanner IAM `6/6`
  contracts pass after the final image/probe/resource render; and
- the exact target node architecture and child image digest are confirmed.

Green health/setup alone, and the text `Waiting...` alone, are not sufficient.

### Lower-env probe/resource failure rehearsal — 2026-08-11

The fresh lower-env control used the chart-native probe/resource fields with a
plain vendor tag only to isolate probe behavior from the image-parser blocker.
The resulting StatefulSet was inspected after Operator reconciliation:

| Container | Resources | Probes |
| --- | --- | --- |
| MinIO | requests `500m/1Gi`, limits `2 CPU/4Gi` | HTTPS `9000 /minio/health/live` startup `30 x 5s`; HTTPS `9000 /minio/health/ready` readiness `6 x 10s`; HTTPS `9000 /minio/health/live` liveness `3 x 10s` |
| `minio-sidecar` | requests `50m/32Mi`, limits `100m/128Mi` | vendor HTTP `4444 /ready` readiness only; no arbitrary liveness |

Fresh PVC startup completed `2/2 Running` with zero restarts and reached
`Initialized/green`. From inside the MinIO container, all three HTTPS health
paths returned `200` with test-only `-k`; normal curl validation against
`127.0.0.1` failed only because the generated certificate SAN is not the IP.
This is compatible with the kubelet HTTPS probe contract: Kubernetes documents
that HTTPS probes skip certificate verification and that startup success gates
readiness/liveness ([official probe documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/)).
No external DNS or Ingress is used by the probes.

Failure rehearsal in the disposable licensed control:

- **S3 unavailable/readiness:** freezing the MinIO server PID caused `/live`
  and `/ready` timeouts/HTTP `502`; kubelet emitted readiness failures and the
  Pod became `0/2` during recovery.
- **Liveness:** kubelet logged `Container minio failed liveness probe, will be
  restarted`; after the disposable process was resumed so termination could
  complete, MinIO restart count became `1`, the Pod returned `2/2`, and the CR
  returned `Initialized/green`. The synthetic freeze was not applied to
  production and did not produce a CrashLoopBackOff.
- **Startup/PVC:** the fresh PVC run had no premature restart loop and retained
  both `aistor.min.io/pvc-protection` and Kubernetes PVC protection finalizers.

The candidate above remains lower-env evidence, not production sizing.
`kubectl top` was unavailable in kind, so point observations were collected
from container cgroups/processes instead: Operator RSS about `105MiB`, webhook
RSS about `89MiB`, MinIO RSS about `205MiB` with cgroup memory about `95.5MiB`
at idle and `99.9MiB` during the disposable `mc` S3 sample, and sidecar RSS
about `26MiB`. Cumulative cgroup CPU samples were also captured, but are not
normalized capacity measurements. No MinIO ephemeral-storage value is promoted
to production; the Operator/webhook observed `500Mi` ephemeral request remains
the only explicit current contract.

The Operator has no chart-provided controller health probe; its HTTP `4221`
Service was inspected but no supported readiness/liveness endpoint was proven.
The webhook's vendor HTTPS `/healthz` probes remain unchanged.

### NetworkPolicy recheck after probes/resources — 2026-08-11

With the lower-env probe/resource render active and ObjectStore
`Initialized/green`:

- intended `aistor-client` namespace: **PASS — allowed request succeeded**;
  disposable health GET exited `0`;
- `aistor-forbidden` namespace: **PASS — forbidden request was blocked**; the
  same GET exited `1` with a timeout;
- Operator reconciliation remained healthy and the ObjectStore stayed
  `2/2 Running`.

The committed NetworkPolicy at that historical point used direct Repetly and
scanner selectors. Fix C replaces those selectors with the final public
Traefik path. The 2026-08-13 production snapshot confirms the exact live
Traefik/CoreDNS labels and active k3s embedded kube-router enforcement. The
disposable AIStor node was `linux/arm64`; use the reviewed amd64 child digests
for production.

### Historical local review verdict — 2026-08-11

| Class | Finding | Disposition |
| --- | --- | --- |
| **VENDOR LIMITATION** | Native direct AIStor digest reconciliation is rejected by Operator 5.11.3/5.11.2/5.11.1; the ordinary immutable Zot tag path converged in the licensed rehearsal | **Not a production BLOCKER** once the Zot source/destination/Pod imageID invariant and amd64 acceptance pass. Selected disposition: `native digest path unavailable; selected immutable-registry fallback in use`. |
| IMPORTANT | DNS/ACME issuance and out-of-band Secret delivery are rollout prerequisites; no production endpoint or Secret exists yet | Keep templates inert; execute only in a separately approved rollout. No prod mutation is part of this task. |
| MINOR | Kind Metrics API is unavailable; lower-env CPU observations are cumulative cgroup samples | Do not treat lower-env samples as sizing; collect target-cluster metrics in preflight. |
| TECH DEBT | Exact vendor source for the proprietary Operator is not present in the chart archive | Retain chart/CRD/binary log evidence and request vendor source/release confirmation; no vendor code changes. |

That verdict predates Fix C and is retained as historical evidence. The current
gate additionally requires rendered RBAC/TLS, public S3/Traefik trust, current
resource inventory, production labels, real-CNI NetworkPolicy CI, and the
current-head validation workflows.

## Active HIGH reachability dispositions

### Operator `grpc-go v1.82.0` — GHSA-hrxh-6v49-42gf

The exact active Operator manifest scan is `0 CRITICAL / 2 HIGH`: `libacl`
`2.3.1-4.el9` and `google.golang.org/grpc v1.82.0`, fixed in `1.82.1`. The
official advisory covers xDS RBAC authorization bypass, HTTP/2 Rapid Reset
resource exhaustion, and an xDS RBAC panic path; it is retained visibly at
<https://github.com/grpc/grpc-go/security/advisories/GHSA-hrxh-6v49-42gf>.

Runtime evidence separates dependency presence from a reachable vulnerable
server path:

- The controller process is `object-store -license /tmp/license/minio.license`;
  its Service is named `http` on TCP `4221`. The webhook process is
  `pod-mutating-webhook -v 2`; its Service is TCP `8443` and the
  MutatingWebhookConfiguration uses HTTPS `/mutate`, `AdmissionReview v1`,
  `CREATE pods`, and `failurePolicy: Fail` only in the watched namespace.
- Socket tables showed the controller listener on `4221` and webhook listener
  on `8443`, with Kubernetes API traffic on `443`; no separate gRPC Service or
  gRPC listener was observed. The webhook `/healthz` returned HTTP/2
  `text/plain` `200`, while a canonical gRPC health POST returned HTTP/2
  `text/plain` `404`, not `application/grpc` or a gRPC status trailer.
- Static strings in the exact Operator binary contain gRPC/xDS/RBAC library
  symbols, including `grpc.Server`/`RegisterService`; that proves the
  dependency is present but does not prove a runtime gRPC server registration.
  No xDS endpoint/configuration was present in the rendered Pod args, active
  Services, webhook object, or approved NetworkPolicy path.

Disposition: **PRESENT BUT VULNERABLE SERVER PATH NOT OBSERVED IN APPROVED
RUNTIME**. This is an evidence disposition, not a suppression: keep the HIGH
visible, re-scan on every Operator change, and treat any future reachable
gRPC/xDS server path as a blocker until the official fixed component is
repinned and rehearsed.

### `libacl` CVE-2026-54369

The active Operator and required `minio-sidecar` images were checked against
the exploit preconditions: a local attacker must control a pathname/symlink,
the vulnerable ACL functions must be called, and a privileged caller must
operate on that path. Both active processes run as UID/GID 1000 with zero
effective capabilities and `allowPrivilegeEscalation: false`. The exact
Operator `/aistor-operator` and sidecar `/sidecar` binaries contain no
`acl_get_file`, `acl_set_file`, `acl_extended_file`, `acl_delete_def_file`, or
related `acl_*` strings. The sidecar's writable path is only the internal
`/tmp/minio` emptyDir; its service-account mount is read-only and it has no
PVC/hostPath.

| Active image | Package finding | Runtime outcome | Remediation |
| --- | --- | --- | --- |
| Operator | `libacl 2.3.1-4.el9`, fixed `2.4.0-1.el9_8` | **NOT USED BY RUNTIME BINARY**; no ACL call path or attacker-controlled pathname was observed | Keep finding visible; repin only an official compatible fixed Operator when published, then re-scan/rehearse. |
| Required MinIO sidecar + init | `libacl 2.3.1-4.el9`, fixed `2.4.0-1.el9_8` | **NOT USED BY RUNTIME BINARY**; non-root/capability evidence also fails the privileged-caller precondition | Keep required sidecar in the approved image set; replace only with an official compatible fixed digest after scan and lower-env PASS. |

This is why the sidecar's `1 HIGH` is not left as an unexplained blocker and
is not silently ignored.

### Active server image findings

The exact active server scan is `0 CRITICAL / 2 HIGH`:

- `GHSA-hrxh-6v49-42gf` is mapped to the bundled `/usr/bin/mc` dependency
  (`grpc-go v1.81.1`), not the running `/usr/bin/minio` process. AdminJob and
  all hooks are disabled, and no `mc` Pod/Job exists. The narrow one-shot
  owner disposition remains in merged PR #45; it is not an active server
  ingress or background process.
- `CVE-2026-39414` is described as S3 Select CSV unbounded-memory DoS for
  releases before `RELEASE.2025-12-20T04-58-37Z`. The active amd64 digest is
  also the official `RELEASE.2026-08-07T18-34-35Z`/`latest` amd64 digest, so
  this is **NOT AFFECTED — scanner mapping mismatch**, not a generic waiver.
  The official release feed and exact digest remain recorded for re-check.

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
ephemeral `/tmp` against disposable synthetic OSS and a licensed AIStor
endpoint. Alias, ready, admin-info, bucket/object operations, mirror, share,
and help paths completed as one-shot processes; the licensed contract returned
S3 `18/18`, application IAM `6/6`, and scanner IAM `6/6`. Each sample had
`listener_count=0` while running. This proves the approved one-shot boundary
has no observed inbound listener or daemon mode; it does not make the `mc`
package clean. Re-check the official release feed and prefer a newer clean
client before production migration.

`admin-client-job.yaml.template` is an inert contract only. It encodes the
owner boundary—immutable image, non-root, no token, read-only root, ephemeral
config/tmp, no Service, `restartPolicy: Never`, and TTL cleanup—without adding
an AdminJob CR or activating any production resource. The template must be
replaced or removed during the future migration review; it is not a license to
run generic troubleshooting containers.

## Required gates before this scaffold can become active

1. Review the collected facts in
   `PRODUCTION_READONLY_FACTS_2026-08-11.md` against the procedural checklist
   in `PRODUCTION_READONLY_PREFLIGHT.md`; never commit secret values.
2. Verify the current read-only recheck in
   `PRODUCTION_READONLY_RECHECK_2026-08-13.md`, including exact Traefik labels,
   Traefik version/ServersTransport support, and fresh
   requests/limits/ephemeral-storage data. OIDC/JWKS is future hardening, not
   a P0 Ready gate.
3. Verify the resolved capacity/StorageClass values (`10Gi`, `local-path`) and
   confirm that the GREEN PVC is independent from `repetly-minio-data`.
4. Provide separately sealed license, object-store config, Operator TLS,
   admission webhook TLS/CA, AIStor server TLS, and Traefik root CA Secrets.
5. Re-check the official client feed before migration, then use either a newer
   clean client or this owner-accepted client only in a separate immutable
   one-shot Job/package; never enable the Operator AdminJob subsystem.
6. Render the exact chart versions and all dependent images; verify CRDs,
   RBAC, TLS, NetworkPolicy, probes, resources, PVC finalizers, and Service
   selectors in a disposable lower environment.
7. Before production cutover, repeat the full licensed ObjectStore/TLS
   reconciliation on native `linux/amd64`, or obtain equivalent
   production-platform proof during the separately approved rollout rehearsal.
   The fresh 2026-08-13 licensed rehearsal passed on native `linux/arm64`;
   its Service/SAN/SNI evidence is not incorrectly promoted as amd64 proof.
8. Keep this directory absent from the active production Kustomization until a
   separate owner-approved activation PR. Follow the complete
   [migration verification and cutover acceptance contract](#migration-verification-and-cutover-acceptance-contract),
   including per-object SHA-256 reconciliation, explicit GREEN health gates,
   storage/scanner separation, and reverse-sync rollback.

No production cluster, PVC, license, Service, IAM, or storage data is touched
by this inert scaffold.
