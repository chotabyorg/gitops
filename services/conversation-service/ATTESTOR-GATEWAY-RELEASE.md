# Stage B — supervised text gateways with retained QA drain

This release replaces the two gateway binaries and installs exact QA admission
fences. It does not enroll a new session or Handoff cohort. Stage A #260 is accepted
at GitOps `eb70cca03b5297c37ddc71bcf08415d298dc42d1`: schema0019, API proof support
and idle retirement driver are healthy. Stage A did not certify actual writer
retirement, predecessor drain, authenticated Inbox or hosted E2E.

## Immutable release inputs

| Service | Source | Published tag | OCI index |
| --- | --- | --- | --- |
| Telegram | `8e771a3f0220145822747ddfc75d726779767d66` | `8e771a3` | `sha256:38f70094b5a0bd9d1447e0d224e5b724a1911e28b23e4f74df4fbdaf08577868` |
| Website | `63cd1aaeab2ebefa80771487fd6a289489ee2c47` | `63cd1aa` | `sha256:cd8e3535eff93ef33e08f6626ad0d0f948ee35199ac83c0fd17c3b937944b463` |

Telegram amd64 manifest:
`sha256:19126babc96fffeb2d3d07c29b25e962da72a1a102690ec59de7ae64c39eb147`.
Website amd64 manifest:
`sha256:90830dcb7b2e3d5d81e98e93dd74e71eb2f8426f68d3e9f622eabc00efe076b0`.
OCI revision/source labels and publication provenance were checked before this
candidate. Source acceptance and publication alone do not approve this rollout.

Both images use `python -m services.writer_attestor` as their CMD. Deployments do
not override it. The parent owns one `services.writer_child` process and private
Unix-socket capability, uses existing writable `/tmp`, and strips producer/proof/
retirement network credentials from the child environment. Existing gateway
health ports serve child liveness; they do not certify witness persistence or
legacy predecessor exit.

## Exact scope and generation semantics

Both entries use owner `dc3dd7eb-536f-45d4-84f2-c8d35575d928` and agent
`0b750714-af8d-4d8c-8fdc-4ddfeda98af9`.

- Telegram: integration `9b43e8ab-7afa-4201-8a88-99e8d256180a`, channel `TELEGRAM`.
- Website: integration `8d4a1b73-7973-4dcc-a3d4-1312d871c1d4`, channel `WEBSITE_WIDGET`.

`WRITER_ATTESTOR_SCOPES` contains only the respective exact entry.
`WRITER_LEGACY_DRAIN_SCOPES` retains that entry with `lifecycle_generation=1` and
`drain_generation=1`. CP read-only evidence at 2026-10-22 15:37:42 UTC observed both
Inbox bindings at binding_generation1/grant_generation0/inactive/READY/no pending
action. The first field names that **integration binding baseline**; the second
names the first reviewed retained drain revision. These positive integers are
receipt metadata; the source does not use them in scope matching and they grant
no authority. Separately observed AI lifecycle at 15:39:04 UTC was generation1,
STABLE, source_generation null. It is a distinct fact, not a substituted binding
or grant. Recheck both lifecycles before later enrollment.

Each parent receives only its own dedicated `WRITER_PRODUCER_TOKEN` through its
strict-name namespace-prod SealedSecret, sync wave -2. It calls
`http://conversation-service:8000`, already allowed by the retained Conversation
API ingress policy. There is no proof-reader/retirement credential in gateway
configuration, no new network listener, and no new network policy.

Telegram retains its managed binding and S2S credentials, removes the exact QA
UUID from fresh canary admission and keeps Handoff admission empty. The retained
drain blocks raw/v1/unsupported sends before unpersisted updates can advance the
provider offset. Website retains its exact integration guard, removes its existing
INTEGRATION_ALL managed cohort and explicitly keeps COMMON_WEBSITE_INTEGRATIONS
empty. Its retained drain blocks sticky LEGACY sends before admission. No QA
visitor/session capability or common transport is enabled. Non-QA configuration
is unchanged. Conversation required attestation stays false and both Handoff
cohorts remain empty; Voice and Business configuration are untouched.

Rollout strategies are retained: Telegram one replica/Recreate; Website one
replica/RollingUpdate, 25% surge and 25% unavailable. New Website instances may
coexist with the old one, but all new instances start drained. Neither strategy
proves the original has stopped. Existing security contexts, resources, volumes
and child health probes are preserved.

## Hard gate before merge

