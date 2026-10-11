# Goal 4A Main production release record

**Current final state — Goal4A PASS (2026-10-10).** Goal4A is complete. The
Conversation PostgreSQL storage persistence fix is in place, and the temporary
Goal4A AI canary runtime and its role lifecycle have been removed. The generic
Conversation NetworkPolicies permit the normal `ai-agent-service` API on port
8000; managed execution remains disabled.

Production remains dark for managed execution: the worker has zero replicas,
`WEBSITE_WORKER_ENABLED=false`, API and worker `MANAGED_AI_BINDINGS=[]`, and
`MANAGED_WEBSITE_COHORTS={}`. All new Website traffic is LEGACY. Retain the
Website admissions, integration guard/S2S configuration, and exact Conversation
`WEBSITE_BINDINGS`; these preserve sticky routing and accepted work and must not
be deleted as cleanup debris. Do not create a permanent managed AI
principal/binding here. Goal4B has not started.

The detailed candidate, gate, and stage records below preserve the rollout
history. Their pre-completion status statements are historical; the current
production state is the one stated above. This follow-up does not repeat the
Goal4A rollout or smoke.
[GitOps #111](https://github.com/chotabyorg/gitops/issues/111),
[Control Plane #21](https://github.com/chotabyorg/control-plane-service/issues/21)
and the [Main ADR](../../docs/main-chota-conversation-foundation.md) retain the
Website-first Goal 4A and subsequent Goal 4B boundary. Foundation is unfinished.

## Goal4A.1 reviewed release candidate (2026-10-10)

This is a materialized source/artifact candidate on the separate GitOps release
branch. It does not claim the subsequent GitOps promotion, Main migration or
runtime readiness, real-model smoke, final Goal4A.1 acceptance or managed Website
activation. The Goal4A production state above remains the observed baseline until
those later gates are independently completed.

AI dual-reader support was released first through [AI PR #49](https://github.com/chotabyorg/ai-agent-service/pull/49)
and [GitOps PR #129](https://github.com/chotabyorg/gitops/pull/129): source merge
`bce5e3abd9c423c72021142014c0b24239741bd6`, OCI index
`sha256:7e005f1c4914c0f3527947500379a9cbbc7a0b7d2c3118a9e8bdb49b6eeee8d9`.
This candidate preserves that AI pin and all AI Business/configuration resources.

Conversation source is [PR #8](https://github.com/chotabyorg/conversation-service/pull/8):
reviewed head `eb83c336a9772eece9b31cbd881f2516c31a992d`, published main merge
`cf95c23c7a4b0e71f9bb1a54136d6675cf8171d1`, identical tree
`493a5ea46078e0b871fc8de0234279dbd4365f46`. The exact image pin is:

- OCI index: `sha256:0905aac9eba294466b94e1aaabae5fd45597a6c610a5f335710a9c57863f45da`.
- Linux/amd64 child: `sha256:2c2986447d40c7660904e389e196395f476c13fb0ee6a02c501aad81d31d02c9`.
- Linked attestation: `sha256:0ed6219c15f5d4af11b2813c5f38077a184a2592f82f2ecb428727e04155ff4d`.

[PR quality run 38077773919](https://github.com/chotabyorg/conversation-service/actions/runs/38077773919),
[main quality run 38078082224](https://github.com/chotabyorg/conversation-service/actions/runs/38078082224)
and the build-only [publisher run 38078154664](https://github.com/chotabyorg/conversation-service/actions/runs/38078154664)
succeeded at those exact heads. Fresh complete source, supplemental security and
exact published-artifact reviews each recorded 0 BLOCKER / 0 IMPORTANT. Separate
independent verification passed 455 full-suite cases plus 21 explicit process/guard
cases with zero failures, errors or skips; the distinct artifact gate verified all
43 packaged files, unchanged dependency pins and native additive migration,
frozen-window retry, delivery/history and real-PostgreSQL concurrency behavior.
The complete combined GitOps/site release requires its own fresh full review.

The actual widget owner is [site PR #60](https://github.com/chotabyorg/chota-site/pull/60),
with reviewed head `28ab9badd9af002586e1ca0cd611e7666f2a7358`, published main
merge `bca7ca230ad557541c36cc5dd0f4b1619476082b`, and identical tree
`373b1798c2a81cd3bf5524f354a4b6c3ebb676a8`. Its published image pin is:

- OCI index: `sha256:9d8231d2ef1a6f187a5edaf9249ad56c5580a752d0c4959f43c8cfa198e5f4a4`.
- Linux/amd64 child: `sha256:92b9bc2fc5e81657e39fef0664f1ff45ddb0f2486e3ebd68f52337397360bc7c`.
- Linked attestation: `sha256:7d3b8dd71349fc454e690e1d50fed81350b879b36c9616a7367d86a8c6c59392`.

Site [PR CI 38079691858](https://github.com/chotabyorg/chota-site/actions/runs/38079691858)
and [main CI/publisher 38080132956](https://github.com/chotabyorg/chota-site/actions/runs/38080132956)
passed at the exact source heads with Node20 validation and image publication.
The fresh complete source R2 review recorded 0 BLOCKER / 0 IMPORTANT. Separate
independent verification passed all 158 frontend tests, lint, live production
build and typecheck; all 15 Chromium identity/retry/reload/privacy scenarios
passed with 93 intercepted requests and no continued external request. Bounded
concurrency repetitions passed and the injected duplicate failed as required.
The stable identity is generated once for the immutable logical-send envelope,
reused on response-loss retry and scoped pending reload recovery, with new UUIDs
for new or edited messages. No browser transcript is canonical authority and
no widget redesign is included. Published site artifact verification and the
combined fresh release review remain separate required gates; registry/CI
provenance alone is not artifact or production acceptance.

The new Conversation image's single additive head is `0004_website_history`.
The existing API init migration wrapper is retained unchanged; API and worker
readiness require that exact head and new columns. Old v1 requests/results,
fingerprints and evidence remain unchanged. Only new immediate Website Turns emit
v2; durable version/window/bounds/agent/hash freeze prevents rebudgeting on retry.
The [history policy](README.md#goal4a1-release-candidate) retains whole canonical
Messages under all three existing limits. A newly committed `WRITE_COMPLETED`
may promote one exact source-Turn AGENT Message; `WRITE_FAILED`/`UNKNOWN` alone
cannot. This is local write evidence, never browser READ. Customer input revision,
frozen Business confirmation authority, OperationReference, strict-v1 evidence
and execution namespace `main-chota.conversation.v1` are unchanged.

No Secret/seal, principal, binding, cohort, replica, NetworkPolicy, PVC, PostgreSQL
image, migration wrapper, Argo Application/ApplicationSet, provider or CRM change
is included. Preserve worker replicas 0, both worker flags false, both managed AI
bindings `[]`, Website cohort `{}` and all retained sticky-routing state. New
Website traffic remains LEGACY. Do not create a permanent managed demo principal,
perform a real CRM write, activate the public widget or start Goal4B.

Promotion must record the exact reviewed GitOps head/merge and both real image
pins, then observe Argo Synced/Healthy, the actual Main image/runtime, successful
0004 migration/readiness and unchanged DARK controls. Separate bounded safe
real-model continuity proof must follow clean deterministic tests and fresh
reviews; it carries no production Business/provider mutation authority. Rollback
keeps managed execution disabled and all accepted admission/history data intact.
After 0004, use a compatible forward fix; old 0003-only images are unready, and
retained v2 or source-Turn history forbids schema downgrade.

## Historical pre-rollout Main baseline (2026-10-08)

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

The initial dark deployment used API replicas 1, PostgreSQL replicas 1, worker
replicas 0, `WEBSITE_BINDINGS=[]` and false worker flags. That was the pre-Website
binding baseline; current final settings are listed at the top of this record.
The initial dark phase also relied on absent Website guard/cohort fields as empty
legacy defaults. Later Goal4A stages installed explicit routing fields and then
closed the cohort while retaining its guard and binding.

All five dedicated credential names and key schemas are in [README](README.md).
SealedSecret metadata and Secret template must retain strict scope `prod/<name>`,
wave −2 and `Prune=false,Delete=false`. Do not replace `ai-agent-secret`, Website's
existing secret, CP credentials, signing/TLS seals or unrelated tokens. For AI
add only `release/ai/deployment-patch.yaml.template` plus its separate real seal to
the existing overlay; preserve image and every resource/hook. Assess the current
AI PostSync MCP credential backfill Job on the exact rendered candidate before
sync; do not remove or redesign it to avoid a gate.

## Historical routing candidate and pre-canary gates

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

## Historical staged release sequence

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

## Retained Website admission and rollback authority

Goal4A ended with the Website cohort empty and managed execution disabled. Keep
the durable Website admissions, `MANAGED_WEBSITE_GUARDED_INTEGRATIONS`, the
Website-to-Conversation S2S configuration, and the exact Conversation
`WEBSITE_BINDINGS`. They keep accepted IDs sticky and ensure guarded new traffic
continues to reserve LEGACY; they are retained production state, not disposable
canary material. The temporary AI canary and its managed execution binding were
removed. The generic network path to normal `ai-agent-service:8000` remains dormant
while `MANAGED_AI_BINDINGS=[]`.

Already accepted managed messages are never replayed through legacy AI. Do not
delete the guard, admission journal, database, Website binding, or compatible
gateway routing state as cleanup. Do not recreate the temporary AI canary or
activate managed execution as part of this follow-up.

## Historical Goal4A Business-track handoff and next stage

This section describes the pre-Goal4A.1 source and handoff. Its inbound-only
context statement is historical; the reviewed Goal4A.1 candidate above adds
canonical assistant history. Its later activation and Goal4B sequence do not
authorize either action within Goal4A.1.

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
