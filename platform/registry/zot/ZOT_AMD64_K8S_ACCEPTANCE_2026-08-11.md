# Zot v2.1.20 amd64 Kubernetes acceptance — 2026-08-11

Verdict: **PENDING — ISOLATED GITHUB-HOSTED X64 ACCEPTANCE**.

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

The run URL, conclusion, exact imageID, and sanitized evidence are appended
after the first GitHub-hosted run.

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

Until this passes on the GitHub-hosted amd64 node, PR #48 must remain Draft and
issue #47 must remain In Progress.
