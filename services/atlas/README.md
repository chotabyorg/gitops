# Atlas

Public URL: https://atlas.chota.by. ArgoCD application: atlas-prod.
The legacy `atlas` pod is still a single replica with Recreate strategy because
SQLite has one writer and persists in `atlas-data` (1 GiB). Two stateless web
slots (`atlas-web-blue` and `atlas-web-green`) run alongside it. Static
application traffic currently uses blue; dynamic `/api` and editorial routes
use the legacy `atlas` Service. Admin and policy routes temporarily use that
Service until the new web image passes its smoke test in inactive green.

The separate API Deployment remains inactive in `prod/api-split-deployment.yaml`.
Before switching static traffic to a new slot, verify its release ID, model
manifest, search, cards and camera interactions, and check the current API's
`/api/health` and `/api/ready`. The singleton API must remain available.
The B2C policy rollout updates the API while blue still serves the old web;
`ATLAS_LEGACY_POLICY_ACCEPT_UNTIL` briefly accepts the previous policy version
without recording it as the new one. Then green takes static traffic and old
accounts must accept the new policy in the new web app.
During staging, `X-Atlas-Preview: b2c-20260923` selects green for static
routes; the higher-priority API route stays on the singleton. Remove this
temporary preview rule after the switch.

The web slots prefer `/etc/nginx/nginx-web.conf`, which is present only in Atlas
images built after the web/API split change, and fall back to the image default
nginx configuration while an older image is being staged. Do not activate the
split ingress until the intended image is present; readiness alone is not a
content or routing smoke test. The inactive slot is a rollback target; update only
the inactive slot, test it, switch the ingress service, and keep the old slot
ready during the rollback window.

The legacy web/API containers share a pod; API listens on loopback there. During
this migration, dynamic ingress routes stay on the legacy `atlas` Service and
only static routes move to a web slot. `prod/api-split-deployment.yaml` and
`base/api-service.yaml` are inactive future targets and must not be added while
the legacy pod still mounts the RWO SQLite PVC. Existing `ghcr-pull-secret`
supplies registry access.

The Atlas repository publishes tested images tagged with full commit SHA.
Update both newTag (full release SHA) and digest (published image digest) in
prod/kustomization.yaml; the digest takes precedence over the tag. Validate using
`kubectl kustomize services/atlas/prod`, and push through the authorized GitOps
workflow. No GITOPS_PAT is provisioned in Atlas; tag promotion is explicit.

Rollback: switch the ingress service back to the previous ready web slot and
restore its image tag and digest in Git. Do not delete the PVC. Keep the last
known-good release manifest and image digest until the new slot has passed live
checks.
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

The 2026-09-23 B2C migration creates and quick-checks
`/data/pre-b2c-20260923.sqlite` before the API image changes. Its init
container is removed after the new API and web slot pass the live checks, so
a later restart cannot recreate a misleading "pre-release" snapshot.
The application removes that snapshot after seven days. Restoring it would
discard subsequent registrations and consent changes; use it only for a
verified incident recovery with those changes reconciled.

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
