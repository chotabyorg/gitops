# Goal 4A default-legacy credential privacy release

This is a separate exact release candidate based on Main GitOps dark merge
`f30e256493cc644c6e8e755446aaf121db248fb1` ([PR #112](https://github.com/chotabyorg/gitops/pull/112)).
It changes Website and Control Plane images and explicitly sets both Website
routing mappings to `{}`. It records candidate inputs, not live deployment or
approval. Complete native Main dark verification and a fresh independent exact
release CLEAN are required before this candidate can merge to GitOps main.

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
flags false. AI image, Business settings, credentials, providers and PostSync
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

## Required release and runtime gates

1. Independently finish native dark verification on Main `chota.by`, node
   `153.80.244.178`, context `default`, namespace `prod` UID
   `84409e45-1c54-4893-bf30-d353a55acb47`, kube-system UID
   `a90ac8e6-6a20-46d2-8af8-ee4580edeaa0`. Refresh identity, current images and Argo
   state before promotion. A document or image tag is not live proof.
2. Review the complete exact GitOps candidate and actual immutable artifacts;
   require fresh CLEAN before merging. Argo is the deployment authority. Render
   every prod overlay and run the unchanged Conversation validator with
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

If native dark checks fail, do not promote this candidate. If reconciliation,
readiness, migration, provenance or deployed logging proof fails, stop subsequent
stages and real credential use. Diagnose safely and submit a bounded forward fix
through GitOps with a fresh complete review. Retain Conversation/PVC/seals and
existing credentials; do not manually apply resources, rotate secrets, downgrade
databases or change Business/CNI/controller infrastructure to bypass a gate.
Both Website routing mappings remain empty, so this stage admits no managed work.
Any future activated stage must retain the sticky-admission image, guards and
journal during routing rollback: **already accepted managed messages are never
replayed through legacy AI.**
