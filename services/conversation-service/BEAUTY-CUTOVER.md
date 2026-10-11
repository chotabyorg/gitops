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
