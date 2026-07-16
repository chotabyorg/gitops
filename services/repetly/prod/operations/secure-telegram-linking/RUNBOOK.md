# Secure Telegram linking maintenance rollout

This runbook is the operational companion to Repetly issue #75 and application
PR #74. These files live below the active Kustomize load root so an execution
change can reference them without `--load-restrictor` exceptions. They remain
deliberately **inert** because `services/repetly/prod/kustomization.yaml` does
not reference them. Merging this operational PR alone must not scale the
application, run a migration, change traffic, or mutate a Secret.

The execution workflow has four separately reviewed Git desired states:

1. **STOP** — close Service traffic, scale Repetly to zero, and prove drain.
2. **MIGRATE** — keep traffic closed and replicas at zero; run one exact-release
   migration Job.
3. **RESUME-CLOSED** — start the schema-compatible app while the Service still
   has no matching endpoints; perform direct, approved smoke tests.
4. **OPEN** — remove the Service traffic gate only after smoke passes.

Do not combine states, use selective sync, manually scale the live Deployment,
or apply these templates with `kubectl`. Argo CD auto-sync and self-heal make Git
the only durable deployment control.

## Preconditions and hard stops

- PR #74 must remain unmodified and unmerged until its owner separately
  authorizes execution. The reviewed commit is
  `6cb8a891911d1c194ff7792790689d882b69cf0e`. The short value `6cb8a89`
  is only a human-readable release identifier inside the Job name; it is not an
  executable image reference. The initial Job identity is
  `repetly-telegram-linking-migrate-6cb8a89-a1`, where `a1` is the reviewed
  attempt number.
- Every active Repetly workload image must use
  `ghcr.io/chotabyorg/repetly@sha256:<64 lowercase hex>`. Tag-only references,
  mutable tags, and tag-plus-digest references are forbidden. The real target
  digest is unavailable until the reviewed image is published. The inert Job
  and release-identity patch therefore contain an all-zero digest sentinel.
  That sentinel is intentionally non-executable and must never appear in an
  active render.
- Before each execution change, independently obtain and verify the registry
  digest against the intended image. Do not infer a digest from the commit or
  tag. In MIGRATE, RESUME-CLOSED, and OPEN, replace the sentinel in the
  release-identity patch; in MIGRATE also replace it in both Job fields. Replace
  the active `images[].newTag` with `images[].digest`. The rendered Deployment
  init container, application container, Job, and release annotations must all
  agree on the same verified target digest.
- A fresh, approved database backup and tested restore procedure must be
  evidenced before STOP. This repository does not currently prove either one;
  their absence blocks execution, not review of these inert templates.
- Record the reviewed application commit, immutable image digest, GitOps
  commit, Argo revision, and sanitized timestamps. Never paste credentials,
  Telegram identifiers, tokens, hashes, emails, user IDs, raw DB rows, or Secret
  values into Git, GitHub, commands, or logs.
- Run the reviewed aggregate-only preflight from the exact PR #74 commit before
  STOP. A false final column is a hard failure even when SQL execution itself
  exits zero.
- Any failed guard, missing backup evidence, unexpected writer, mutable image,
  or unverifiable state is a stop condition.

### Owner-approved downtime window

STOP through successful OPEN is one planned downtime window. The owner must
approve it before STOP merges. Record the approved start, maximum duration,
hard deadline, and escalation route in the authorized operations system without
putting contact credentials or sensitive details in GitHub.

The window starts when Argo applies the wave-0 Service gate and ends only when
OPEN is Synced/Healthy with a ready endpoint. At the hard deadline, do not
reopen traffic or bypass a failed check: keep the Service closed, preserve
evidence, and escalate through the approved route. Extending the window requires
fresh owner approval. Each state transition must include an elapsed-time check
against the approved deadline.

### Safe SQL connection contract

`sql-boolean-guard.sh` deliberately rejects Prisma `DATABASE_URL`: its
`?schema=...` query parameter is not accepted by libpq, and passing a connection
URL would expose credentials in process arguments. Inject either `PGSERVICE` or
`PGHOST`, `PGDATABASE`, and `PGUSER` through the approved operator-session
mechanism. Supply authentication through the approved libpq mechanism; do not
put it in arguments, shell history, repository files, issue comments, or logs.

