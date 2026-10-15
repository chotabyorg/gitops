# Goal4B Telegram release and QA activation checkpoints

**DRAFT ACTIVATION CANDIDATE — DO NOT MERGE — FRESH INDEPENDENT ACTIVATION REVIEW REQUIRED.**

## Exact new QA activation candidate — 2026-10-14

The DARK foundation PR #148 is already merged. This new candidate starts from
GitOps main `5ca25801830e7a90003c4465681329d1d56551fa` and prepares only the newly
created QA Telegram integration. It does not activate production or establish
Goal4B managed acceptance. The historical DARK release record follows below.

Selection and polling evidence is in [GOAL4B-CANARY-IDENTITY.json](GOAL4B-CANARY-IDENTITY.json);
the public scope contract is [GOAL4B-ACTIVATION.json](GOAL4B-ACTIVATION.json).

| Identity | Selected value |
| --- | --- |
| Bot username / ID | `@chota_test_4343434_bot` / `8778392344` |
| Owner | `dc3dd7eb-536f-45d4-84f2-c8d35575d928` |
| Integration | `9b43e8ab-7afa-4201-8a88-99e8d256180a` |
| Agent | `0b750714-af8d-4d8c-8fdc-4ddfeda98af9`, salon «У Светланы» |
| Created / status | `2026-10-13T22:42:17.608130Z` / `ACTIVE`, active=true |

The prior stopped checkpoint was `2026-10-13T22:32:40Z`. The selected row is newer.
Its sole registration at `22:42:32.710521029Z` is followed by the first exact
username/bot-ID polling start at `22:42:41.887773310Z`. Complete available logs
from the sole zero-restart gateway pod include the earlier registrations and
polling starts; those earlier bot IDs are all different. The exhaustive current
Control Plane Telegram table contains three older rows and this one new row.
Control Plane has no separate bot-ID column: identity exclusion uses that table
plus the exhaustive live lifecycle inventory and the user's authoritative fresh
bot designation, without selecting or decrypting credentials.

The last conflict in any gateway polling task precedes the new integration's
creation. There are zero gateway conflicts from its creation through the final
recorded observation, one new-bot polling start and one intended gateway process
in one ready pod. No extra Docker Telegram container or separate non-container
Python poller is present; the host Python processes in the observation are the
two read-only audit probes. **SINGLE POLLER SAFE: YES** for this observed Main
runtime. Ownership must be rechecked during the independent activation review.
Handled baseline updates establish only LEGACY behavior. No message content or
BOT_TOKEN was read; no Telegram API call or message was sent by this preparation.
The withdrawn older bot/integration is excluded and is not repaired or restarted.

### Exact grants, bindings and credential references

Both gateway and Conversation admission cohorts contain only
`9b43e8ab-7afa-4201-8a88-99e8d256180a`. The gateway's exact sticky binding is
`{owner_id,integration_id,agent_id}` with the values above. There is no wildcard,
owner-wide, agent-wide or second-integration Telegram activation.

- `main-telegram-qa-api`: role `TELEGRAM`, one complete grant
  `{owner_id,integration_id,channel=TELEGRAM,provider_namespace=main-chota.telegram.v1}`.
- `main-telegram-qa-processing`: role `TELEGRAM_PROCESSING`, the same single grant.
  It is the exact `TELEGRAM_WORKER_PRINCIPAL_ID`; its registry contains no API or
  Website principal.
- `main-telegram-qa-managed-ai`: caller `conversation-service`, execution namespace
  `main-chota.conversation.v1`, one grant with exact owner/integration/TELEGRAM/agent
  and `agent_owner_id=dc3dd7eb-536f-45d4-84f2-c8d35575d928`.

Three distinct fresh S2S credentials were generated only in memory and sealed
with the Main controller's public key. Existing credentials were not fetched,
decrypted, printed, replaced or copied into plaintext. No BOT_TOKEN is included.

| Consumer | Secret object / key |
| --- | --- |
| Gateway → Conversation | `telegram-conversation-s2s-secret` / `CONVERSATION_SERVICE_TOKEN` |
| Conversation API auth | `conversation-principals-secret` / `API_AUTH_PRINCIPALS`; fixed template appends `TELEGRAM_API_AUTH_PRINCIPALS` |
| Telegram worker auth | `conversation-telegram-processing-secret` / `PROCESSING_AUTH_PRINCIPALS` |
| API + retained Website Managed AI | `conversation-beauty-managed-secret` / `MANAGED_AI_BINDINGS`; fixed template appends `TELEGRAM_MANAGED_AI_BINDINGS` |
| Telegram worker Managed AI | `conversation-telegram-managed-ai-secret` / `MANAGED_AI_BINDINGS`; only the new Telegram binding |
| Normal AI auth | `ai-beauty-managed-secret` / `MANAGED_AI_AUTH_PRINCIPALS`; fixed template appends `TELEGRAM_MANAGED_AI_AUTH_PRINCIPALS` |

