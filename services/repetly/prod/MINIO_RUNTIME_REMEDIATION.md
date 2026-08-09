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
only; it is not authorized for the active production overlay.

The current Repetly CI workflow is not an exact-target validation: it starts
the historical open-source image
`minio/minio:latest@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`
and the historical `minio/mc` pin. Those checks are useful application
regression coverage, but they do not prove that this AIStor candidate starts,
preserves the S3 contract, or accepts the current IAM policy.

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

The minimum-risk supported direction is **AIStor Free single-node**, but it
cannot be approved for production until the owner confirms:

1. acceptance of the AIStor license and Free-tier limitations;
2. whether a one-way migration from this repository-managed workload is
   acceptable, or whether the storage architecture must first move to the
   supported Operator/ObjectStore model; and
3. the required outage/bake window and an operator with cluster-admin access.

This PR deliberately stops at that gate. It does not invent an in-place
OSS-Deployment-to-AIStor migration.

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

## Irreversible operations and rollback

- OSS→AIStor migration is permanent according to the vendor documentation.
- From AIStor `RELEASE.2026-04-11T03-20-12Z` onward, API auto-bump is enabled by
  default and can make downgrade impossible as soon as the cluster commits the
  new API version.
- Before a real upgrade, set `MINIO_API_AUTO_BUMP=off` on every server, or use
  a documented bounded `MINIO_API_BUMP_BAKE_TIME`, and require an explicit
  approval before any manual `mc admin update --bump-api`.
- A rollback is a restore/cutover to the preserved old environment or an
  export/import recovery, not an assumption that an old binary can start after
  an API bump.
- The production rollback remains the existing GitOps patch: preserve PVC,
  SealedSecrets, bucket, user metadata, and PostgreSQL rows; keep storage and
  scanner disabled.

## Release gates still open

The following evidence is intentionally **not claimed** by this memo:

- exact target runtime startup/version output;
- exact-target conditional create, ETag, replay, collision, concurrent-winner,
  lost-response, metadata, range, CORS, signed URL, and normal S3 regression
  results;
- exact target IAM/policy compatibility;
- SBOM and HIGH/CRITICAL scan of the exact container image;
- disposable upgrade/rollback rehearsal;
- live cluster image, PVC, bucket inventory, credential, console, TLS, and
  NetworkPolicy verification.

The local Docker daemon is unavailable and no production SSH session was
obtained, so these gates require a disposable Kubernetes environment and
cluster-owner access. Do not merge an active runtime image change until they
are attached to the implementation PR.

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