The operator must also set `APP_DB_SCHEMA` to the safe lowercase identifier
reviewed in the exact Prisma connection contract. If the approved Prisma URL
omits `schema`, its reviewed value is Prisma's PostgreSQL default, `public`.
Do not infer or change this value during the maintenance window. The guard
rejects a missing, mixed-case, qualified, system, or syntactically unsafe
identifier. It sets `PGOPTIONS` to that schema plus `pg_catalog`, passes the same
value as the quoted psql `app_schema` variable, and fails unless the schema
exists and is `current_schema()`. This binds the unqualified reviewed preflight
to the same schema. The postflight additionally sets the transaction-local
search path and schema-qualifies the application tables.

The invocation contains no connection value or credential:

```text
APP_DB_SCHEMA=approved_schema_identifier \
  ./sql-boolean-guard.sh /approved/path/telegram-linking-preflight.sql
```

Use the same `APP_DB_SCHEMA` for the post-drain preflight and postflight. The
wrapper suppresses query output and emits only a generic pass/fail line.

## 1. STOP

1. Before editing the active overlay, run `validate.sh` to prove the shipped
   state templates are internally consistent and production remains untouched.
2. Open a dedicated execution change that **adds** these two patch entries to
   the existing `patches` list in `services/repetly/prod/kustomization.yaml`:

   ```diff
    patches:
      # keep every existing entry
   +  - path: operations/secure-telegram-linking/stop/service-traffic-closed-patch.yaml
   +  - path: operations/secure-telegram-linking/stop/replicas-zero-patch.yaml
   ```

3. In the same STOP change, replace the active tag with the independently
   verified digest of the currently deployed image. Do not use the unavailable
   target digest and do not add the target release-identity patch yet.
4. Render and schema-validate the exact active production overlay with
   `validate.sh --execution-stage STOP`. The runtime changes must be a
   non-matching selector on the Repetly Service, Repetly desired replicas
   changing from one to zero, and tag-to-equivalent-digest pinning. PostgreSQL,
   MinIO, Secrets, PVCs, and configuration remain present.
5. Confirm the owner-approved downtime window is open, record its deadline, then
   merge through normal approval and wait for a full Argo sync. Selective sync
   is forbidden.

   The full sync ordering is important: the Service gate is ordinary wave 0;
   the existing `repetly-minio-bootstrap` Sync hook reruns at wave 1; and the
   Repetly Deployment scales to zero at wave 2. If the MinIO hook fails, traffic
   is already closed but Argo stops before the Deployment drain. Keep traffic
   closed, resolve the hook failure, and do not claim zero writers or run the
   post-drain preflight until wave 2 completes. A selective sync can skip hooks
   and invalidates this ordering proof.
6. Prove from sanitized aggregate status that desired/current/ready Repetly
   replicas are zero, no Repetly pod remains, the Service has no ready
   endpoints, in-flight requests drained, and no worker, CronJob, admin route,
   or external process can change Telegram connection state.
7. Reconfirm backup/restore evidence, elapsed time against the downtime
   deadline, and repeat the aggregate preflight after drain. A non-canonical
   verdict or anything other than exactly one aggregate row ending in `t`
   blocks MIGRATE.

Scale-to-zero closes every current linking-state writer:
issue/replace/reconnect/cancel/disconnect and webhook claim. The existing
scheduler only reads linked destinations.

## 2. MIGRATE

This state requires a separately authorized merge of the unchanged PR #74 while
Repetly remains at zero. Its CI may add or update a short tag in the active
GitOps image entry, but zero replicas and the closed Service prevent application
startup. That CI-generated tag is not accepted for MIGRATE: the execution change
must remove `newTag` and pin the verified target `digest`.