The three registry extensions keep every existing encryptedData value and all
prior fields intact. SealedSecrets controller templates combine the raw old JSON
array with the dedicated new JSON array using
`concat (mustFromJson ...) (mustFromJson ...) | mustToJson`; no application startup
wrapper or secret-reading preparation script is introduced. API and Telegram
worker receive the same exact Telegram Managed AI binding, while the existing
Website binding and scopes remain present. The helper encrypted keys also remain
in the generated Secrets. Existing consumers keep their original canonical keyRef.

This behavior is verified for installed controller `0.36.6` against
[official Unseal source](https://github.com/bitnami/sealed-secrets/blob/v0.36.6/pkg/apis/sealedsecrets/v1alpha1/sealedsecret_expansion.go#L283-L314).
The six exact manifests passed controller `--validate`: fixed templates execute
inside the controller, returning status only and writing no resources. This is
not a claim that arbitrary validation templates are safe: the v0.36.6 validator
can act as a conditional decryption oracle, fixed upstream in
[PR #2019](https://github.com/bitnami/sealed-secrets/pull/2019). This preparation uses
only the fixed concatenation templates and performs no secret-derived probes.

### Worker, rollout and verification boundary

Telegram worker changes `replicas: 0 → 1`, `TELEGRAM_WORKER_ENABLED=true`, principal
`main-telegram-qa-processing`, lease 30s, poll 1s, health port 8002. It retains
the accepted immutable Conversation image, isolated selector, Recreate strategy,
security settings, no Service ingress, PostgreSQL/DNS/normal-AI egress and no
provider credentials. Managed AI URL is `http://ai-agent-service:8000`;
gateway Conversation URL is `http://conversation-service:8000`.

Gateway remains one replica and changes to Recreate so a configuration upgrade
does not overlap two long-polling processes. This future rollout briefly restarts
the shared gateway and pauses all its pollers; it changes no other integration's
routing binding or credentials. The normal AI pod receives an explicit registry
rollout annotation because Secret environment values are captured at startup.
Conversation API and retained Website worker also roll with the changed shared
ConfigMap hash; Website settings, processing keyRef and prior grants/bindings stay
intact. No image, schema, network policy, Service, Website cohort or Business/Voice
configuration is changed. `TURN_SETTLING_POLICIES` is absent throughout.

Offline checks:

```sh
python3 -m unittest discover -s services/conversation-service/operations -p 'test_goal4b*.py' -v
```

- Base DARK render suite: 6/6 PASS. Candidate: 13/13 PASS, including rollback renders.
- Complete Conversation, Telegram gateway and normal AI production overlays render.
- Accepted-source synthetic config validation passes for API, retained Website
  worker, exact Telegram worker and empty-cohort drain; wrong cohort/principal/role
  configurations are rejected. The accepted AI parser accepts the new exact grant.
- All prior ciphertext, immutable images, selectors, network rules, Services and
  unrelated source files are preserved. The source scope contains one Telegram
  integration only.
- Historical Goal4A suite is separately unchanged: 21 tests / 7 fixture-render
  errors on both exact base and candidate. It is not reported as PASS.
- Six ciphertext manifests and fixed registry templates pass native controller
  validation without decrypted responses or Kubernetes writes.

This is a draft desired-state diff. Argo applications reconcile independently;
sync waves do not order gateway, Conversation and AI across applications. A fresh
review must recheck the bot/CP identity and single poller, inspect this exact head,
assess credential/controller/network/readiness and cross-application rollout gates,
and approve any future merge separately. Managed failures remain fail closed while
dependencies converge. No native managed delivery acceptance or live CNI execution
proof is claimed by offline checks. No merge, Argo sync, apply, patch, restart,
database write or Telegram traffic has been performed.

### Supported rollback for the new QA cohort

1. Empty `TELEGRAM_CANARY_INTEGRATION_IDS=[]` on **both** admission sides only.
   Preserve the exact sticky gateway binding, all new grants/credential references,
   controller templates and compatible images/schema.
2. Keep the Telegram worker enabled/one replica while retained MANAGED work needs
   draining or recovery. Already accepted MANAGED events remain MANAGED, including
   replay; there is no legacy AI fallback for managed uncertainty/failure.
3. Disable `TELEGRAM_WORKER_ENABLED=false` and scale that worker to zero only after
   a separately observed safe drain. Emergency containment before drain leaves
   work MANAGED/pending/uncertain for compatible recovery, never relabelled LEGACY.
4. Retain Turns, canonical history, admissions, delivery attempts and evidence.
   No blind resend, removal of credentials/bindings, whole-PR git revert, old-image
   rollback or DB downgrade. A binary replacement requires a reviewed compatible
   forward fix.

**DRAFT ONLY. PRODUCTION MANAGED CANARY ACTIVE: NO. STOP FOR FRESH INDEPENDENT ACTIVATION REVIEW.**

## Historical DARK foundation release record

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
