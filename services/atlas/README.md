# Atlas

Public URL: https://atlas.chota.by. ArgoCD application: atlas-prod.
Single replica with Recreate strategy: SQLite has one writer and persists in
atlas-data (1 GiB). PVC pruning is disabled to preserve data during removal.
The web and API containers share a pod; only web is exposed. API listens on
loopback. Existing ghcr-pull-secret supplies registry access.

The Atlas repository publishes tested images tagged with full commit SHA.
Update prod/kustomization.yaml to the successful release SHA, validate using
`kubectl kustomize services/atlas/prod`, and push through the authorized GitOps
workflow. No GITOPS_PAT is provisioned in Atlas; tag promotion is explicit.

Rollback: restore the previous image tag in Git and push. Do not delete the PVC.
For the first release, remove the Deployment, Service and Ingress resources
from the overlay to withdraw traffic, retaining the PVC resource. Take a database
backup before releases that change schema. Do not roll back across incompatible
schema changes without restoring a verified backup.

Provision admin using cluster operator access (password through protected stdin):
`kubectl exec -i -n prod deploy/atlas -c api -- node server/manage.mjs admin owner`
Use a unique password of at least 14 characters. Never commit it. No default
admin or public registration exists; credentials for local previews do not apply.

Backup with `node server/manage.mjs backup /data/backup-UNIQUE.sqlite` inside the
API container, then copy to protected off-server storage. The PVC alone is not a
backup. Analytics are opt-in and public bug reports are rate-limited.