The reusable application CI writes `newTag`; it does not remove the STOP
`digest`. Immediately after PR #74 CI, Kustomize may therefore render a
temporary tag-plus-old-digest image identity. This mixed state is permitted
**only** while the already-synced STOP state is still proven drained: replicas
remain zero, the Service gate remains closed, and no Repetly pod exists. Do not
run the migration Job, RESUME-CLOSED, OPEN, or any workload from that transient
render. The MIGRATE execution change must remove `newTag`, replace the old
digest with the independently verified target digest, and pass the digest-only
execution validator before the Job is allowed into Git desired state.

1. Independently resolve the published image for commit
   `6cb8a891911d1c194ff7792790689d882b69cf0e` to a nonzero SHA-256 digest.
   Verify the registry evidence through the approved mechanism.
2. Open a new execution change that keeps both STOP patches, replaces the
   all-zero sentinel in `migration-job.yaml` and
   `release-identity-patch.yaml`, pins the active Repetly image by that digest,
   adds the release-identity patch, and appends the migration Job:

   ```diff
    resources:
      # keep every existing base, MinIO, PVC, Service, and SealedSecret entry
   +  - operations/secure-telegram-linking/migrate/migration-job.yaml
    patches:
      # keep the wave and STOP entries
   +  - path: operations/secure-telegram-linking/release-identity-patch.yaml
   ```

3. Render and schema-validate the exact active production overlay. Verify zero
   replicas, the closed Service selector, namespace `prod`, and the same exact
   digest on both Deployment containers, the Job, and release annotations.
   `validate.sh --execution-stage MIGRATE` rejects tag-only images, a zero
   sentinel, mismatch, or malformed digest. The Job must remain ordinary, not an
   Argo hook; release-and-attempt-specific; `restartPolicy: Never`;
   `backoffLimit: 0`; deadline bounded; and retained for evidence. The
   `metadata.name` suffix `-a1` and
   `repetly.chota.by/migration-attempt: "1"` must agree. It receives only the
   existing `DATABASE_URL` Secret key and no service-account token.
4. Merge through normal approval. The Job's wave 3 is defense in depth, not a
   substitute for the already completed STOP and drain proof.
5. Wait for the one named Job to reach `Complete`. Never automatically retry,
   delete, mutate, or reuse a failed Job. Capture only sanitized status,
   termination reason, timestamps, image identity, and migration names.
6. Run `postflight.sql` through `sql-boolean-guard.sh` with the exact same
   reviewed `APP_DB_SCHEMA`. Its PostgreSQL 18 contract verifies the three
   Prisma migrations; exact definitions for all ten validated CHECK
   constraints; exact type/typmod/nullability/default for all seven new columns;
   the exact schema, labels, and order of `TelegramLinkPurpose`; exact
   schema/name/column structure for three unique/ready/valid btree indexes with
   ordinary NULL semantics; absence of known plaintext-token columns; and
   aggregate integrity counts including linked timestamps before user creation.
   A non-true verdict blocks RESUME-CLOSED.

## 3. RESUME-CLOSED

Only a documented Job and postflight PASS permits this state.

1. Capture retained Job evidence.
2. Open a third reviewed execution change that removes the migration Job and
   replicas-zero patch, keeps the verified digest and release-identity patch,
   and replaces the STOP gate with the RESUME-CLOSED gate:

   ```diff
    patches:
      # keep every unrelated existing entry
   +  - path: operations/secure-telegram-linking/release-identity-patch.yaml
   +  - path: operations/secure-telegram-linking/resume-closed/service-traffic-closed-patch.yaml
   ```

3. Render and schema-validate the active production overlay against the
   `resume-closed` contract with
   `validate.sh --execution-stage RESUME-CLOSED`: one replica, the verified
   target digest on both containers and release annotation, no migration Job,
   and exactly one non-matching Service selector gate.
4. Merge and wait for Argo Synced/Healthy and the pod Ready. The init container's
   repeated `prisma migrate deploy` must be an idempotent no-op. The Service must
   still have zero ready endpoints, so public traffic and Telegram webhook
   traffic remain closed.
5. Use only the approved direct-to-pod diagnostic path for schema-aware health
   and isolated Telegram-linking smoke tests. Confirm sanitized logs and metrics.
   Any failure returns the Deployment to zero through a reviewed Git change;
   never reopen traffic or start the old image.

