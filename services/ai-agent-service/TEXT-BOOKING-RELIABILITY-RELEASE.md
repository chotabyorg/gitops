# Text booking recovery release

Pin AI PR92 merge `9190fbbdade3b2f71ff7d240ee4740d55a5346af`, tree
`78bfca319f94513b2df78496d80f9caaaf623c4d`, to OCI digest
`sha256:6e9ecfceba0d1d4c5d3ceab6d9ad3b5ba1016966ba5f053c19a40f361fc8ecbe`.

Buffered non-Voice model requests can retry once on selected 5xx responses,
within their original deadline and after rechecking execution authority. CRM
effects are not retried by this change. Malformed proposal-tool arguments can
receive one bounded pre-dispatch correction, and the model cannot choose a
decision tool without a pending proposal. Existing confirmation, result and
replay guards remain enforced.

Verification: all four Linux native CI shards (run 39163675150), full
PostgreSQL/migration Quality run 39163675175, exact-head review at `0c981bd`,
and build 39165062458 passed. The merged source tree equals the reviewed tree.
Kustomize renders three changed AI image references; all other rendered
resources are structurally identical. Local Windows socket fault tests have
an existing failure reproduced on unchanged main; Linux native CI passed.

The own-number admission was closed at 20:48:59 UTC on 2026-10-18; fresh drain
at 20:49:14 UTC found zero active calls, open call rows, active playback
responses and nonterminal turns. Recheck drain immediately before merging
this GitOps release. ArgoCD is the only manifest deployment mechanism. Verify
the running image digest, six relevant deployments and Argo health/sync
before reopening admission. Voice must retain PID 2368232 and revision
`da3eeda9f6221bbe30555c68ad7ea2939f8ab52d`; Conversation remains
`3f0669156c016cbdcdea53e9a62c0bf15090c686`.

Post-deployment acceptance is pending: public widget proposal before consent,
CRM CONFIRMED after consent, same-message replay without another write, cancel
proposal and consent, CRM CANCELLED, repeated cancellation without another
effect. Synthetic tests are not substitutes for this acceptance. Current
telephone-carrier acceptance remains deferred by the user.

Rollback: close admission, wait for the same zero-activity gates, revert the
AI image pin to `253e98d` and digest
`sha256:3368dbadfc7b275216c84f9539aadd67a477a48caea500a63a4d484adc9b4601`
through a reviewed GitOps change, and verify Argo/runtime provenance before
restoring the previous verified route evidence. Never blindly repeat a CRM
effect with an uncertain result.

AI PR82, Conversation PR23, request identity, fingerprint and wire-profile
contracts are excluded. Text parallel-tool selection remains disabled because
the fictional exploratory probe did not establish a reliable improvement.
