# Off-cluster S3 storage and retention contract

This tooling is inert until a platform owner supplies an off-node, off-cluster
private S3-compatible destination. The existing single-node application storage
is not an eligible sole backup target.

## Required setup

- Private bucket reached by its reviewed HTTPS FQDN only; the script rejects
  single-label hosts, Kubernetes service suffixes, `.local`/`.internal`, and IP
  literals (including loopback, link-local, private, and CGNAT ranges).
- A local endpoint is available only to isolated tests when all three conditions
  hold: `BACKUP_ENVIRONMENT=test`, `BACKUP_ALLOW_LOCAL_TEST_STORAGE=1`, and
  `BACKUP_LOCAL_TEST_STORAGE_APPROVED=1`. Production has no local-endpoint path.
- Encryption at rest enabled by the provider. Uploads request SSE-S3 (`AES256`);
  use an approved equivalent only if the provider requires a different header.
  The script accepts `none` only when both `BACKUP_ENVIRONMENT=test` and the
  explicit local-test override are set; production fails closed without `AES256`.
- Bucket versioning enabled. The backup fails if an archive or marker does not
  have a non-empty VersionId, or if a storage `head-object` does not report the
  requested encryption. The archive is checked before the marker is written; a
  final read-only marker head follows the marker's final write.
- Prefer object lock/immutability with a retention period covering the policy.
- The writer identity uses `writer-policy.template.json` as a least-privilege
  starting point: object write/read/verification only and an explicit Delete
  denial. It does not list buckets or delete objects.
- A separate restore-reader identity may call only `GetObjectVersion` for the two
  explicitly selected ARNs: one dump and its completion marker. Each allow rule
  has its own exact `s3:VersionId` condition; it is not the writer identity.
- Alert through available Job/CronJob status plus the sanitized output fields:
  last successful timestamp, age, size, checksum state, and last restore drill.
  Escalate a failed Job or stale successful timestamp to the named on-call.

## Retention and lifecycle administration

Baseline proposal for this small database, subject to storage capability and
owner approval: retain daily backups for 30 days, weekly backups for 8 weeks,
and monthly backups for 6 months. The object-store lifecycle service or a
separate lifecycle-admin identity performs deletion; the backup writer never
does.

Before any deletion, export a sanitized inventory with exactly six TSV fields:

`dump_key<TAB>dump_version<TAB>marker_key<TAB>marker_version<TAB>created_at_utc<TAB>state`

The marker key must equal `dump_key.complete.json`; each version is the exact
storage version for that key. State is `eligible`, `restore-verified`, or
`pinned-75`. Prepare a four-column proposed deletion plan with the same
dump-and-marker pair fields (without timestamp/state) and run:

```sh
./retention-preflight.sh --dry-run INVENTORY.tsv PLAN.tsv
```

The dry-run rejects unsafe keys, dump-only plans, marker-only plans, mismatched
dump/marker key or version proposals, pairs absent from inventory, duplicate plan
entries, the newest eligible complete pair, every restore-verified pair, and
every pair pinned for issue #75. It prints aggregate counts only and does not
call storage APIs or delete anything. A reviewed lifecycle-admin execution is a
separate, explicitly authorised operation.

The inventory generator may label a dump eligible only after validating its
exact completion-marker version. Retain every marker for at least as long as
its bound dump version. A lifecycle execution must treat the dump and marker as
one reviewed candidate and must never leave a marker that claims a missing dump
is a successful backup.

Capacity monitoring must cover object count, total stored bytes, storage quota,
and lifecycle failures. Record owner/on-call, approved RPO, approved RTO, and
the latest verified restore-drill timestamp outside this repository.
