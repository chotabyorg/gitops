# MinIO runtime remediation decision gate

Status: **blocked before runtime change**. This document is a reviewable
decision memo for GitOps #44. It intentionally does not change the active
production image, PVC, secrets, storage rollback patch, or scanner activation.

## Current deployment and security impact

The active Repetly production overlay is a repository-managed Kubernetes
`Deployment`, not a MinIO Community Operator `Tenant`:

- `repetly-minio` has one replica, `Recreate` strategy, and one `ReadWriteOnce`
  PVC mounted at `/data`;
- the desired server image is the floating-by-tag
  `minio/minio:RELEASE.2025-09-07T16-13-09Z`;
- the API is routed by the public HTTPS host
  `repetly-storage.chota.by`; the console has no Service or route;
- the bootstrap hook retains a root-backed application identity with
  `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on
  `arn:aws:s3:::repetly-homework/*`;
- `storage-disabled-rollback-patch.yaml` remains active, so Repetly does not
  receive usable S3 credentials and scanner traffic is still inert.

The live cluster image/digest and object inventory are **not yet confirmed**:
the supplied SSH endpoint currently rejects password-only authentication and
the available key requires an unknown passphrase. No production command was
run.

The issue's historical `minio/minio:latest@sha256:14cea...` CI pin must not be
treated as current runtime evidence. Re-resolving the mutable Docker tag now
returns different platform manifests. The repository itself has no immutable
MinIO image pin.

## Confirmed advisories

The current desired release is in the affected range for both P0 advisories:

| Advisory | Affected range / path | Applicability to this deployment |
| --- | --- | --- |
| CVE-2026-40344 | `>= RELEASE.2023-05-18T00-05-36Z` and `< RELEASE.2026-04-11T03-20-12Z`; Snowball auto-extract accepts a fabricated signature when a valid access key and bucket are supplied | Applicable to the runtime. Exploitation still requires a valid access key; the deployment has a write-capable application identity and a public S3 endpoint. |
| CVE-2026-41145 | Same range; unsigned-trailer `PutObject`/multipart path trusts query-string credentials without cryptographic signature verification | Applicable to the runtime under the same credential prerequisite. It can bypass the create-only application invariant if an access key is obtained. |
| CVE-2026-39414 | All OSS releases; unbounded S3 Select CSV allocation; fixed in AIStor `RELEASE.2025-12-20T04-58-37Z` | Applicable to the old OSS runtime; the exact AIStor candidate is newer than the vendor-fixed AIStor boundary and is dispositioned **NOT AFFECTED — scanner product/version mapping mismatch**. |
| CVE-2026-34204 | OSS releases through the final OSS line; crafted replication headers can poison SSE metadata for a write-capable identity; fixed in AIStor `RELEASE.2026-03-26T21-24-40Z` | Applicable as a conditional integrity/availability risk to the current write-capable identity. Repetly does not use replication headers. |
| CVE-2025-62506 | All versions before `RELEASE.2025-10-15T17-29-55Z`; restricted service/STS accounts can create unrestricted child accounts | Not demonstrated in this deployment because the application identity is a normal user and the repository does not configure STS/service-account creation. It remains a reason not to retain the old runtime. |

The two P0 vulnerabilities are not made safe by the current application
rollback: the MinIO API and bootstrap identity still exist, while credential
exposure would make the bypass reachable. Until migration, the vendor
workaround is to reject `X-Amz-Content-Sha256:
STREAMING-UNSIGNED-PAYLOAD-TRAILER` at the edge and limit write permissions to
trusted principals. This is defense in depth, not a replacement for upgrade.

Primary sources:

- <https://nvd.nist.gov/vuln/detail/CVE-2026-40344>
- <https://nvd.nist.gov/vuln/detail/CVE-2026-41145>
- <https://github.com/minio/minio/security/advisories/GHSA-h749-fxx7-pwpg>
- <https://github.com/minio/minio/security/advisories/GHSA-3rh2-v3gr-35p9>
- <https://github.com/minio/minio/security/advisories/GHSA-jjjj-jwhf-8rgr>
- <https://github.com/grpc/grpc-go/security/advisories/GHSA-hrxh-6v49-42gf>
- <https://docs.min.io/aistor/operations/licenses/>
- <https://docs.min.io/aistor/reference/cli/mc-license/mc-license-update/>
- <https://docs.min.io/aistor/upgrade-aistor-server/>
- <https://trivy.dev/docs/dev/docs/configuration/db/>
- <https://dl.min.io/aistor/minio/release/notes/>
- <https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0>
- <https://kind.sigs.k8s.io/docs/user/quick-start/>
- <https://www.min.io/pricing>

## Supported target options

### Option A — AIStor Free, single-node

AIStor Free is the only vendor-supported free-tier direction that matches the
current single-compute MVP shape. It requires an active license, supports a
single-node deployment, has no SLA/SLO, and excludes enterprise capabilities
such as distributed deployment and replication. The reviewed candidate is:

```text
quay.io/minio/aistor/minio:RELEASE.2026-08-07T18-34-35Z
linux/amd64 manifest: sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1
```

The candidate is newer than every fixed release listed above and is available
from the official AIStor release feed. The digest is recorded as a candidate
only for production; its startup/platform behavior is confirmed below, but it
is not authorized for the active production overlay.

The current Repetly CI workflow is not an exact-target validation: it starts
the historical open-source image
`minio/minio:latest@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`
and the historical `minio/mc` pin. Those checks are useful application
regression coverage, but they do not prove that this AIStor candidate starts,
preserves the S3 contract, or accepts the current IAM policy.

A disposable linux/amd64 smoke of the exact candidate was run locally on
2026-08-09 using tmpfs only. The image reported version
`2026-08-07T18:34:35Z`, formatted one pool with one online drive, and returned
live health `200`. Without a license, readiness returned `503` and bucket
creation was denied with `No license is installed`. This proved startup,
platform behavior, and the license gate only.

The owner has supplied an AIStor Free license locally and authorized it for
disposable rehearsal only. It was mounted read-only and applied to the
disposable alias with `mc license update`; the license file was not copied to
the repository, Git history, logs, or a production secret. Filtered license
metadata reported `status=success`, `plan=FREE`, no-expiry Free-tier
semantics, `product=AIStor`, and one node. License contents, identifiers, and
credentials remain secret material. The documented `mc license info` check
was used after application and after restart; `mc license register` was not
needed.

### Licensed disposable evidence — 2026-08-10

The exact immutable candidate was run as a separate disposable single-node
AIStor instance with a dedicated named volume, never a production PVC. The
licensed instance returned live and ready health `200`; `mc admin info`
reported AIStor version `2026-08-07T18:34:35Z`, one pool, and one online drive.
After a container restart, readiness remained `200`, the license metadata
remained valid, and a marker object written before restart was readable. This
is a disposable restart-persistence result, not production migration proof.

The full exact-target S3 contract suite passed **17/17**. It covered bucket
creation, object metadata and content type, HEAD/GET/range reads, matching and
stale `If-Match`, create-only `If-None-Match`, staging overwrite and ETag
invalidation, immutable promotion metadata, replay, a true concurrent winner,
lost-response reconciliation, foreign-canonical collision rejection,
presigned PUT/GET, CORS preflight, and delete/404 behavior.

The disposable IAM suite passed **6/6** for both identities. The application
policy allowed its intended object read/write/delete actions and denied bucket
listing; the scanner policy allowed reads only under the canonical and staging
homework prefixes and denied outside-prefix reads, writes, deletes, and bucket
listing. Direct user enumeration was denied to the non-admin identities.
These are synthetic disposable principals and do not authorize any production
identity or policy change.

## Direct image and SBOM security scan — 2026-08-10

The exact image was scanned from a locally saved immutable image archive, not
from a floating tag. The scanner was `Trivy 0.72.0` on linux/amd64,
`docker.io/aquasec/trivy@sha256:c6e969c5662a546ad5de4a73c2a6b7a7c627f86d916903e175aa623af5b97ada`.
The vulnerability database came from the documented public ECR repository
`public.ecr.aws/aquasecurity/trivy-db:2`, schema `2`, updated at
`2026-08-10T12:59:55Z`, with next update at `2026-08-11T12:59:55Z`.

The direct exact-image result is **0 CRITICAL / 2 HIGH**:

| Finding | Package and installed version | Fixed version | Exact target/path | Disposition |
| --- | --- | --- | --- | --- |
| `GHSA-hrxh-6v49-42gf` | `google.golang.org/grpc` `v1.81.1` | `1.82.1` | embedded `/usr/bin/mc` | **PRESENT BUT NOT RUNTIME-REACHABLE**: `/usr/bin/mc` is an auxiliary CLI; the normal image entrypoint starts only `/usr/bin/minio`, and no gRPC listener or xDS/RBAC server path was observed. Retain as an explicit owner-accepted residual image risk, not as a clean package result. |
| `CVE-2026-39414` | `github.com/minio/minio` `v0.0.2-0.20260807183435-59a3350e61d0` | none reported by Trivy | `/usr/bin/minio` | **NOT AFFECTED — scanner product/version mapping mismatch**: the exact binary reports AIStor `RELEASE.2026-08-07T18-34-35Z`, while the vendor advisory fixes the AIStor product at `RELEASE.2025-12-20T04-58-37Z`. Trivy is mapping the AIStor binary to the OSS Go module; the product release boundary is newer and the advisory is unambiguous. |

The direct result is therefore **CONDITIONALLY ACCEPTABLE WITH EXPLICIT
DISPOSITIONS**, not a clean package-level `SECURITY PASS`: the CVE is closed as
product-version not affected, while the embedded gRPC finding remains present
but not runtime-reachable and requires owner risk acceptance. No global ignore,
`--ignore-unfixed`, or generic suppression was used.

The official CycloneDX SBOM was scanned as supplemental evidence. Trivy
reported 197 HIGH/CRITICAL records: 12 CRITICAL and 185 HIGH, of which 12
were marked affected and 185 fixed. The report includes build, historical, and
embedded dependency records and Trivy warned that a third-party SBOM may be
inaccurate; it materially differs from the direct runtime scan and cannot be
used as a clean runtime verdict. The official SPDX JSON was structurally
downloaded and validated, but Trivy 0.72.0 could not decode it because some
external references have a PURL with no package name. No finding was hidden
with `--ignore-unfixed`.

### Product mapping, reachability, and VEX/CSAF reconciliation

The exact image was independently verified with `/usr/bin/minio --version` as
`RELEASE.2026-08-07T18-34-35Z` and with the immutable linux/amd64 manifest
`quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`.
The official MinIO advisory states that the OSS S3 Select CSV allocation issue
is fixed in AIStor `RELEASE.2025-12-20T04-58-37Z`; the reviewed binary is
strictly newer. The direct scanner sees the embedded Go build module name
`github.com/minio/minio`, which explains the OSS mapping without changing the
AIStor product identity. The checked official release-feed and Quay metadata
contained release notes and SBOMs but no VEX or CSAF artifact. The advisory's
product-version boundary is therefore the documented applicability evidence;
the finding is not hidden in Trivy.

The exact image metadata has entrypoint `/usr/bin/docker-entrypoint.sh` and
command `minio`. The entrypoint script only prepends `/usr/bin/minio` and
executes it; it does not invoke `mc`, run a shell hook, start a bootstrap
daemon, or expose a license helper. Kubernetes readiness/liveness are HTTP
probes against the MinIO health endpoints. `/usr/bin/mc` was invoked only by
the rehearsal operator action that installed the license, not by the normal
server lifecycle.

The disposable AIStor process tree contained only `/usr/bin/minio server
/data`; the exact image's listening sockets were TCP 9000 (S3 API) and 9001
(console), with no gRPC listener. `mc` is not a daemon and no xDS management,
gRPC RBAC server, or gRPC server process was reachable. The appropriate
classification is therefore **PRESENT BUT NOT RUNTIME-REACHABLE**, with the
residual risk limited to a future operator/script accidentally executing the
embedded CLI. Production acceptance must record that exception and keep the
image entrypoint/bootstrap contract unchanged.

Candidate freshness was rechecked against both the official release feed and
Quay. The reviewed candidate is the newest actually published Quay manifest;
newer-looking feed filenames such as `RELEASE.2026-08-07T19-14-57Z`,
`RELEASE.2026-08-11T04-07-05Z`, and later future-dated entries had no usable
Quay manifest during this run. No candidate substitution was made.

### SBOM/direct-image critical reconciliation

The official CycloneDX scan's 12 CRITICAL records are not twelve active
runtime vulnerabilities. The critical subset reconciles as follows:

| Finding | SBOM component/location | Runtime reachable? | Direct-image present? | Disposition |
| --- | --- | --- | --- | --- |
| `CVE-2026-53713` (two records) | Envoy Gateway `v1.6.3`/`v1.8.0` under `/integrationtests/go.mod` and `.claude/worktrees/...` | No; source/integration-test records | No | Build/test history in the third-party SBOM; supplemental only. |
| `CVE-2026-33322`, `CVE-2026-33419` | `github.com/minio/minio` `v0.0.0-20210304223623-fa9cf1251bc7` from historical `mc.RELEASE.2021-03-12T03-36-59Z` | No; old auxiliary binary record | No | Historical embedded/build record; not the current `/usr/bin/minio`. |
| `CVE-2026-33186` (two records) | gRPC `v1.26.0` in the historical `mc` binary and `v1.77.0` in integration-test source | No | No | Historical/test records; current direct findings are separately reported on `/usr/bin/mc` and `/usr/bin/minio`. |
| `CVE-2022-23806`, `CVE-2023-24538`, `CVE-2023-24540`, `CVE-2024-24790`, `CVE-2025-68121` | Go `stdlib` `1.16.1` in old `mc` and `1.25.0` in tool/build binaries | No | No | Auxiliary historical/toolchain records, not the active server filesystem. |

The remaining SBOM HIGH records similarly include old source worktrees,
integration-test modules, build caches, Node.js tooling, Python tooling, and
embedded auxiliary artifacts. The direct filesystem scan is the runtime gate:
it reports only two HIGH findings, `/usr/bin/mc` and `/usr/bin/minio`, and both
now have explicit dispositions above.

### Required-CVE disposition

- `CVE-2026-40344`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2026-04-11T03-20-12Z` line. The old OSS runtime
  remains in the affected range and still requires migration.
- `CVE-2026-41145`: not reported by direct Trivy; candidate is after the same
  vendor-fixed AIStor `RELEASE.2026-04-11T03-20-12Z` line. The old OSS runtime
  remains in the affected range and still requires migration.
- `CVE-2026-39414`: direct Trivy finding on `/usr/bin/minio`; classify as
  **NOT AFFECTED — scanner product/version mapping mismatch** because the
  vendor advisory fixes AIStor at `RELEASE.2025-12-20T04-58-37Z` and the exact
  AIStor candidate is newer. No official VEX/CSAF artifact was found in the
  checked release-feed or Quay metadata, so retain the advisory and exact
  version evidence in the review record.
- `CVE-2026-34204`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2026-03-26T21-24-40Z` line.
- `CVE-2025-62506`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2025-10-15T17-29-55Z` line.

The AIStor release feed currently lists newer-looking filenames than the
reviewed candidate, but Quay returned no manifest for
`RELEASE.2026-08-07T19-14-57Z`, `RELEASE.2026-08-11T04-07-05Z`, or later
future-dated entries. No newer candidate was substituted without a verifiable
immutable manifest, official artifact/SBOM, and fresh S3/IAM regression.

### Option B — AIStor Operator/ObjectStore migration

This is the vendor-documented Kubernetes migration path. It installs the
AIStor Operator, converts a Community Operator `Tenant` to an AIStor
`ObjectStore`, requires cluster-admin access and a license, and deliberately
deletes/recreates the managed object-store resources while retaining PVCs.
The procedure is permanent and cannot be reversed.

It does **not** directly apply to this repository-managed `Deployment`, because
there is no `Tenant` or Operator-owned PVC topology to convert. Adopting it
requires a separate architecture change and a lower-environment rehearsal;
creating a `Tenant`/`ObjectStore` manifest by analogy is not a safe migration.

### Option C — remain on open-source `minio/minio`

Rejected. The upstream repository is archived and vendor advisories direct OSS
users to AIStor for fixed releases. No current supported OSS security stream
was found that can be pinned as a production target for this workload.

## Decision gate

The minimum-risk supported direction remains **AIStor Free single-node** as a
rehearsal candidate. The owner has approved disposable AIStor Free rehearsal,
but production architecture and migration are explicitly **not approved**.
Before production work, the owner must confirm:

1. acceptance of the AIStor license and Free-tier limitations for production;
2. whether a one-way migration from this repository-managed workload is
   acceptable, or whether the storage architecture must first move to the
   supported Operator/ObjectStore model; and
3. the required outage/bake window and an operator with cluster-admin access.

This PR deliberately stops at that production gate. It does not invent an
in-place OSS-Deployment-to-AIStor migration.

Current rehearsal verdict: **BLUE/GREEN RECOMMENDED** for production data
movement; direct OSS-binary replacement on the existing production PVC is
**REJECTED / UNSUPPORTED** for this repository-managed topology. An
Operator/ObjectStore adoption remains a separate architecture decision, not
an automatic implementation of this PR.

## Preservation and migration plan after approval

Before any candidate is applied to data-bearing infrastructure:

1. Export MinIO config with `mc admin config export`, bucket metadata with
   `mc admin cluster bucket export`, and IAM with
   `mc admin cluster iam export`; store the exports encrypted outside Git.
2. Capture a JSON object inventory for `repetly-homework` including key, size,
   ETag, content type, metadata, and last-modified timestamp. Reconcile it with
   PostgreSQL `StoredFile` metadata and record counts/checksums.
3. Export the rendered Deployment, Service, PVC, bootstrap policy, and all
   Secret metadata. Never export plaintext root/application credentials to the
   repository or logs.
4. Preserve `repetly-minio-data`, `repetly-homework`, all objects, both
   application/scanner identities, bucket privacy, and the PostgreSQL metadata.
   Do not delete or recreate the existing PVC as part of rollback.
5. Rehearse the migration in a disposable environment using a separate PVC.
   The preferred production design is blue/green data migration to a
   vendor-supported AIStor ObjectStore, followed by a reviewed Service cutover;
   a direct replacement of the binary on this PVC is not vendor-documented for
   this deployment model.
6. Keep the rollback patch and scanner package inert during the runtime bake.
   Only after storage contract evidence and security sign-off may a separate
   activation change remove the rollback override or set `FILE_SCANNER_URL`.

### Disposable blue/green and rollback rehearsal — 2026-08-10

The current raw single-node OSS topology was modeled with the exact old
manifest `minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`
and a dedicated persistent Docker volume. The new side used the exact
licensed AIStor candidate and a different dedicated volume. Both had one
pool, one drive, bucket `repetly-homework`, synthetic application/scanner
users, and no production connectivity. No disposable Kubernetes cluster,
kind/k3d runtime, or active Kubernetes context was available during this
container/volume run; the separate disposable Kubernetes proof is recorded
below.

The documented backup mechanisms were exercised: old IAM export/import and
bucket metadata export/import, followed by `mc mirror` data transfer. Initial
reconciliation passed with **3 objects / 162 bytes**, identical keys, sizes,
ETags, SHA-256 content hashes, `Content-Type`, custom metadata, and private
bucket policy on both sides. IAM checks passed on both sides: application
GET/PUT/DELETE plus denied list, and scanner GET for canonical/staging plus
denied outside-prefix GET, PUT, DELETE, and list.

The client endpoint was cut over from OLD to NEW and the full S3 suite passed
**17/17** on NEW after a synthetic green-only write. That write was absent on
OLD before reverse-sync, proving that a simple endpoint rollback can lose new
writes. A controlled reverse-sync from NEW to OLD was then performed; final
reconciliation passed with **4 objects / 207 bytes** and identical keys, sizes,
ETags, and content. The rollback endpoint was switched back to OLD and the
full S3 suite passed **17/17**; the local rollback harness elapsed about one
second, which is not a production RTO/SLO measurement.

Production sequence must therefore be: write freeze or maintenance window,
final forward sync, reconciliation, reviewed Service cutover, contract and
IAM verification, controlled reopen, and preserve NEW/OLD until sign-off. Do
not introduce dual-write without a separate architecture decision.

### Disposable Kubernetes blue/green and rollback rehearsal — 2026-08-10

The Kubernetes rehearsal started with no current kube context. An official
kind `v0.32.0` binary was SHA-256 verified, and cluster
`repetly-gitops-20260810` used pinned arm64 node image
`kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95`.
The context was `kind-repetly-gitops-20260810`; no production kubeconfig or
context was used. The candidate and old images were loaded from exact local
image IDs and addressed by local immutable rehearsal tags because kind's
image loader imports digest references under an internal tag; the source image
IDs and digests were verified before loading and no floating registry pull was
used by the pods.

The disposable namespace modeled two raw single-node Deployments with
`strategy: Recreate`, separate `ReadWriteOnce` PVCs, separate old/new
Services, and an application-facing `minio-s3` Service. The old Deployment used
the exact OSS image; the new Deployment used the exact AIStor candidate and
`MINIO_API_AUTO_BUMP=off`. The license was created imperatively as a local
Kubernetes Secret and mounted only in the green pod. Synthetic root,
application, and scanner credentials were created only in the disposable
namespace; no license or credential YAML was written to Git.

Initial data migration created **3 objects / 64 bytes** on old, mirrored the
bucket to new, copied shared API settings, and recreated synthetic IAM
policies/users on both sides. Keys, sizes, and SHA-256 content hashes matched;
OSS and AIStor ETags differed as backend-specific values. Application IAM and
scanner IAM each passed **6/6** on old, new, and the application-facing
Service. The direct S3 suite had **18/18** passes on old, new, green Service,
and rollback Service (17 core contract cases plus bucket HEAD).

The actual Kubernetes sequence was:

1. `minio-s3` selected old pod `10.244.0.10`; readiness was `200`.
2. The selector changed to new pod `10.244.0.11`; no PVC or object mutation
   was part of the Service cutover, and readiness remained `200`.
3. A green-only application write was created through `minio-s3`; it was
   absent on old before reverse-sync.
4. Under write-freeze simulation, the delta was copied new → old. Final
   reconciliation passed with **4 objects / 84 bytes** and matching SHA-256
   hashes on both PVCs.
5. The selector changed back to old; readiness was `200`, S3 was `18/18`, and
   application/scanner IAM remained `6/6` each.
6. The green pod was restarted; its AIStor PVC retained the synthetic object
   and licensed readiness. The green Deployment was then deleted while old
   PVC remained `Bound`/`ReadWriteOnce`, old Service stayed healthy, and the
   reverse-synced object remained readable on old.

This proves disposable Kubernetes selector cutover, separate RWO storage,
license isolation, restart persistence, reverse-sync rollback, and green
workload deletion safety. It does not prove production PVC reuse or make
direct OSS-PVC binary replacement supported.

## Irreversible operations and rollback

- OSS→AIStor migration is permanent according to the vendor documentation.
- The disposable OLD volume had no `.minio.sys/api-version` file; the
  disposable NEW AIStor volume reported `backendVersion.major=16`. This is
  not a production compatibility claim because the rehearsal used separate
  volumes and did not replace a live data volume.
- From AIStor `RELEASE.2026-04-11T03-20-12Z` onward, API auto-bump is enabled by
  default and can make downgrade impossible as soon as the cluster commits the
  new API version. The Docker rehearsal containers did not set
  `MINIO_API_AUTO_BUMP` or `MINIO_API_BUMP_BAKE_TIME`; the disposable
  Kubernetes green Deployment explicitly set `MINIO_API_AUTO_BUMP=off`.
- Before a real upgrade, set `MINIO_API_AUTO_BUMP=off` on every server, or use
  a documented bounded `MINIO_API_BUMP_BAKE_TIME` such as `24h`, and require
  an explicit approval before any manual `mc admin update --bump-api`. No
  actual API bump was executed in this rehearsal.
- A rollback is a restore/cutover to the preserved old environment or an
  export/import recovery, not an assumption that an old binary can start after
  an API bump.
- The production rollback remains the existing GitOps patch: preserve PVC,
  SealedSecrets, bucket, user metadata, and PostgreSQL rows; keep storage and
  scanner disabled.

## Release gates still open

The following evidence is intentionally **not claimed** by this memo:

- final security sign-off of the exact candidate: `CVE-2026-39414` is
  dispositioned **NOT AFFECTED — scanner product/version mapping mismatch**;
  the embedded gRPC finding remains **PRESENT BUT NOT RUNTIME-REACHABLE** and
  needs explicit owner risk acceptance;
- production-cluster Deployment/Service/PVC/Secret/ConfigMap/NetworkPolicy,
  TLS, cluster-admin, and Operator validation; the disposable Kubernetes
  rehearsal is complete but is not production proof;
- direct OSS-Deployment-to-AIStor data migration compatibility;
- live cluster image, PVC, bucket inventory, credential, console, TLS, and
  NetworkPolicy verification.

The exact candidate startup/platform smoke, licensed readiness, S3 contract,
restart persistence, container and Kubernetes blue/green reconciliation,
rollback contract, and disposable IAM checks are complete. No production SSH
session was obtained, so live inventory and production preflight still require
cluster-owner access. Do not merge an active runtime image change until the
explicit gRPC risk acceptance and production-specific gates are attached to
the implementation PR.

## Decision status and implementation-PR gate

- **Blocker:** owner/security approval of the residual `GHSA-hrxh-6v49-42gf`
  image finding as `PRESENT BUT NOT RUNTIME-REACHABLE`; keep the direct Trivy
  finding visible and do not add a generic ignore.
- **Blocker:** production read-only preflight, cluster-owner access, exact
  image/PVC/Service/Secret/TLS/NetworkPolicy inventory, and final supported
  architecture decision.
- **Important:** keep `MINIO_API_AUTO_BUMP=off`, preserve both environments
  through the bake window, and require write-freeze + reverse-sync + reconcile
  for rollback after writes reopen.
- **Minor/tech debt:** formal production RTO measurement, encrypted backup
  restore rehearsal, TLS/NetworkPolicy validation, and the separate
  Operator/ObjectStore architecture decision remain to be scheduled.

A runtime implementation PR is **not ready to create**. A future
owner-approved implementation PR may use the blue/green sequence from this
memo; this Draft PR remains the decision/evidence gate and must not be merged
or applied to production.

## Activation boundary

After this memo is merged, all of the following must remain true:

- the scanner package is not in the active production Kustomization;
- `FILE_SCANNER_URL` is unset;
- `storage-disabled-rollback-patch.yaml` remains active;
- no production MinIO restart, API bump, PVC change, license registration,
  secret change, storage activation, scanner activation, or EICAR execution is
  performed.

This decision memo does not close #44. It is ready to be superseded by a
separate owner-approved architecture/license decision and a later runtime
implementation PR.
