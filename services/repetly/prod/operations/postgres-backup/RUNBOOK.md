# Repetly PostgreSQL backup and verified restore

This directory is an **inert operations package** for issue #8. It is deliberately
absent from `services/repetly/prod/kustomization.yaml`, the scheduled backup is
suspended, and executable images use non-runnable digest sentinels. Merging this
package does not create a CronJob, Job, Secret, database role, or storage object.

## Ownership and service objectives

| Field | Required value before activation |
| --- | --- |
| Service owner | `<owner>` |
| Primary on-call | `<on-call route>` |
| Backup schedule | `<UTC cron expression>` |
| Approved RPO | `<duration; pending schedule approval>` |
| Approved RTO | `<duration; pending measured restore drill>` |
| Restore drill frequency | `<frequency>` |
| Evidence location | `<private, access-controlled reference>` |

Do not claim an RPO until the schedule and alerting path are approved. Do not
claim an RTO until an isolated restore drill has been timed end to end.

## Architecture and trust boundaries

- Backups are PostgreSQL 18 custom-format logical archives produced with a
  dedicated, read-only database login defined by `role/postgres-backup-role.sql`.
- The object key is built only from validated, controlled identifiers and a UTC
  timestamp. The archive is uploaded before a SHA-256-bound completion marker.
- The destination must be a reviewed private, off-node/off-cluster S3-compatible
  service reached through its approved HTTPS FQDN. Single-label names, Kubernetes
  service suffixes, `.local`/`.internal`, and every IP literal are rejected in
  production. Repetly's node-local production MinIO is not an acceptable sole
  destination.
- The backup storage writer may put and inspect its own objects, but cannot delete
  them. The restore reader is a separate identity with no write permission.
- Restore uses a fixed, ephemeral PostgreSQL target listening on `127.0.0.1` only.
  It has no Service and never receives the production database Secret.
- Logs and evidence contain status, timestamps, object references, sizes,
  checksums, durations, and aggregate/boolean checks only. Never copy rows, dump
  content, credentials, presigned URLs, emails, Telegram identifiers, or user IDs.

## Production prerequisites

An owner must complete and independently review every item before proposing an
activation change:

1. Provision a separate private S3-compatible bucket with TLS, encryption at
   rest, versioning, capacity monitoring, and preferably Object Lock/immutability.
2. Create three storage policies: put/head-only backup writer without Delete,
   read-only restore reader, and a separately controlled lifecycle administrator.
3. Configure lifecycle retention only after its preview proves that the newest
   successful dump-and-marker pair and any pair pinned for maintenance issue #75
   survive.
4. Run `role/postgres-backup-role.sql` through the approved secret-aware database
   administration path. Supply the password outside Git and verify the negative
   privilege assertions. Investigate row-level security or extension objects;
   never add `BYPASSRLS` or superuser as a shortcut.
5. Build the operations image from reviewed sources, scan it, confirm its
   `pg_dump --version` reports major 18, and replace every all-zero image digest
   with an approved immutable digest.
6. Create separate Kubernetes Secrets for the database backup login, storage
   writer, and restore reader. Use the exact manifest key names, an approved
   secret-management workflow, and no shared application/superuser credential.
7. Run `./validate.sh` and all integration tests in a disposable environment.
8. Fill the ownership, schedule, alerting, drill, RPO, and RTO fields above.
9. Verify the backup database Secret cannot override `PGSSLMODE=verify-full` or
   `PGSSLROOTCERT=/var/run/repetly-backup-db-ca/ca.crt`; the Pod and runner force
   both values before `pg_dump` connects.

## First-time validation

From the GitOps repository root:

```sh
services/repetly/prod/operations/postgres-backup/validate.sh
kubectl kustomize services/repetly/prod/operations/postgres-backup
kubectl kustomize services/repetly/prod
```

Review the rendered operations package; do not pipe it to `kubectl apply`. The
validator must confirm that the active production render remains unchanged.

## Manual pre-maintenance backup

Manual execution is a separate, owner-approved GitOps change; this runbook does
not authorize it. Before issue #75 maintenance:

1. Confirm the prerequisites, current alert route, storage versioning, and latest
   successful restore-drill evidence.
2. Copy the manual Job template to an execution overlay and give it a unique name
   of the form `repetly-postgres-backup-manual-<UTC timestamp>`.
3. Pin the approved image digests and reference only the dedicated backup database
   Secret and put-only storage writer Secret.
4. Add that one Job through a reviewed GitOps PR. Never use a shell-created Secret
   or a direct production `kubectl apply`.
5. Require a successful exit plus sanitized evidence: UTC timestamp, immutable
   object/version reference, non-zero size, SHA-256 match, and completion marker.
6. Record that immutable reference privately on issue #75. Do not begin the
   maintenance window if evidence is missing, stale, partial, or unverified.

A retry must use a new unique Job name and timestamp. It must not delete or
overwrite the last known-good logical backup.

## Scheduled backup activation

Activation needs a new explicit owner-approved PR. In that PR only:

