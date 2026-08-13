# AIStor GREEN resource and rollout contract — 2026-08-12

This is a scheduler contract, not a `kubectl top` estimate. The active GitOps
Kustomization still does not reference this directory.

## Terminology correction

The earlier `312m CPU / 5671Mi memory` values are **observed point-in-time
usage**, collected on 2026-08-11. They are not scheduler headroom. The same
evidence records current scheduled requests/limits as `300m / 396Mi` and
`1 CPU / 1194Mi`.

Fresh `kubectl top`, pod request/limit, and ephemeral-storage recheck was not
possible on 2026-08-12 because the authorized SSH connection timed out. The
2026-08-11 values below are therefore carried-forward evidence and do not
clear the final activation gate.

## Candidate scheduler budget

The added figures are derived from the final values in this PR and the Zot
scaffold: Zot `100m/256Mi`, Operator `200m/256Mi/500Mi ephemeral`, admission
webhook `200m/256Mi/500Mi ephemeral`, GREEN MinIO `500m/768Mi`, and sidecar
`50m/32Mi`. Limits are Zot `250m/384Mi`, Operator/webhook `500m/256Mi/500Mi
ephemeral`, GREEN MinIO `1 CPU/1Gi`, and sidecar `100m/128Mi`.

| Metric | Existing recorded requests | Added candidate requests | Combined recorded total | Allocatable comparison |
| --- | ---: | ---: | ---: | ---: |
| CPU | 300m | 1050m | 1350m | 33.75% of 4 CPU |
| Memory | 396Mi | 1568Mi | 1964Mi | about 24.8% of 8127796Ki |
| Ephemeral storage | not recorded | 1000Mi | not determinable | fresh node inventory required |

| Metric | Existing recorded limits | Added candidate limits | Combined recorded total |
| --- | ---: | ---: | ---: |
| CPU | 1 CPU | 2350m | 3350m |
| Memory | 1194Mi | 2536Mi | 3730Mi |
| Ephemeral storage | not recorded | 1000Mi | not determinable |

Kubernetes does not add an init container's request to the sum of app
containers. The pod request is the larger of the init-container request and
the app-container sum. The `sidecar-init` path must therefore be inspected in
the licensed rendered/reconciled workload, but it must not be double-counted
if it has the same `50m/32Mi` request as the sidecar.

## Rollout safety

The sequence is deliberately staged and reversible:

1. Start Zot, wait for probes and PVC persistence, then observe.
2. Start the Operator and admission webhook, verify RBAC/TLS/readiness, then
   observe.
3. Start GREEN, verify the three HTTPS health endpoints, pool readiness, S3
   IAM and presigned URL paths, then observe.
4. Run BLUE/GREEN migration validation and final delta checks.
5. Cut over the stable `repetly-storage.chota.by` route.
6. Keep BLUE and its rollback PVC intact until an explicit post-cutover sign-off.

Abort the sequence on any of the following:

- `MemoryPressure=True`, `DiskPressure=True`, or `PIDPressure=True`;
- any new `OOMKilled` termination;
- any new component restart during the observation window;
- readiness failure persisting for more than three consecutive checks;
- node `memory.available` below the configured floor of 20% of allocatable
  memory (approximately 1.55Gi using the carried-forward allocatable value);
- scheduler rejection, PVC pending, TLS trust failure, or a failed S3
  presigned browser request.

These are rollout criteria only. No threshold was applied and no production
workload was started or changed by this fix cycle.
