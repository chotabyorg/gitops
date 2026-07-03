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

1. First remove `minio-bootstrap-job.yaml` from the `resources` list in `kustomization.yaml`. Keep the Job manifest tracked, but do not run the bootstrap hook while application credentials are intentionally disabled.
2. Remove `STORAGE_PROVIDER`, `S3_ENDPOINT`, `S3_REGION`, and `S3_BUCKET` from `config.properties`.
3. Add a rollback-only patch to the production `patches` list that overrides the two app-visible credentials with empty values. Explicit `env` entries override values imported through `envFrom`, while the sealed credentials remain intact for MinIO and a later re-enable:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: repetly
   spec:
     template:
       spec:
         initContainers:
           - name: repetly-migrations
             env:
               - name: S3_ACCESS_KEY_ID
                 value: ""
               - name: S3_SECRET_ACCESS_KEY
                 value: ""
         containers:
           - name: repetly
             env:
               - name: S3_ACCESS_KEY_ID
                 value: ""
               - name: S3_SECRET_ACCESS_KEY
                 value: ""
   ```

4. Keep both SealedSecrets unchanged. Also keep the MinIO Deployment, Service, bootstrap ConfigMap, bucket, application user, and PVC intact.
5. Preserve all database metadata; rollback disables new file transfers and does not delete homework attachment or submission records.
6. Verify the Argo CD sync succeeds and Repetly returns to its storage-disabled behavior.

To re-enable storage later, remove the rollback-only credential override, restore the required S3 config, and restore `minio-bootstrap-job.yaml` to the Kustomization in the same reviewed change. The preserved credentials let the wave 1 hook reconcile the MinIO application user before the wave 2 Repetly rollout.

Do not remove `minio-pvc.yaml` during rollback. Argo CD pruning and the `local-path` reclaim policy can delete storage when the PVC is removed.

## Durability and operations

This is a single-node MVP: one MinIO replica backed by node-local storage. It has no high availability, cross-node replication, or repository-managed backup. Establish and test encrypted off-node backup and restore before relying on the storage broadly, monitor node capacity, and plan migration to managed S3-compatible storage if the durability requirement grows. The current StorageClass does not support volume expansion, so increasing capacity requires a separate migration plan.

The following application-level safeguards remain follow-up work and must be operationally accepted before broad storage usage:

- an orphan/PENDING upload reaper for abandoned two-phase uploads;
- malware scanning and byte-level content sniffing rather than MIME/extension checks alone;
- UX polish for rare upload transaction/version conflicts.
