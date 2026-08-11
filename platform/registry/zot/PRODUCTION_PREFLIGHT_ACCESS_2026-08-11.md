# Production read-only preflight access result — 2026-08-11

Result: **BLOCKED — no legitimate Kubernetes context is configured in this
workspace**.

Read-only checks performed:

```text
kubectl config current-context
error: current-context is not set

kubectl config get-contexts -o name
<no contexts returned>
```

No SSH connection, root credential, bypass, mutation, or production API call
was attempted. Consequently no production facts were collected and no
production state was changed.

## Exact owner action required

Make an already-approved, read-only production kubeconfig available in the
authorized execution environment and select its exact production context.
Do not paste kubeconfig contents, tokens, certificates, or passwords into an
issue or chat. After the access is provisioned, the owner can run:

```bash
export KUBECONFIG=/secure/path/to/approved-read-only-kubeconfig
kubectl config get-contexts
kubectl config use-context REPLACE_WITH_APPROVED_PRODUCTION_CONTEXT
kubectl config current-context
kubectl cluster-info
kubectl get --raw=/version
```

The returned context and cluster identity must be reviewed before any further
read-only collection. If the kubeconfig is protected by an SSH key,
passphrase, or unavailable secret, stop and provide that access through the
approved channel; do not brute-force or bypass it.

After context identity is confirmed, collect only the approved facts in
[`PRODUCTION_READONLY_PREFLIGHT.md`](../../../services/repetly/prod/operations/aistor-green/PRODUCTION_READONLY_PREFLIGHT.md),
including node architecture/topology and independent StorageClass/PVC options
for the Zot design. Never collect Secret values.
