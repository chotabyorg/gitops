# Repetly file scanner production package

This package contains the ClamAV Deployment/Service, scanner Deployment/Service,
read-only MinIO identity bootstrap, and the private HTTPS route contract. It is
deliberately not included by `services/repetly/prod/kustomization.yaml` yet.

Activation is blocked until the scanner image has a reviewed registry digest, the
three scanner bearer/S3 credentials are sealed with the cluster certificate, and the
private DNS/TLS owner confirms that `repetly-file-scanner.internal.chota.by` is
reachable from the Repetly pod and is not publicly published.

The package does not include a NetworkPolicy yet because the repository does not
declare the production Traefik namespace/pod labels or an egress policy for the
external MinIO HTTPS endpoint. Those owner-specific selectors and egress rules
must be supplied and reviewed before the package is activated; do not infer them
from this draft.

The scanner Deployment uses the existing `ghcr-pull-secret` convention from the
Repetly production workload. The image must still be published to the approved
registry and its pull authorization verified before activation.

The application upload-integrity gate is now the immutable server-controlled
promotion design: teacher and student browser PUTs target only `staging/...`,
the server scans the HEAD ETag with a matching `If-Match`, and conditional
server-side copy creates the canonical object only when the destination is
absent and the source ETag still matches. The canonical object is linked only
after that copy succeeds. This application change must still be smoke-tested
against the exact MinIO deployment before storage activation.
