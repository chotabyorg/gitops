# Repetly production object storage

## Topology

- Dedicated MinIO workload and API-only ClusterIP service: `repetly-minio:9000`.
- Public S3 API: `https://repetly-storage.chota.by`, routed by Traefik (k3s ingress) to `http://repetly-minio.prod.svc.cluster.local:9000`.
- Private bucket: `repetly-homework`.
- Persistent data: `repetly-minio-data`, 10Gi on the cluster default `local-path` StorageClass.
- The MinIO console listens inside the pod but is not exposed by a Service or Cloudflare route.
- MinIO API CORS is restricted at server startup to `https://repetly.chota.by` with `MINIO_API_CORS_ALLOW_ORIGIN`.
- Repetly uses a dedicated bucket-scoped application user. Root and application credentials are stored only as SealedSecrets.

The bootstrap Job is an idempotent Argo CD sync hook. It creates the bucket if needed, enforces private anonymous access, reconciles the application user, and attaches an object-only policy for the Repetly bucket. MinIO does not implement the S3 BucketCORS API; the Deployment-level setting above provides the supported origin restriction for every API response.

## Scanner delivery package and activation gates

The reviewable scanner infrastructure is kept in
`services/repetly/prod/operations/file-scanner/`. It is intentionally **not** in
the production Kustomization while storage is disabled. This preserves the
current rollback safety property and prevents Argo from starting a workload with
placeholder image or credential material.

The package contains:

- a pinned `clamav/clamav` workload with a bounded definitions volume, resource
  limits, and ping-based startup/readiness/liveness probes;
- an internal-only ClusterIP for ClamD on TCP/3310;
- a scanner Deployment/ClusterIP with non-root/read-only-root settings, probes,
  bounded scanner configuration, and a placeholder that must be replaced by a
  published immutable scanner image digest;
- an idempotent MinIO bootstrap hook that grants only `s3:GetObject` on
  `repetly-homework/*` to the scanner identity;
- three separate secret templates for the scanner bearer token, S3 access key,
  and S3 secret key; and
- a Traefik HTTPS route contract using the private DNS name
  `repetly-file-scanner.internal.chota.by` and an infrastructure-owner-managed
  TLS Secret. The route must not be changed to a public hostname without an
  architecture review.

### Phase A — code and artifact gates

Before enabling the package:

1. Confirm the existing Repetly scanner PR has green typecheck, lint, format,
   unit/scanner tests, build, image smoke, vulnerability checks, and the
   upload-integrity invariant that prevents a browser upload URL from replacing
   bytes after scan.
2. Publish the reviewed scanner image from the approved CI workflow and replace
   `REPLACE_WITH_REVIEWED_IMAGE_DIGEST` with the exact immutable registry digest.
   Do not use a tag, a local image digest, or a fabricated zero digest.
3. Run the GitOps render checks without applying anything:

   ```bash
   kubectl kustomize services/repetly/prod/operations/file-scanner
   kubectl kustomize services/repetly/prod
   ```

### Phase B — credentials and private HTTPS

The cluster owner must supply the Sealed Secrets controller certificate and the
private DNS/TLS arrangement before activation. Generate values outside Git:

```bash
umask 077
openssl rand -base64 48 > /tmp/repetly-scanner-token
openssl rand -hex 16 > /tmp/repetly-scanner-s3-access
openssl rand -base64 48 > /tmp/repetly-scanner-s3-secret
```

Use those values to fill a temporary copy of
`services/repetly/prod/operations/file-scanner/secrets.yaml.template`, then seal
the three Secret documents with the real cluster certificate. The temporary
plaintext file and generated value files must be deleted immediately after
sealing and must never be committed or printed:

```bash
kubeseal --format yaml --cert /path/to/cluster-sealed-secrets-cert.pem \
  < /path/to/filled-scanner-secrets.yaml \
  > services/repetly/prod/operations/file-scanner/sealed-secrets.yaml
```

