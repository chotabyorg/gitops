# Scoped beauty canary: diagnostic image

This image-only update preserves the existing single-session cohort and every
binding, principal, timeout, schema, migration and terminal/replay rule. It is
not booking acceptance or the required restart proof after a successful booking.

Conversation source [PR 9](https://github.com/chotabyorg/conversation-service/pull/9)
was independently reviewed at `79742757de657f16176f5306ebf62837f8a53cec`.
Merged source `5803e89a5898f8467714831f77bc75661da6d4e4` has an identical tree.
[Quality run](https://github.com/chotabyorg/conversation-service/actions/runs/38142384589)
passed. The manual build-only
[publisher](https://github.com/chotabyorg/conversation-service/actions/runs/38142670409)
published OCI index
`sha256:a6f2f01b30f745e0ba6a179db61e1d987851555fcd6522a3c18346cf9649ab35`,
with Linux amd64 manifest
`sha256:3d86b6d1ea7b480c6c53ade2ceab7a976e5c6b9960c25596601f9b2a620cc97c`.

The image adds finite diagnostic tags only for validated, correlated managed AI
error results and exact known preexecution 401/404 envelopes. It never logs raw
bodies, text, credentials or arbitrary exception strings. It cannot reconstruct
previous errors, explain every transport ambiguity or clear retained UNKNOWN.

Before promotion, independently review the exact rendered image-only delta and
refresh read-only evidence: no pending/claimed or dispatched work, no unmapped
managed admissions, and no unfinished Business operations. Keep synthetic sends
paused. Existing quiescence evidence combined stable records, no active database
transactions or worker-to-AI sockets, and the joined response lifecycle; elapsed
time alone is insufficient.

After Argo applies this update, verify the exact image, API and worker readiness,
migration `0004_website_history`, unchanged exact cohort/bindings and identical
retained IDs, statuses, request/projection fingerprints and counts. Preserve the
failed confirmation and terminal EXECUTION_UNKNOWN. Any fresh model experiment
requires a separate review; this update authorizes no replay or new message.

The previous compatible diagnostic rollback image remains
`ghcr.io/chotabyorg/conversation-service:cf95c23c7a4b0e71f9bb1a54136d6675cf8171d1@sha256:0905aac9eba294466b94e1aaabae5fd45597a6c610a5f335710a9c57863f45da`.
Any rollback follows reviewed GitOps and preserves database evidence. No schema
downgrade or old managed-message replay through legacy AI is permitted.
