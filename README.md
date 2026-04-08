# CHOTA GitOps

Kubernetes manifests for the CHOTA platform, managed with [Kustomize](https://kustomize.io/).

## Architecture

```
Internet
   |
   v
Traefik Ingress (HTTP/HTTPS)         namespace: dev / prod
   |
   v
KrakenD (chota-gateway)              namespace: dev / prod
   |
   +---> user-service            + PostgreSQL 15
   +---> ai-agent-service        + PostgreSQL 15 + Redis 7
   +---> control-plane-service   + PostgreSQL 15
   +---> instagram-gateway-service
   +---> payment-service         + PostgreSQL 16
   +---> chota-site              (Next.js frontend)
```

## Directory Structure

```
gitops/
├── cluster/                          # Cluster-wide resources
│   ├── kustomization.yaml
│   └── cluster-issuer.yaml          # Let's Encrypt issuer for TLS
│
└── services/
    ├── chota-gateway/                # KrakenD API gateway (official image)
    │   ├── base/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── ingress.yaml         # Ingress for chota.by + api.chota.by
    │   ├── dev/
    │   │   └── kustomization.yaml   # HTTP only
    │   └── prod/
    │       └── kustomization.yaml   # HTTPS with TLS
    ├── user-service/                 # Auth & user management
    ├── ai-agent-service/             # AI agents & LLM chat
    ├── control-plane-service/       # Integration lifecycle
    ├── instagram-gateway-service/   # Instagram webhook handler
    ├── payment-service/             # bePaid payments
    ├── chota-site/                  # Next.js frontend
    └── telegram-gateway-service/    # Telegram bot gateway
```

Each service follows the same layout:

```
<service>/
├── base/                  # Shared resources (no namespace)
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── postgres-*.yaml    # (if applicable)
│   └── redis-*.yaml       # (if applicable)
├── dev/
│   ├── kustomization.yaml # namespace: dev, configMapGenerator
│   ├── sealed-secrets.yaml # Committed (kubeseal generated)
│   ├── secrets.yaml.template # Template for secrets.yaml
│   ├── config.properties  # Non-sensitive env vars
│   └── postgres.properties# (if applicable)
└── prod/
    └── ...                # Same structure, production values
```

## Services

| Service | Image | Port | Dependencies |
|---------|-------|------|--------------|
| chota-gateway | `krakend:2.9` | 8080 | krakend.json, krakend-jwk.json |
| user-service | custom build | 8000 | PostgreSQL 15 |
| ai-agent-service | custom build | 8000 | PostgreSQL 15, Redis 7 |
| control-plane-service | custom build | 8000 | PostgreSQL 15 |
| instagram-gateway-service | custom build | 8080 | — |
| payment-service | custom build | 8000 | PostgreSQL 16 |
| chota-site | custom build | 3000 | — |
| telegram-gateway-service | custom build | 8080 | — |

## Usage

### Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) (v5+)
- A Kubernetes cluster with:
  - [Traefik](https://traefik.io/traefik/) as the ingress controller (default in k3s)
  - [cert-manager](https://cert-manager.io/) for TLS certificates

### Build and preview

```bash
# Build a specific overlay
kustomize build services/user-service/dev

# Pipe to kubectl for dry-run
kustomize build services/user-service/dev | kubectl apply --dry-run=client -f -

# Build all services for an environment
for svc in services/*/dev; do
  echo "--- $svc ---"
  kustomize build "$svc"
done
```

### Deploy

```bash
# Create namespaces
kubectl create namespace dev
kubectl create namespace prod

# Deploy cluster-wide resources (cert-manager issuer)
kustomize build cluster/ | kubectl apply -f -

# Install cert-manager if not already installed
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml

# Deploy services (order matters for first deploy)
kustomize build services/chota-gateway/dev | kubectl apply -f -
kustomize build services/user-service/dev | kubectl apply -f -
kustomize build services/ai-agent-service/dev | kubectl apply -f -
kustomize build services/control-plane-service/dev | kubectl apply -f -
kustomize build services/instagram-gateway-service/dev | kubectl apply -f -
kustomize build services/payment-service/dev | kubectl apply -f -
kustomize build services/chota-site/dev | kubectl apply -f -
kustomize build services/telegram-gateway-service/dev | kubectl apply -f -
```

## Configuration

### Environment variables

Each service splits config into two files:

- **`config.properties`** — non-sensitive values (feature flags, URLs, timeouts)
- **`secrets.properties`** — sensitive values (passwords, API keys, tokens)

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
     namespace: dev
   data:
     POSTGRES_PASSWORD: cGFzc3dvcmQ=
     SECRET_KEY: c2VjcmV0a2V5
   ```
   (Use `echo -n "value" | base64` to encode values)

3. **Seal the secret:**
   ```bash
   kubeseal --format yaml -- sealed-secrets.yaml < secrets.yaml
   ```
**Note:** `secrets.yaml` is in `.gitignore` and should never be committed.

### Images

Base deployments use generic image names (e.g., `user-service`). Each overlay already has an `images:` block in `kustomization.yaml` that overrides the image to GHCR:

```yaml
images:
  - name: user-service
    newName: ghcr.io/chotabyorg/user-service
    newTag: latest
```

The `newTag` defaults to `latest`. CI pipelines or Argo CD Image Updater will update `newTag` to the actual image digest (e.g., a git SHA).

To manually override for a one-off deploy:

```bash
kustomize build services/user-service/dev | kubectl apply -f -
```

Or update the tag directly:

```bash
cd services/user-service/dev
kustomize edit set image ghcr.io/chotabyorg/user-service:abc1234
```

### KrakenD gateway

The chota-gateway uses the official `krakend:2.9` image with config injected via ConfigMap:

- **`krakend.json`** — route definitions (per overlay)
- **`krakend-jwk.json`** — JWT signing key for token validation

To regenerate the JWK file from `SECRET_KEY`:

```bash
cd chota-gateway
python generate_jwk.py
cp krakend-jwk.json gitops/services/chota-gateway/dev/
cp krakend-jwk.json gitops/services/chota-gateway/prod/
```

### Ingress + TLS

The `chota-gateway` service includes an Ingress resource that exposes `chota.by` and `api.chota.by` via Traefik.

- **Dev**: HTTP only (no TLS)
- **Prod**: HTTPS with automatic TLS via cert-manager and Let's Encrypt

The `cluster/` directory contains the `ClusterIssuer` that cert-manager uses to provision certificates.

## Adding a new service

1. Create the directory structure:
   ```
   services/my-service/{base,dev,prod}/
   ```

2. Add `base/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - deployment.yaml
     - service.yaml
   labels:
     - includeSelectors: true
       pairs:
         app: my-service
   ```

3. Add `base/deployment.yaml` and `base/service.yaml`

4. Create overlay configs:
   - `dev/config.properties` — non-sensitive env vars
   - `dev/secrets.properties` — sensitive env vars
   - `dev/kustomization.yaml` — namespace + generators

5. Validate:
   ```bash
   kustomize build services/my-service/dev
   ```

## Troubleshooting

```bash
# Check what kustomize generates without applying
kustomize build services/user-service/dev | less

# Diff against what's running
kustomize build services/user-service/dev | kubectl diff -f -

# Check a specific resource
kubectl get deployment user-service -n dev -o yaml

# View logs
kubectl logs -n dev -l app=user-service --tail=100 -f
```