Add the generated `sealed-secrets.yaml` to the file-scanner Kustomization in the
same reviewed activation change, then rerun both render commands from Phase A.
Do not add the plaintext template or a placeholder Secret resource.

The TLS Secret `repetly-file-scanner-tls` is a separate infrastructure-owner
input. Verify private DNS from the Repetly pod and verify the certificate chain
with the same trust store used by the Repetly Node runtime. Do not set
`FILE_SCANNER_URL` to the plain ClusterIP URL and do not disable HTTPS checks.

### Phase C — infrastructure smoke while Repetly storage remains disabled

Add the `operations/file-scanner` package only in a reviewed GitOps change after
the gates above, keep `storage-disabled-rollback-patch.yaml` active, and wait
for ArgoCD `repetly-prod` to report Synced/Healthy. Then verify:

1. `repetly-clamav` is Ready and has current definitions; TCP/3310 is reachable
   only from the scanner workload.
2. `repetly-file-scanner` is Ready and `/health/live` is 200 while
`/health/ready` becomes non-2xx when ClamD is unavailable.
   Readiness is intentionally a ClamD dependency check; storage credentials and
   the S3 endpoint must also be exercised by the scan smoke below.
3. A clean fixture returns `{"verdict":"clean"}` and an EICAR fixture returns
   `{"verdict":"infected"}`.
4. Wrong token, wrong endpoint/bucket/key, oversized object, storage 4xx/5xx,
   timeout, unavailable ClamD, malformed ClamD reply, and queue saturation all
   return non-2xx without exposing credentials or signed URLs.
5. The scanner identity can read the exact homework object but cannot put,
   delete, list, or administer objects.
6. Browser PUTs for teacher attachments and student submissions must target only
   a `staging/...` key. Verify the application performs HEAD/GET `If-Match`, scans
   that ETag, then uses conditional server-side copy with destination
   `If-None-Match: *` and source `x-amz-copy-source-if-match` before marking the
   canonical object READY. Replay of an old browser URL may only replace its
   staging object and must never change a promoted canonical object.

Do not run EICAR or failure injection against production without explicit
approval and a cleanup plan. Prefer an isolated cluster or maintenance window.

### Phase D — application activation

Only after Phase C evidence is attached to the reviewed change:

1. Add the exact private HTTPS `/scan` URL as `FILE_SCANNER_URL` and expose the
   sealed bearer token to Repetly as `FILE_SCANNER_TOKEN`.
2. Remove the rollback-only credential override and restore the required
   production S3 settings in the same reviewed change. Keep the MinIO PVC and
   existing user metadata unchanged.
3. Restore the existing MinIO bootstrap hook in the activation wave so the app
   identity and scanner read-only identity reconcile before the wave-2 Repetly
   rollout.
4. Wait for application readiness, then run the approved clean/EICAR/upload
   smoke through the normal Repetly flow.

Never use `ALLOW_UNSCANNED_TEST_UPLOADS=true` in this activation. If any scanner,
TLS, storage, or readiness check fails, leave the rollback patch in place and
keep objects quarantined.

## Post-merge verification

1. Confirm Argo CD reports `repetly-prod` as `Synced` and `Healthy`, and that the sync hook completed successfully.
2. Confirm `deployment/repetly-minio` and `deployment/repetly` are available, with no restart loop.
3. Confirm `pvc/repetly-minio-data` is `Bound` at 10Gi. Never delete this PVC as part of rollback.
4. Confirm `https://repetly-storage.chota.by/minio/health/live` responds successfully over HTTPS.
5. Send an OPTIONS preflight from origin `https://repetly.chota.by` for PUT with
   `Content-Type`; confirm the response allows that origin and method. The
   browser PUT is staging-only; immutable canonical promotion is server-side.
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

- bounded cleanup and retry monitoring for abandoned staging uploads and failed
  deletion claims;
- active-content scanning beyond the ClamAV byte scan and byte-level content sniffing rather than MIME/extension checks alone;
- UX polish for rare upload transaction/version conflicts.
