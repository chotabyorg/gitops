# Atlas

Public URL: https://atlas.chota.by. ArgoCD application: atlas-prod.
The legacy `atlas` pod is still a single replica with Recreate strategy because
SQLite has one writer and persists in `atlas-data` (1 GiB). The first safe
migration stage adds two stateless web slots (`atlas-web-blue` and
`atlas-web-green`). The active ingress remains on
the legacy `atlas` Service until the new slots pass their release gate.

The target split ingress is stored in `prod/ingress-bluegreen.yaml` and is
intentionally not included by `prod/kustomization.yaml` yet. Do not activate
it until both web slots are ready with the intended image, port-forward smoke
tests pass, and the release ID, model manifest, search, cards, rotation,
`/api/health`, and `/release.json` match the same build. The old pod remains
available during this staged migration so a content release cannot remove the
only working database process.

The web slots prefer `/etc/nginx/nginx-web.conf`, which is present only in Atlas
images built after the web/API split change, and fall back to the image default
nginx configuration while an older image is being staged. Do not activate the
split ingress until the intended image is present; readiness alone is not a
content or routing smoke test. The green slot is a rollback target; update only
the inactive slot, test it, switch the ingress service, and update the old slot
after the new one is proven.

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
