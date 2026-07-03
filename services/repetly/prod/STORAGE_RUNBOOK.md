# Repetly production object storage

## Topology

- Dedicated MinIO workload and API-only ClusterIP service: `repetly-minio:9000`.
- Public S3 API: `https://repetly-storage.chota.by`, routed by the remotely managed Cloudflare Tunnel to `http://repetly-minio.prod.svc.cluster.local:9000`.
- Private bucket: `repetly-homework`.
- Persistent data: `repetly-minio-data`, 10Gi on the cluster default `local-path` StorageClass.
- The MinIO console listens inside the pod but is not exposed by a Service or Cloudflare route.
- Repetly uses a dedicated bucket-scoped application user. Root and application credentials are stored only as SealedSecrets.

The bootstrap Job is an idempotent Argo CD sync hook. It creates the bucket if needed, enforces private anonymous access, applies browser CORS, reconciles the application user, and attaches an object-only policy for the Repetly bucket.

## Post-merge verification

1. Confirm Argo CD reports `repetly-prod` as `Synced` and `Healthy`, and that the sync hook completed successfully.
2. Confirm `deployment/repetly-minio` and `deployment/repetly` are available, with no restart loop.
3. Confirm `pvc/repetly-minio-data` is `Bound` at 10Gi. Never delete this PVC as part of rollback.
4. Confirm `https://repetly-storage.chota.by/minio/health/live` responds successfully over HTTPS.
5. Send an OPTIONS preflight from origin `https://repetly.chota.by` for PUT with `Content-Type`; confirm the response allows that origin, method, and header.
6. Confirm an unsigned request for a non-existent object under `repetly-homework` is denied rather than exposing a bucket listing.
7. Use approved tutor/student test accounts to upload and download a tiny generated text file. Confirm the signed PUT, server-side HEAD completion, signed GET, and expiry behavior. Remove the test object and product metadata afterward.
8. Review Repetly and MinIO logs for configuration errors without printing environment variables, credentials, or signed URLs.

## Rollback

Disable application storage through a reviewed GitOps change:

1. Remove `STORAGE_PROVIDER`, `S3_ENDPOINT`, `S3_REGION`, and `S3_BUCKET` from `config.properties`.
2. Seal empty values for `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` in `repetly-secret`, so no required S3 value remains while the provider is unset.
3. Keep the MinIO Deployment, Service, bootstrap resources, bucket, and PVC in GitOps.
4. Verify Repetly returns to its storage-disabled behavior.

Do not remove `minio-pvc.yaml` during rollback. Argo CD pruning and the `local-path` reclaim policy can delete storage when the PVC is removed.

## Durability and operations

This is a single-replica MinIO instance backed by node-local storage. It has no high availability, cross-node replication, or repository-managed backup. Establish an encrypted off-node backup and restore drill, monitor node capacity, and plan migration to managed S3-compatible storage if the durability requirement grows. The current StorageClass does not support volume expansion, so increasing capacity requires a separate migration plan.
