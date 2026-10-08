# Main Conversation deployment candidate

Goal 4A prepares a private Main `prod` Conversation API, a separate immediate Website
worker and dedicated PostgreSQL 16 with persistent storage. [GitOps #111](https://github.com/chotabyorg/gitops/issues/111)
tracks this lane; the [Main ADR](../../docs/main-chota-conversation-foundation.md)
is architecture authority. The Foundation remains an unfinished umbrella.

**Source candidate only. No Conversation `prod` overlay exists yet, no real seal or
release image is supplied, and no production mutation has been performed.** Files
under `release/` are staging inputs, outside the live ApplicationSet's
`services/*/prod` discovery. A template or fixture render is not a deployable seal.
Read [release stages, prerequisites and rollback](RELEASE.md) before materializing
the complete production directory.

## Components and ownership

The API uses private ClusterIP port 8000; only Website pods in the same namespace may
reach it under the NetworkPolicy. Worker health port 8001 has no Service and no pod
ingress. PostgreSQL port 5432 accepts API/migration and worker pods only. API and worker
egress is limited to PostgreSQL, AI port 8000 and kube-system DNS. The API uses AI solely
for the protected processing-role operational evidence query; Website credentials
cannot execute/claim/complete/control or access that query. There is no AI proof
callback, KrakenD route, public ingress, NodePort or externalIP.

API and worker use the same immutable source image and UID/GID 10001; PostgreSQL 16
Alpine uses 70. Every component disables service-account token automount, uses
RuntimeDefault seccomp, drops all capabilities, forbids privilege escalation and
has a read-only filesystem with bounded writable mounts. API and worker have
bounded CPU/memory, `/health` liveness and `/ready` schema/scope readiness. Worker
readiness is provided by the actual `python worker.py` process on port 8001, including
exact migration head, configured binding and polling heartbeat.

Component-specific Kustomizations inject disjoint Deployment and Service
selectors. PostgreSQL and API use single-replica Recreate. The 4Gi `local-path` PVC
has `Prune=false,Delete=false`; basic storage protection does not imply backup or
HA guarantees. PostgreSQL SCRAM TCP authentication is explicit; local socket trust
is confined to its pod. No shared database or backup/replication work is added.

## Migration and launch

The API initContainer alone runs the image's `alembic upgrade head ` through
`release/dark/migrate.py`. Its dedicated session holds Conversation advisory
lock 4348534 for the entire child process. DB readiness, lock acquisition and child
execution each have 180-second bounds; lock/session loss or child failure prevents
startup. Driver/Alembic output is suppressed; only fixed phase/status codes reach
logs. The wrapper reads only `DATABASE_URL`, never auth registries. The worker
does not run migrations and its readiness requires `0003_website_canary`.

Argo waves within this Application are sealed credentials −2; ConfigMaps,
NetworkPolicies and Services −1; PVC plus PostgreSQL 0; API/migration 1; worker 2.
Putting local-path PVC and PostgreSQL in the same wave permits
WaitForFirstConsumer binding. Waves do not coordinate separate Website/AI/CP
Applications; release gates explicitly observe each stage before enabling the
next.

Initial config has `WEBSITE_BINDINGS=[]`, `WEBSITE_WORKER_ENABLED=false` and worker
replicas 0. Website guards/cohorts remain `{}`. Admission is bounded by exact
trusted IDs, then the coordinator processes only positively committed managed
Website work. Immediate parity is one Message→one stable Turn with a durable
serial queue. No debounce, grouping, supersede, Telegram or Voice is introduced.

## Private configuration

Dedicated Main-scoped SealedSecrets, never shared chat/widget/internal tokens:

| Secret | Keys / consumer |
| --- | --- |
| `conversation-database-secret` | `POSTGRES_PASSWORD` for PG; matching async `DATABASE_URL` for API/migration/worker |
| `conversation-principals-secret` | `API_AUTH_PRINCIPALS` (WEBSITE+PROCESSING); `PROCESSING_AUTH_PRINCIPALS` (PROCESSING only), each mapped to `CONVERSATION_AUTH_PRINCIPALS` |
| `conversation-managed-ai-secret` | `MANAGED_AI_BINDINGS` for worker and protected API evidence read |
| `website-conversation-s2s-secret` | `CONVERSATION_S2S_TOKEN` for Website, matching only the Website principal |
| `ai-conversation-managed-secret` | `MANAGED_AI_AUTH_PRINCIPALS` for the existing AI application only |

Website and processing principals have separate dedicated tokens and exact
owner/integration/WEBSITE_WIDGET/`main-chota.website-widget.v1` grants. AI's third
token has caller `conversation-service`, execution namespace
`main-chota.conversation.v1`, exact owner/integration/channel/agent and
`agent_owner_id`. The AI registry uses a separate keyRef; existing AI secrets,
image, Business TLS/signing and PostSync hooks remain intact. Registry templates
use candidate IDs pending supported credential binding verification.

## Verification

```sh
python3 services/conversation-service/operations/validate.py --fixture
# Only after genuine artifacts are materialized into the complete prod directory:
python3 services/conversation-service/operations/validate.py --stage dark
kubectl kustomize services/conversation-service/prod
kubectl kustomize services/website-gateway-service/prod
kubectl kustomize services/ai-agent-service/prod
kubectl kustomize services/control-plane-service/prod
```

The fixture check uses temporary synthetic schema-only ciphertext and image
digests to verify source rendering and references. It never claims cryptographic
validity, a pulled image, runtime readiness, CNI enforcement or production release
approval. Production validation refuses fixture markers and missing artifacts.
Canary validation additionally requires `--approval-record` pointing to a private
non-secret record with exact candidate IDs and true binding, logging, smoke-safety
and CLEAN exact-release gates; the record references completed external proofs,
it does not perform or replace them.
Real migration serialization, hardened container/API/worker lifecycle and
effective positive/negative NetworkPolicy proof remain pre-release gates.
