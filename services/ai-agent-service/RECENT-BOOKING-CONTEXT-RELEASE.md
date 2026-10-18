# Recent booking context and text phase timings

After a confirmed booking, a later cancellation could ask for the already known
contact again. AI PR93 provides a validated historical booking reference when
no proposal is pending. The agent must read current CRM state/revision before
preparing a change and obtain a separate confirmation. No customer contact or
write permission is added by this projection. Text also emits bounded setup
checkpoints and per-tool wall times without arguments, results or transcripts.

Source [PR93](https://github.com/chotabyorg/ai-agent-service/pull/93): reviewed
`d4cf34ac599a56ac487b9cc1e3edbb30a79421e6`, merged `ae576eadeefe57889f0ed5de6f4b1233f6958116`, identical tree
`1991cadb8d8dac73f1ac51692a5488c1f4c21403`. Full PostgreSQL/migration Quality run 39167290865 and
all four native shards in 39167290755 passed. Exact-head review has no new
actionable findings; its effect-eligibility finding was fixed and tested.
Local checks include 12 projection cases, 60 existing focused cases and 44
timing/recovery cases. Image build 39168562528 passed at
the exact merged revision. Immutable image:
`ghcr.io/chotabyorg/ai-agent-service:ae576ea@sha256:c897f1335ef9c7aae10f801cb3f65fc7361210e980363c772d51aaaca574ab7d`.

Kustomize changes exactly three AI image references; every other rendered
resource is structurally identical. Voice remains
`da3eeda9f6221bbe30555c68ad7ea2939f8ab52d` / PID2368232 and Conversation remains
`3f0669156c016cbdcdea53e9a62c0bf15090c686`. AI PR82, Conversation PR23, managed
identity/fingerprint and wire-profile contracts are excluded. Text parallel
tool selection remains disabled.

Own-number admission was closed before the source merge. Drain at
`2026-10-18T21:35:50.607371+00:00` found zero active calls, open call rows, active playback
responses and nonterminal turns; Voice had only its SIP socket. Recheck this
drain immediately before merging this GitOps pin. ArgoCD alone deploys it.
Require all six relevant deployments current/ready, actual container image IDs
matching the digests, old pods gone and both Argo apps Healthy/Synced at the
merged GitOps revision before reopening the same DID. Voice must not restart.

Post-deployment text acceptance remains pending: cancel the retained own
CONFIRMED booking through ordinary dialogue without repeating contacts, then
start a fresh create/proposal/consent/CONFIRMED/cancel-proposal/consent/CANCELLED
session. Verify zero dispatch before consent, one create/cancel attempt, same
message-ID and natural consent replays, and native CRM audit counts. No test
booking may remain active. Carrier acceptance is deferred by the user.

Six fictional matched cancellation phrases reduced model requests from four
to two in every pair and mean model time from 9535 to 5379 ms. These probes
made no CRM calls. This small synthetic result is not production p95 or an
A/B claim; real phase timings and dialogue acceptance must be collected after
deployment.

Rollback: close admission, wait for the same drain gates, restore the previous
AI image through reviewed GitOps:
`ghcr.io/chotabyorg/ai-agent-service:9190fbb@sha256:6e9ecfceba0d1d4c5d3ceab6d9ad3b5ba1016966ba5f053c19a40f361fc8ecbe`.
Verify Argo/runtime provenance before restoring the previous retained route
evidence. Never blindly replay a business effect with an uncertain result.
