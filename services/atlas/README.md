# Atlas

Public URL: https://atlas.chota.by. ArgoCD application: atlas-prod.
Single replica with Recreate strategy: SQLite has one writer and persists in
atlas-data (1 GiB). PVC pruning is disabled to preserve data during removal.
The web and API containers share a pod; only web is exposed. API listens on
loopback. Existing ghcr-pull-secret supplies registry access.

The Atlas repository publishes tested images tagged with full commit SHA.
Update both newTag (full release SHA) and digest (published image digest) in
prod/kustomization.yaml; the digest takes precedence over the tag. Validate using
`kubectl kustomize services/atlas/prod`, and push through the authorized GitOps
workflow. No GITOPS_PAT is provisioned in Atlas; tag promotion is explicit.

Rollback: restore the previous image tag and digest in Git and push. Do not delete the PVC.
For the first release, remove the Deployment, Service and Ingress resources
from the overlay to withdraw traffic, retaining the PVC resource. Take a database
backup before releases that change schema. Do not roll back across incompatible
schema changes without restoring a verified backup.

Provision admin using cluster operator access (password through protected stdin):
`kubectl exec -i -n prod deploy/atlas -c api -- node server/manage.mjs admin owner`
Use a unique password of at least 14 characters. Never commit it. No default
admin or public registration exists; credentials for local previews do not apply.

Backup with `node server/manage.mjs backup /data/backup-UNIQUE.sqlite` inside the
API container. Keep copies on approved protected infrastructure in Belarus with an explicit
retention period and withdrawal/deletion handling; never copy the production
database to Git or foreign cloud storage. The PVC alone is not a
backup. Analytics are opt-in and public bug reports are rate-limited.

The 0.4.0 account migration first runs an initContainer using the previous pinned
image. It creates and quick-checks /data/pre-accounts-20260906.sqlite before the
new API opens the database. This is an on-volume migration snapshot, not an
off-server backup. The migration only adds tables and a nullable column. An app
rollback can leave those additions in place; restoring this snapshot would lose
new registrations and must not be done as an ordinary image rollback.

The 0.5.0 privacy migration adds nullable consent-version fields and a receipt
registry; it never backfills consent for existing users. The initContainer now
uses the preceding 0.4.0 image to quick-check pre-privacy-20260906.sqlite first.
Known pre-accounts/pre-privacy snapshots older than 7 days are cleaned at API
startup and hourly. The public policy allows up to 8 days. Do not create other
snapshots without matching retention controls. Old snapshots are not an automatic
recovery source: subsequent withdrawals/deletions must be reapplied before public
access is restored. If they cannot be reconstructed, do not restore that snapshot.
Rollback the image without restoring the DB; additive schema changes can remain.
A rollback to pre-privacy application code also removes its consent enforcement
and cleanup: use only as an incident response with public registration disabled,
not as a routine way to keep serving the new policy.

The 0.6.0-beta.1 osteology release adds nullable diagnostic/app_version event
columns. The initContainer uses the previous 0.5.0 image and quick-checks
/data/pre-privacy-20260908.sqlite before the API migration. The existing
pre-privacy filename family intentionally preserves seven-day cleanup support
in both 0.5.0 and 0.6.0, including after an image rollback. This is an on-volume
migration snapshot, not an off-server backup. Roll back to 0.5.0 without DB
restoration; the extra nullable columns are compatible with its named inserts.
The previous image is a57980acd16a4537e1ffbb8a8d3183c885956bf7, digest
sha256:38dd283d471c9fec5e59d2e1d79afec018554fbf7658b53fb931a85f43f58bf4.
