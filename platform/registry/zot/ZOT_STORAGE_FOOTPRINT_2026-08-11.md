# Zot storage footprint — 2026-08-11

The owner-approved P0 PVC is `10Gi`, independent from BLUE and GREEN. The
footprint below was calculated from read-only Quay OCI manifests for the active
AIStor amd64 mirror candidates; no production registry was written.

| Artifact | Config bytes | Compressed layer bytes | Compressed total |
| --- | ---: | ---: | ---: |
| `quay.io/minio/aistor/minio@sha256:e8394b0407206d967208d86040a0c82e87c2b912068e2fdd2e876777bf2d16a1` | 9,302 | 128,764,616 | 128,773,918 |
| `quay.io/minio/aistor/minio-sidecar@sha256:560e204d8fbd05d095719a39af0db36e177829528d80366962d1bc22102c9b57` | 6,477 | 16,674,742 | 16,681,219 |
| **Total, without cross-image deduplication** | **15,779** | **145,439,358** | **145,455,137** |

The total is approximately **138.7 MiB**. Retaining two upgrade generations
would be about **290,910,274 bytes (~277.5 MiB)**. The selected `10Gi` PVC
leaves ample space for registry metadata, temporary uploads, future mirror
generations, and filesystem headroom. Retention remains ledger-driven.

The selected main content tag is `aistor-minio-e8394b040720`; the full source
digest remains authoritative for the mirror invariant.
