# Goal 4A Main production release gates

**Dark storage forward-fix candidate; no repaired release approved.** Reviewed source
PRs and the initial dark GitOps PR #112 have merged. Native verification of Main
revision `f30e256493cc644c6e8e755446aaf121db248fb1` found PostgreSQL on a CRI image
volume shadowing its PVC, despite healthy probes and schema. All nine journal
tables were empty and admission was disabled. [STORAGE-FIX.md](STORAGE-FIX.md)
records the minimal candidate, fresh zero-data pre-merge condition and independent
post-fix persistence gate. Fresh complete source and exact-release CLEAN are
required before this separate fix merges. The reviewed v2 architecture
does not authorize real widget credential use, production canary or Business-provider smoke.
[GitOps #111](https://github.com/chotabyorg/gitops/issues/111),
[Control Plane #21](https://github.com/chotabyorg/control-plane-service/issues/21)
and the [Main ADR](../../docs/main-chota-conversation-foundation.md) retain the
Website-first Goal 4A and subsequent Goal 4B boundary. Foundation is unfinished.

## Recorded Main baseline

The historical pre-rollout read-only 2026-10-08 baseline identifies Main `chota.by`, node 153.80.244.178,
context `default`, prod UID `84409e45-1c54-4893-bf30-d353a55acb47` and kube-system
UID `a90ac8e6-6a20-46d2-8af8-ee4580edeaa0`. Refresh these immediately before any
mutation; this document does not prove a future shell/context. Never use the
separate Voice server/cluster.

| Component | Source / recorded runtime provenance | Goal 4A status |
| --- | --- | --- |
| Conversation | source `d238064215d3875c5d2061bba5a00b55dc5fad0e`; absent in prod | source candidate, release image/seals pending |
| Website | source/tag `fda632c0f694ae1b5ffc74ce4abd92d87ebeb04b` / `fda632c`; pod digest `sha256:78967f3d40b9c505bec7650b2a01a800d3ce40aa8786dd49d21f9a7df3ad80e7` | replacement logging/sticky-routing image requires review |
| AI | source/tag `4fa17597b8083d2e09428c9c1ac949aa42f5990d` / `4fa1759`; pod digest `sha256:5eba680cf018acf0f8062bbc1b0909e8c09ff157795e5a7f79ac4232a863ef4c` | preserve current Business V2 baseline; separate managed registry only |
| Control Plane | source `96a4b40daeb113f435f5cd02a6f7a2fc12502b24`; digest `sha256:1979950cebd0bd20a26ff96e9284f3e3252d2c7ce6b253f75f8f1aa0af857e9a` | actual PID1 lacks access suppression; reviewed source error-boundary image plus `--no-access-log` required |
| GitOps / Argo | `72438529a6db91ce2595f2f31353c745eddb334c`; AI/Website/CP Applications Synced/Healthy at observation | candidate branch is separate; no desired/live change claimed |

Actual live prod-services discovers `services/*/prod` except payment, with
automated enabled/prune/selfHeal and CreateNamespace. The source ApplicationSet
is reconciled to exactly that observed spec; no discovery expansion is introduced
and it must never be applied manually. A new discoverable directory on main is a
deployment action. Website's reviewed workflow now stages only on its isolated
release branch; Conversation's publisher is manual/build-only. Do not invoke reusable
deploy expecting it to publish without changing the selected GitOps branch.

## Concrete candidate-image flow

The existing reusable workflow checks out the selected `gitops_branch` (default
main), writes `newTag`, also writes the new build `digest` when that field exists,
and pushes the branch. Adding a digest pin to Website does **not** contain its
main-merge promotion. A reviewed source SHA cannot stand in for the digest of a
future CI build, and an already-reviewed local image does not approve a later
unobserved replacement build.

Before Website source main merge, independently review the narrow service-owned
workflow change `gitops_branch: releases/website-gateway-service`, matching the
existing Control Plane `releases/control-plane-service` pattern. Keep the shared
reusable workflow unchanged. Create that GitOps release branch if absent, or
inspect and advance an existing one without discarding other work; it must contain
the current valid Website prod overlay before CI runs. Source merge then publishes
the image and writes only the isolated release branch. Read the completed CI run,
full source SHA, actual published GHCR digest/OCI provenance and Main-node platform;
verify the resulting candidate. A separate exact-candidate GitOps PR copies only
the reviewed image reference and required reviewed config/patch/seal changes into
main after CLEAN release review. Do not merge the whole release branch blindly or
assume separate Application wave ordering. Control Plane already uses its own
release branch; promote its actual reviewed privacy image by the same explicit
GitOps gate.

Conversation initial source uses a manually dispatched **build-only** publisher,
with no GitOps PAT/check-out/write/deploy step and no automatic main promotion.
Dispatch the reviewed immutable source ref, build the verified Dockerfile, publish
the full source-SHA tag and record the actual returned registry digest before
materialization/release review. An operator may instead build/push that exact
reviewed worktree with the same Dockerfile and platform through a separately
authorized publisher; it still must record real digest/provenance and test the
actual artifact. Neither option invokes reusable-deploy. If publication cannot be
performed independently of promotion, image readiness remains blocked.

A direct build-only Website branch image is another possible candidate input,
but it does not make a later automatic Website main merge safe. That merge must
still be contained by a separately reviewed service-workflow gate, or remain
unmerged. No future CI digest, main merge, registry write or production action is
authorized by this source staging document.

## Materialized dark artifacts

`services/conversation-service/prod` is materialized from unchanged `release/dark`
properties and migration wrapper. It pins Conversation source merge
`506f3edd7ef26f12f9433fc9f2917c12e7c22453` at OCI index
`sha256:fa63a329173e4400985ae87d5896ab3effd45f0f7040adb4849b5d3f9ccdfe63`
and PostgreSQL `16.15-alpine` at
`sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea`.
Both have a linux/amd64 manifest matching Main. The Conversation merge tree is
identical to independently reviewed `a47cd733867c7479a4f353d84bff062a244eb713`.
Manual build-only publisher run `37842445696` succeeded. Published artifact checks
and the initial exact release review passed before PR #112 merged; they did not
establish native PVC durability. The repaired candidate retains both image pins.

Three actual strict `prod/<name>` Conversation seals passed the existing Main
controller's read-only `/v1/verify`; changed-name ciphertext was rejected, and
Secret resource names remained unchanged. The matching kubeseal 0.36.6 archive and
checksums passed publisher signature verification before execution. Controller
runtime version 0.36.6 and digest were observed on the verified Main node. Values
were generated and matched in memory, with no plaintext file or token output.
Website/AI matching seals are privately staged for a later separate release and
are absent from this dark production overlay. Schema fixtures were never inputs.
Do not regenerate the database password during redeploy: retain these credentials.

Initial state remains API replicas 1, PostgreSQL replicas 1, worker replicas 0,
`WEBSITE_BINDINGS=[]` and all worker flags false. Existing Website, AI and CP prod
overlays are unchanged. Missing Website cohort/guard settings mean legacy default
only during this dark phase; later stages require explicit exact configuration.
The separate dark validator staging finding was fixed in a fresh context, with
six offline tests and retained synthetic-seal/public-exposure negative checks;
a fresh complete GitOps and exact-release review was performed before dark merge.
The subsequent native storage Important finding invalidates progression until
this separate forward fix, another complete review and actual persistence proof.

All five dedicated credential names and key schemas are in [README](README.md).
SealedSecret metadata and Secret template must retain strict scope `prod/<name>`,
wave −2 and `Prune=false,Delete=false`. Do not replace `ai-agent-secret`, Website's
existing secret, CP credentials, signing/TLS seals or unrelated tokens. For AI
add only `release/ai/deployment-patch.yaml.template` plus its separate real seal to
the existing overlay; preserve image and every resource/hook. Assess the current
AI PostSync MCP credential backfill Job on the exact rendered candidate before
sync; do not remove or redesign it to avoid a gate.

## Candidate routing identities and blocked gates

The non-secret candidate is integration `8d4a1b73-7973-4dcc-a3d4-1312d871c1d4`,
owner `dc3dd7eb-536f-45d4-84f2-c8d35575d928`, expected agent
`0b750714-af8d-4d8c-8fdc-4ddfeda98af9`, dedicated technical session
`5074470b-e568-4828-be24-f7c815c6bf16`. `routing-candidate.json` explicitly records
`credential_binding_verified=false`, `smoke_safety_approved=false`. These are not
verified user-key bindings or an approval record.

Before supported real-key resolution, independently reviewed credential-safe
Website/CP/Conversation logging must be deployed in every relevant ready pod and
proved with distinct fake query/header/config/proof sentinels through normal,
failure, DEBUG, descendant logger, reconfiguration and actual server/process
paths. CP source DTO/error protection and actual `--no-access-log` are both
required. Every credential-observing proxy must satisfy the same gate. Do not
inspect/print matching raw production log lines. Output only safe counters and
boolean assertions. Only then resolve the real key privately and assert the exact
trusted active WEBSITE_WIDGET owner/integration/agent binding without exposing it.

The demo agent currently exposes 16 active CRM capabilities including writes.
A harmless prompt cannot prove no provider mutation. No-business smoke safety
remains unresolved; no canary admission, real AI/provider smoke, Business
capability disabling, CRM rebinding or alternate agent/topology is authorized by
this source candidate. A different safe topology needs explicit human approval
and a new cross-track design/release review.

## Declarative stages and abort points

1. Complete isolated source branches, baseline/regression/real-PG A–H and
   concurrency proof, migration empty→head and populated upgrade, Docker
   hardened lifecycle and fresh independent source reviews. Every accepted
   Important finding requires separate fix and new complete review.
2. Publish the exact reviewed Conversation image through a manual build-only
   publisher. Collect immutable provenance and real seals. Materialize a complete
   dark prod overlay before any main merge; fixtures/templates are release blockers.
3. Fresh exact-candidate release review records source SHAs, image digests,
   complete GitOps diff, secret names, migration head `0003_website_canary`, current
   Main identity, routing/gates and rollback. Require CLEAN before dark merge.
4. Argo deploys dark API+PG only: API replicas 1, worker replicas 0, shared
   `WEBSITE_BINDINGS=[]`, API+worker worker flagsfalse; Website guards/cohorts `{}`.
   Website routing fields may still be absent in its existing prod config; only
   dark validation treats those omissions as empty legacy defaults. Later stages
   require both explicit fields, and nonempty dark routing always blocks release.
   Observe Synced/Healthy, actual images, PVC, PG/schema/API readiness, endpoints,
   private exposure and effective approved/unauthorized-caller policy enforcement.
   Stop here on failure; no CNI/controller infrastructure change is in scope.
   The initial rollout failed the native storage gate. Before this storage fix
   merges, independently refresh the full public-table census and disabled
   admission state. Continue only with migration metadata and zero domain rows.
   The PVC mount changes at PostgreSQL wave 0; API template annotation changes at
   wave 1, causing Recreate and the existing serialized init migration against the
   now-persistent database. Do not manually restart/migrate/copy/delete data. All
   next stages remain held until fresh native verification proves the PVC mapping
   and the same database across a separately reviewed GitOps pod recreation.
5. Add separate exact AI registry and Website S2S keyRef/seals through reviewed
   GitOps changes. Preserve all existing AI Business/image/hook state. Deploy the
   reviewed default-legacy Website and CP privacy candidates, keeping empty guards
   and cohorts. Observe every actual ready process and sentinel proof before key use.
6. After privately verified key binding, merge the retained exact Website guard,
   Conversation `WEBSITE_BINDINGS` and exact grants/bindings, with cohorts still `{}`.
   Worker remains disabled during binding activation. New identified guarded
   messages reserve LEGACY atomically; CS failure is 503. No AI smoke is implied.
7. Independently reviewed worker enable adds replicas 1 and sets
   `WEBSITE_WORKER_ENABLED=true` only in worker.properties. API flag stays false.
   Observe worker exact-head/scope/heartbeat readiness. Keep cohorts `{}` while the
   no-business gate is unresolved; retained managed work remains recoverable.
8. Only after all separate approvals and a fresh release gate, merge the one
   `SESSION_ALLOWLIST` entry in `technical-session.properties.template`. Validate
   exactly one integration/session, no INTEGRATION_ALL, no wildcard or unrelated
   guard/scope. Ordinary demo and all other integration sessions remain legacy.
9. Bounded approved public canary, exact retry, changed-content conflict, new-ID
   identical text, legacy isolation and retained result replay after one API/worker
   restart. Restart is a GitOps pod-template annotation on each Deployment, never
   manual rollout drift; PVC/DB is untouched. Mid-dispatch A–H failures use fake
   provider real-process infrastructure, not live Business ambiguity.
10. Fresh independent production verifier distinguishes source, reviewed
    candidate, Git main desired, Argo revision and actual runtime. PASS requires
    all user gates and evidence. Handoff then stop; no Goal 4B work here.

## Feature rollback

Prepare and review the exact rollback before smoke. Edit only Website production
`MANAGED_WEBSITE_COHORTS={}` through GitOps, using
`release/activation/rollback-website.properties.template`. Remove the technical
cohort/session; **retain MANAGED_WEBSITE_GUARDED_INTEGRATIONS**, compatible sticky
Website image, Conversation API/worker/PG/PVC, exact `WEBSITE_BINDINGS`, principals,
managed-AI bindings/registry, scopes, guards, network isolation and images. Observe
the new Argo revision and ready gateway pods, and prove new IDs reserve LEGACY
while already accepted IDs retain managed disposition/result with zero AI repeat.

**Already accepted managed messages are never replayed through legacy AI.**
Uncertain CS admission/result returns retryable failure. Do not remove the service
directory, guard, journal/DB or grants, downgrade schema, rotate secrets, or revert
to a gateway image predating durable sticky routing. If execution needs temporary
containment, worker can be paused by separately reviewed declarative replicas 0;
do not confuse that with feature rollback or delete recoverable accepted work.

## Business-track handoff and next stage

Goal 4A ordinary demo stays legacy. Future full demo cutover requires actual widget
UUID `message_id` generated once per message and retained on every retry, valid
session UUID, verified bindings, separate explicit release approval and reviewed
assistant-history/context-limit policy. Current managed context is inbound-only;
local HTTP WRITE_COMPLETED never establishes browser acknowledgement or a delivered
assistant Message. Configuration-only expansion cannot supply conversational parity.
Source supports bounded exact-integration INTEGRATION_ALL for that later reviewed
handoff, but Goal 4A validation rejects its production use. The worker processing
scope remains generic exact integration/agent and does not hardcode the canary
session.

Next is **Goal 4B — Telegram managed canary using verified live Conversation
infrastructure, parity-first without advanced debounce/supersede**. Neither that
stage nor Foundation is completed by this source candidate.
