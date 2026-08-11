# Registry architecture audit — 2026-08-11

Status: **owner-approved conditional fallback; production registry not deployed**.

This audit covers the GitOps repository, the locally available CHOTA source
and GitOps checkouts, the visible CHOTA GitHub repository inventory, and the
CI/Kubernetes configuration that is safe to inspect without production
access. It does not inspect or change a production cluster, registry, IAM,
license, or secret.

## Decision

**Recommendation: `DEPLOY DEDICATED REGISTRY`.**

The only registry demonstrated in the existing CHOTA delivery path is GHCR.
It is operationally available, but the audited configuration does not provide
the security contract required for the AIStor fallback:

- the reusable workflow grants `packages: write` and publishes both a commit
  tag and the reusable `latest` alias;
- the workflow can update the production GitOps image tag after the push;
- production workloads use one `ghcr-pull-secret`, but the repository contains
  no proof that the corresponding identity is pull-only or that the package
  denies tag update/delete;
- no negative overwrite test, registry audit-retention evidence, or immutable
  tag policy is present in CHOTA GitOps;
- no existing Harbor, Quay, Zot, GitLab Container Registry, ECR, GAR, ACR, or
  registry DNS/infra definition was found in the audited local CHOTA material.

GHCR remains usable for ordinary CHOTA service delivery, but it is **not
selected as the AIStor production fallback** merely because it is already in
use. A dedicated Harbor-class registry (Harbor is the preferred product
candidate if the platform team can operate it) should be designed with
immutable-tag rules, separate identities, durable storage, backup/restore,
HA expectations, TLS, and retained audit events before activation. The
disposable Zot proof remains useful as a protocol rehearsal, not as evidence
that a production Zot service already exists.

## Evidence inventory

| Area | Observed evidence | Security meaning |
| --- | --- | --- |
| GitOps repository boundary | `AGENTS.md` and `README.md` describe service images under `ghcr.io/chotabyorg/<service>` | GHCR is the current existing registry path |
| CI publication | `.github/workflows/reusable-deploy.yaml` logs into GHCR, grants `packages: write`, pushes `type=sha` and `latest`, then updates prod `newTag` | Publisher is not pull-only; reusable aliases are part of the current pipeline |
| Runtime pulls | Service Deployments reference `ghcr-pull-secret`; `platform/secrets/secrets.yaml.template` contains a GHCR Docker config template | Private pull authentication exists as a naming/config convention |
| Secret ownership | `platform/secrets/sealed-secrets.yaml` contains only the sealed object metadata and ciphertext; no plaintext token was inspected | The repo does not prove token scope, rotation, or publisher/puller separation |
| Existing platforms | No Harbor, Quay, Zot, GitLab registry, ECR/GAR/ACR, registry DNS, or registry deployment was found in the audited CHOTA GitOps/source material or visible org repository names | No existing compliant registry can be selected from repository evidence |
| AIStor fallback proof | Disposable Zot with TLS, private auth, `read/create` policy, no `update/delete`, digest-preserving Skopeo copy, matching destination digest, anonymous `401`, and denied overwrite | The compatibility path is technically viable when the registry itself enforces the contract |

The encrypted Secret payload was deliberately not decoded. No production
endpoint or credential was used.

## Candidate comparison

| Candidate | Availability in CHOTA | True immutability | Auth/TLS | Audit, backup, HA, cost | Kubernetes integration | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| Existing GHCR | In use by all audited service CI/prod image references | **Not evidenced.** Current workflow publishes `latest`; no immutable-tag rule or overwrite-negative exists in CHOTA | Private package auth and TLS are available; current design does not prove separate publisher/puller scopes | GitHub provides package controls, but required retained audit/backup/restore evidence is not in the repo; marginal registry cost is attractive | Existing `imagePullSecrets` pattern works | **Reject for AIStor fallback until an independently reviewed immutable policy and identity split are proven** |
| Existing Harbor | Not found in CHOTA/local infrastructure evidence | Native project tag-immutability rules are designed to prevent overwrite/delete of matching tags | Supports private projects, TLS termination, and separate robot accounts; exact deployment/auth topology must be designed | Requires durable object storage, backup/restore, monitoring, HA decision, and operational ownership; higher platform cost/overhead | Standard `imagePullSecrets`; can be integrated with Argo/Kustomize | **Best dedicated-registry target; design required, no deployment authorized by this PR** |
| Existing Zot | Not found as an existing CHOTA service | Disposable proof used registry authorization with `read/create` and no `update/delete`; production policy, storage, audit retention, and HA still need review | TLS and htpasswd worked in disposable proof; production CA, identity lifecycle, and pull/publish split are pending | Lightweight, but production durability, backup, HA, and audit are not supplied by the disposable run; lower software footprint does not remove ops work | Standard OCI/Docker pulls and `imagePullSecrets` | **Viable dedicated alternative only with an approved production operations design** |
| Existing Quay / GitLab Registry / ECR / GAR / ACR | No CHOTA evidence found | Product-specific policy not verified; no current access, project, or negative overwrite evidence | Unknown for this installation | Unknown cost, retention, backup, HA, and audit contract | Generally standard OCI/Kubernetes integration, but not evidenced here | **Defer; do not call these “existing” without owner-provided evidence** |
| Plain Docker Distribution | Not found as an existing service | Upstream tag-to-digest immutability is not established by a naming convention | Auth/TLS can be added, but they do not create immutable tags by themselves | Requires the most surrounding policy/operations work | Standard registry API | **Reject as the standalone fallback** |

