# AGENTS.md — CHOTA GitOps

Kubernetes manifests for the CHOTA platform. Managed with Kustomize (v5+) and deployed via ArgoCD. No application code lives here.

## Repository boundaries

- **This repo** = GitOps config only (Kustomize overlays)
- **Service source code** = separate repositories under `ghcr.io/chotabyorg/<service>`
- **CI** = each service repo calls `.github/workflows/reusable-deploy.yaml` in this repo
- **Deployment** = ArgoCD watches this repo and auto-syncs to the cluster (no manual `kubectl apply`)

### Product boundary and evidence

- GitOps describes **Main Chota Platform**. Use [Project #3 — Chota Platform](https://github.com/orgs/chotabyorg/projects/3) for Main planning.
- Never conflate Main with [`chotabyorg/chota`](https://github.com/chotabyorg/chota) / [Project #6 — Chota 2.0](https://github.com/orgs/chotabyorg/projects/6), the separate, currently paused fashion/e-commerce product. Its code, Conversation Core, E0/E1/E4, issues and roadmap are not Main architecture evidence or backlog. A separate task must explicitly authorize any use as an external reference.
- Audits must identify the repository and exact source revision for each finding. Distinguish **source code**, **draft/pending PR**, **GitOps desired state** and **verified live runtime**. Neither a default branch nor an image tag alone proves deployed code; report the limit when live provenance was not verified.
- Follow the accepted [Main Chota Conversation Foundation ADR](docs/main-chota-conversation-foundation.md) for future communication work. Foundation is unfinished. The initial Goal4A dark Conversation rollout reached Main with no admission, but failed native PVC durability; see the [storage finding and gates](services/conversation-service/STORAGE-FIX.md). Do not present this as production readiness, managed Website traffic or a deployed clean Voice Gateway.

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
| `argocd-ui` | `platform/argocd-ui` | `argocd` |
| `zot-registry` | `platform/registry/zot` | `registry` |
| `kube-prometheus-stack` | OCI helm chart + `platform/monitoring` | `monitoring` |

### Repo Credential

The ArgoCD repo credential (SSH key) is stored as a SealedSecret in `platform/argocd/sealed-secrets.yaml` with the label `argocd.argoproj.io/secret-type: repository`. The template is at `platform/argocd/secrets.yaml.template`.

### Bootstrapping

On a fresh cluster, apply the platform-level ArgoCD manifests first, then ArgoCD syncs everything else:

```bash
kubectl apply -f platform/argocd/sealed-secrets.yaml
kubectl apply -f platform/argocd/prod.yaml
kubectl apply -f platform/traefik-routes/traefik-routes.yaml
kubectl apply -f platform/argocd-ui/argocd-ui.yaml
kubectl apply -f platform/registry/zot-registry.yaml
kubectl apply -f platform/monitoring/monitoring.yaml
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

## Monitoring (kube-prometheus-stack)

Deployed via a multi-source ArgoCD `Application` ([`platform/monitoring/monitoring.yaml`](platform/monitoring/monitoring.yaml)):

- **Chart source** — `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`, version pinned in `monitoring.yaml`
- **Values** — [`platform/monitoring/values.yaml`](platform/monitoring/values.yaml), referenced via `$values` ref
- **Kustomize source** — `platform/monitoring/` (same git repo, `path:` source) renders the Grafana `IngressRoute` and `SealedSecret`

### Grafana

- Exposed at `grafana.chota.by` via a Traefik `IngressRoute` ([`platform/monitoring/ingressroute-grafana.yaml`](platform/monitoring/ingressroute-grafana.yaml)) → service `kube-prometheus-stack-grafana:80`
- **Auth** — GitHub OAuth SSO only:
  - `security.disable_initial_admin_creation: true` — no local `admin` account is ever created
  - `auth.disable_login_form: true` + `auth.github.auto_login: true` — login form hidden, auto-redirect to GitHub
  - `allowed_organizations: chotabyorg` — only org members may log in
  - Role mapping: `NeOchenHorosho` → `GrafanaAdmin`, everyone else → org `Admin`
- The GitHub OAuth App callback URL must be `https://grafana.chota.by/login/github`

### Alertmanager

Disabled (`alertmanager.enabled: false`). Alerts are not routed anywhere yet.

### Secrets

The `grafana-secrets` secret holds the GitHub OAuth `client_id`/`client_secret` (consumed via `grafana.envValueFrom`). Template at [`platform/monitoring/secrets.yaml.template`](platform/monitoring/secrets.yaml.template); seal it before first sync:

```bash
cp platform/monitoring/secrets.yaml.template platform/monitoring/secrets.yaml
# fill client_id / client_secret from the GitHub OAuth App
kubeseal --format yaml < platform/monitoring/secrets.yaml > platform/monitoring/sealed-secrets.yaml
rm platform/monitoring/secrets.yaml
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
