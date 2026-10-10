# Main Conversation production state

Goal4A is complete and passed. The PostgreSQL storage persistence fix is in place,
and the temporary Goal4A AI canary runtime has been removed. Production keeps the
Conversation API, PostgreSQL/PVC, durable Website admissions, integration guard,
and exact Website binding. The [Main ADR](../../docs/main-chota-conversation-foundation.md)
remains the architecture authority; the broader Foundation is unfinished.

Managed execution remains disabled: worker replicas are 0,
`WEBSITE_WORKER_ENABLED=false`, `MANAGED_AI_BINDINGS=[]`, and
`MANAGED_WEBSITE_COHORTS={}`. All new Website traffic is LEGACY. The base
Conversation NetworkPolicies allow the normal `ai-agent-service` API on port 8000;
the path is dormant while managed bindings are empty. Retained Website admission,
guard/S2S, and `WEBSITE_BINDINGS` state must not be deleted as canary debris. No
permanent managed AI principal/binding or Goal4B work is included here.

See [release record](RELEASE.md) for current operational state and historical
Goal4A rollout evidence. The [storage record](STORAGE-FIX.md) preserves the fix
history; it is no longer a pending release gate.

## Components and ownership

The API uses private ClusterIP port 8000; only Website pods in the same namespace may
reach it under the NetworkPolicy. Worker health port 8001 has no Service and no pod
ingress. PostgreSQL port 5432 accepts API/migration and worker pods only. Base
NetworkPolicies permit API and worker egress to PostgreSQL, normal `ai-agent-service`
port 8000, and kube-system DNS. Managed execution is inactive in the current
production configuration because bindings are empty and the worker is disabled.
Website credentials cannot execute/claim/complete/control or access the protected
processing-role evidence query. There is no AI proof callback, KrakenD route, public
ingress, NodePort or externalIP.

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
The PVC mounts at `/var/lib/postgresql/data`, exactly overriding the pinned image's
declared VOLUME; `PGDATA=/var/lib/postgresql/data/pgdata` is its UID 70-owned child.
Mounting only `/var/lib/postgresql` is invalid on the observed Main containerd CRI.

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

Final production config retains the exact `WEBSITE_BINDINGS`, keeps the Website
integration guard, and sets `MANAGED_WEBSITE_COHORTS={}`. Therefore all new
Website traffic is LEGACY while earlier accepted admission decisions remain
sticky. Worker replicas stay 0 and `WEBSITE_WORKER_ENABLED=false`; API and worker
`MANAGED_AI_BINDINGS` are both `[]`. Immediate parity remains one Message→one
stable Turn with a durable serial queue. No debounce, grouping, supersede,
Telegram or Voice is introduced.

## Private configuration

Dedicated Main-scoped SealedSecrets, never shared chat/widget/internal tokens:

| Secret | Keys / consumer |
| --- | --- |
| `conversation-database-secret` | `POSTGRES_PASSWORD` for PG; matching async `DATABASE_URL` for API/migration/worker |
| `conversation-principals-secret` | `API_AUTH_PRINCIPALS` (WEBSITE+PROCESSING); `PROCESSING_AUTH_PRINCIPALS` (PROCESSING only), each mapped to `CONVERSATION_AUTH_PRINCIPALS` |
| `conversation-managed-ai-secret` | Retained sealed source; prod API and worker explicitly override `MANAGED_AI_BINDINGS` to `[]` |
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
python3 -m unittest discover -s services/conversation-service/operations -p test_validate.py
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
Dark validation accepts absent Website guard/cohort fields as their empty legacy
defaults, so it does not require an early Website deployment. Explicit nonempty
values are rejected. Every later stage requires both fields explicitly present.
The canary validation and release steps in this historical section describe the
pre-completion Goal4A candidate; they are not current operational gates. Goal4A
passed, and the storage fix and native persistence proof completed. Managed
execution remains disabled as stated above. See the [release record](RELEASE.md)
for final state and retained rollback authority.
