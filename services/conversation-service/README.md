# Main Conversation production state

The next, still-closed controlled QA prerequisites are documented in
[CONTROLLED-ENROLLMENT-PREREQUISITES](CONTROLLED-ENROLLMENT-PREREQUISITES.md).
This draft pins the final Website admission image and requires accepted Stage B.

The additive text writer attestor release and its staged production gates are
documented in [ATTESTOR-RELEASE](ATTESTOR-RELEASE.md). Stage A keeps Handoff
admission empty and existing managed bindings unchanged.

**Goal4B exact QA draft activation:** [GOAL4B-RELEASE](GOAL4B-RELEASE.md) now starts
with the separate activation candidate for newly created `@chota_test_4343434_bot`,
integration `9b43e8ab-7afa-4201-8a88-99e8d256180a`. The candidate prepares one scoped
Telegram cohort/worker and retains the current Website/Beauty configuration.
It is DRAFT ONLY and requires a fresh independent activation review before any
merge or production acceptance. The older foundation sections below are retained
historical checkpoints, not a description of this draft or current Beauty state.

**Goal4B DARK release candidate:** [GOAL4B-RELEASE](GOAL4B-RELEASE.md) is the
current Telegram release/runbook checkpoint for PR #148. It preserves the live
Website selector, prepares an isolated zero-replica Telegram worker and defines
forward-compatible configuration rollback after schema 0005. The historical
Goal4A sections below do not describe current Website/Beauty activation state.
This candidate does not authorize merge or Telegram canary activation.

**Current beauty rollout candidate:** [BEAUTY-CUTOVER](BEAUTY-CUTOVER.md) records
the permanent exact managed principal and normal-production-AI binding stages.
Stage 3 enables one permanent worker after the exact stage 2 binding gate. Stage 4
admits one explicit synthetic QA session only after independent worker readiness;
integration-wide admission and public HTML remain gated. The Goal4A/Goal4A.1 dark-state values
below describe the retained pre-cutover baseline, not this stage's binding target.
Actual deployment acceptance is recorded separately after Argo/runtime checks.

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

## Goal4A.1 release candidate

The reviewed Conversation image adds bounded canonical Website history and managed
v2 projection support. This GitOps candidate changes only the immutable
Conversation and widget-owner site images; production deployment,
migration/readiness and real-model continuity
remain separate verification gates recorded in [RELEASE](RELEASE.md). It does not
activate managed Website traffic.

Existing v1 Turns retain their full canonical prefix, immutable wire bytes and
fingerprints; omitted contract version still means v1. New immediate Website Turns
use a contiguous v2 window with absolute canonical Message sequences. Creation
freezes the version, window start, existing selected/context bounds, authoritative
agent and exact request hash. Whole Messages remain in canonical order; oldest
eligible prior units are dropped deterministically until the unchanged 256-Message,
524288 projected UTF-8 text-byte and 1048576 serialized request-byte limits fit.
Selected input is retained entirely or the Turn fails before dispatch. Retry and
restart reconstruct the frozen projection without choosing a new window.

A new durable Website `WRITE_COMPLETED` response attempt may append the exact
retained draft once as `AGENT/OUTBOUND/TEXT`, uniquely related to its source Turn
in the same Conversation. That append advances `last_message_sequence` once and
leaves customer-only `input_revision` unchanged. `WRITE_FAILED`, `UNKNOWN` and
draft existence alone create no assistant history; a later successful attempt
may append it once. Completion replay creates no Message or backfill. Local write
completion is not browser READ acknowledgement. Late successful delivery never
changes an earlier frozen Turn.

The execute endpoint, OperationReference, v1 managed-evidence contracts and
`main-chota.conversation.v1` execution namespace remain unchanged. Business keeps
its frozen proposal, confirmation policy and operation authority. The separate
widget owner is `chotabyorg/chota-site/public/widget.js`; its stable logical-send
identity is a separate reviewed source/artifact gate in this release. One logical
send creates one UUID and an immutable `{session_id,message_id,message}` envelope;
retry reuses that same envelope, while a new or edited message gets a new UUID.
Pending reload recovery is scoped to the current full widget identity and session,
and completed pending envelopes are removed. Browser presentation/transcripts are
never canonical history authority. Legacy traffic remains compatible.

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
does not run migrations. The Goal4A.1 image's API and worker readiness require
exactly `0004_website_history` and the new projection/history column queries.
The existing wrapper and its lock/time bounds are unchanged.

`0004_website_history` is additive: old Turns default to v1/start 1 with null
projection agent/hash, and old Messages retain a null source-Turn relation.
Existing evidence and fingerprints are not rewritten. Downgrade refuses retained
v2 Turns or source-Turn assistant history, including history from a v1 draft.
Keep managed execution disabled for rollback; use a compatible forward fix rather
than an older image expecting schema 0003 or a destructive schema downgrade.

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

The commands below retain the historical pre-Goal4A fixture/stage checks, not the
Goal4A.1 release gate. On exact GitOps base
`3cf36da5a157788a51581673b75e4d29d3a31fd4` and this candidate, the unchanged
validator suite runs 21 tests with the same 7 fixture-render errors: its synthetic
fixture adds a duplicate already-retained Website S2S SealedSecret resource.
Both historical `--fixture` runs fail; this suite is not reported as PASS.
The actual complete production overlays render successfully, and separate author
checks prove the exact image-only resource delta and retained DARK controls.
Fresh combined release review must independently assess that inherited failure
and the current candidate before promotion. No validator or resource is changed
to bypass it.

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