## 4. OPEN

1. After RESUME-CLOSED smoke passes, open a fourth reviewed execution change
   that removes the maintenance Service patch, retains the digest and
   release-identity patch, and changes nothing else.
2. Render and schema-validate with `validate.sh --execution-stage OPEN`: one
   replica, the verified target digest, matching release annotation, no
   migration Job, and no maintenance selector.
3. Merge, wait for Argo Synced/Healthy and a ready Service endpoint, then perform
   approved external health/linking checks and observe sanitized logs/metrics.
4. Keep issue #75 in Ready for Review until the owner separately accepts the
   operational work. This runbook does not authorize merging PR #74 or any
   execution PR.

## Failure and recovery contract

- **Before the migration Job starts:** if the database is proven unchanged, the
  prior image may be restored under normal review while traffic stays closed.
- **From the moment the Job starts:** never start the old image. Prisma's
  PostgreSQL migrations are not fully atomic, and the first migration
  irreversibly revokes unused legacy tokens. Keep traffic closed and use a
  schema-compatible forward fix.
- **Failed main migration:** retain the failed Job and sanitized evidence. Do not
  bypass preflight or mark a migration applied without proving its effects.
- **Interrupted concurrent index:** inspect only the known index name and
  aggregate catalog state. For an invalid index, keep maintenance active, use
  the approved concurrent-index removal path, mark only the corresponding
  Prisma migration rolled back, repeat preflight, and create a new
  release-specific Job. A valid index with an incomplete migration record
  requires review of the exact structural definition before deliberate resolve.
- **Job succeeded but postflight failed:** do not resume. Preserve evidence and
  diagnose under maintenance.
- **RESUME-CLOSED fails:** return to zero replicas through Git; do not open the
  Service and do not roll back to the old image.
- **Database restore:** emergency-only with the tested procedure. Repeat the
  complete safe sequence; restored unused legacy tokens must not silently become
  usable.

Every retry requires a new reviewed Git change and a new attempt identity. First
capture the retained failed Job evidence. Then change both
`metadata.name` from the prior safe suffix `-aN` to `-a(N+1)` and
`repetly.chota.by/migration-attempt` from `"N"` to `"N+1"` in the same reviewed
execution change. The old Job name must leave Git desired state as the new name
enters it, so exactly one secure-linking migration Job remains declared. Do not
edit a live Job in place, reuse a prior name, keep two attempt resources, or
skip an attempt. `validate.sh` derives the expected safe
`repetly-telegram-linking-migrate-6cb8a89-aN` identity from the manifest,
requires the annotation to match, and compares it with at most one prior
operation-annotated Job in `origin/main`. With no prior Job, only `a1` is
accepted. With prior `aN`, the validator removes that inventory key, requires
exactly `a(N+1)`, and rejects skipped, mismatched, wrong-release, or duplicate
attempts. Inert validation also simulates the successful replacement and those
failure cases. No retry is automatic.

## Local validation

From the GitOps repository root, before activating any state:

```text
services/repetly/prod/operations/secure-telegram-linking/validate.sh
```

The no-argument mode builds temporary exact copies of the active production
kustomization for STOP, MIGRATE, RESUME-CLOSED, and OPEN with standard Kustomize
load restrictions. It leaves the real active overlay untouched. The validator
requires `kubectl`, Git, tar, Bash, and Ruby with its standard YAML library.

For each execution change, first fetch the current base and ensure the branch is
based on the intended `origin/main`, then run the matching
`--execution-stage` mode against the actual active overlay. Execution validation
renders `origin/main` as the baseline and compares normalized resource
inventories. It permits only the stage-specific Repetly Service, Deployment,
and migration Job changes; every other resource must remain structurally
identical. Missing MinIO, PostgreSQL, PVC, ConfigMap, Service, Deployment, hook,
or SealedSecret resources fail validation before Argo prune can act.

Separately schema-validate the render, run shell lint and secret scanning, and
run `git diff --check`. Validation is local and must not contact or mutate
production.
