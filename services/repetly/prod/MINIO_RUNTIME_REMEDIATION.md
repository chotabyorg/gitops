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
| CVE-2026-39414 | All OSS releases; unbounded S3 Select CSV allocation; fixed in AIStor `RELEASE.2025-12-20T04-58-37Z` | High availability risk if an authenticated identity with the required object permissions can reach the S3 Select path. Repetly does not rely on S3 Select, but the current app policy has object read/write actions and this needs exact target verification. |
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
| `GHSA-hrxh-6v49-42gf` | `google.golang.org/grpc` `v1.81.1` | `1.82.1` | embedded `/usr/bin/mc` | **IMPORTANT**: the scanned client binary is not the running `minio` server process, but the candidate image still contains the vulnerable client and its release notes claim the dependency was bumped to `1.82.1`; require vendor resolution, a newer candidate, or a separately pinned/fixed client before treating the image as clean. |
| `CVE-2026-39414` | `github.com/minio/minio` `v0.0.2-0.20260807183435-59a3350e61d0` | none reported by Trivy | `/usr/bin/minio` | **VEX/product-mapping gate**: Trivy maps the binary to the OSS Go module and reports `affected`, while the vendor advisory states that AIStor fixed this S3 Select CSV DoS in `RELEASE.2025-12-20T04-58-37Z`; the reviewed AIStor candidate is newer, but this needs vendor-backed applicability evidence rather than silent suppression. |

The direct result is therefore **SECURITY CHANGES REQUIRED**, not a clean
`SECURITY PASS`. The `CVE-2026-39414` result is not accepted merely because
the application does not use S3 Select; the vendor product fix and the
Trivy-to-AIStor package mapping must be reconciled. The gRPC result must be
resolved even though the embedded `mc` executable is not the server process.

The official CycloneDX SBOM was scanned as supplemental evidence. Trivy
reported 197 HIGH/CRITICAL records: 12 CRITICAL and 185 HIGH, of which 12
were marked affected and 185 fixed. The report includes build, historical, and
embedded dependency records and Trivy warned that a third-party SBOM may be
inaccurate; it materially differs from the direct runtime scan and cannot be
used as a clean runtime verdict. The official SPDX JSON was structurally
downloaded and validated, but Trivy 0.72.0 could not decode it because some
external references have a PURL with no package name. No finding was hidden
with `--ignore-unfixed`.

### Required-CVE disposition

- `CVE-2026-40344`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2026-04-11T03-20-12Z` line. The old OSS runtime
  remains in the affected range and still requires migration.
- `CVE-2026-41145`: not reported by direct Trivy; candidate is after the same
  vendor-fixed AIStor `RELEASE.2026-04-11T03-20-12Z` line. The old OSS runtime
  remains in the affected range and still requires migration.
- `CVE-2026-39414`: direct Trivy finding on `/usr/bin/minio`; vendor advisory
  says fixed in AIStor `RELEASE.2025-12-20T04-58-37Z`, so the candidate is
  product-version-fixed but the scanner mapping requires VEX/vendor
  confirmation before release acceptance.
- `CVE-2026-34204`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2026-03-26T21-24-40Z` line.
- `CVE-2025-62506`: not reported by direct Trivy; candidate is after the
  vendor-fixed AIStor `RELEASE.2025-10-15T17-29-55Z` line.

The AIStor release feed currently lists newer-looking filenames than the
reviewed candidate, but the corresponding `RELEASE.2026-08-07T19-14-57Z` and
`RELEASE.2026-08-11T04-07-05Z` release-note URLs returned 404 during this run.
No newer candidate was substituted without verifiable artifacts and a fresh
S3/IAM regression.

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
kind/k3d runtime, or active Kubernetes context was available, so this is a
container/volume rehearsal and not PVC/Service proof.

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

## Irreversible operations and rollback

- OSS→AIStor migration is permanent according to the vendor documentation.
- The disposable OLD volume had no `.minio.sys/api-version` file; the
  disposable NEW AIStor volume reported `backendVersion.major=16`. This is
  not a production compatibility claim because the rehearsal used separate
  volumes and did not replace a live data volume.
- From AIStor `RELEASE.2026-04-11T03-20-12Z` onward, API auto-bump is enabled by
  default and can make downgrade impossible as soon as the cluster commits the
  new API version. Neither disposable container set
  `MINIO_API_AUTO_BUMP` or `MINIO_API_BUMP_BAKE_TIME` explicitly.
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

- final security acceptance of the exact candidate: Trivy found two HIGH
  findings and requires a gRPC embedded-client resolution plus
  vendor-backed VEX/applicability evidence for `CVE-2026-39414`;
- Kubernetes-specific Deployment/Service/PVC/Secret/ConfigMap/NetworkPolicy
  rehearsal and cluster-admin/operator validation;
- direct OSS-Deployment-to-AIStor data migration compatibility;
- live cluster image, PVC, bucket inventory, credential, console, TLS, and
  NetworkPolicy verification.

The exact candidate startup/platform smoke, licensed readiness, S3 contract,
restart persistence, container blue/green reconciliation, rollback contract,
and disposable IAM checks are complete. No production SSH session was
obtained, so live inventory and production preflight still require
cluster-owner access. Do not merge an active runtime image change until the
security disposition and Kubernetes-specific gates are attached to the
implementation PR.

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
