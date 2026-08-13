# MinIO AIStor vendor defect report — prepared, not submitted

Submission status: **not submitted**. This payload is intentionally limited to
non-secret technical evidence. It contains no production IPs, credentials,
license bytes, production object names, or production data.

## Suggested subject

AIStor Operator 5.11.x rejects the documented immutable ObjectStore image syntax

## Environment

- AIStor Operator chart: `5.11.3` (also reproduced with official `5.11.2` and
  `5.11.1`); package SHA-256 values are in
  [`OFFICIAL_HELM_INDEX_2026-08-11.md`](./OFFICIAL_HELM_INDEX_2026-08-11.md).
- AIStor ObjectStore chart: `1.0.17`.
- Kubernetes test runtime: kind `v0.32.0`, node image
  `kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95`.
- Test node architecture: `linux/arm64`; the reviewed server digest below is
  the exact amd64 child and ran under disposable lower-env emulation. No
  production cluster was accessed.
- AIStor server release tag used for the documented candidate:
  `RELEASE.2026-08-07T18-34-35Z`.
- Exact immutable server image:
  `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`.
- Active Operator manifest used in the matrix:
  `quay.io/minio/aistor/operator@sha256:50bd6c34a1d2e811cc881116dc3fcce210e2f5fc2276a3933d8cacf71b39d68a`.
- Active sidecar manifest used in the matrix:
  `quay.io/minio/aistor/minio-sidecar@sha256:1cf294b61514a46786d4233e7f4ea66fe179dbb996114fc7af33d3e023961ebc`.
- All test ObjectStores were licensed, single-node, one PVC, and disposable.
  License contents were never read into evidence.

## Documented configuration

The official AIStor Object Store Helm documentation documents digest input as:

```yaml
image:
  repository: quay.io/minio/aistor/minio@sha256
  digest: <sha256>
  pullPolicy: IfNotPresent
```

Reference: <https://docs.min.io/aistor/reference/kubernetes/object-store-helm-chart/>.

The chart rendered the exact intended CR field:

```yaml
spec:
  image: quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1
```

## Minimal reproduction

Each Operator chart release was installed on a fresh disposable kind cluster.
Each cluster used three independent licensed single-node ObjectStores and the
same current ObjectStore chart `1.0.17`.

| Operator chart | Case A: documented digest | Case B: plain tag control | Case C: `tag@digest` control | Restart persistence |
| --- | --- | --- | --- | --- |
| 5.11.3 | `Waiting`, green, setup 100, `PoolCreated/running=1`, parser error | `Initialized`, green, setup 100, `PoolCreated/running=1`, no parser error | `Waiting`, green, setup 100, `PoolCreated/running=1`, parser error | Reproduced |
| 5.11.2 | Same as 5.11.3 | Same as 5.11.3 | Same as 5.11.3 | Reproduced |
| 5.11.1 | Same as 5.11.3 | Same as 5.11.3 | Same as 5.11.3 | Reproduced |

The representative 5.11.3 raw evidence below was identical in image form for
5.11.2 and 5.11.1:

| Case | ObjectStore `.spec.image` | Generated StatefulSet MinIO image | Kubelet-reported MinIO imageID |
| --- | --- | --- | --- |
| A | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` | Same digest form | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` |
| B | `quay.io/minio/aistor/minio:RELEASE.2026-08-07T18-34-35Z` | Same plain tag | `quay.io/minio/aistor/minio@sha256:d1eb0f79ced75d6c024fc6a2ab6a7b3629ff54c798d967d9c6f89951237480a7` |
| C | `quay.io/minio/aistor/minio:RELEASE.2026-08-07T18-34-35Z@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` | Same tag@digest form | `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` |

The sidecar StatefulSet image was
`quay.io/minio/aistor/minio-sidecar@sha256:1cf294b61514a46786d4233e7f4ea66fe179dbb996114fc7af33d3e023961ebc`
in all cases. Case C's Kubelet imageID was the same exact server digest as
case A; the state failure is therefore caused by reconciliation of the image
string, not by the server failing to start.

For every digest case, the Pod started with the exact server image and the
ObjectStore reached `healthStatus: green`, `setup: 100`, `drivesOnline: 1`,
and `PoolCreated` with `podStatus.running: 1`. The Operator then failed its
reconcile with the exact message:

```text
Error extracting tag from current image quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1: invalid image format
```

For the `tag@digest` case the same error was emitted for:

```text
quay.io/minio/aistor/minio:RELEASE.2026-08-07T18-34-35Z@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1
```

Restarting the Operator reproduced the error and preserved the waiting state.
The plain-tag control reached `Initialized` in every tested chart release;
that tag-only result is control evidence, not an acceptable immutable
production configuration.

## Expected result

The documented digest form should remain reconcilable after the Pod is healthy
and should reach `currentState: Initialized` without an image parser error.

## Impact

The current official chart/runtime combination cannot simultaneously provide:

1. the documented MinIO AIStor Operator reconciliation path; and
2. immutable OCI digest pinning for the AIStor server image.

This is a production and security blocker for a deployment that requires
immutable image provenance. A plain tag must not be silently used as a
workaround.

## Requested vendor action

Please confirm one of the following:

1. a corrected Operator release that accepts the documented digest form;
2. an official compatible Operator/ObjectStore chart pair where the documented
   digest form reaches `Initialized`; or
3. a correction to the documentation, with the supported immutable syntax and
   the security/rollback implications explicitly documented.

Please also state the supported Kubernetes compatibility range and whether a
fixed release changes the CRD/status contract.

## Safe attachments available on request

- rendered CR and StatefulSet image strings;
- Pod image IDs and non-secret status summaries;
- Operator logs containing only the parser error above;
- package SHA-256 values and the official Helm index snapshot;
- the exact matrix table in this report.

No infrastructure-specific production details are included or required to
reproduce the defect.

## Submission channel

First choice: MinIO SUBNET, <https://subnet.min.io>, if the AIStor Free account
has a product-issue path. MinIO's AIStor license documentation directs users
to contact the MinIO team on SUBNET, while also stating that AIStor Free has no
SLA and does not include `mc support` commands.

If the Free account cannot open a product issue, use the official MinIO contact
page's technical-support/SUBNET route: <https://www.min.io/contact-us>.

### Final disclosure/channel audit — 2026-08-11

- The public SUBNET entry point exposed only Email/Password login. No product
  issue, deployment issue, or technical-ticket form was reachable without an
  authenticated account session.
- Therefore no additional account/deployment metadata was requested or
  disclosed, and no SUBNET or Contact Us submission was made.
- This report itself is the ready-to-send non-secret payload: suggested subject,
  Environment, Documented configuration, Minimal reproduction, Expected
  result, Impact, Requested vendor action, and Safe attachments above.
- The payload excludes production endpoint/namespace/credentials, license
  bytes or ID, S3 keys, object names/data, SSH details, and unnecessary
  internal infrastructure identifiers.
- If the owner confirms the account's disclosure entitlement, send this exact
  report through the official MinIO support route. Do not add production logs,
  license material, or unrelated deployment/account metadata.
