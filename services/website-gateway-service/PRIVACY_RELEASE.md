# Goal 4A default-legacy credential privacy release

This v2 exact release candidate is based on the **prospective frozen storage-proof
source tree** `a1750930ad32dca263c3e1b270c3402401240e9e`, branch
`codex/goal4a-conversation-storage-proof` ([PR #115](https://github.com/chotabyorg/gitops/pull/115)).
That parent is a reviewed conditional candidate, not a claim of current Main or
successful native persistence. The original dark Main merge
`f30e256493cc644c6e8e755446aaf121db248fb1` ([PR #112](https://github.com/chotabyorg/gitops/pull/112))
failed native storage verification: the image volume shadowed its parent PVC mount.
The separately reviewed Stage 1 correction source
`3a851eb9d734ddd720531df718e44d791c1f2751` merged as
`caddbafeb23a3cc580ccc861f873f04b9f94de8b`
([PR #114](https://github.com/chotabyorg/gitops/pull/114)). Both Stage 1 native PASS
and a different verifier's Stage 2 native persistence PASS remain mandatory gates.
It changes Website and Control Plane images and explicitly sets both Website
routing mappings to `{}`. It records candidate inputs, not live deployment or
approval. The v1 privacy candidate was HELD at the failed dark-storage gate and
received no release CLEAN; its successful offline checks are not approval for v2.
Both finite native storage gates and a fresh independent complete v2 exact release
CLEAN are required before this candidate can merge to GitOps main. See the
[storage correction and finite proof](../conversation-service/STORAGE-FIX.md).

## Immutable image inputs

| Component | Reviewed source head | Source main merge / publication tag | Published OCI index |
| --- | --- | --- | --- |
| Website | `a7016b9ea271e376f824943e0c2e9b3ed58b91ca` | `d9e1622475a7d39e2a521f1c2487a384171f4e73` / `d9e1622` ([source PR #15](https://github.com/chotabyorg/website-gateway-service/pull/15)) | `sha256:aa6f8cae622a38bffcde08d788fa6de91737e1cce803263a43f1a836d686ff09` |
| Control Plane | `9d74b4b720142171d839d5d8facd9ce08fac306c` | `79b720e6428da94d2e2598376d8706f4977d15aa` / `79b720e` ([source PR #22](https://github.com/chotabyorg/control-plane-service/pull/22)) | `sha256:7041035f6454e3bed3114a6c79610bd0e9444288238eacc17381680a2030f038` |

The published linux/amd64 children are Website
`sha256:10ce64eade5551ed3db28f5f068a8e0781e7714a9f984a1e2174fb654120fad2`
and Control Plane
`sha256:1f603278c2ffcfbd678f00bfbec038f21798d58c88587e0543bcbbd397f08b31`.
Source merge trees equal their reviewed heads. Completed source publication runs
are [Website 37842342145](https://github.com/chotabyorg/website-gateway-service/actions/runs/37842342145)
and [Control Plane 37842352965](https://github.com/chotabyorg/control-plane-service/actions/runs/37842352965).
They stage only on `releases/website-gateway-service` and
`releases/control-plane-service`; Main Argo watches GitOps `main`.
The shared publisher workflow is unchanged. This release copies the two exact
image references instead of merging either staging branch wholesale.

Published artifact verification compared all packaged runtime files to reviewed
source and passed the Website 96-test suite and Control Plane 117-test suite in
disposable offline containers. The first emulated Control Plane run had 116 passes
and one fixed 10-second INFO process-startup gate failure; an unchanged full rerun
passed 117. Runtime dependency versions were preserved. Those local checks do not
establish native production startup or logging protection.

## Exact stage and migration

`MANAGED_WEBSITE_GUARDED_INTEGRATIONS={}` and `MANAGED_WEBSITE_COHORTS={}` retain
100% legacy routing for the demo and every other integration. No Conversation
URL, S2S reference, seal, binding or cohort is added. Conversation remains at the
reviewed dark state: API 1, PostgreSQL 1, worker 0, `WEBSITE_BINDINGS=[]`, both worker
flags false. Its storage mapping and API/PG proof annotations are unchanged from
the exact prospective Stage 2 parent: retained PVC at `/var/lib/postgresql/data`,
`PGDATA=/var/lib/postgresql/data/pgdata`, API layout stamp `pvc-data-v1`, and both
API/PG `storage-persistence-proof: recreate-v1` annotations. This privacy diff
neither changes nor performs either storage stage. AI image, Business settings, credentials, providers and PostSync
hook are unchanged. Existing service ports/selectors, probes, secret references,
Control Plane Voice services and Website configuration/CORS are preserved.

Control Plane migrations, models, database module, requirements and Alembic
configuration are byte-identical to currently deployed source
`96a4b40daeb113f435f5cd02a6f7a2fc12502b24`. The existing initContainer still uses
the same application image and runs `alembic upgrade head`; the graph remains
`0001_initial` → `0002_website_widget` → `0003_voice`. It introduces no new migration
or database downgrade. Current schema head must be confirmed read-only at the
fresh release preflight and after reconciliation. The new Control Plane image's
actual Docker CMD includes `--no-access-log`; this overlay has no command/args
override. Website starts its reviewed AppRunner with `access_log=None`.

Author verification rendered all 24 production overlays and compared every
canonical resource to the exact prospective Stage 2 parent. Only the two service
image substitutions and explicit empty Website fields change rendered production
resources; ConfigMap hashing updates its Deployment reference as expected. The
original 14 operations tests and actual `--stage dark` check passed, but
`--fixture` failed because its helper appended duplicate routing keys. That
accepted Important validation finding was fixed in a separate context: the
temporary fixture now upserts only default-overlay keys, preserves unrelated
Website properties and leaves source configuration bytes unchanged. Seven new
regressions exercise real fixture trees and Kustomize rendering for missing,
empty, configured, duplicate/indented/BOM and distinct-key inputs. They retain
synthetic seal markers and actual-release rejection, and prove actual nonempty
routing is still rejected. All 21 tests, actual `--stage dark`, `--fixture`, all
24 actual overlays and whitespace checks pass. Running the new regressions with
the original helper fails, retaining direct evidence of the defect. The bounded
privacy diff now includes only these two operations files in addition to its
original four files. This fix establishes no release CLEAN or native PASS; a new
complete source and exact privacy release review is required.

## Required release and runtime gates

1. Independently finish both finite storage stages on Main `chota.by`, node
   `153.80.244.178`, context `default`, namespace `prod` UID
   `84409e45-1c54-4893-bf30-d353a55acb47`, kube-system UID
   `a90ac8e6-6a20-46d2-8af8-ee4580edeaa0`. Stage 1 must prove corrected native PVC
   mapping without image-volume shadow, retained PV/PVC/file identity, the fresh
   database system identifier, schema, readiness, zero domain census and disabled
   admission. Only after Stage 1 PASS may the frozen Stage 2 be promoted. A different
   fresh native verifier must then prove both PG/API pod UIDs replaced while that
   same Stage 1 system identifier, PV/PVC/file inodes and schema survive, and recheck
   native hardening, effective policies, private exposure and existing services.
   Any failure or uncertainty holds this privacy candidate. Storage source/release
   CLEAN does not establish either native PASS or approve this privacy promotion.
   Refresh identity, current images, zero-admission state and Argo revision before
   promotion. A document or image tag is not live proof.
2. Review the complete exact GitOps candidate and actual immutable artifacts;
   require fresh complete v2 CLEAN before merging. Initially its draft PR targets
   the frozen Stage 2 branch. Retarget the same frozen privacy head to `main` only
   after the Stage 2 merge tree equals the reviewed prospective parent; do not rebase
   or change a reviewed head. New parent/tree/runtime drift requires reevaluation.
   Argo is the deployment authority. Render
   every prod overlay and run the Conversation validator with
   `--stage dark`; here it checks empty routing and retained dark infrastructure,
   not approval of image provenance or credential privacy.
3. After Argo reconciliation, prove both Applications Synced/Healthy, ready pods,
   exact OCI image identity and actual entry points in every relevant ready
   process, successful unchanged CP migration, and healthy Website polling with
   empty routing. Verify Conversation/AI state still matches the baseline.
4. Before any real widget-key resolution or use, a fresh verifier must prove
   deployed credential-safe logging through synthetic query/header/config/proof
   sentinels at INFO and DEBUG, normal and failure paths, dependency descendants,
   supported reconfiguration and actual server/output sinks. Include every
   credential-observing proxy in the real public and CP path. Do not print or save
   matching raw production log lines; return only safe counts and booleans.
   Source/local fixture tests alone cannot discharge this gate.
5. Real-key binding, dedicated S2S activation, worker enabling, technical cohort
   and no-business smoke remain separate reviewed gates in
   [Conversation RELEASE.md](../conversation-service/RELEASE.md). The current demo
   agent has active CRM capabilities including writes. A harmless prompt is not
   proof of smoke safety; this release does not approve disabling Business,
   rebinding CRM, using an alternate topology, provider access or a model call.

No real widget credential, customer test message, AI/provider smoke, frontend
change, ordinary-demo cutover, Voice-cluster action or Goal 4B action belongs to
this stage.

## Abort and recovery

If either native storage stage fails or remains uncertain, do not promote this candidate. If reconciliation,
readiness, migration, provenance or deployed logging proof fails, stop subsequent
stages and real credential use. Diagnose safely and submit a bounded forward fix
through GitOps with a fresh complete review. Retain Conversation/PVC/seals and
existing credentials; do not manually apply resources, rotate secrets, downgrade
databases or change Business/CNI/controller infrastructure to bypass a gate.
Both Website routing mappings remain empty, so this stage admits no managed work.
Any future activated stage must retain the sticky-admission image, guards and
journal during routing rollback: **already accepted managed messages are never
replayed through legacy AI.**
