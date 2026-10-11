# Beauty demo staged cutover

Stage 1 installs only the dedicated permanent managed principal in normal production
AI. Exact scope: owner `dc3dd7eb-536f-45d4-84f2-c8d35575d928`, integration
`8d4a1b73-7973-4dcc-a3d4-1312d871c1d4`, agent
`0b750714-af8d-4d8c-8fdc-4ddfeda98af9`, channel `WEBSITE_WIDGET`, execution namespace
`main-chota.conversation.v1`. CP integration authority and its AI ownership check,
plus the owner's normal product session, independently verified the relation.

The new credential is random and dedicated to this relation. Only strict-scoped
SealedSecret ciphertext is committed. The old retained credentials and Website
binding are preserved. Business V2 stays enabled; normal AI images, CRM trust,
other channels, database state, and public endpoints are unchanged.

During stage 1 Conversation bindings remain empty, its worker remains disabled
with zero replicas, and Website cohorts remain empty. Principal installation
alone grants no managed Website admission. Observe Argo reconciliation, effective
principal scope and AI health before preparing the separately reviewed Conversation
binding. Later gates are worker readiness, one-session real-model Business canary,
independent canary acceptance, exact integration-wide admission, and public HTML.

Rollback after any managed traffic: stop only NEW exact integration admissions;
keep principal, bindings, worker and retained evidence for pending/replay work.
Never replay retained managed input through legacy. Business's kill switch is
`BUSINESS_CAPABILITIES_ENABLED=false`; it preserves operation/receipt evidence.
No destructive database rollback or downgrade is permitted.

Public demo HTML is deployed separately from `chotabyorg/demo-site` using a reviewed
immutable ConfigMap/Pod and a Service selector change with resourceVersion and
full-selector preconditions. Its immediate rollback target is the current
`default/demo-catalog-7efb04733203`, which must remain available during acceptance.

This source document records the candidate's intent, not runtime acceptance.

## Stage 2: permanent binding, worker and admissions still dark

The Conversation API and worker now reference `conversation-beauty-managed-secret`
instead of the explicit empty binding overrides. This is the exact matching
owner/integration/channel/agent binding, using the same dedicated credential as
stage 1. `MANAGED_AI_BASE_URL=http://ai-agent-service:8000` selects ordinary production
AI. The historical sealed binding is retained but is not the active credential.

The worker remains `WEBSITE_WORKER_ENABLED=false`, replicas=0, and Website cohorts
remain empty. No new admission is enabled. Before merging, require independent
runtime confirmation of stage 1's effective principal and independent review of
this exact stage 2 render. After Argo sync, verify exact binding/principal pairing,
normal AI reachability, API readiness, unchanged retained queue, and all dark controls.
Worker activation is a later independently reviewed candidate; this binding change
does not approve it.

## Stage 3: one permanent worker, new admissions remain dark

Set only the worker-specific `WEBSITE_WORKER_ENABLED=true` and its replicas to 1.
The API's worker flag remains false because it does not run the worker process.
The worker's exact PROCESSING principal and permanent managed binding are retained.
No Website cohort changes accompany this stage. Before merge require stage 2's
independent live binding/token-pair/normal-AI verification and a fresh check that no
retained work can cause an unexpected business dispatch: require zero MANAGED
admissions without a WebsiteImmediateTurn mapping (checked by an anti-join), zero
PENDING/CLAIMED Turns, zero managed dispatches in flight, and zero unfinished
Business operations in the exact target scope. Aggregate admission/Turn counts
alone are insufficient.

After Argo sync, inspect the actual worker `/health` and `/ready`, schema head
`0004_website_history`, poll heartbeat, exact processing scope and managed binding,
normal AI reachability and CRM-only-through-AI network policy. Recheck the queue and
Business ledger. Only a separately reviewed one-session cohort may then admit
synthetic real-model Business QA. Integration-wide/public traffic remains prohibited.
