# CHOTA GitOps

Kubernetes manifests for the CHOTA platform, managed with [Kustomize](https://kustomize.io/).

## Architecture

```
Internet
   |
   v
Cloudflare Tunnel                    namespace: default
   |
   v
KrakenD (chota-gateway)              namespace: prod
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
   +---> subscription-service     + PostgreSQL 15
   +---> notification-service    + PostgreSQL 15 + RabbitMQ 3.13
    +---> chota-site              (Next.js frontend)
    +---> blockrise              (Vite static frontend)
```

## Directory Structure

```
gitops/
├── .github/workflows/
│   └── reusable-deploy.yaml       # Reusable workflow for CI/CD
├── platform/
│   ├── argocd/                    # ArgoCD Application manifests
│   └── cloudflare-tunnel/        # Cloudflare tunnel for ingress
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
    └── chota-site/               # Next.js frontend
    └── blockrise/               # Block Rise 3D (static Vite, no backend)
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
| payment-service | `ghcr.io/chotabyorg/payment-service` | 8000 | PostgreSQL 16 |
| subscription-service | `ghcr.io/chotabyorg/subscription-service` | 8000 | PostgreSQL 15 |
| notification-service | `ghcr.io/chotabyorg/notification-service` | 8000 | PostgreSQL 15, RabbitMQ 3.13 |
| telegram-gateway-service | `ghcr.io/chotabyorg/telegram-gateway-service` | 8080 | — |
| website-gateway-service | `ghcr.io/chotabyorg/website-gateway-service` | 8080 | — |
| blockrise | `ghcr.io/chotabyorg/blockrise` | 80 | — |
| chota-site | `ghcr.io/chotabyorg/chota-site` | 3000 | — |

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
| `cloudflare-tunnel` | `platform/cloudflare-tunnel` | `default` |

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
kubectl apply -f platform/argocd/cloudflare-tunnel.yaml
```

### Bootstrapping a fresh cluster

```bash
# 1. Install ArgoCD and Sealed Secrets controller
# 2. Apply the repo credential SealedSecret
kubectl apply -f platform/argocd/sealed-secrets.yaml
# 3. Apply ArgoCD Applications (they pull everything else)
kubectl apply -f platform/argocd/prod.yaml
kubectl apply -f platform/argocd/cloudflare-tunnel.yaml
```

After bootstrap, ArgoCD self-manages — all subsequent changes go through git.

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

The platform uses a Cloudflare Tunnel for external access, configured in `platform/cloudflare-tunnel/`. No TLS certificates or ingress controllers are needed.

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
