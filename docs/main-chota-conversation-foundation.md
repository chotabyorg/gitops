# Main Chota Conversation Foundation

## Status and scope

**Accepted direction; implementation pending.** This ADR defines Main Chota Platform communication ownership and the next implementation boundaries. It creates no runtime capability, repository, schema, deployment or production routing change.

Main planning belongs to [Project #3 — Chota Platform](https://github.com/orgs/chotabyorg/projects/3). [`chotabyorg/chota`](https://github.com/chotabyorg/chota) / [Project #6 — Chota 2.0](https://github.com/orgs/chotabyorg/projects/6) are a separate, paused fashion/e-commerce product. Their code, E0/E1/E4, Conversation Core, issues and roadmap were **not used as Main architecture evidence**.

The current-flow statements below describe inspected Main source revisions, not verified live runtime. GitOps expresses desired state; its default branch does not prove a running service revision. [Business V2 PR #43](https://github.com/chotabyorg/ai-agent-service/pull/43) is **draft/pending**, not an implemented or deployed platform dependency.

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

Introduce a small independent **`conversation-service` with PostgreSQL** as the authoritative owner of communication lifecycle. Redis may accelerate work, but must not own durable history, queue or handoff. Exact schemas, APIs and state-machine details remain future implementation decisions.

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
| Business receipts / recovery | Legacy tool execution; PR #43 draft/pending | AI business runtime owns operation reservation, idempotency, receipts and UNKNOWN recovery; no second ledger in Conversation |
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

[Business V2 PR #43](https://github.com/chotabyorg/ai-agent-service/pull/43) remains draft/pending. Its proposed receipt/recovery contract must be checked for compatibility before any future managed cohort rollout. Discovery or a draft PR does not establish implementation or deployment.

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

1. Thin Conversation foundation with PostgreSQL and contracts; no production traffic.
2. Managed AI contract carrying stable Turn identity and authorized context.
3. Business receipt/recovery compatibility, retaining AI ownership.
4. One explicitly selected Telegram integration cohort; other integrations retain their legacy path.
5. Turn coordination and bounded settling/debounce.
6. Remaining text channels, including Instagram, Website and WhatsApp.
7. Platform handoff/operator authority and optional CRM projection.
8. Clean Voice Gateway foundation.
9. Voice integration.
10. Production recordings decisions and later legacy retirement.

Future cohort enable/disable/drain and rollback must have one routing authority. An integration must never be processed by legacy and managed paths simultaneously. Retain accepted inbound and delivery evidence through restart/drain; recover stable processing/sending identities and reconcile UNKNOWN outcomes before retry. Tenant/integration identities must not collide. Non-migrated integrations preserve current behavior. Exact rollout controls and schema are future decisions.

## Non-goals and next stage

Automatic cross-channel identity merging, a full contact center, campaigns, live Voice transfer, production recordings, implementing debounce/queue/handoff/schema, creating `conversation-service`, merging Business V2 PR #43, runtime changes, image updates, migrations and deployment are outside this documentation decision.

**Next planned stage: Goal 1 — create thin `conversation-service` foundation with PostgreSQL and contracts, with zero production traffic routed through it.** This ADR does not start Goal 1.

## Evidence and backlog

Source evidence must be pinned to exact inspected revisions; live deployment was not verified. See the existing [internal AI chat boundary](internal-agent-chat-s2s-boundary.md) for authentication rollout scope, separate from Conversation ownership.

AI, Telegram and control-plane default-branch revisions were reconfirmed on 2026-10-05. Instagram, Website and WhatsApp evidence uses the correction audit's pinned source snapshots; their latest default-branch revisions were not rechecked for this ADR. The concurrency risk is an inference from the inspected unsynchronized history read/whole-list write, not a claimed observed production incident.

| Main repository / inspected revision | Source evidence and compatibility limits |
| --- | --- |
| ai-agent-service — `3eafb97726fd33e614e443bbac5c10f9fce72a81` | [Session model](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/models/session.py#L13-L38), [session identity lookup](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/session_service.py#L33-L59), [load/generate/save-before-return flow](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/llm_service.py#L340-L470), [Redis whole-history GET/SET with TTL](https://github.com/chotabyorg/ai-agent-service/blob/3eafb97726fd33e614e443bbac5c10f9fce72a81/services/history_service.py#L49-L78) |
| telegram-gateway-service — `591d713302f06dd15fd583db1ca5629b240b4bf7` | [Direct AI request and external identity](https://github.com/chotabyorg/telegram-gateway-service/blob/591d713302f06dd15fd583db1ca5629b240b4bf7/services/core_api.py#L22-L34), [provider send after AI returns](https://github.com/chotabyorg/telegram-gateway-service/blob/591d713302f06dd15fd583db1ca5629b240b4bf7/bot/handlers.py#L27-L34) |
| control-plane-service — `96a4b40daeb113f435f5cd02a6f7a2fc12502b24` | [ChannelType enum without WhatsApp](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/models/integration.py#L14-L18), [integration binding](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/models/integration.py#L27-L47), [authenticated internal route](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/api/routes/internal.py#L18-L30), [trusted integration/owner/agent and credential response](https://github.com/chotabyorg/control-plane-service/blob/96a4b40daeb113f435f5cd02a6f7a2fc12502b24/services/integration_service.py#L135-L156) |
| instagram-gateway-service — `f366b46cee2c4e845da150f81df573af467503b6` | [Direct AI request](https://github.com/chotabyorg/instagram-gateway-service/blob/f366b46cee2c4e845da150f81df573af467503b6/services/core_api.py), [in-memory dedup and provider send](https://github.com/chotabyorg/instagram-gateway-service/blob/f366b46cee2c4e845da150f81df573af467503b6/bot/worker.py) |
| website-gateway-service — `fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b` | [Direct AI request](https://github.com/chotabyorg/website-gateway-service/blob/fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b/services/core_api.py), [validated widget request and HTTP reply](https://github.com/chotabyorg/website-gateway-service/blob/fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b/api/handlers.py) |
| whatsapp-gateway-service — `ac47fea4a5c630622cee218747c0f0b9ec551d69` | [MVP scope](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/README.md#L1-L5), [expected WHATSAPP polling contract](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/services/control_plane_client.py#L31-L39), [direct AI request](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/services/core_api.py), [in-memory dedup, scoped external identity and provider send](https://github.com/chotabyorg/whatsapp-gateway-service/blob/ac47fea4a5c630622cee218747c0f0b9ec551d69/bot/worker.py). End-to-end compatibility is unresolved against the pinned control-plane enum. |

The foundation implementation belongs in Project #3 as **`[HOT] Main Chota Conversation foundation: durable messages, turn coordination and delivery authority`**, under the existing initiative rather than a duplicate epic. Keep future implementation in Backlog and link the item to this ADR, AI #18 and pending Business V2 PR #43.

- [EPIC — Conversations / Inbox / Handoff](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891847) and [Discovery — Conversation workspace & handoff plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892197).
- [EPIC — Voice / Calls](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891834) and [Discovery — Voice product & implementation plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892126): depend on the Conversation foundation for canonical lifecycle/authority; acoustic decisions remain Voice-specific.
- [EPIC — Business Capabilities & MCP 2.0](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255891840) and [Discovery — Business capabilities & MCP 2.0 plan](https://github.com/orgs/chotabyorg/projects/3/views/1?pane=issue&itemId=255892193): retain separate business-operation ownership.
- [AI #18](https://github.com/chotabyorg/ai-agent-service/issues/18): dependent settling slice; [AI PR #43](https://github.com/chotabyorg/ai-agent-service/pull/43): draft/pending receipt compatibility input. Discovery, accepted direction and backlog are not implementation/deployment evidence.
