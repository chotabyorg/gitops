# Goal4B Telegram DARK release foundation

**DO NOT MERGE — NEW INDEPENDENT RELEASE REVIEW REQUIRED.**

This is the release/runbook checkpoint for GitOps PR #148. Goal4B source remains
accepted and merged. This PR prepares topology, reviewed image pins and an empty
Telegram admission cohort; it does not provision or activate a canary. The broader
Goal4A/Beauty/Business/Voice state on current GitOps main is preserved.

## Source, artifacts and base

- Conversation merged source: `d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3`.
  Image: `ghcr.io/chotabyorg/conversation-service:d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3@sha256:a37fc3344e78664fe861a793393e8dbbe0cdf1268e376965a7a3038ce9274a38`.
- Telegram merged source: `4ee10d9271d1b72427f44aa86c6a151c5250678d`.
  Image: `ghcr.io/chotabyorg/telegram-gateway-service:4ee10d9@sha256:c59533541dd0147feea4fe26e94cbbf67977c6a99f19c5076bc225355d294f7a`.
- Previous PR head: `319a2b574db60f4acf7670824f158efc94b36efd`.
- Release fixes rebased onto fetched GitOps main
  `c9fcc17d1bdb0588c5fc6b3f361ef9318219717e`. The newer frontend release is retained;
  no unmerged changes from other PRs are imported.

The independent live review on 2026-10-13, 23:47–23:50 Europe/Minsk, established
that Telegram `4ee10d9` was healthy and matched its reviewed digest. Its automatic
GitOps update `ad772f968789c896ce0db089ff2740da7e2a317b` had been reconciled by Argo.
Conversation still ran the previous image with DB revision `0004_website_history`;
no Telegram worker existed. Telegram managed gates were effectively empty,
`TURN_SETTLING_POLICIES` was absent, and relevant Argo apps were Synced/Healthy.
These are the prior review's observations, not a new live verification by this
fix checkpoint. No production mutation is part of these fixes.

## Isolated dormant worker

Website stays in `base/worker`, with its existing immutable selector exactly:

```yaml
app: conversation-service
component: worker
```

Telegram is a sibling resource scope in `base/telegram-worker`, with selector and
pod labels injected only by that scope's Kustomization:

```yaml
app: conversation-service
component: telegram-worker
```

Neither worker's pod labels satisfy the other Deployment selector. The existing
Website Deployment selector and base worker Kustomization are unchanged. API and
PostgreSQL Services select neither worker. Telegram has a dedicated deny-ingress
NetworkPolicy, with egress limited to Conversation PostgreSQL TCP 5432, the normal
AI API TCP 8000 and kube-system DNS TCP/UDP 53. PostgreSQL admits this component
only on TCP 5432. Gateway ingress is separately limited to the Conversation API
on TCP 8000 in the same namespace. Worker health port 8002 has no Service.

Telegram remains `replicas: 0`, `TELEGRAM_WORKER_ENABLED=false`, and has no selected
processing principal ID. Gateway `TELEGRAM_MANAGED_BINDINGS=[]` and
`TELEGRAM_CANARY_INTEGRATION_IDS=[]`; Conversation
`TELEGRAM_CANARY_INTEGRATION_IDS=[]`. Existing Website/Beauty bindings and worker
configuration are retained. No Goal5 settling policy is added.

## Supported rollback: forward-compatible configuration/features

Routine Goal4B rollback retains compatible binaries and schema. It is not a
return to the old Goal4A images, and it is not a database downgrade.

1. Empty/disable the new managed Telegram cohort on **both** admission sides:
   gateway and Conversation `TELEGRAM_CANARY_INTEGRATION_IDS=[]`.
2. Preserve the exact sticky gateway binding, Conversation/Managed AI bindings,
   dedicated principals/grants and credential references needed by already
   accepted MANAGED work. Do not remove them as canary cleanup or alter unrelated
   Website/Beauty configuration.
3. Keep the Goal4B-compatible Conversation image/schema and Telegram gateway
   available. New events with no retained MANAGED disposition use LEGACY. Replay
   of an already accepted MANAGED event remains MANAGED, including while the new
   admission cohort is empty. Managed failures/uncertainty never fall back to AI
   through the legacy path.
