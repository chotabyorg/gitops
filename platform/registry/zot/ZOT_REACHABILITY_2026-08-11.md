# Zot v2.1.20 go-git reachability evidence — 2026-08-11

Status: the Trivy image finding remains visible and keeps the v2.1.20 image
gate at **BLOCKER**. The separate runtime reachability verdict for the cited
go-git CVE is:

> **NOT USED BY APPROVED REGISTRY RUNTIME**

This is a reachability disposition, not an image approval and not permission
to suppress the Trivy finding.

## Finding and candidate

- Zot release: `v2.1.20`, source tag `v2.1.20`.
- Source revision: `3b5796d834e8661ea661a5fcc47add8d4405aebf`.
- Official multi-architecture index:
  `sha256:542e25be4d32e7879c0cfad93492a93c81b1e059cbd2d30d485d4bd567318234`.
- Linux amd64 manifest:
  `sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`.
- Linux arm64/v8 manifest:
  `sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`.
- Trivy finding: `CVE-2026-71556` / `GHSA-hc8v-wwc9-vgxm`,
  `github.com/go-git/go-git/v5` installed at `v5.19.1`, fixed at `v5.19.2`.

## Dependency and runtime evidence

1. The exact Zot v2.1.20 `go.mod` lists `github.com/go-git/go-git/v5
   v5.19.1` only as an indirect module, together with indirect go-billy and
   gcfg modules.
2. An exact-source audit found no Go imports or runtime calls to
   `go-git`, `go-billy`, or `gcfg`, and no Zot server use of go-git
   `Worktree`/`WorkTree`, `Clone`, or `Checkout` APIs. The only matching
   `git clone` text is in build-time Stacker recipes, outside the registry
   server runtime.
3. The official linux/amd64 v2.1.20 binary provenance identifies Zot v2.1.20
   and records go-git v5.19.1 in module metadata. A focused `go tool nm`
   inspection of that exact binary found no linked `go-git`, `go-billy`,
   `gcfg`, plumbing, or worktree symbols.
4. The completed official `govulncheck` v1.1.4 binary-mode run against that
   exact binary reported `0 vulnerabilities in packages you import`. It
   reported three findings in two required modules whose vulnerable symbols
   are not called by the binary; no go-git vulnerable symbol was reported as
   called.

## Threat-precondition assessment

The vendor advisory requires a filesystem-backed go-git Worktree, an
attacker-controlled symlink, and an application write through that path. The
approved Zot registry runtime has no go-git Worktree creation/control path,
no runtime go-git imports or linked symbols in the inspected binary, and no
server operation that exposes this build-time recipe as a request path.
Therefore the advisory's required runtime preconditions are not present in
the approved registry runtime examined here.

## Upstream and release decision

Upstream Zot PR [#4310](https://github.com/project-zot/zot/pull/4310) merged
on 2026-08-08 and changes go-git from `v5.19.1` to `v5.19.2`. The official
latest-release check on 2026-08-11 still returned Zot `v2.1.20`; its image
therefore remains the vulnerable-by-version candidate recorded by Trivy.

Decision: wait for the next official Zot release containing the upstream
dependency fix. Do not use `main`, a custom patched image, or a private
rebuild as a substitute. Before the next gate, re-check official release
metadata and image tags, then repeat multi-architecture digest inspection,
platform Trivy, official govulncheck, dependency verification, `zot verify`,
and the full disposable acceptance contract.

## References

- [Official Zot releases](https://github.com/project-zot/zot/releases)
- [Upstream dependency update PR #4310](https://github.com/project-zot/zot/pull/4310)
- [Zot authentication and authorization](https://zotregistry.dev/v2.1.18/articles/authn-authz/)
- [Image scan evidence](./ZOT_IMAGE_SCAN_2026-08-11.md)
