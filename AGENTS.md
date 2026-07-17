# AGENTS.md — CHOTA GitOps

Kubernetes manifests for the CHOTA platform. Managed with Kustomize (v5+) and deployed via ArgoCD. No application code lives here.

## Repository boundaries

- **This repo** = GitOps config only (Kustomize overlays)
- **Service source code** = separate repositories under `ghcr.io/chotabyorg/<service>`
- **CI** = each service repo calls `.github/workflows/reusable-deploy.yaml` in this repo
- **Deployment** = ArgoCD watches this repo and auto-syncs to the cluster (no manual `kubectl apply`)

## Verification

```bash
# Validate a service's manifests
kustomize build services/<service>/prod

# Build all services
for svc in services/*/prod; do echo "--- $svc ---"; kustomize build "$svc"; done

# Diff against cluster
kustomize build services/<service>/prod | kubectl diff -f -
```

There are no tests, lint, or typecheck steps. `kustomize build` is the only verification.

## ArgoCD

ArgoCD is the sole deployment mechanism. The repository contains `Application` and `ApplicationSet` manifests in `platform/argocd/`.

### ApplicationSet (prod services)

[`platform/argocd/prod.yaml`](platform/argocd/prod.yaml) uses a git directory generator to auto-discover all `services/*/prod` paths and create an ArgoCD Application for each:

- **Auto-discovery** — new services are picked up automatically when a `services/<name>/prod/` directory appears on `main`
- **Automated sync** — no manual sync needed; ArgoCD reconciles within 3 minutes of a git change
- **selfHeal: true** — any drift from git is auto-corrected
- **prune: true** — resources removed from git are deleted from the cluster
- **Exclusion** — services can be excluded by adding a entries to the `directories` list with `exclude: true` (see `payment-service`)

### Platform Applications

| Application | Source | Namespace |
|-------------|--------|-----------|
| `traefik-routes` | `platform/traefik-routes` | `prod` |

### Repo Credential

The ArgoCD repo credential (SSH key) is stored as a SealedSecret in `platform/argocd/sealed-secrets.yaml` with the label `argocd.argoproj.io/secret-type: repository`. The template is at `platform/argocd/secrets.yaml.template`.

### Bootstrapping

On a fresh cluster, apply the platform-level ArgoCD manifests first, then ArgoCD syncs everything else:

```bash
kubectl apply -f platform/argocd/sealed-secrets.yaml
kubectl apply -f platform/argocd/prod.yaml
kubectl apply -f platform/argocd/traefik-routes.yaml
```

### Sync flow

```
Service CI pushes Docker image to GHCR
  → updates newTag in services/<service>/prod/kustomization.yaml
  → pushes to this repo
  → ArgoCD detects the git change (polling every 3 minutes)
  → ArgoCD renders the Kustomize overlay (kustomize build under the hood)
  → ArgoCD applies the diff to the cluster
```

### Debugging sync issues

```bash
# Check ArgoCD app status
argocd app list
argocd app get <app-name>

# Trigger immediate refresh
argocd app get <app-name> --refresh

# View diff between git and cluster
argocd app diff <app-name>

# Force sync
argocd app sync <app-name>
```

## Service overlay pattern

Every service (except `chota-gateway`) follows this convention:

| File | Purpose |
|------|---------|
| `base/deployment.yaml` | Bare image name (`image: user-service`), `envFrom` references `<service>-config` and `<service>-secret` |
| `base/service.yaml` | ClusterIP Service |
| `base/postgres-*.yaml` | Sidecar PostgreSQL (if applicable) |
| `dev/prod/kustomization.yaml` | `namespace`, `images:` override to GHCR, `configMapGenerator`, `resources: [../base, sealed-secrets.yaml]` |
| `dev/prod/config.properties` | Non-sensitive env vars (key=value) |
| `prod/sealed-secrets.yaml` | Bitnami SealedSecret (committed) |
| `prod/secrets.yaml.template` | Template for secret keys |

