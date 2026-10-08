# Dark PostgreSQL storage finding and forward-fix candidate

This is the bounded correction for accepted Important finding I1 from independent
Main dark verification. It is source/release candidate evidence, not a repaired
runtime or Goal 4A PASS. The author neither deploys nor verifies this production fix.

## Observed failure

Initial Main GitOps revision `f30e256493cc644c6e8e755446aaf121db248fb1`
(PR #112; reviewed head `419e72e45a4349d037b23ef9cde3c3b8eff5a365`) deployed
private API 1 / PostgreSQL 1 / worker 0. API/schema/security/NetworkPolicy readiness
passed, but PostgreSQL durability failed native verification.

The official PostgreSQL `16.15-alpine` image at OCI index
`sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea`
declares `VOLUME /var/lib/postgresql/data`; its linux/amd64 config is
`sha256:81bd698b4594e751a3269e4dcd3e03a4a0ec0daf7b72e7aa1abd43cce9887542`.
The manifest mounted the retained PVC at the parent `/var/lib/postgresql` while
PGDATA was `/var/lib/postgresql/data/pgdata`. Main's containerd 2.2.3 CRI created
the image volume at `/var/lib/postgresql/data`, shadowing the PVC. The running
PG_VERSION and pg_control inodes belonged to that runtime volume; the actual PV
root was empty. A Bound PVC and successful migration never proved durability.
The exact-destination behavior is present in the primary
[containerd 2.2.3 CRI source](https://github.com/containerd/containerd/blob/v2.2.3/internal/cri/server/container_create.go).

Independent read-only census at `2026-10-08T21:38:59.330144+00:00` found exactly
ten public tables: `alembic_version` had its one migration row; `conversations`,
`inbound_events`, `messages`, `delivery_attempts`, `delivery_reconciliations`,
`agent_turns`, `website_admissions`, `website_immediate_turns` and
`website_response_attempts` each had zero rows. No additional public user-data
tables existed. Website bindings were empty, both processing flags false and
worker replicas zero. No widget, AI or provider call was made by this verification.
The observed retained PVC UID was `42ef2409-790b-4801-a599-55c4dad74328`.

## Exact correction and release eligibility

Only two rendered resources change: PostgreSQL's existing `postgres-data` PVC
mount becomes `/var/lib/postgresql/data`; the API pod template gains
`goal4a.chota.by/postgres-storage-layout: pvc-data-v1`. The latter is necessary:
PostgreSQL wave 0 initializes the previously unused PVC, then API wave 1 recreates
and reruns the existing serialized init migration to `0003_website_canary`.
Otherwise the already-started API would not rerun init against that new datadir.

Retain the same PVC name/UID and 4Gi local-path claim, PGDATA child, UID/GID/fsGroup
70, OnRootMismatch ownership policy, Recreate, wave order, image digests, seals,
credentials, private exposure, empty bindings and worker 0. No application source,
schema downgrade, Business settings or unrelated service overlay changes belong
to this fix.

Immediately before merge, the orchestrator and independent reviewer must refresh
the complete read-only public-table census, Main identity/current GitOps revision,
zero-admission configuration and worker-zero state. The old observation is not
permission to discard later state. If any domain table is nonzero, any additional
user-data table exists, accepted work appears or admission is enabled, STOP this
transition and obtain a separately reviewed preservation/recovery plan. A valid
credential alone must never substitute for those checks.

This empty-schema transition does not copy the original runtime volume or preserve
its database system identifier. No manual SQL, host-path transfer, volume deletion,
kubectl restart/apply, or containerd/controller/CNI reconfiguration is authorized.
The original runtime volume is not explicitly deleted by this procedure; runtime
garbage collection may reclaim it during pod recreation, so continued retention is
not guaranteed. Only migration metadata was present at the recorded observation.
Do not claim accepted data was moved or that an orphan runtime volume is durable.

Any merge is an intentional Main deployment through ArgoCD and requires a fresh
complete review of cumulative Goal 4A changes since
`72438529a6db91ce2595f2f31353c745eddb334c`, plus exact repaired-release CLEAN.
All Website/CP/AI promotions, real widget use, worker enable and managed canary
remain held until the repaired native storage gate passes.

## Finite two-stage GitOps proof

Stage 1 is branch `codex/goal4a-conversation-storage-fix`: the exact mapping fix
and API layout stamp above. It may merge only after complete review and a fresh
zero-data/disabled-admission preflight. After Argo finishes, an independent native
verifier must first establish the corrected mount, PVC/PV identities, host/pod file
identity and permissions, PostgreSQL system identifier, schema and zero census.
Any failed or uncertain check stops Stage 2 and all subsequent promotions.

Stage 2 is a separate dependent branch
`codex/goal4a-conversation-storage-proof`, frozen from Stage 1. Its only changes
add `goal4a.chota.by/storage-persistence-proof: recreate-v1` to both PostgreSQL
and API pod templates. It retains the Stage 1 API layout stamp. Its dependent draft
PR must receive a complete cumulative source and exact-release review before any
Stage 1 mutation; the exact two commit heads belong in that review record. After
Stage 1 merges, retarget the same frozen Stage 2 head to main only if Stage 1's
merge tree is identical to its reviewed tree. Stage 2 is still held until the
independent Stage 1 native baseline passes and immediately refreshed admission and
table counts remain zero.

Stage 2 causes only PostgreSQL wave 0 and API wave 1 Recreate, again using the
unchanged image and serialized source-controlled init migration. A different fresh
native verifier compares the Stage 1 system identifier/schema and PVC-backed files
with Stage 2, requires both old pods to be replaced, and rechecks native readiness,
security, private exposure and effective policies. This is the finite durability
proof; no SQL record insert, manual restart, migration, host copy or volume deletion
is part of either stage. Neither reviewed source tree alone can claim that proof.

## Regression protection and native proof still required

The release validator now rejects a parent-only PVC mount, wrong claim, subPath,
read-only data mount, PGDATA outside the retained mount, mismatched UID/GID/fsGroup,
wrong migration wave order or absent API reinitialization annotation. Tests use
the actual rendered Conversation production resources and retain the old parent
mount as a failing counterexample. These render checks establish desired mapping,
not live CRI behavior.
The fix author's 14 existing/new validator tests passed, dark and fixture checks
passed, and all 24 production overlays rendered. Canonical comparison with the
initial dark merge changed only the API template annotation and PostgreSQL mount;
all resource identities, images, credentials/seals, configs, PVC, policies, worker
and unrelated overlays remained identical. Running the new validator against the
unmodified initial dark tree failed with `POSTGRES_IMAGE_VOLUME_MOUNT_REQUIRED`.

Local lifecycle evidence for this exact immutable PostgreSQL image already used
the corrected `/var/lib/postgresql/data` mount: a committed synthetic local record
survived container removal/recreation with UID 70, SCRAM, read-only root, zero
capabilities and no privilege escalation. It was disposable Docker on arm64 with
amd64 emulation, not Main Kubernetes/fsGroup proof. The initial failed local
parent-mount run and native failure evidence remain retained; the previous
assumption that Kubernetes ignored image VOLUME was disproven.

After the separately reviewed GitOps fix, a fresh independent production verifier
must prove actual mountinfo resolves PGDATA to the retained PV (with no shadowing
mount), matching host/pod PG_VERSION and pg_control inodes, expected owner/group
and permissions, native seccomp/capability/read-only settings, schema/readiness,
zero admission and unchanged legacy/AI/CP deployments. Capture PVC/PV identity and
the new PostgreSQL system identifier. A subsequent separately reviewed GitOps
pod-template recreation of PostgreSQL and API must preserve that same system
identifier, schema and PVC-backed files. No production data insert is required for
this dark proof; a read-only pg_control identity survives only with the same
database. Re-run private exposure and positive/negative policy checks before the
next rollout stage. Worker remains zero until its own reviewed activation.

Failure keeps all next stages held. Preserve evidence and forward-fix through a
new author context and fresh complete review; do not delete/downgrade the database
or convert accepted managed work into legacy replay. Backup, HA and DR are outside
this bounded correction.
