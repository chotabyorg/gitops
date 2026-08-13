# AIStor GREEN resource and rollout contract — 2026-08-13

This is the fresh production read-only capacity snapshot paired with the
licensed disposable rehearsal. The active GitOps Kustomization still does not
reference this directory.

## Fresh production baseline

| Metric | Current scheduled | Node allocatable |
| --- | ---: | ---: |
| CPU requests | `300m` | `4 CPU` |
| CPU limits | `1 CPU` | `4 CPU` |
| Memory requests | `396Mi` | `8127796Ki` |
| Memory limits | `1194Mi` | `8127796Ki` |
| Ephemeral-storage requests/limits | `0 / 0` | `200693717859` bytes |

The node was `Ready`; `MemoryPressure`, `DiskPressure`, and `PIDPressure` were
all `False`. Point-in-time usage was `523m` CPU (`13%`) and `5652Mi` memory
(`71%`). Usage must be watched during any future rollout, but it did not
produce a scheduler or node-health blocker in this read-only snapshot.

## Candidate scheduler budget

The rendered candidate adds Zot `100m/256Mi`, Operator `200m/256Mi`, admission
webhook `200m/256Mi`, GREEN MinIO `500m/768Mi`, and sidecar `50m/32Mi` requests:
`1050m` CPU and `1568Mi` memory. The recorded combined baseline is therefore
`1350m` CPU and `1964Mi` memory requests. The rendered ephemeral limit is
`1000Mi` across Operator and webhook; current production workloads do not
declare ephemeral requests/limits, so rollout observation remains required.

## Rollout boundary

This evidence does not authorize starting GREEN, changing the stable route,
or deleting/changing BLUE. Future activation remains staged: deploy private
registry and Operator prerequisites, wait for GREEN probes/PVC persistence,
validate S3 IAM and presigned URLs, then perform an explicitly approved route
cutover while retaining BLUE rollback.

Abort on pressure conditions, OOM, repeated restarts, pending PVC/scheduling,
TLS trust failure, failed S3 health, or failed presigned URL validation.
