# Text writer attestor — staged production release

Stage A is additive Conversation support only. It does not enroll Telegram or
Website Handoff and does not certify legacy drain. Release source and immutable
image are pinned in `prod/kustomization.yaml`; the same image serves the API,
migration and existing Website/Telegram/Voice workers. Voice configuration,
routing, principals and admissions remain unchanged.

## Frozen release inputs

GitOps base: `9873277b9cc0eaf9b1f61726ff647a4a376162ab` (Site #259).
Conversation source: `d1e41d582ccb7191ba93f8652a85b03fc5802c6a`, tree-identical
to independently reviewed `b320ab746b7bed2f8127a8cbc09cde62e7f62eef`.
[Manual publication run 39803021782](https://github.com/chotabyorg/conversation-service/actions/runs/39803021782)
succeeded. OCI revision/source labels and BuildKit provenance bind that source.

- Pinned OCI index: `sha256:28924aa627d95b040ec644dbd90a43c469d8d5a8d79bf96dfe9b36cb11a976c1`.
- Linux amd64 manifest: `sha256:9a5c8fc6225c49fe590a202b2c4f72a50969ce0bd37b01548829a82f4746db8f`.

These are release inputs, not a claim of production reconciliation or formal
GitOps acceptance. A new independent review of this frozen candidate is required.

## Stage A topology and authority

The main Conversation API loads the two exact producer grants from
`conversation-writer-attestation-secret`: owner
`dc3dd7eb-536f-45d4-84f2-c8d35575d928`, agent
`0b750714-af8d-4d8c-8fdc-4ddfeda98af9`, Telegram integration
`9b43e8ab-7afa-4201-8a88-99e8d256180a` and Website integration
`8d4a1b73-7973-4dcc-a3d4-1312d871c1d4`. It also loads independent proof-reader and
retirement credentials. These strict-name, namespace `prod` SealedSecrets use the
existing Main sealing certificate. No plaintext credential is stored here.

The API reads its own immutable proof endpoint through `http://127.0.0.1:8000`.
The new `conversation-service-retirement-worker` uses the same database and calls
that endpoint through `http://conversation-service:8000`. Its NetworkPolicy allows
only Conversation PostgreSQL TCP 5432, the main API TCP 8000 and kube-system DNS;
it accepts no ingress and has no Service. The existing API and DB policies add
only this component as a peer. No provider or AI network permission is added.

The driver has only DB, proof and retirement secret references plus the existing
narrow `PROCESSING_AUTH_PRINCIPALS`. That last registry is required by shared
Settings validation; the driver does not use it for network authentication or
execute Turns. It receives no producer, general API, managed-AI or provider
credential. Credential separation is a trusted-process capability boundary; it is
not a new database-role isolation architecture.

The API runs additive migration `0019_writer_attestation` through the existing
bounded, advisory-locked initContainer. Sync waves remain secrets -2, configuration
and network -1, existing database 0, API/migration 1, workers 2. The new worker has
one Recreate replica, UID/GID 10001, RuntimeDefault seccomp, all capabilities
dropped, no service-account token, read-only root filesystem, bounded resources
and a 64Mi `/tmp`. Its 60-second termination grace permits an in-flight bounded
proof call to complete; the loop stops admitting rows on SIGTERM. Forced
termination never creates a witness or retirement fact.

`WRITER_ATTESTATION_REQUIRED=false`; both Conversation Handoff cohorts are
explicitly empty. Existing managed bindings and cohorts are retained. The
producer secrets for gateways and their new images are a separate Stage B release.
The driver cannot create historical proof, grants, scopes, deliveries or sends.
A matching durable positive witness is required for recovery; absence remains
UNKNOWN/LIVE. CLOSED fences remain enforced even with registration optional.

## Stage A release gates

1. Independently review the exact source, source-to-image provenance, GitOps diff,
   credential boundaries and structural renders. Refresh `origin/main`, preserve
   unrelated work and recheck the exact candidate before merge. Argo is the sole
   deployment mechanism; do not apply or restart production manually.
2. Observe all seals successfully producing their exact named Secrets without
   printing data. Capture only object status and key names. Verify the new API
   credential references do not reach existing worker or Voice environments.
3. Record Argo revision and Synced/Healthy/Succeeded; actual Deployment image and
   container `imageID`; API migration init exit 0; and DB read-only
   `alembic_version = 0019_writer_attestation`. Verify API `/health` and `/ready`
   return 200. Retain readiness for the existing Website, Telegram and Voice
   workloads and their unchanged effective scopes.
4. For the retirement worker, inspect exact imageID, PID1 command
   `python retirement_worker.py`, Running state, restart count and termination
   status across the observation window. This executable has **no HTTP health
   endpoint**. Kubernetes availability alone proves neither loop progress nor
   successful recovery. No invented health port/probe is configured.
5. From that worker's network context, perform a bounded read-only GET of API
   `/ready` and a read-only DB readiness query, without printing DSN or headers.
   Confirm the `writer_recovery_scan` row `name='text-v1'` is present: migration
   creates no row, so its appearance proves the driver reached its first scan.
   Record bounded sanitized logs; recurring `WRITER_RECOVERY_RETRY`,
   `WRITER_RECOVERY_PENDING` or `WRITER_RECOVERY_STOPPED` requires diagnosis before
   further rollout. An idle cursor need not move and is not an ongoing heartbeat.
6. If a real retained matching registration/witness exists, observe exact command
   and receipt progression through read-only inspection, preserving identity and
   outcome. If none exists, report only idle-driver readiness. Do not invent an
   outbound intent, upload fabricated proof, signal a production writer, or make
   a provider/model call as a probe. End-to-end production retirement acceptance
   remains a later controlled gate.

## Stage B prerequisite and exact drain

Create its branch from fresh main only after Stage A acceptance. Before merging
any gateway replacement, independently review and attach the bounded observer to
**every old-image incarnation**, including starts/restarts during rollout. Retain
Kubernetes/CRI continuity, exact process identity and positive pidfd exit receipts.
A missing incarnation, observer gap or unmatched process blocks enrollment.
Recreate, an empty pod list, rollout success and timeouts are not exit proof.
Website currently uses RollingUpdate; account for overlap without claiming it
proves drain. Ordinary Argo termination is the only rollout termination action.

Stage B starts each supervised gateway with its own dedicated producer secret,
exact attestor scope, and retained exact legacy drain (owner/integration/agent/
channel plus freshly verified lifecycle and reviewed drain generations). Keep
Handoff admission empty. Telegram keeps its managed binding and clears its fresh
canary admission; the drain fences raw/v1/unsupported fallback. Website retains
its exact guard and clears integration-wide managed admission before its new
common path can start. Do not merely retain the existing `INTEGRATION_ALL` setting:
the new Website implementation uses common sessions. Sticky LEGACY writes must
also remain fenced by the retained drain. Non-QA integrations keep their current
configuration.

After all positive exits, recheck durable attempts, original writer identities,
nonterminal Turns, grants/generations and UNKNOWN/DISPATCHING/LIVE state. Never
relabel old writers with new supervisor IDs or infer browser/provider receipt
from process completion. Only then may a separately reviewed release enable
required attestation and admit one exact Telegram QA integration or explicit
Website QA session. No broad Website admission is part of this release.

## Rollback

Keep schema 0019, retained registrations, CLOSED fences, witnesses, commands,
receipts, generations and UNKNOWN outcomes. The previous pre-attestor image is
not a safe schema/reader rollback after this migration or any retained evidence.
Use a compatible forward fix; if the new driver itself is faulty, a reviewed
GitOps change may scale only that worker to zero while preserving its configuration
and evidence. LIVE continues to block subsequent writers until positive recovery.
After Stage B preserve exact drains and guards during rollback; never remove a
managed cohort in a way that re-enables legacy fallback. After enrollment revoke
only the new exact admissions through the established lifecycle. Do not downgrade
the database or touch Voice routes.