**Key conventions:**
- Base deployments use bare image names — overlays rewrite them via `images:` block
- `configMapGenerator` hashes names; Deployment `envFrom.configMapRef` relies on kustomize's automatic `nameReference` transformation
- Do **not** add `spec.selector.matchLabels` to base Deployments — kustomize injects selectors via `includeSelectors: true`
- `.gitignore` blocks `**/secrets.yaml` and `**/krakend-jwk.json` — never commit these

## chota-gateway (special case)

- Uses official `krakend/krakend:2.13.3` image — **no Docker build**, CI workflow does not apply
- Config injected via **file-based ConfigMap** (`files: [krakend.json]`), not `env:` like other services
- `krakend.json` differs between `dev/` and `prod/`
- JWK secret (`krakend-jwk.json`) is a SealedSecret mounted at `/etc/krakend/krakend-jwk.json`
- Image override in overlay: `name: krakend` → `newName: krakend/krakend`, `newTag: "2.13.3"` (pinned, not `latest`)

## CI/CD

- Each service repo has a workflow that calls `reusable-deploy.yaml` from this repo
- CI builds Docker image → pushes to GHCR → updates `newTag` in `services/<service>/prod/kustomization.yaml`
- **Only prod overlays are updated by CI** — dev overlays always use `newTag: latest`
- chota-gateway uses a separate `sync-config.yaml` that copies `krakend.json` into this repo on push

## Database migrations

All services that use PostgreSQL apply schema migrations via **initContainers** in their Deployment specs. The initContainer runs `alembic upgrade head` before the main application container starts, ensuring the database schema is up to date before the app serves traffic.

### How it works

The initContainer uses the same Docker image and environment variables as the main container, so it has access to the database URL via `configMapRef` and `secretRef`. If the migration fails, the pod does not start.

```yaml
initContainers:
  - image: <service-name>
    name: <service-name>-migrations
    command:
      - alembic
      - upgrade
      - head
    envFrom:
      - configMapRef:
          name: <service-name>-config
      - secretRef:
          name: <service-name>-secret
```

### Services using alembic initContainers

| Service | Command |
|---------|---------|
| ai-agent-service | `alembic upgrade head` |
| control-plane-service | `alembic upgrade head` |
| knowledge-base-service | `alembic upgrade head` |
| notification-service | `alembic -c alembic.ini upgrade head` |
| payment-service | `alembic upgrade head` |
| subscription-service | `alembic upgrade head` |
| user-service | `alembic upgrade head` |

### Exceptions

- **document-service** — Uses [Liquibase](https://www.liquibase.org/) via Spring Boot. Migrations run automatically on application startup through the `spring-boot-starter-liquibase` integration. No initContainer needed.
- **repetly** — Uses [Prisma](https://www.prisma.io/) with `npx prisma migrate deploy` as an initContainer.
- **No-database services** — `chota-gateway`, `chota-site`, `blockrise`, `outsors`, `chunking-service`, `instagram-gateway-service`, `rag-service`, `telegram-gateway-service`, `website-gateway-service` do not need migrations.

## Sealed Secrets workflow

```bash
# 1. Copy template, fill values
cp services/<service>/prod/secrets.yaml.template services/<service>/prod/secrets.yaml
# Edit secrets.yaml with actual values

# 2. Seal it
kubeseal --format yaml < services/<service>/prod/secrets.yaml > services/<service>/prod/sealed-secrets.yaml

# 3. Delete the unsealed file (it's .gitignored but be safe)
rm services/<service>/prod/secrets.yaml
```

## Adding a new service

1. Create `services/<name>/{base,dev,prod}/`
2. Add `base/kustomization.yaml`, `base/deployment.yaml`, `base/service.yaml`
3. Add overlay `kustomization.yaml` files with `namespace`, `images:`, `configMapGenerator`, `resources`
4. Add `config.properties` and `secrets.yaml.template` to each overlay
5. Generate `sealed-secrets.yaml` for prod
6. Validate: `kustomize build services/<name>/prod`
7. Push to `main` — ArgoCD auto-discovers the new directory (no app registration needed)