The Harbor immutability behavior referenced here is documented by the vendor:
[Harbor tag immutability rules](https://goharbor.io/docs/2.0.0/working-with-projects/working-with-images/create-tag-immutability-rules/).
GHCR's published permissions model distinguishes read, write, and admin, and
documents that write can upload/download while admin can delete/manage the
package; see [GitHub Packages permissions](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages)
and [Container Registry authentication and digest pulls](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Required production registry contract

The selected implementation must prove all of the following before an
AIStor production image is allowed to reference it:

1. TLS is terminated with an organization-approved CA/trust path; anonymous
   pull is denied.
2. Publisher and puller identities are separate. The production workload is
   pull-only. The publisher cannot update an already-used immutable tag.
3. Delete is denied or restricted to a break-glass role with an approved,
   retained audit event and recovery procedure.
4. The tag is unique and content-identifying; it is never `latest`, `stable`,
   `prod`, `current`, or another reusable alias.
5. The source digest is pulled, verified, scanned, and copied with digest
   preservation. The destination registry digest must equal the source
   digest. A second push to the same tag must fail.
6. Destination scanning and the exact scan result are retained with the
   release evidence.
7. Registry audit events, backup/restore, storage capacity, retention,
   monitoring, and HA/failure behavior have an owner and a tested runbook.
8. Kubernetes uses a dedicated private-registry `imagePullSecret` with no
   publisher capability, and runtime evidence verifies:

   `official source digest == private registry destination digest == production Pod imageID`

   Any mismatch is a blocker and must fail closed.

## Conditional fallback contract for PR #46

The owner-approved path is now:

**`OWNER-APPROVED CONDITIONAL PRODUCTION PATH`** — mirror the exact vendor
OCI manifest into an approved private registry under a unique immutable tag,
then reference that tag as the ordinary `ObjectStore.spec.image` value because
the current Operator rejects the documented digest syntax.

The path is conditional, not active. The owner-approved P0 contract is now
resolved as namespace `registry`, one Zot replica, independent `10Gi`
`local-path` PVC, `registry.chota.by` behind Traefik ACME `le`, and separate
publisher/puller Secret contracts. DNS, ACME issuance, Secret delivery, and
the first mirror remain rollout-time prerequisites. No production registry,
Secret, ObjectStore, PVC, or image reference is created by this PR.

The disposable proof in
[`PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md`](./PRIVATE_REGISTRY_FALLBACK_RESEARCH_2026-08-11.md)
remains the compatibility evidence. It must be repeated against the selected
production registry, including the source/destination digest equality,
anonymous-denied check, overwrite-negative, destination scan, and Pod
`imageID` equality.

## Migration when the vendor fixes native digest support

1. Reproduce the fix in disposable infrastructure with the exact Operator and
   ObjectStore chart versions selected for production.
2. Scan the exact Operator, sidecar, and AIStor server images and retain the
   digest evidence.
3. Repeat the S3/IAM/restart/PVC/health/NetworkPolicy contract.
4. Change the ObjectStore back to the direct vendor digest reference; do not
   retain the fallback tag as a hidden second source of truth.
5. Verify the production Pod `imageID` equals the official vendor digest and
   that the Operator no longer reports the parser defect.
6. Retire the mirror tag only under the approved registry retention/delete
   process, preserving the vendor report, release evidence, and migration
   record.

## Current gate

- PR #46 remains Draft and must not merge until the isolated x64 Zot
  acceptance and final rendered review pass.
- Issue #44 remains In Progress; #112 remains Ready for Test.
- Vendor report remains prepared but not submitted.
- Production read-only preflight is **executed and recorded** in
  [`PRODUCTION_READONLY_FACTS_2026-08-11.md`](./PRODUCTION_READONLY_FACTS_2026-08-11.md):
  one amd64 k3s node, only node-local `local-path`, no current registry DNS,
  and embedded kube-router NetworkPolicy enforcement enabled. No production
  state was changed.
- The next acceptance packet is the GitHub-hosted x64 workflow result and the
  rollout-time DNS/ACME/Secret evidence; the native parser is recorded as
  **VENDOR LIMITATION — native digest path unavailable; selected
  immutable-registry fallback in use**, not as a production BLOCKER.
