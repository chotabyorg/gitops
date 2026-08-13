# Zot production activation

This active Kustomize root is the separately approved Phase 1 activation for
GitOps issue #47. It materializes the reviewed scaffold without changing the
BLUE MinIO/Repetly storage overlay and without activating any AIStor GREEN
resource.

ArgoCD registers this root through `platform/argocd/zot-registry.yaml` and
reconciles it as `argocd/zot-registry`. The following values remain out of
band and are never committed:

- `registry/zot-registry-auth`, key `htpasswd`;
- `prod/aistor-zot-puller`, key `.dockerconfigjson`;
- DNS for `registry.chota.by` pointing to `153.80.244.178`;
- ACME certificate issuance through the existing Traefik `le` resolver.

The runtime is one amd64 Zot replica with an independent 10Gi `local-path`
PVC, exact reviewed image digest, non-root/read-only security context, and
the reviewed Traefik/CoreDNS NetworkPolicy selectors. The public route is
HTTPS only at `registry.chota.by`.

Before accepting the real AIStor mirror, verify the ACL matrix with synthetic
content, restart persistence, source/destination digest equality, and the
production-node pull. Stop before AIStor Operator/ObjectStore/GREEN or any
Repetly storage/scanner activation.