1. Replace digest sentinels and configure the approved UTC schedule.
2. Reference the backup package from the active production Kustomization.
3. Keep `concurrencyPolicy: Forbid`, bounded histories/deadline/resources, and
   `restartPolicy: Never`; then change `suspend` only after the render is reviewed.
4. Confirm Argo CD owns the resource and that no one applied a competing CronJob.
5. Observe the first run, verify its version/checksum/marker, and immediately run
   the isolated restore drill before accepting the schedule.

Rollback is a GitOps change that sets `suspend: true`; it must not delete previous
backup objects or their completion markers.

## Backup verification and stale-backup alerting

A backup is successful only when all of these are true:

- the Job exited successfully and emitted `status=success`;
- archive size is non-zero and SHA-256 matches locally;
- storage returned an immutable version identifier;
- storage `head-object` reports the required encryption for both the archive and
  its completion marker;
- the completion marker was written last and binds the exact key, version, size,
  checksum, format, and creation time (a read-only marker `head-object` check is
  the only permitted operation after that final write);
- the object is younger than the approved RPO threshold.

Until a metrics stack exists, alert from Kubernetes CronJob/Job state and a
credential-minimal scheduled checker. Alert on failed Jobs, absent completion
markers, checksum/version failures, unexpected size changes, or backup age beyond
the approved threshold. Capacity warnings belong to the off-cluster storage owner.

## Isolated restore drill

Restore execution also requires a separate reviewed GitOps PR and an allowlisted
immutable object **and version** with its completion marker:

1. Select a successful reference; reject free-form paths, prefixes, `latest`, or
   an object without its exact version and marker.
2. Pin the approved operations and PostgreSQL image digests. Give the drill Job a
   unique UTC-suffixed name and provide only the dedicated storage reader Secret.
3. Verify marker structure, object identity/version, non-zero size, and SHA-256
   before `pg_restore` starts.
4. Restore to fixed database `repetly_restore_drill` using
   `--single-transaction --exit-on-error --no-owner --no-privileges`.
5. Emit only booleans and aggregates for: readable archive, public schema, the
   five approved application tables, exactly 41 public ordinary tables (including
   Prisma's `_prisma_migrations` bookkeeping table), exactly 95 validated foreign
   keys, at least 100 ready/valid public indexes, exactly 25 completed Prisma
   migrations, and migration
   `20260714184000_telegram_active_token_unique_index`. The check never asserts
   business row counts or emits rows/PII; a missing migration, invalid index, or
   count mismatch is a failed drill.
6. Record elapsed restore time and the sanitized result in the private evidence
   location. Remove the execution manifest through GitOps after evidence capture;
   the Pod's ephemeral database is deleted with it.

Any empty or unsafe target, production database name, or system database name must
fail before download or connection. There is no path in this package that connects
the restore target to the production database.

## Retention and cleanup

Initial proposal for this small database is 30 daily, 8 weekly, and 6 monthly
successful backups, subject to storage capability and owner approval. Retention is
implemented by bucket lifecycle or the separate lifecycle identity, never the
backup writer. Before enabling or changing it:

1. Run a dry-run/preview against metadata only.
2. Protect the newest successful dump-and-completion-marker pair, every
   legal/incident hold pair, and the pair pinned for issue #75.
3. Confirm incomplete objects can be aged out without treating them as successes.
4. Review versioning/noncurrent-version and Object Lock interactions.
5. Capture only aggregate deletion counts and policy revision as evidence.

Cleanup of Kubernetes execution Jobs is independent of backup retention. Never
delete the last successful backup to clean up a failed Job.

## Failure handling

- **Dump or database authentication failure:** preserve prior backups, mark the Job
  failed, page the database owner, and do not grant broader privileges ad hoc.
- **Upload denied or partial upload:** no completion marker means no valid backup.
  Fix the writer/TLS/storage condition and retry with a new timestamp.
- **Versioning absent:** fail closed; enable bucket versioning before retrying.
- **Checksum/marker mismatch or missing object:** quarantine the reference, alert
  storage and database owners, and restore only another independently verified
  version.
- **Restore/integrity failure:** preserve sanitized evidence, remove the ephemeral
  target after investigation, and do not approve RTO or maintenance readiness.
- **Stale backup:** block maintenance issue #75 until a new backup and verified
  restore succeed.

## Credential rotation

Rotate database backup, writer, and reader credentials independently. Create the
replacement through the approved secret manager, update the corresponding Secret
reference through GitOps, prove one backup or restore with the new identity, then
revoke the old identity. Rotation must never expose values in Git, shell history,
logs, PRs, or issue comments. Re-run negative privilege/policy tests after rotation.

## Issue #75 handoff gate

Issue #75 may consume this tooling only after: the implementation PR is merged;
all prerequisites are filled; the first manual backup is successful and immutable;
an isolated restore drill passes; measured duration and backup age are recorded;
and owner/on-call explicitly approve the maintenance window. This tooling alone
does not authorize maintenance and does not make application PR #74 mergeable.
