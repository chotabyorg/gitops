# Local backup and safe restore

Owner: Chota platform operator. v0.1 intentionally accepts the same physical server failure domain. No R2, paid subscription or external storage is used; independent external storage is future work, not a release blocker.

## Scheduled and initial backups

`chota-crm-service-backup` runs at **02:15 UTC daily** (05:15 Minsk), `concurrencyPolicy: Forbid`, one-hour starting deadline, 15-minute active deadline, one retry and two successful/failed Jobs retained. Exact reviewed backend `backup.sh` uses pg_dump custom format, no owner/privileges, umask077, archive catalogue validation and atomic rename. Files are `/backups/chotacrm-YYYYMMDDTHHMMSSZ.dump`, mode0600. Only completed matching archives older than 14 days are removed, after a new successful archive. A failed dump cannot replace a completed one. Never commit dumps or publish them as CI artifacts.

The separate **8Gi PVC `prod/chota-crm-service-backups`** mounts `/backups`; PostgreSQL's **4Gi PVC `chota-crm-service-postgres-data`** mounts `/var/lib/postgresql`. Both use local-path and are annotated `Prune=false,Delete=false`. The storage request is not a filesystem quota guarantee; node free space is the practical capacity limit. Credentials use `PGPASSWORD` from the same new CRM Secret and host/database/user from the backup ConfigMap. The DB has no TLS inside this single-node dedicated network; policies restrict traffic. Backups inherit node/PVC access protections and are not independently encrypted at rest.

Both Jobs call the GitOps `backup-ready.sh` wrapper before the byte-identical reviewed `backup.sh`. It probes the existing `PGHOST`/`PGPORT` with `pg_isready -q -t 2` up to 30 times, sleeping 2 seconds only between failed probes. Each probe is also bounded by pinned-image BusyBox `timeout -k 1 3` (TERM after 3 seconds, KILL after 1 more), covering DNS/connect stalls. The total waiting budget is approximately 178 seconds at worst, plus process scheduling overhead; the unchanged 900-second Job deadline caps the whole operation, including any retry. The wrapper emits only constant waiting/ready/timeout messages and suppresses probe diagnostics. No dump starts before readiness; budget exhaustion exits 1. On readiness it `exec`s the helper exactly once. It does not retry or hide dump, authentication, archive validation or write failures; `pg_isready` is not proof of any of those successes.

`chota-crm-service-backup-initial-v02` is a normal, versioned first-release recovery Job in wave2. It binds the backup PVC and attempts the first archive after successful API migration/readiness and its own database readiness gate; it is intentionally retained for inspection. The CronJob remains active afterward. Do not edit the spec of an existing completed or failed Job (Kubernetes treats its template as immutable); remove it in a reviewed cleanup or use a newly versioned Job name after changing its image/template. Forbid covers scheduled Jobs, not the initial/manual Job: avoid launching a manual backup while another runs, and count two 128Mi Jobs in the worst-case first-release memory budget.

### Initial-release failure and recovery rollout

On 2026-10-02, initial-v01's two attempts at 10:23:21Z and 10:23:33Z failed immediately with `pg_dump` connection-refused errors. PostgreSQL was continuously Ready with zero restarts, the API was migrated/ready, and subsequent credential-free probes from the backup policy class reached both the PostgreSQL PodIP and ServiceIP for 30/30 samples over 60 seconds. These observations establish transient connection refusals plus a one-shot backup path without startup tolerance. They do **not** prove a particular CNI propagation race or low-level network root cause.

Deploy the fix only through a fresh reviewed GitOps PR. The desired object becomes initial-v02, so Argo creates a new Job and prunes the old tracked initial-v01; no immutable Job template patch or manual cluster workaround is required. The script ConfigMap gets a new content hash and both initial-v02 and future daily Jobs use it. Confirm no backup is currently active and enough node headroom remains before merge. Do not touch the unchanged database/backup PVCs, Secret retention, application images, migrations, policies or active CronJob schedule. A newly ready probe cannot guarantee continued connectivity during a later dump; that failure must still be investigated and surfaced normally.

After rollout, a fresh runtime tester must verify the new Job's exact revision/script hash, completed archive metadata, schedule/freshness and isolated restore, following the procedure below. Do not claim live success from local tests. If the wrapper itself needs repair, forward-fix it through another reviewed GitOps change and use initial-v03 if the Job template changes again. A reviewed rollback to direct helper execution can restore the prior CronJob behavior, but it also restores the original transient-startup weakness; remove the tracked v02 Job rather than recreating the failed v01 identity. Preserve both PVCs, their data, the existing credential and the daily schedule in either case.

## Actual production checks after deployment review