Obtain NEW independent release/security acceptance on the frozen candidate.
Refresh main and recheck unrelated drift, exact rendered delta, generation
snapshots, image provenance and sealed-secret names. Before merging either
gateway replacement, the separately accepted bounded observer must already be
attached to all frozen original identities. Record its exact code/review hash,
attachment receipts and continuity inputs with this release's evidence.

The binding architecture is `legacy-cutover-architecture-r2.md` and the lead's
`legacy-cutover-operational-decision.md` in the 2026-10-22 production evidence.
The rejected r1 timestamp-watermark observer is not permitted. The accepted
mechanism must retain exact trusted kubelet termination ACK, positively verify
the same original still alive after ACK, then retain that pidfd's POLLIN. Exit
before the live-after-ACK observation, missing ACK, observer loss, an additional
old-image Pod/task incarnation, identity/epoch change or unexpected exec rejects
the attempt. Do not delay, signal, freeze or otherwise alter the original writer
to improve the timing. Failed proof keeps QA closed.

The operational decision permits the trusted normal controller/API contract with
no known unresolved old-Pod creation and no unrelated concurrent control-plane
or debug changes. It is not an unconditional guarantee against ambiguous late
API commits or later administrator rollback. Known ambiguity is a blocker; an
empty snapshot or desired-zero count alone is insufficient.

For the positive kubelet ACK, the decision permits a bounded temporary V4 diagnostic
followed by explicit normalization to the existing **declared baseline 0** under
no concurrent debug writer. The prior dynamic effective value is unknown because
the endpoint is write-only; never describe reset as measured-prior restoration.
The independently accepted observer must bound duration/volume, bind trusted
journald identity/cursor and boot/process epoch, export only allowlisted lifecycle
fields, and provide an independent cleanup guard. Record successful reset-to-0
acknowledgment separately; failed cleanup remains an operational failure even if
process evidence passed. This GitOps release performs no diagnostic mutation.

Only after those gates may ordinary Argo reconciliation replace the old pods.
No manual apply, sync, restart, scale, signal or provider/model call is part of
this release.

## Post-rollout acceptance

1. Record Argo Synced/Healthy/Succeeded at the merged GitOps revision, exact new
   Deployment generations/templates and running imageIDs/OCI labels, readiness
   and restart histories. Retain old ReplicaSets at desired zero with their zero
   generations observed; this does not replace continuity/creation obligations.
2. Retain the accepted observer's complete per-original ACK/live/POLLIN chain,
   processed cutoff, all Pod transitions and stable node/K3s/runtime epoch. Report
   any failed proof window explicitly; do not reconstruct it by rolling back.
3. Check each seal Synced and exact Secret key name without printing values.
   Read only allowlisted parent/child identities, configured scopes and private
   current-process drain receipts: generation1/1 and zero active/acquired tasks
   in the new drained process. Never dump process environment or IPC capability.
   Child receipt `DRAINED` covers only that child; it does not certify its old
   unsupervised predecessor.
4. Read durable original attempts, LIVE/UNKNOWN/DISPATCHING writers, nonterminal
   Turns, grants/revoke floors, binding/agent generations and pending work. Do
   not relabel old identities with new supplier/process IDs. An old unfinished
   acquired writer without sufficient proof blocks enrollment. Preserve Website
   UNKNOWN even when its original socket completed; exit is not browser receipt.
5. Verify all new admissions remain empty and non-QA configuration is unchanged.
   Actual positive retirement, owner Inbox and hosted provider/model acceptance
   remain subsequent gates rather than synthetic production probes.

## Later enrollment and rollback

The dark Inbox middleware intentionally returns404 while both Conversation Handoff
cohorts are empty. Stage A's owner verifier URL/egress are now healthy prerequisites;
authenticated Inbox list/render/no-store acceptance awaits legitimate exact QA
enrollment. Do not enable a flag solely to probe that page.

Website enrollment also needs a separate reviewed common transport configuration:
HTTPS Conversation URL, exact TLS peer/trusted CA, dedicated common S2S credential,
explicit trusted proxy CIDRs/privacy checks and one reviewed QA session. Those
settings are currently unconfigured in production; Stage B must not fill them in
or enable integration-wide sessions. Verify current binding/grant/capability and
required attestation before any new writer. Provider/model calls remain subject
to the existing budget/admission gate.

On trouble keep exact drains and guards, empty/revoke only exact new admissions
through their lifecycle, and use a compatible forward fix. Do not restore the
old unsupervised gateway, revive raw fallback, downgrade schema0019, overwrite
recovery commands, delete CLOSED fences or change UNKNOWN outcomes. If predecessor
proof was lost, report the specific missing evidence and leave that QA scope closed.
