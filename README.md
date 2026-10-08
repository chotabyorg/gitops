# CHOTA GitOps

Kubernetes manifests for the CHOTA platform, managed with [Kustomize](https://kustomize.io/).

## Main Chota Platform vs Chota 2.0

This repository describes the desired deployment state of **Main Chota Platform**, the production platform built from separate service repositories. Main planning belongs to [GitHub Project #3 — Chota Platform](https://github.com/orgs/chotabyorg/projects/3).

[`chotabyorg/chota`](https://github.com/chotabyorg/chota) and [Project #6 — Chota 2.0](https://github.com/orgs/chotabyorg/projects/6) belong to a **separate, currently paused fashion/e-commerce AI sales product**. Its code, Conversation Core, E0/E1/E4, issues and roadmap are not Main Platform implementation, architecture evidence or backlog.

Source code at a named revision, a draft PR, GitOps desired state and verified live runtime are different evidence. The default branch or an image tag in GitOps alone does not prove which revision is running. Record the source commit, image provenance and observed runtime when making deployment claims.

The [Main Chota Conversation Foundation ADR](docs/main-chota-conversation-foundation.md) records accepted architecture, Goals0–3 source maturity and the Website-first Goal4A rollout boundary. The [Conversation release candidate](services/conversation-service/RELEASE.md) stays outside auto-discovered production paths until real immutable images, Main-scoped seals and independent release review are complete. Foundation and the next Telegram Goal4B remain unfinished.

## Architecture

```
Internet
   |
   v
Traefik (ingress + TLS)              namespace: kube-system
   |  (Let's Encrypt HTTP-01 auto-renewal)
   |
   +---> outsors:80              (chota.by — landing page)
   +---> chota-site:3000         (agents.chota.by — main frontend)
   +---> blockrise:80            (blockrise.chota.by)
   +---> demo-website:80         (demo.chota.by)
   +---> repetly:3000            (repetly.chota.by)
   +---> repetly-minio:9000      (repetly-storage.chota.by)
   +---> website-gateway-service:8080  (widget.chota.by)
   |
   +---> control-plane-service:8000  (GET api.chota.by/v1/instagram/callback only; exact Traefik route preserves OAuth 302)
   +---> KrakenD (chota-gateway):8080  (all other api.chota.by requests)
          |
          +---> user-service            + PostgreSQL 15
          +---> ai-agent-service        + PostgreSQL 15 + Redis 7
          +---> control-plane-service   + PostgreSQL 15
          +---> knowledge-base-service  + PostgreSQL 15
          +---> rag-service             + Qdrant
          +---> document-service        + PostgreSQL 15 + MinIO
          +---> chunking-service        (no sidecar)
          +---> instagram-gateway-service
          +---> payment-service         + PostgreSQL 16
          +---> subscription-service    + PostgreSQL 15
          +---> notification-service    + PostgreSQL 15 + RabbitMQ 3.13
```

## Directory Structure

```
gitops/
├── .github/workflows/
│   └── reusable-deploy.yaml       # Reusable workflow for CI/CD
├── platform/
│   ├── argocd/                    # ArgoCD Application manifests
│   └── traefik-routes/           # Traefik IngressRoutes and TLS config
└── services/
    ├── chota-gateway/            # KrakenD API gateway (official image)
    │   ├── base/
    │   ├── dev/
    │   └── prod/
    ├── user-service/              # Auth & user management
    ├── ai-agent-service/          # AI agents & LLM chat (+ Redis)
    ├── control-plane-service/     # Integration lifecycle
    ├── knowledge-base-service/    # Knowledge base CRUD & document indexing
    ├── rag-service/               # RAG vector store & generation (+ Qdrant)
    ├── document-service/          # Document storage in S3 (+ MinIO)
    ├── chunking-service/          # Document chunking (no sidecar)
    ├── instagram-gateway-service/ # Instagram webhook handler
    ├── payment-service/           # bePaid payments
    ├── subscription-service/      # Plans & subscriptions
    ├── notification-service/     # Email notifications (+ RabbitMQ)
    ├── telegram-gateway-service/ # Telegram bot gateway
    ├── website-gateway-service/  # Website chat widget gateway
    ├── chota-site/               # Next.js frontend
    ├── blockrise/               # Block Rise 3D (static Vite, no backend)
    ├── outsors/                 # Outsors landing page (static Vite, no backend)
    └── repetly/                 # Tutor SaaS (Next.js + Prisma + PostgreSQL)
```

Each service follows the same layout:

```
<service>/
├── base/                  # Shared resources (no namespace)
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── postgres-*.yaml   # (if applicable)
├── dev/
│   ├── kustomization.yaml # namespace: dev, configMapGenerator
│   ├── config.properties  # Non-sensitive env vars
│   └── secrets.yaml.template
└── prod/
    ├── kustomization.yaml # namespace: prod, configMapGenerator
    ├── sealed-secrets.yaml # Committed (kubeseal generated)
    ├── config.properties
    └── secrets.yaml.template
```

## Services

| Service | Image | Port | Dependencies |
|---------|-------|------|--------------|
| chota-gateway | `krakend/krakend:2.13.3` | 8080 | krakend.json, krakend-jwk.json |
| user-service | `ghcr.io/chotabyorg/user-service` | 8000 | PostgreSQL 15 |
| ai-agent-service | `ghcr.io/chotabyorg/ai-agent-service` | 8000 | PostgreSQL 15, Redis 7 |
| control-plane-service | `ghcr.io/chotabyorg/control-plane-service` | 8000 | PostgreSQL 15 |
| knowledge-base-service | `ghcr.io/chotabyorg/knowledge-base-service` | 8000 | PostgreSQL 15 |
| rag-service | `ghcr.io/chotabyorg/rag-service` | 8080 | Qdrant |
| document-service | `ghcr.io/chotabyorg/document-service` | 8080 | PostgreSQL 15, MinIO |
| chunking-service | `ghcr.io/chotabyorg/chunking-service-lite` | 8000 | — |
| instagram-gateway-service | `ghcr.io/chotabyorg/instagram-gateway-service` | 8080 | — |
| whatsapp-gateway-service | `ghcr.io/chotabyorg/whatsapp-gateway-service` | 8080 | — |
| payment-service | `ghcr.io/chotabyorg/payment-service` | 8000 | PostgreSQL 16 |
| subscription-service | `ghcr.io/chotabyorg/subscription-service` | 8000 | PostgreSQL 15 |
| notification-service | `ghcr.io/chotabyorg/notification-service` | 8000 | PostgreSQL 15, RabbitMQ 3.13 |
| telegram-gateway-service | `ghcr.io/chotabyorg/telegram-gateway-service` | 8080 | — |
| website-gateway-service | `ghcr.io/chotabyorg/website-gateway-service` | 8080 | — |
| blockrise | `ghcr.io/chotabyorg/blockrise` | 80 | — |
| outsors | `ghcr.io/chotabyorg/outsors` | 80 | — |
| chota-site | `ghcr.io/chotabyorg/chota-site` | 3000 | — |
| repetly | `ghcr.io/chotabyorg/repetly` | 3000 | PostgreSQL 18 (Prisma) |

## CI/CD

Each service repository has a `.github/workflows/deploy.yaml` that:
1. Builds a Docker image on push to `main`
2. Pushes to GHCR (`ghcr.io/chotabyorg/<service>`)
3. Updates the image tag in `services/<service>/prod/kustomization.yaml`

**chota-gateway** is special — it uses the official KrakenD image, so no Docker build is needed. Instead, a `sync-config.yaml` workflow copies `krakend.json` to this repository on push.

The reusable workflow is at `.github/workflows/reusable-deploy.yaml`.

## ArgoCD Deployment

ArgoCD watches this repository and continuously syncs manifests to the cluster. There is no separate `kubectl apply` step in the pipeline — once CI updates the image tag, ArgoCD picks up the change within 3 minutes (default polling interval) and reconciles the cluster.

### ApplicationSet (prod services)

All prod services are managed by a single [`ApplicationSet`](platform/argocd/prod.yaml) that auto-discovers `services/*/prod` directories:

```yaml
# platform/argocd/prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: prod-services
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: git@github.com:chotabyorg/gitops.git
        revision: main
        directories:
          - path: "services/*/prod"
          - path: "services/payment-service/prod"
            exclude: true
  template:
    spec:
      source:
        path: "{{path}}"
      destination:
        namespace: prod
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
        syncOptions:
          - CreateNamespace=true
```

**Key behavior:**
- Each `services/<name>/prod` directory becomes an ArgoCD Application named `<name>-prod`
- Sync is **automated** — no manual intervention needed
- `selfHeal: true` — any manual cluster changes are reverted to match Git
- `prune: true` — resources removed from Git are deleted from the cluster
- `CreateNamespace=true` — the `prod` namespace is created automatically
- New services are **auto-discovered** — just create `services/<name>/prod/` and ArgoCD picks it up
- To exclude a service, add an explicit exclude entry (see `payment-service` above)

### Platform Applications

Additional Applications manage platform-level resources:

| Application | Source Path | Namespace |
|-------------|-------------|-----------|
| `traefik-routes` | `platform/traefik-routes` | `prod` |

### Repo Credentials

ArgoCD needs an SSH key to access this private repository. The credential is managed as a SealedSecret in [`platform/argocd/sealed-secrets.yaml`](platform/argocd/sealed-secrets.yaml):

```bash
# Set up the ArgoCD repo credential
cp platform/argocd/secrets.yaml.template platform/argocd/secrets.yaml
# Fill in the SSH private key in secrets.yaml
kubeseal --format yaml < platform/argocd/secrets.yaml > platform/argocd/sealed-secrets.yaml
rm platform/argocd/secrets.yaml

# Apply the SealedSecret and the ApplicationSet
kustomize build --enable-alpha-plugins platform/argocd/prod.yaml
# or apply directly:
kubectl apply -f platform/argocd/sealed-secrets.yaml
kubectl apply -f platform/argocd/prod.yaml
kubectl apply -f platform/argocd/traefik-routes.yaml
```

### Bootstrapping a fresh cluster

```bash
# 1. Install ArgoCD and Sealed Secrets controller
# 2. Apply the repo credential SealedSecret
kubectl apply -f platform/argocd/sealed-secrets.yaml
# 3. Apply ArgoCD Applications (they pull everything else)
kubectl apply -f platform/argocd/prod.yaml
kubectl apply -f platform/argocd/traefik-routes.yaml
```

After bootstrap, ArgoCD self-manages — all subsequent changes go through git.

## Database Migrations

All services with PostgreSQL sidecars apply database migrations via **initContainers** defined in their `base/deployment.yaml`. The initContainer runs `alembic upgrade head` using the same image and database credentials as the main application, before the main container starts.

| Service | Migration tool | Method |
|---------|:---:|--------|
| ai-agent-service | Alembic | initContainer |
| control-plane-service | Alembic | initContainer |
| knowledge-base-service | Alembic | initContainer |
| notification-service | Alembic | initContainer |
| payment-service | Alembic | initContainer |
| subscription-service | Alembic | initContainer |
| user-service | Alembic | initContainer |
| document-service | Liquibase | Spring Boot startup (auto) |
| repetly | Prisma | initContainer (`npx prisma migrate deploy`) |

Services without PostgreSQL sidecars (`chota-gateway`, `chota-site`, `blockrise`, `outsors`, `chunking-service`, `rag-service`, gateway services) do not require migrations.

## Usage

### Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) (v5+)
- A Kubernetes cluster with:
  - [ArgoCD](https://argo-cd.readthedocs.io/) (primary deployment mechanism)
  - [Sealed Secrets controller](https://github.com/bitnami-labs/sealed-secrets)

### Build and preview

```bash
# Build a specific overlay
kustomize build services/user-service/prod

# Build all services
for svc in services/*/prod; do
  echo "--- $svc ---"
  kustomize build "$svc"
done
```

### Deploy manually (without ArgoCD)

ArgoCD is the primary deployment mechanism (see [ArgoCD Deployment](#argocd-deployment) above). Manual `kubectl apply` is useful for local testing or debugging:

```bash
# Create namespaces
kubectl create namespace prod

# Deploy services
kustomize build services/chota-gateway/prod | kubectl apply -f -
kustomize build services/user-service/prod | kubectl apply -f -
# ... etc
```

## Configuration

### Environment variables

Each service splits config into two files:

- **`config.properties`** — non-sensitive values (feature flags, URLs, timeouts)
- **`secrets.yaml.template`** — template for sensitive values (passwords, API keys, tokens)

Kustomize turns these into ConfigMaps and Secrets via `configMapGenerator` / `secretGenerator`, which are then referenced in the Deployment via `envFrom`.

### Sealed Secrets Workflow

This repository uses [SealedSecrets](https://github.com/bitnami-labs/sealed-secrets) to manage secrets safely in Git.

**Workflow:**

1. **Create a template:**
   ```bash
   cp secrets.yaml.template secrets.yaml
   ```

2. **Fill in the secret manifest:**
   Edit `secrets.yaml` with your actual secret values:
   ```yaml
   apiVersion: v1
   kind: Secret
   type: Opaque
   metadata:
     name: user-service-secret
     namespace: prod
   stringData:
     POSTGRES_PASSWORD: actual-password
   ```

3. **Seal the secret:**
   ```bash
   kubeseal --format yaml < secrets.yaml > sealed-secrets.yaml
   ```

**Note:** `secrets.yaml` is in `.gitignore` and should never be committed. Only `sealed-secrets.yaml` and `secrets.yaml.template` are committed.

### Images

Base deployments use generic image names (e.g., `user-service`). Each overlay has an `images:` block in `kustomization.yaml` that overrides the image to GHCR:

```yaml
images:
  - name: user-service
    newName: ghcr.io/chotabyorg/user-service
    newTag: latest
```

CI pipelines update `newTag` to the git SHA on each push to `main`.

### KrakenD Gateway

The chota-gateway uses the official `krakend:2.13.3` image with config injected via ConfigMap:

- **`krakend.json`** — route definitions (per overlay)
- **`krakend-jwk.json`** — JWT signing key for token validation (sealed secret)

To regenerate the JWK file from `SECRET_KEY`:

```bash
cd chota-gateway
python generate_jwk.py
```

All backend services use Kubernetes service DNS names (e.g., `http://user-service`, `http://ai-agent-service`) instead of Docker Compose hostnames or IP addresses.

### Ingress

External traffic enters via **Traefik** (k3s built-in ingress controller) with **Let's Encrypt HTTP-01** for automatic TLS. IngressRoutes are defined in `platform/traefik-routes/` and managed by ArgoCD.

**Host/path → Service mapping:**

| Host/path | Service | Port |
|----------|---------|------|
| `chota.by` | `outsors` | 80 |
| `www.chota.by` | → redirect to `chota.by` | |
| `api.chota.by/v1/instagram/callback` (`GET` only) | `control-plane-service` (exact Traefik route; preserves OAuth `302 Location`) | 8000 |
| `api.chota.by` (all other requests) | `chota-gateway` (KrakenD) | 8080 |
| `agents.chota.by` | `chota-site` | 3000 |
| `blockrise.chota.by` | `blockrise` | 80 |
| `demo.chota.by` | `demo-website` (ExternalName → default ns) | 80 |
| `repetly.chota.by` | `repetly` | 3000 |
| `repetly-storage.chota.by` | `repetly-minio` | 9000 |
| `widget.chota.by` | `website-gateway-service` | 8080 |

**DNS:** All hostnames have A records pointing to the server's public IP. Cloudflare proxy is disabled (DNS-only mode).

**TLS:** Traefik automatically obtains and renews Let's Encrypt certificates via HTTP-01 challenges. Certificates are stored on the host at `/var/lib/rancher/k3s/traefik-acme/acme.json`. No cert-manager or manual certificate management is needed.

The exact `GET /v1/instagram/callback` route has explicit priority above the broad `Host(api.chota.by)` route and forwards directly to `control-plane-service:8000`. This preserves the OAuth callback's `302 Location` response; all other API requests, including other methods on this path, continue through KrakenD. The callback remains public and Instagram self-service remains disabled.

**Traefik configuration** is managed via k3s's HelmChartConfig (see `platform/traefik-routes/traefik-helm-config.yaml.ref`).

## Adding a new service

1. Create the directory structure:
   ```
   services/my-service/{base,dev,prod}/
   ```

2. Add `base/kustomization.yaml`, `base/deployment.yaml`, `base/service.yaml`

3. Create overlay configs:
   - `prod/kustomization.yaml` — namespace + generators
   - `prod/config.properties` — non-sensitive env vars
   - `prod/secrets.yaml.template` — secret key template
   - `prod/sealed-secrets.yaml` — sealed secrets (generated)


4. Add CI workflow:
   Create `.github/workflows/deploy.yaml` in the service repository

5. Validate:
   ```bash
   kustomize build services/my-service/prod
   ```

6. ArgoCD will auto-discover the new service once the directory is pushed to `main`. No additional ArgoCD Application registration is needed.

## Troubleshooting

```bash
# Check what kustomize generates without applying
kustomize build services/user-service/prod | less

# Diff against what's running
kustomize build services/user-service/prod | kubectl diff -f -

# Check a specific resource
kubectl get deployment user-service -n prod -o yaml

# View logs
kubectl logs -n prod -l app=user-service --tail=100 -f
```

## ChotaCRM v0.1

The independently reviewed CRM release is promoted through a separate GitOps PR, not direct application CI pushes. See [release provenance, checks and rollout](services/chota-crm-service/RELEASE.md), [backend/storage boundaries](services/chota-crm-service/README.md), [local daily backup and recovery](services/chota-crm-service/operations/BACKUP.md), and [frontend deployment](services/chota-crm-web/README.md). CRM exposes only crm.chota.by; its API is internal behind the existing gateway.

The Goal4A source change reconciles tracked `platform/argocd/prod.yaml` to the read-only 2026-10-08 live generator: `services/*/prod`, payment exclusion and existing automated enabled/prune/selfHeal. It adds no discovery scope beyond actual Main behavior. ArgoCD remains deployment authority; do not manually apply the ApplicationSet. Both complete CRM prod overlays use this existing discovery behavior.