4. Keep the Telegram worker available while accepted MANAGED work needs
   processing. Disable it and scale it to zero only when that processing is no
   longer required. If emergency containment stops processing before completion,
   retained work remains MANAGED/pending/uncertain until compatible recovery; it
   must not be relabelled LEGACY. A zero worker is not evidence of completed work.
5. Retain Turns, DeliveryAttempts, canonical history and delivery/evidence rows.
   Recover/replay through the compatible managed path; never blindly resend a
   provider request or infer delivery from draft existence.

The release API init uses the reviewed image and runs `alembic upgrade head`
through the existing bounded migration wrapper. After this release installs
`0005_telegram_canary`, the older Conversation `058b78e` is not an ordinary rollback
candidate: its readiness requires exactly `0004_website_history`. An image-only
revert is incompatible with schema 0005 and can fail migration init/readiness.
The older Telegram `591d713` has no retained MANAGED behavior and directly calls
legacy AI, so it is not a safe fallback when managed routing must be retained.

If a compatible binary needs replacement after schema 0005 exists, use a
**separately reviewed forward fix/newer compatible image**, preserving retained
routing and evidence. A downgrade, even if technically possible before any
Telegram rows exist, requires a separate explicitly reviewed procedure and is
outside routine release rollback. Migration 0005's downgrade guard refuses any
retained Telegram admission, including LEGACY.

Compatibility evidence: [old Conversation readiness](https://github.com/chotabyorg/conversation-service/blob/058b78e4c0482036ad8bea6700b783cc77aa6006/db/database.py#L53),
[Goal4B readiness](https://github.com/chotabyorg/conversation-service/blob/d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3/db/database.py#L53),
[migration guard](https://github.com/chotabyorg/conversation-service/blob/d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3/migrations/versions/0005_telegram_canary.py#L105),
[retained route precedence](https://github.com/chotabyorg/conversation-service/blob/d77e75dc3d7b97a3817239b2b6a3c8d58e48acd3/services/telegram.py#L110),
[old Telegram handler](https://github.com/chotabyorg/telegram-gateway-service/blob/591d713302f06dd15fd583db1ca5629b240b4bf7/bot/handlers.py#L14).

## Offline verification

From the GitOps repository, using kubectl's embedded Kustomize and the same
PyYAML dependency as the existing validator:

```sh
python3 -m unittest discover -s services/conversation-service/operations -p test_goal4b_release.py
```

The suite renders both complete production overlays in memory without contacting
Kubernetes. It never prints renderer payloads or secret values. It checks the
unchanged Website selector, mutual worker selector exclusion, each Deployment's
own selector/template validity, effective empty Telegram gates, disabled/zero
worker, absent Goal5 policy, exact reviewed images (including migration init),
runtime/security/secret-key references and intended Services/NetworkPolicies.
The selector exclusion check fails on the original PR topology.

The historical Goal4A `test_validate.py` suite has a pre-existing baseline of 21
tests with seven `RENDER_FAILED` fixture errors. It must be reported separately;
this checkpoint does not repair or claim that historical suite as PASS. Actual
Goal4B production renders and the focused regression suite are separate evidence.
Offline checks do not establish live CNI enforcement, credential scope validity,
migration execution or canary readiness. Those remain independent release gates.

## Activation prerequisites and boundary

**CANARY INTEGRATION SELECTION REQUIRED.** No customer integration is selected.
Later activation needs an explicitly designated test `owner_id`, `integration_id`
and `agent_id`; a dedicated TELEGRAM API principal/token and TELEGRAM_PROCESSING
principal/token with exact `main-chota.telegram.v1` grants; the worker principal
ID; matching Managed AI/AI-side scope; gateway service-token reference; and the
exact sticky binding/cohort on both admission sides. API currently reads
`conversation-beauty-managed-secret`, while the Telegram worker reads
`conversation-managed-ai-secret`; their eventual Telegram bindings must agree.
No such identity, token, principal or binding is added by this PR.

Fresh independent review must assess this final GitOps head before merge. After
any separately approved dark release, verify schema 0005, readiness, digest and
network enforcement before a separate focused activation review. Neither the
reviewed source nor this release foundation authorizes activation.

- GITOPS PR MERGED: NO
- PRODUCTION MANAGED CANARY ACTIVE: NO
- No production apply/patch/delete/restart, credential provisioning, database
  downgrade or customer traffic is performed by this checkpoint.
