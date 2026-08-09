# Repetly file scanner production package

This package contains the ClamAV Deployment/Service, scanner Deployment/Service,
read-only MinIO identity bootstrap, and the private HTTPS route contract. It is
deliberately not included by `services/repetly/prod/kustomization.yaml` yet.

Activation is blocked until the scanner image has a reviewed registry digest, the
three scanner bearer/S3 credentials are sealed with the cluster certificate, and the
private DNS/TLS owner confirms that `repetly-file-scanner.internal.chota.by` is
reachable from the Repetly pod and is not publicly published. A NetworkPolicy with
reviewed selectors and egress rules is also required.

The package does not include a NetworkPolicy yet because the repository does not
declare the production Traefik namespace/pod labels or an egress policy for the
external MinIO HTTPS endpoint. Those owner-specific selectors and egress rules
must be supplied and reviewed before the package is activated; do not infer them
from this draft.

The scanner Deployment uses the existing `ghcr-pull-secret` convention from the
Repetly production workload. The image must still be published to the approved
registry and its pull authorization verified before activation.

The application upload-integrity gate is now the immutable server-controlled
promotion design: teacher and student browser PUTs target only
`staging/homework/...`; chat uploads are server-side canonical writes under
`homework/...`; the server scans the staging HEAD ETag with a matching
`If-Match`, reads the same ETag-bound source, and uses conditional
`PutObject` with `If-None-Match: *` to create canonical bytes. The canonical
object is linked only after a create-only write and reconciliation of the
server-owned promotion token, source ETag metadata, and expected size. This
application change has been smoke-tested against the exact pinned MinIO image;
the MinIO runtime security gate remains separate and must be resolved before
storage activation.

The bootstrap Job can compare and reconcile policy contents, but MinIO does not
expose a safe way for it to compare an existing user's secret with the mounted
Kubernetes Secret. Therefore the storage owner must perform and verify a
controlled scanner-credential rotation, and must verify that the dedicated user
has no additional policies, before activation. A successful Job alone does not
clear that prerequisite.
