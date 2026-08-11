# Zot image scan evidence — 2026-08-11

Status: **Trivy scanner finding present — 0 Critical / 1 High; runtime
exploitability disposition accepted by owner; no activation blocker while the
approved runtime/security contract is unchanged**.

## Candidate identity

- Official release: Zot `v2.1.20`, published 2026-08-04.
- Multi-architecture index:
  `ghcr.io/project-zot/zot@sha256:542e25be4d32e7879c0cfad93492a93c81b1e059cbd2d30d485d4bd567318234`.
- Linux amd64 manifest:
  `sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`.
- Linux arm64/v8 manifest:
  `sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`.
- Official release notes:
  https://github.com/project-zot/zot/releases/tag/v2.1.20
- Pinned scanner:
  `aquasec/trivy@sha256:405015d1cd07a2630301169e694a5a420afc4dd553fb462189d4f109ba56a6df`
  (Trivy v0.72.0).

## Results

Both platform manifests were scanned directly from GHCR with HIGH/CRITICAL
severity and unfixed findings ignored for the count. Both returned the same
result:

| Platform | OS | Go binary | Critical | Result |
| --- | --- | ---: | ---: | --- |
| linux/amd64 | Debian 13.6: 0 HIGH/CRITICAL | 1 HIGH | 0 | **SCANNER FINDING** |
| linux/arm64/v8 | Debian 13.6: 0 HIGH/CRITICAL | 1 HIGH | 0 | **SCANNER FINDING** |

Finding:

```text
CVE-2026-71556
library: github.com/go-git/go-git/v5
installed: v5.19.1
fixed: 5.19.2
severity: HIGH
```

The fixed version is available, so a new official Zot release containing
`go-git >=5.19.2` remains preferred. Under the unchanged approved registry
runtime/security contract, the owner disposition removes this finding as a
production activation blocker. Do not rebuild or privately patch the registry
image; if future configuration adds Git/worktree functionality, reopen the
disposition and repeat the security review.

## Previous disposable proof image

The successful disposable ACL/immutability/restart/PVC rehearsal used Zot
`v2.1.18`, pinned at:

```text
ghcr.io/project-zot/zot@sha256:96913b282b93ee7bc415555c14887e81ece9078631f3189c2e8c1fbb5f888af6
```

That image scan returned five HIGH and zero CRITICAL findings and is not a
substitute for this v2.1.20 test. Its registry behavior is historical protocol
evidence only.

## Acceptance gate

The registry Draft PR may document the v2.1.20 candidate, but it must remain
inert and Draft until production-specific preflight facts and rendered
Kubernetes review are complete. The exact v2.1.20 ACL, immutability,
restart/PVC, TLS, backup/restore, and security-context rehearsal is recorded
in [`ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md`](./ZOT_DISPOSABLE_ACCEPTANCE_2026-08-11.md).
A new official release with the upstream fix is preferred when available and
must repeat the multi-architecture scan and acceptance gates.

## Reachability disposition

The exact-source and exact-binary review for the cited go-git finding is
recorded in [`ZOT_REACHABILITY_2026-08-11.md`](./ZOT_REACHABILITY_2026-08-11.md).
Its single runtime verdict is **NOT USED BY APPROVED REGISTRY RUNTIME**:
go-git is present in indirect/module metadata, but the inspected Zot source
has no runtime imports or Worktree path, the exact amd64 binary has no focused
go-git/worktree symbols, and official `govulncheck` v1.1.4 binary mode found
zero vulnerabilities in packages imported by the binary. The Trivy finding
remains visible, but the owner disposition makes it **not an activation
blocker while the approved runtime/security contract is unchanged**.
