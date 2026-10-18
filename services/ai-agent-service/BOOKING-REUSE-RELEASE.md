# Booking preparation and playback cancellation release

## Reviewed source and image provenance

- AI [PR90](https://github.com/chotabyorg/ai-agent-service/pull/90), reviewed head `fafd50331765003d135f4d17023278c4b9a92b0c`, merged source `f5c712eacc2ee22ed30f3ad9cc16b1df78766c4e`.
- AI image `ghcr.io/chotabyorg/ai-agent-service:f5c712e@sha256:b6487ae35d5b48e975f9dc05a966c39176c9ec5c795a422293b69d8647559737`. Published by [run39151929388](https://github.com/chotabyorg/ai-agent-service/actions/runs/39151929388), at the exact merged source. All three rendered AI image references (Deployment, init container, migration Job) change together; other rendered resources stay unchanged.
- AI full PostgreSQL quality/migration [run39150564707](https://github.com/chotabyorg/ai-agent-service/actions/runs/39150564707) passed. All four native latency/workflow jobs in [run39150564763](https://github.com/chotabyorg/ai-agent-service/actions/runs/39150564763) passed. Local targeted regression suite:182 passed; exact-head CodeRabbit review has no actionable comments.
- Voice [PR32](https://github.com/chotabyorg/voice-gateway-service/pull/32), reviewed head `01093f137fba0d598a51c1ae241806eb9c3d9f5c`, merged source `e8993383a26b57d9c50d45d16fe1ce032ac5d574`. Host source archive and unchanged dependency environment are staged alongside the running process; staging does not activate the candidate. [CI39151882820](https://github.com/chotabyorg/voice-gateway-service/actions/runs/39151882820) and 412 native tests passed, with Ruff/format/mypy. Exact-head review has no actionable comments.
- Conversation remains `3f0669156c016cbdcdea53e9a62c0bf15090c686`, image `ghcr.io/chotabyorg/conversation-service:3f0669156c016cbdcdea53e9a62c0bf15090c686@sha256:75d754bfd7cb71ac8b06d5abf8cfae37d0b13c6ae9727cafabddf443fc8a228e`. No Conversation contract, identity/fingerprint compatibility, AI PR82, or Conversation PR23 change is included.

## Resulting behavior

AI requires one bounded, model-authored continuation of CUSTOMER_REUSE_REQUIRED using the returned customer reference before asking to confirm a frozen proposal. It advertises only the required preparation tool and suppresses prose streaming until that continuation validates. Ordinary confirmation and execution guards remain authoritative.

Voice preserves a committed playback POST's acknowledgement and local event sequence under the existing evidence lock before propagating audio-producer cancellation. The existing HTTP deadline bounds the wait. Audio stays revoked; a lost or invalid ACK fails the boundary without a conflicting follow-up fact. The prior source suffix fence remains included.

## Rollout and observed-runtime gate

This document records the candidate, not a completed deployment. At PR creation production still runs AI38f7ceb / Voiceab00bb0 / Conversation3f066915. Full booking and carrier acceptance on this candidate are pending.

Before merging this GitOps PR, close admission for the already authorized single DID, wait for active calls, open call rows, active playback and nonterminal turns to reach zero, and verify that only the SIP control socket remains. Stop Voice only after that fresh drain gate and retain its previous unit/environment for rollback. Merge this PR; ArgoCD alone applies the immutable AI image pins. Require healthy current-image pods, all six relevant Deployments ready, no old pods, and synced Argo applications before starting the exact staged Voice/Conversation pair and activating fresh route evidence on both hosts.

After activation, retain actual pod image IDs, Voice PID/source, readiness, routing evidence and rollout timestamps separately from desired state. Run the real-provider initial-partial interruption plus three presence replies; then one frozen proposal/one consent to CONFIRMED in CRM in text and audio, repeat confirmation without duplicate execution, and cancel only the resulting test bookings. A carrier call is a separate acceptance gate; loopback audio cannot establish telephone-network success.
