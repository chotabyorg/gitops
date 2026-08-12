# Zot v2.1.20 amd64 Kubernetes acceptance — 2026-08-11

Verdict: **PASS — GITHUB-HOSTED AMD64 KUBERNETES ACCEPTANCE**.

This is an evidence record for the required production-architecture gate. No
production cluster, BLUE MinIO, GREEN AIStor, Repetly storage, or production
credential was used.

## Target image

- Zot release: `v2.1.20`.
- Required production child image:
  `ghcr.io/project-zot/zot@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`.
- The digest is the independently resolved official `linux/amd64` manifest
  and is the value that must be compared with the eventual production Pod
  `imageID`.

## Previous local attempt (not acceptance evidence)

1. Local `kind v0.32.0` with `kindest/node:v1.35.5` and `DOCKER_DEFAULT_PLATFORM=linux/amd64` could not bootstrap the node under Docker
   Desktop emulation; the node image did not reach the expected systemd
   readiness line.
2. A local `k3d v5.8.3` / `rancher/k3s:v1.31.5-k3s1` attempt with the image
   explicitly pulled as `linux/amd64` reached the k3s API startup, but the
   kubelet exited because the emulated `/proc/cpuinfo` exposed ARM CPU fields
   and the kubelet could not detect clock speed. The node therefore never
   became a valid amd64 Kubernetes worker.

The Docker runtime itself can execute the Zot amd64 image under emulation, but
that is not equivalent to an amd64 Kubernetes node and is not accepted as the
required architecture gate.

## GitHub-hosted acceptance contract

Workflow: `.github/workflows/zot-amd64-acceptance.yaml`.

It runs only on `ubuntu-24.04`, creates a disposable kind cluster, uses the
exact amd64 Zot image and synthetic credentials/certificates, and never reads
production configuration or secrets. It checks node architecture, Pod
`imageID`, `/startupz`, `/readyz`, `/livez`, publisher create and
overwrite/delete denial, puller read/create denial, anonymous denial, PVC
persistence after Pod recreation, securityContext, and NetworkPolicy object
semantics. kind's default CNI does not enforce NetworkPolicy, so the workflow
reports enforcement as unavailable rather than claiming a negative network
test; production enforcement is separately evidenced by K3s chains.

## Historical recorded run — 2026-08-11 (pre-Fix C)

- Workflow run: [31521568936](https://github.com/chotabyorg/gitops/actions/runs/31521568936)
- Commit: `f070f8200de201368cd9cede9ce37b7c6a5fa2d8`
- Runner: `ubuntu-24.04`; disposable kind node: `amd64`
- Conclusion: `success`; sanitized artifact was uploaded by the workflow.
- Exact Pod imageID:
  `ghcr.io/project-zot/zot@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`
- Health probes: `/startupz=200`, `/readyz=200`, `/livez=200`.
- Publisher create: PASS; same-tag overwrite: HTTP `403`; delete: HTTP
  `403`; puller create: HTTP `403`; anonymous read: HTTP `401`.
- Puller read remained successful after Pod deletion/recreation; PVC UID
  `c74a3056-db2c-4f90-bbc2-53d8f25daa7c` remained bound and the immutable
  manifest remained readable.
- Security context assertions: PASS (`runAsNonRoot`, UID 1000,
  `allowPrivilegeEscalation=false`, read-only root filesystem, dropped ALL,
  no service-account token).
- NetworkPolicy object: default deny semantics PASS. kind's default CNI does
  not enforce NetworkPolicy, so the workflow records
  `enforcement=unavailable_kind_default_cni`; production enforcement is
  separately evidenced by K3s embedded kube-router chains.

## Required abbreviated acceptance

Use the exact child digest above and record all results for the rendered
StatefulSet:

| Gate | Required result |
| --- | --- |
| Startup/readiness/liveness | all pass; no startup loop |
| Publisher create | unique content-identifying tag succeeds |
| Publisher overwrite/delete | denied |
| Puller read | succeeds |
| Puller create/update/delete | denied |
| Anonymous read | denied |
| PVC persistence | tag and digest survive Pod/PVC recreation |
| Pod imageID | exact equality with `sha256:95a837...e6d4fd5` |

That run passed the pre-Fix-C amd64 contract. After Fix C, the same workflow
must pass again on the current head, together with the real-k3s embedded
kube-router NetworkPolicy workflow, before PR #48 can leave Draft and issue #47
can leave In Progress.
