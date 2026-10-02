# Local backup and safe restore

Owner: Chota platform operator. v0.1 intentionally accepts the same physical server failure domain. No R2, paid subscription or external storage is used; independent external storage is future work, not a release blocker.

## Scheduled and initial backups

`chota-crm-service-backup` runs at **02:15 UTC daily** (05:15 Minsk), `concurrencyPolicy: Forbid`, one-hour starting deadline, 15-minute active deadline, one retry and two successful/failed Jobs retained. Exact reviewed backend `backup.sh` uses pg_dump custom format, no owner/privileges, umask077, archive catalogue validation and atomic rename. Files are `/backups/chotacrm-YYYYMMDDTHHMMSSZ.dump`, mode0600. Only completed matching archives older than 14 days are removed, after a new successful archive. A failed dump cannot replace a completed one. Never commit dumps or publish them as CI artifacts.

The separate **8Gi PVC `prod/chota-crm-service-backups`** mounts `/backups`; PostgreSQL's **4Gi PVC `chota-crm-service-postgres-data`** mounts `/var/lib/postgresql`. Both use local-path and are annotated `Prune=false,Delete=false`. The storage request is not a filesystem quota guarantee; node free space is the practical capacity limit. Credentials use `PGPASSWORD` from the same new CRM Secret and host/database/user from the backup ConfigMap. The DB has no TLS inside this single-node dedicated network; policies restrict traffic. Backups inherit node/PVC access protections and are not independently encrypted at rest.

`chota-crm-service-backup-initial-v01` is a normal, versioned first-release Job in wave2. It binds the backup PVC and produces the first archive after successful API migration/readiness; it is intentionally retained for inspection. The CronJob remains active afterward. Do not edit the spec of an existing completed Job (Kubernetes treats its template as immutable); remove it in a reviewed cleanup or use a newly versioned Job name after changing its image/template. Forbid covers scheduled Jobs, not the initial/manual Job: avoid launching a manual backup while another runs, and count two 128Mi Jobs in the worst-case first-release memory budget.

## Actual production checks after deployment review

A rendered manifest/local restore does not prove a production backup. Check the first Job and PVC, then at least the next scheduled Job:

```sh
kubectl get pvc -n prod chota-crm-service-postgres-data chota-crm-service-backups
kubectl wait -n prod --for=condition=complete --timeout=900s job/chota-crm-service-backup-initial-v01
kubectl logs -n prod job/chota-crm-service-backup-initial-v01
kubectl get cronjob -n prod chota-crm-service-backup -o jsonpath='{.spec.suspend}{" "}{.status.lastScheduleTime}{" "}{.status.lastSuccessfulTime}{"\n"}'
kubectl get jobs -n prod -l app=chota-crm-service
```

Some CronJob-created Job metadata may not inherit pod labels; if the final listing is empty, list Jobs by `chota-crm-service-backup-` name or owner reference. Safe expected output is `CRM backup completed`. Do not print SQL, dump contents, environment or Secret values. To start an authorized one-off backup outside the daily run:

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