A rendered manifest/local restore does not prove a production backup. Check the first Job and PVC. The next 02:15 UTC scheduled execution and subsequent 26-hour freshness checks are operator follow-up; they are not a new requirement to delay release until the next day, and a manual Job must never be reported as a scheduled run:

```sh
kubectl get pvc -n prod chota-crm-service-postgres-data chota-crm-service-backups
kubectl wait -n prod --for=condition=complete --timeout=900s job/chota-crm-service-backup-initial-v02
kubectl logs -n prod job/chota-crm-service-backup-initial-v02
kubectl get cronjob -n prod chota-crm-service-backup -o jsonpath='{.spec.suspend}{" "}{.status.lastScheduleTime}{" "}{.status.lastSuccessfulTime}{"\n"}'
kubectl get jobs -n prod -l app=chota-crm-service
```

Some CronJob-created Job metadata may not inherit pod labels; if the final listing is empty, list Jobs by `chota-crm-service-backup-` name or owner reference. Safe expected phase output is `CRM backup waiting for database readiness`, then `CRM backup database ready`, then `CRM backup completed`. The first two do not prove a backup was made. `CRM backup database readiness timed out` is a failure, as is any nonzero helper exit. Do not print SQL, dump contents, environment or Secret values. To start an authorized one-off backup outside the daily run:

```sh
kubectl create job -n prod --from=cronjob/chota-crm-service-backup chota-crm-backup-check-YYYYMMDDHHMMSS
```

Wait for completion, inspect the safe log and delete only that temporary Job after recording the result. This operational verification is temporary, never a persistent deployment patch. Record timestamp, completion, PVC Bound, archive basename/size/mode and result without customer contents. An archive listing can be performed by an approved temporary pod with the backup PVC mounted read-only; never expose that mount publicly or copy archives into this repository.

Daily operator checks: after the first scheduled run, lastSuccessfulTime must be within **26 hours**; inspect failed Job conditions, unscheduled/suspended CronJob, missing/unbound PVC, Pending/image-pull failures and node free disk. A completed Job proves the script finished, not that all prior backups are recoverable. Investigate a missing/failed/stale backup before the next schedule, run a reviewed one-off after correcting the cause and repeat restore validation as needed. No external alert delivery is configured by this release; the operator owns these checks. Monitor aggregate backup size and free host disk; local-path cannot expand in place. Keep headroom before archives or database growth consume the node.

## Restore drill: new disposable in-pod PostgreSQL only

The inert `operations/restore/` Kustomization is **not referenced by prod** and cannot be auto-discovered as a service. It is an operator-run, reviewed diagnostic Job. Before running, set only `RESTORE_FILE` in its Job manifest to a specific completed archive basename and render it for review. It deliberately fails closed with the placeholder. Recheck memory/disk headroom and do not overlap the daily/initial backup. The 256Mi restore limit adds to the CRM baseline; it uses up to4Gi temporary node storage.

```sh
kubectl kustomize services/chota-crm-service/operations/restore > /tmp/crm-restore-reviewed.yaml
# After explicit deployment-review authorization for this temporary verification:
kubectl create -f /tmp/crm-restore-reviewed.yaml
kubectl wait -n prod --for=condition=complete --timeout=900s job/chota-crm-restore-check-v01
kubectl logs -n prod job/chota-crm-restore-check-v01
# Removes only temporary Job/ConfigMap/NetworkPolicy; the backup PVC is NOT in this bundle.
kubectl delete -f /tmp/crm-restore-reviewed.yaml
```

This Job has **no production database Secret or network route**. PostgreSQL runs only on the pod's Unix socket, with a new ephemeral data directory and no TCP listener/Service. NetworkPolicy denies all ingress/egress. The backup PVC is read-only. The unchanged reviewed `restore-check.sh` creates a NEW `crm_restore_verification` database, refuses an existing DB, restores one transaction with error-stop, verifies Alembic revision, booking exclusion, customer/workspace links and absence of confirmed overlaps, and prints aggregate counts only. The wrapper drops that exact temporary DB, verifies its absence and stops PostgreSQL. A failed verification emits a generic failure; deleting the temporary Job removes its emptyDir data. No command can connect to or overwrite the production database. Check cleanup even on failure.

The independent pre-release test restored a nonempty synthetic dataset into a separate PG18 instance, matched all16 table counts/full-row digests and executed restored constraints. This GitOps proof additionally exercised UID70/read-only root/actual volume layout and scripts. A live archive drill must still be recorded; do not label it PASS from these local checks.

For disaster recovery, restore into a separately provisioned new database, verify it independently, then switch only through a reviewed GitOps change. Preserve old data until recovery acceptance. Never run the initial destructive Alembic downgrade or restore over production.
