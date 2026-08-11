# Private-registry immutable-tag fallback — research only

Status: **validated in disposable infrastructure; not selected or enabled for
production**.

This document records the only fallback tested after the supported digest path
was classified as a vendor blocker. It contains no production endpoint,
production namespace, credentials, license material, S3 keys, object data, or
production logs.

## Registry enforcement

The disposable registry was Zot `v2.1.18`, run from the pinned image
`ghcr.io/project-zot/zot@sha256:96913b282b93ee7bc415555c14887e81ece9078631f3189c2e8c1fbb5f888af6`.
The registry used:

- TLS with a disposable test certificate;
- htpasswd authentication with one restricted disposable push identity;
- repository authorization `defaultPolicy: [read, create]`, with no
  `update` or `delete` action;
- Docker compatibility mode `docker2s2` so OCI manifest bytes and digests are
  preserved;
- debug registry logs as the disposable audit trail.

This satisfies the local proof requirements. A production registry must also
provide an organization-approved CA/trust path, private authentication,
restricted push identity, durable audit retention, delete/retention
protection, and operator-approved access controls. A registry that only relies
on a naming convention remains rejected.

## Mirror integrity

Source was pulled by exact digest:

```text
quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1
```

The first Docker-native push was deliberately retained as a negative control:
it converted the OCI manifest and produced destination digest
`sha256:d0bdda03675c1585142274a300dd97337417529f6254a32e0131c18f2bf93cf7`.
That tag was rejected and was not used for the final rehearsal.

The exact copy used pinned Skopeo
`quay.io/skopeo/stable@sha256:3d4893e764cfabab5d0ac62d3391b256a90733d075a57f5fa73b8e4e87a68f8f`
with `--preserve-digests` and the tag:

```text
host.docker.internal:5443/aistor/minio:RELEASE.2026-08-07T18-34-35Z-e8394b040720-oci
```

The registry returned `Docker-Content-Digest:
sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1`.
Anonymous read returned HTTP `401`. An overwrite attempt with a different
disposable image returned `denied: requested access to the resource is denied`
with exit code `1`.

Direct Trivy scan of the exact destination tag used pinned Trivy
`aquasec/trivy@sha256:405015d1cd07a2630301169e694a5a420afc4dd553fb462189d4f109ba56a6df`:

- Red Hat OS packages: `0` HIGH/CRITICAL;
- `/usr/bin/minio`: `0` HIGH/CRITICAL;
- bundled `/usr/bin/mc`: one HIGH `GHSA-hrxh-6v49-42gf`, fixed in `grpc-go`
  `1.82.1` (the existing one-shot client boundary remains visible).

## Operator rehearsal

Fresh disposable kind `v0.32.0` used node image
`kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95`.
AIStor Operator `5.11.3` and ObjectStore chart `1.0.17` were installed with
the valid disposable license Secret, `adminjob.disabled=true`, one disposable
PVC, and `MINIO_API_AUTO_BUMP=off`.

The private registry tag was supplied to the ObjectStore as an ordinary tag.
After removing a stale Docker-format image from the disposable node cache, the
runtime result was:

| Check | Result |
| --- | --- |
| `ObjectStore.spec.image` / StatefulSet tag | exact `...-e8394b040720-oci` tag |
| `currentState` | `Initialized` |
| `healthStatus` | `green` |
| `setup` | `100` |
| pool | `1/1 Running` |
| Kubelet MinIO `imageID` | `host.docker.internal:5443/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` |
| Operator restart | same state/imageID |
| StatefulSet/Pod restart | same state/imageID |
| PVC | `Bound`, both AIStor and Kubernetes PVC-protection finalizers present |
| object persistence | PASS after Pod recreation |
| HTTPS `/minio/health/live`, `/ready`, `/cluster` | `200`, `200`, `200` |
| synthetic S3 CRUD | PASS |
| synthetic application IAM | PASS |
| synthetic scanner IAM | PASS; write denied |
| NetworkPolicy intended client | PASS |
| NetworkPolicy forbidden client | blocked by timeout/denied connection |

The previously accepted exact-byte lower-environment contract remains
`S3 18/18`, application IAM `6/6`, and scanner IAM `6/6`. The new fallback
rehearsal additionally re-ran synthetic S3 CRUD and both IAM paths against the
mirrored tag; it does not invent a new 18/18 test count where the historical
harness is not present in this disposable workspace.

Runtime inventory contained only the Operator, webhook, MinIO, sidecar, and
the explicitly created one-shot `mc` test Pods. Minwall and KES/KES-sidecar did
not materialize in Deployments, StatefulSets, Pods, initContainers, or Jobs.

## Supply-chain comparison

| Reference | Security | Operational result | Disposition |
| --- | --- | --- | --- |
| Native OCI digest | Best: Git/Kubernetes directly names the manifest digest | Broken by current Operator parser | Vendor blocker |
| Registry-enforced immutable tag | Exact source digest verified; overwrite denied; trust additionally moves to registry policy/control plane | Operator-compatible in rehearsal | Research candidate; owner approval required |
| Plain public `RELEASE` tag | Mutable public reference | Operator-compatible control only | Rejected |
| Mutation/admission workaround | Hides or rewrites the documented contract | Not vendor-supported | Deferred/rejected |

## Owner decision gate

No fallback was activated automatically. The owner must choose one of:

- `WAIT FOR VENDOR FIX` — recommended default;
- `ACCEPT PRIVATE-REGISTRY IMMUTABLE-TAG FALLBACK` — only after approving the
  registry control plane, trust shift, retention/delete controls, audit path,
  TLS/authentication, and exact mirror workflow;
- `ARCHITECTURE CHANGE REQUIRED`.

Production preflight remains deferred until that decision and the vendor
digest-path outcome are resolved.
