# Zot v2.1.20 amd64 Kubernetes acceptance — 2026-08-11

Verdict: **BLOCKED — NO REAL AMD64 DISPOSABLE KUBERNETES NODE AVAILABLE IN
THIS ARM64 WORKSPACE**.

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

## Attempts

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

## Required abbreviated acceptance when a real amd64 environment is available

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

Until this is run on a real amd64 disposable node or an approved amd64 lower
environment, PR #48 must remain Draft and issue #47 must remain In Progress.
