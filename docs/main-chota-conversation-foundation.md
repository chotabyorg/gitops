# Main Chota Conversation Foundation

## Status and scope

**Accepted architecture; Goals 0–3 source foundation complete; Goal 4A production gates in progress.** The initial private dark Conversation rollout reached Main through GitOps PR #112 with admission disabled and worker zero. Independent native verification found PostgreSQL on an image volume shadowing its PVC, so durability failed despite readiness. The [separate storage forward fix](../services/conversation-service/STORAGE-FIX.md) requires a fresh complete review and native persistence proof; no Website managed canary is enabled. Goal 4B will follow with Telegram. The Foundation remains an unfinished umbrella; source maturity or a dark deployment does not establish production readiness or complete the roadmap.

Main planning belongs to [Project #3 — Chota Platform](https://github.com/orgs/chotabyorg/projects/3). [`chotabyorg/chota`](https://github.com/chotabyorg/chota) / [Project #6 — Chota 2.0](https://github.com/orgs/chotabyorg/projects/6) are a separate, paused fashion/e-commerce product. Their code, E0/E1/E4, Conversation Core, issues and roadmap were **not used as Main architecture evidence**.

The representative legacy-flow statements below remain historical source observations. Goals 1–3 have since added the durable Conversation journal, managed v1 Turn contract and AI-owned Business evidence recovery. The pre-rollout Goal4A read-only Main baseline on 2026-10-08 identified Conversation source `d238064215d3875c5d2061bba5a00b55dc5fad0e` with no production Deployment, Website `fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b`, AI `4fa17597b8083d2e09428c9c1ac949aa42f5990d` with Business V2 enabled, and Control Plane `96a4b40daeb113f435f5cd02a6f7a2fc12502b24`. Preserve that current AI Business baseline; PR #43's earlier draft status is historical, not the current release authority. GitOps desired state, Argo revision and observed pod digests are separate evidence. See the [Goal4A release record](../services/conversation-service/RELEASE.md) for actual dark rollout limits and remaining gates.

## Context and problems

The representative inspected Telegram, Instagram and Website Widget source paths resolve integration configuration through control-plane and call AI independently for each inbound message:

```text
Provider event
  → Channel Gateway
  → trusted control-plane integration resolution / gateway external_client_id
  → ai-agent-service POST /v1/chat/completions
  → PostgreSQL ConversationSession → Redis history
  → prompt / KB / LLM / tools
  → user + assistant history saved to Redis
  → answer returned → Gateway formatting / network delivery → Provider
```

WhatsApp's pinned source describes an MVP gateway foundation, not a full production launch. Its client expects control-plane polling with `channel_type=WHATSAPP`, while the pinned control-plane `ChannelType` enum contains only `TELEGRAM`, `INSTAGRAM`, `WEBSITE_WIDGET` and `VOICE`. This unresolved source-contract mismatch means the WhatsApp snapshot does not establish end-to-end integration compatibility. These source observations do not establish live WhatsApp behavior.

The compact current diagram is `Gateway → AI → Redis → Gateway`; Redis stores context before the gateway sends the answer. `ConversationSession` is AI context identity, not a provider-neutral platform Conversation. Redis history has a TTL and stores the entire user/assistant context, not an authoritative communications journal.

The inspected legacy AI path has no shared per-Conversation serialization: concurrent requests can read the same Redis history and overwrite each other's update. Quick successive messages can start separate AI executions. A successful LLM response is saved before provider delivery; AI cannot establish whether it was accepted, delivered, read, interrupted or never sent. There is no shared durable inbound-event/message journal, delivery journal or operator/control authority in this path. Voice additionally needs call and speech metadata while keeping acoustic coordination separate from platform communication coordination.

## Decision and target flow

Use the independent **`conversation-service` with PostgreSQL** as the authoritative owner of communication lifecycle. Redis may accelerate work, but must not own durable history, queue or handoff. Goals 1–3 define the accepted journal/Turn/delivery primitives and stable managed v1 contracts. Goal4A adds narrowly scoped Website admission, immediate processing and HTTP transport evidence without redesigning those ownership boundaries.

```text
Provider ↔ Channel Gateway ↔ Conversation Service ↔ ai-agent-service
                                                    ↕
                                       Business Runtime / KB / RAG

control-plane-service → trusted integration / owner / agent / routing binding
Conversation Service → optional CRM projection
```

The managed request/response path is:

```text
Gateway → Conversation → AI → Conversation → Gateway → Provider
                 ↑                           │
                 └──── actual delivery outcome ┘
```

Conversation accepts inbound durably before AI, creates a managed AgentTurn with authorized context, receives a draft/outcome/operation references, and decides whether dispatch is still authorized. Gateway performs network delivery and reports the actual outcome. Control-plane and CRM are not conversation-history owners.

## Terminology and foundation contracts

| Concept | Meaning and boundary |
| --- | --- |
| **Conversation** | Provider-neutral communication thread. Trusted identity includes at least tenant/owner, integration, channel and provider thread/external communication identity. It is neither AI session nor CRM Inquiry; exact schema is deferred. |
| **Message** | Normalized user/agent/human communication unit. Internal tool calls are not Messages. A generated LLM draft does not automatically become a delivered outbound Message. |
| **AgentTurn** | Internal AI execution linking input Message IDs, stable processing identity, input/context revision, draft, operation references and processing outcome. It can finish with no delivered outbound Message. Retry retains the same processing identity. |
| **DeliveryAttempt** | Fact of an attempted provider dispatch, separate from generation. Distinguish generated, dispatch requested, provider accepted, delivered, read, failed, unknown and partial/interrupted; represent only states the provider can support with evidence. |
| **Inbound Event** | Durable accepted provider event with trusted provider namespace, provider event identity, payload hash, deduplication and ordering evidence. Changed payload under the same identity is a conflict. |
| **Control Mode / Authority** | Conversation owns who may initiate outbound. Illustrative modes are `AGENT`, `HUMAN_PENDING`, `HUMAN`; the detailed state machine is deferred. AI and human must not have simultaneous authority. |
| **Handoff** | Platform workflow owned by Conversation. AI can request it; Conversation controls the workflow and authority; Gateway later executes channel actions. CRM can receive an optional Inquiry/case projection. |
| **Call** | Voice metadata linked to Conversation: start/end, direction, outcome, caller/callee, provider IDs, recording artifact reference and transcript/speech segment references. |

Conversation stores trusted integration/routing references, not gateway/provider credentials. Control-plane retains encrypted integration credentials and binding authority. The future managed AI contract must carry trusted context and stable Turn identity, and return draft, execution outcome and operation references without claiming provider delivery.

## Responsibility map

“Current” is the representative inspected Telegram, Instagram and Website Widget source path above; absence means no shared platform owner identified in that path. WhatsApp compatibility remains unresolved as described above. Voice donor capabilities are not current Main capabilities.

| Responsibility | Current | Target |
| --- | --- | --- |
| Integration resolution | Control-plane binding; gateways poll/validate | Control-plane owns lifecycle, encrypted credentials, tenant/owner/agent/integration binding and routing; Conversation consumes trusted references |
| Provider protocol / validation | Channel Gateway | Channel Gateway: webhook/polling/connection, provider validation, inbound normalization and outbound formatting |
| Inbound event journal / dedup | Gateway-specific intake; no shared durable journal | Conversation: durable event identity, payload-conflict detection, dedup and ordering evidence |
| Conversation | AI `ConversationSession` context identity; no provider-neutral owner | Conversation: canonical thread and trusted identity |
| Message | Gateway text and Redis user/assistant entries | Conversation: canonical communication units distinct from drafts and tool calls |
| AgentTurn | Independent AI request execution | Conversation coordinates managed execution; AI owns reasoning/execution diagnostics |
| Debounce / burst aggregation | No shared authoritative policy in inspected path | Conversation policy over final Messages; [AI #18](https://github.com/chotabyorg/ai-agent-service/issues/18) is a narrow dependent slice |
| Queue / serialization / supersede | Independent gateway calls; no shared durable queue | Conversation: one active Turn, durable pending inputs, revision checks, recovery and supersede |
| AI reasoning / prompts / agent config | ai-agent-service | ai-agent-service |
| KB / RAG | AI retrieval with knowledge/RAG services | AI composes/retrieves context; knowledge/RAG services retain their responsibilities |
| Tool selection / business authorization | AI / MCP tool execution | AI business runtime: intent, permission, confirmation and tool selection |
| Business receipts / recovery | AI Business V2 is part of the current Main baseline; early draft evidence below is historical | AI business runtime owns operation reservation, idempotency, receipts and UNKNOWN recovery; Conversation stores opaque operation references, never a second ledger |
| Provider delivery | Gateway sends after AI answer; no shared delivery journal | Gateway performs network delivery and reports outcome; Conversation owns DeliveryAttempt records and dispatch authority |
| Handoff / operator authority | No shared owner in inspected path | Conversation workflow/control authority; AI requests, Gateway performs channel actions |
| CRM projection | Separate business product/integration | Optional consumer: Inquiry/case, summary, status, known customer reference and Conversation link/ID |
| Voice / acoustic turn coordination | No clean Main Voice Gateway in this path | New clean `voice-gateway-service`: provider/media, STT/TTS, VAD, final utterances, playback and barge-in |
| Call metadata | No shared provider-neutral Call owner | Conversation owns linked Call lifecycle/metadata; Voice reports facts and references |
| Recordings | Not established as Main communication storage by this ADR | Voice may have bounded temporary spool; Conversation stores artifact references. Production artifact storage, retention and access are deferred |

Gateways do not own canonical history, cross-request AI queues, authoritative debounce, operator authority or a business-operation ledger. AI remains owner of agent configuration, prompt composition, LLM reasoning, retrieval, tool selection, business runtime/authorization, receipts/recovery and execution diagnostics; it does not become the authoritative communications-history owner.

## Architecture invariants

1. Only one active AgentTurn exists per Conversation.
2. An inbound event/Message is accepted durably **before** AI starts.
3. A duplicate provider event creates no second Message.
4. Reusing a provider event ID with a different payload is a conflict, never silently accepted as a duplicate.
5. Retrying one processing Turn preserves stable Turn identity.
6. Message and AgentTurn are different entities.
7. Draft generation and actual provider delivery are different facts.
8. A successful LLM response alone never establishes delivery.
9. Gateway reports the actual provider delivery outcome to Conversation.
10. Superseding/canceling a Turn does not automatically undo completed business effects.
11. Completed business effects remain available to the next Turn.
12. An UNKNOWN business effect must not be blindly repeated.
13. Conversation does not duplicate the BusinessOperation/receipt ledger.
14. Redis loss must not destroy authoritative history, queue or handoff; Redis is cache/acceleration only.
15. AI and a human operator must not simultaneously hold outbound authority for one Conversation.
16. A single dispatch path checks outbound authority.
17. Provider/network UNKNOWN is not guaranteed failure and must not trigger blind retry.
18. Conversation stores trusted integration/routing references; gateway/provider credentials remain outside it.
19. Automatic cross-channel customer merging is outside this foundation.
20. CRM is an optional consumer, not a mandatory dependency of communications runtime.

## Concurrent inbound, supersede and bounded settling

```text
Message A durably accepted → Turn A ACTIVE
Message B accepted while A runs → B durable → input revision changes
Turn A finishes → draft + operation references persisted
Before dispatch → check input revision + control mode + dispatch authority
                → send if still authorized, or SUPERSEDED / NOT_DELIVERED
```

Supersede suppresses an obsolete draft according to policy; it is not rollback of completed tools. An already delivered answer cannot later be relabeled `NOT_DELIVERED`. Cancellation depends on execution stage. A continuous inbound stream must not starve processing: settling/debounce has a bounded maximum wait. The exact timeouts and stage-specific cancellation policy are deferred.

[AI #18](https://github.com/chotabyorg/ai-agent-service/issues/18) covers only configurable settling/burst aggregation: reset the window on new inbound, impose bounded maximum waiting, preserve Message ordering, support channel/cohort policy, and form one AgentTurn input from a burst such as “Здравствуйте” / “Хочу записаться” / “на завтра”. It must not recreate the foundation's durable queue, single-active-Turn, concurrency, supersede or dispatch-authority architecture, or add independent gateway debounce implementations. There is no universal five-second timeout.

Voice acoustic TurnCoordinator handles `audio / STT partial / VAD → final utterance`. Platform settling starts with canonical/final inbound Messages and does not coordinate audio frames or partial transcripts.

## Business V2 boundary

| Conversation coordination | AI business-operation coordination |
| --- | --- |
| Which Messages belong to a Turn; when AI starts; serialization; supersede; delivery/human authority | Business intent; permission; confirmation; operation reservation; provider-mutation receipt; UNKNOWN recovery; business idempotency |

Do not create another BusinessOperation ledger in Conversation. Keep completed operation references/outcomes available after supersede so the next Turn can use authoritative receipts. Cancellation of communication work cannot erase completed effects. UNKNOWN reconciliation belongs to business runtime; the next Turn must not blindly create a new operation.

The current AI baseline has Business V2 and the accepted managed execution/evidence interfaces. Goal3 preserves frozen actions, stable BusinessOperation identity, durable receipts, `UNKNOWN != FAILED`, scoped confirmation and no blind mutation retry. Conversation carries opaque `operation_refs`; it neither replays an ambiguous AI dispatch nor reconciles providers. Goal4A must preserve the current AI image, Business settings, TLS/signing sidecar and migration/backfill hooks. Early PR #43 discovery remains historical evidence only.

## Handoff, CRM and Voice

Conversation owns handoff and control authority. AI may request handoff; a single dispatch path must enforce the current mode for AI and human outbound. CRM may consume `Handoff → Inquiry/case → summary + status + known customer reference + Conversation link/ID`. Communications must continue without CRM.

Main Voice will use a new clean **`voice-gateway-service`**:

```text
PBX/audio → Voice Gateway → Conversation → AI
                                            │
playback ← Voice Gateway ← Conversation ←───┘
```

Voice owns provider/PBX media integration, SIP/RTP/Asterisk/AudioSocket where required, STT, TTS, VAD/end-of-speech, acoustic TurnCoordinator, playback, barge-in, call execution and bounded temporary recording spool. Conversation owns communication authority and linked Call metadata; AI retains reasoning/business work.

[`chotabyorg/chota-va`](https://github.com/chotabyorg/chota-va) remains a separate standalone product/reference/donor. Do not refactor it into Main Voice or transfer its local LLM, local RAG, Bitrix business logic, ToolAgent, standalone scenarios, authoritative history, standalone `human_tasks`, standalone analytics or campaigns into the inbound MVP. No Voice implementation is performed by this ADR.

## Migration order and rollout boundary

1. Goal0 architecture/ownership foundation — complete.
2. Goal1 thin Conversation durable journal and contracts — source complete, unconsumed in production.
3. Goal2 managed AI v1 contract carrying stable Turn identity and authorized context — source complete.
4. Goal3 Business receipt/evidence compatibility, retaining AI ownership — source complete.
5. Goal4A first private Conversation production deployment plus one exact Website integration's dedicated technical session — current stage; ordinary demo and every other Website integration retain legacy. Production cohorts remain empty until separate binding, logging and no-business smoke gates pass.
6. Goal4B one explicitly selected Telegram canary using the proven production infrastructure — next; no Telegram migration in Goal4A.
7. Goal5 advanced settling/debounce/grouping/supersede/fencing policy — later; Goal4 parity is one accepted inbound Message per logical Turn with a durable serial queue.
8. Remaining text channels, including Instagram and compatible WhatsApp, after their own reviewed cutovers.
9. Platform handoff/operator authority and optional CRM projection.
10. Clean Voice Gateway foundation.
11. Voice integration.
12. Production recordings decisions and later legacy retirement.

Website cohort admission and rollback have one durable routing authority: Conversation atomically reserves LEGACY or commits MANAGED admission plus inbound Message under the stable client `message_id`. A retained disposition cannot change on cohort rollback. The trusted integration guard survives cohort disable/removal; identified guarded traffic fails closed if Conversation is unavailable. Retain API/worker/DB, exact scopes/grants and compatible images. Already accepted managed messages are never replayed through legacy AI. There is no database downgrade or pre-sticky gateway image rollback.

Goal4A uses `SESSION_ALLOWLIST` for exactly one technical session only. Source supports bounded `INTEGRATION_ALL` as a future capability, but no Goal4A production stage may activate it. Future full demo cutover requires stable per-message IDs in the real widget, explicit review/approval, and a separate assistant-history/context-limit policy review: current managed history is inbound-only and does not establish full conversation parity. See [release and rollback](../services/conversation-service/RELEASE.md).

## Non-goals and next stage

Automatic cross-channel identity merging, full contact center, campaigns, live Voice transfer, production recordings, advanced debounce/settling/supersede, human Inbox/handoff, CRM/provider configuration and backup/HA/DR remain outside Goal4A. This ADR itself applies no manifest or traffic change.

**Current stage: Goal4A — Website technical managed canary and first Main Conversation production rollout. Next: Goal4B — Telegram managed canary, parity-first, after the actual Goal4A production infrastructure and evidence gates pass.** Foundation and Goal4B are not complete.

## Evidence and backlog

The table below records historical architecture discovery, not the current deployment or Goal4A candidate. Source evidence must remain pinned; actual live status requires refreshed Main-cluster and pod evidence. See the [Goal4A release record](../services/conversation-service/RELEASE.md) and existing [internal AI chat boundary](internal-agent-chat-s2s-boundary.md).

AI, Telegram and control-plane default-branch revisions were reconfirmed on 2026-10-05. Instagram, Website and WhatsApp evidence uses the correction audit's pinned source snapshots; their latest default-branch revisions were not rechecked for this ADR. The concurrency risk is an inference from the inspected unsynchronized history read/whole-list write, not a claimed observed production incident.

| Main repository / inspected revision | Source evidence and compatibility limits |
| --- | --- |
| ai-agent-service — `3eafb97726fd33e614e443bbac5c10f9fce72a81` | [Session model](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/models/session.py#L13-L38), [session identity lookup](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/session_service.py#L33-L59), [load/generate/save-before-return flow](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/llm_service.py#L340-L470), [Redis whole-history GET/SET with TTL](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/history_service.py#L49-L78) |
| telegram-gateway-service — `591d713302f06dd15fd583db1ca5629b240b4bf7` | [Direct AI request and external identity](https://github.com/chotabyorg/telegram-gateway-service/blob/591d713302f06dd15fd583db1ca5629b240b4bf7/services/core_api.py#L22-L34), [provider send after AI returns](https://github.com/chotabyorg/telegram-gateway-service/blob/591d713302f06dd15fd583db1ca5629b240b4bf7/bot/handlers.py#L27-L34) |
| control-plane-service — `96a4b40daeb113f435f5cd02a6f7a2fc12502b24` | [ChannelType enum without WhatsApp](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/models/integration.py#L14-L18), [integration binding](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/models/integration.py#L27-L47), [authenticated internal route](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/api/routes/internal.py#L18-L30), [trusted integration/owner/agent and credential response](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/services/integration_service.py#L135-L156) |
| instagram-gateway-service — `f366b46cee2c4e845da150f81df573af467503b6` | [Direct AI request](https://github.com/chotabyorg/instagram-gateway-service/blob/f366b46cee2c4e845da150f81df573af467503b6/services/core_api.py), [in-memory dedup and provider send](https://github.com/chotabyorg/instagram-gateway-service/blob/f366b46cee2c4e845da150f81df573af467503b6/bot/worker.py) |
| website-gateway-service — `fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b` | [Direct AI request](https://github.com/chotabyorg/website-gateway-service/blob/fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b/services/core_api.py), [validated widget request and HTTP reply](https://github.com/chotabyorg/website-gateway-service/blob/fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b/api/handlers.py) |
| whatsapp-gateway-service — `ac47fea4a5c630622cee218747c0f0b9ec551d69` | [MVP scope](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/README.md#L1-L5), [expected WHATSAPP polling contract](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/services/control_plane_client.py#L31-L39), [direct AI request](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/services/core_api.py), [in-memory dedup, scoped external identity and provider send](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/bot/worker.py). End-to-end compatibility is unresolved against the pinned control-plane enum. |

The foundation remains the Project #3 umbrella **`[HOT] Main Chota Conversation foundation: durable messages, turn coordination and delivery authority`**. [GitOps #111](https://github.com/chotabyorg/gitops/issues/111) tracks Goal4A production configuration; it does not complete Foundation or Goal4B. Preserve the existing initiative links and historical discovery evidence rather than creating a duplicate Foundation epic.

- [EPIC — Conversations / Inbox / Handoff](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891847) and [Discovery — Conversation workspace & handoff plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892197).
- [EPIC — Voice / Calls](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891834) and [Discovery — Voice product & implementation plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892126): depend on the Conversation foundation for canonical lifecycle/authority; acoustic decisions remain Voice-specific.
- [EPIC — Business Capabilities & MCP 2.0](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891840) and [Discovery — Business capabilities & MCP 2.0 plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892193): retain separate business-operation ownership.
- [AI #18](https://github.com/chotabyorg/ai-agent-service/issues/18): dependent settling slice; [AI PR #43](https://github.com/chotabyorg/ai-agent-service/pull/43): historical receipt compatibility input. Current Goal4A uses the preserved AI `4fa1759` Business baseline. Discovery, accepted direction and backlog are not deployment evidence.
