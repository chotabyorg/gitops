# Goal5 coordinated release — 2026-10-15

The user authorized completing Goal5 and the Voice/Conversation integration,
including coordinated releases and only the controlled phone +375173820015.
Local verification used native Python/PostgreSQL, with no local Docker.

## Verified inputs

Goal4B prerequisite: GitOps #151, `97a31622c97a445bf6bafa3e913e662fd2867cac`,
Synced/Healthy in Main. Two distinct QA Telegram admissions each produced one
COMPLETED/DRAFT_READY Turn, one canonical assistant Message and one
PROVIDER_ACCEPTED send attempt, zero operation_refs, on 2026-10-15 at 14:17 UTC.
No human-read guarantee is inferred from provider acceptance.

| Service | Merged source | Immutable image digest |
| --- | --- | --- |
| Conversation | d7118849fb7883afb920c71402a3c4b8dcf01845 | sha256:3ab7179ccf1850609e6a9d358e4b840230afec6f9fb574fdd36e538501a53f08 |
| Telegram | a94256b1ce71b21e5337ca3fa98a6e0dc64d83ce | sha256:252f519db3829602eef5211a4a5aae18f2a101b7df53979bd7fd92fffb9392f5 |
| Website | 1284c91c2be665f5acd8d76350e74733e4d03871 | sha256:2f4d2b35f36284db85986427fbf049171f19d02c378512c4d2ccfd5992ffb6fd |

Conversation Goal5 #12 and Voice #13 are merged. Validation: 610 Linux tests,
Ruff/mypy/migrations; native cross-service Website 25 and Telegram 13 pass,
plus two Voice loopback acceptance cases. Gateway suites: Website 111 and
Telegram 76. Exact main publications succeeded; staging branches do not deploy.

## Bounded maintenance sequence

Existing Website transport is not compatible with the Goal5 protocol. Argo apps
reconcile independently, so a single image-only commit cannot guarantee order.
Use three reviewed GitOps phases, never an image rollback across retained state:

1. `pause`: replicas zero for Website, Telegram, Conversation API and both old
   workers. Keep PostgreSQL, identities, all cohorts and secrets unchanged.
   Wait for all five deployments to have zero running/terminating pods. Native
   workers retain their 150-second drain; API has 60 seconds. Capture a private
   custom-format Conversation backup on Main, validate its archive, and retain
   content-free baseline counts/fingerprints. Do not migrate before all stop.
2. `publish`: immutable images above, Conversation API and both workers restored
   to one; gateways remain at zero. API's bounded serialized init migration runs
   0006 and 0007, then workers start at the new schema. Verify schema/readiness,
   preserved canonical history/evidence, no duplicate executions, exact images.
   Voice cohort remains empty and no Voice worker is deployed in this phase.
3. `resume`: restore both gateways to one after phase 2 checks. Preserve the
   existing Website identity and exact QA Telegram cohort. Verify all apps
   Synced/Healthy and perform live QA Telegram acceptance, including no duplicate
   response. Goal5 settling is selected only for that QA integration: 350 ms
   quiet window / 1500 ms maximum, version `goal5-qa-v1`.

If pause fails, remove pause overrides to restore the old matching pair before
migration. If migration or new runtime fails, keep gateways paused and repair
forward using the new schema. Do not downgrade the schema, replay UNKNOWN sends,
restore a stale backup over new events, or remove persisted ownership/fences.
Recovery from the private backup requires another explicit destructive decision.

This release does not prove a real Voice call. Dedicated Voice grants/worker,
private network access, PBX trusted called-DID provenance and the controlled
inbound STT → Conversation → AI → TTS/barge-in/hangup test are separate gates.
