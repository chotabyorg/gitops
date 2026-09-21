# Pediatric arthritis quiz service

The production overlay creates an isolated one-replica Node service, a dedicated 1 GiB SQLite PVC, and the service-owned Traefik route for `https://atlas.chota.by/test`.

Before merging the deployment PR, create `prod/sealed-secrets.yaml` from the template using the cluster's Sealed Secrets public certificate. Never commit `prod/secrets.yaml` or plaintext event/admin credentials. The overlay deliberately does not reference an unsealed Secret.

`IngressRoute` priority `100` ensures the `/test` prefix is selected ahead of the host-wide Atlas route while leaving all other Atlas paths untouched.
