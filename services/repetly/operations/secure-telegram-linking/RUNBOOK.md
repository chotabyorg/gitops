# Secure Telegram linking maintenance rollout

This runbook is the operational companion to Repetly issue #75 and application
PR #74. These files are deliberately **inert**: Argo CD watches
`services/repetly/prod`, and that active kustomization does not reference this
directory. Merging this operational PR alone must not scale the application, run
a migration, change traffic, or mutate a Secret.

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
  `6cb8a891911d1c194ff7792790689d882b69cf0e`; the expected image tag is
  `6cb8a89`.
- A fresh, approved database backup and tested restore procedure must be
  evidenced before STOP. This repository does not currently prove either one;
  their absence blocks execution, not review of these inert templates.
- Record the reviewed application commit, immutable image tag/digest, GitOps
  commit, Argo revision, and sanitized timestamps. Never paste credentials,
  Telegram identifiers, tokens, hashes, emails, user IDs, raw DB rows, or Secret
  values into Git, GitHub, commands, or logs.
- Run the reviewed aggregate-only preflight from the exact PR #74 commit before
  STOP. A false final column is a hard failure even when SQL execution itself
  exits zero.
- Any failed guard, missing backup evidence, unexpected writer, mutable image,
  or unverifiable state is a stop condition.

### Safe SQL connection contract

`sql-boolean-guard.sh` deliberately rejects Prisma `DATABASE_URL`: its
`?schema=...` query parameter is not accepted by libpq, and passing a connection
URL would expose credentials in process arguments. Inject either `PGSERVICE` or
`PGHOST`, `PGDATABASE`, and `PGUSER` through the approved operator-session
mechanism. Supply authentication through the approved libpq mechanism; do not
put it in arguments, shell history, repository files, issue comments, or logs.

The invocation contains no connection value:

```text
./sql-boolean-guard.sh /approved/path/telegram-linking-preflight.sql
```

The wrapper suppresses query output and emits only a generic pass/fail line.

## 1. STOP

1. Before editing the active overlay, run `validate.sh` to prove the shipped
   state templates are internally consistent and production remains untouched.
2. Open a dedicated execution change that **adds** these two patch entries to
   the existing `patches` list in `services/repetly/prod/kustomization.yaml`:

   ```diff
    patches:
      # keep every existing entry
   +  - path: ../operations/secure-telegram-linking/stop/service-traffic-closed-patch.yaml
   +  - path: ../operations/secure-telegram-linking/stop/replicas-zero-patch.yaml
   ```

3. Render and schema-validate the exact active production overlay. The only
   runtime changes must be a non-matching selector on the Repetly Service and
   Repetly desired replicas changing from one to zero. PostgreSQL, MinIO,
   Secrets, PVCs, and configuration remain present.
4. Merge through normal approval and wait for a full Argo sync. Selective sync
   is forbidden.
5. Prove from sanitized aggregate status that desired/current/ready Repetly
   replicas are zero, no Repetly pod remains, the Service has no ready
   endpoints, in-flight requests drained, and no worker, CronJob, admin route,
   or external process can change Telegram connection state.
6. Reconfirm backup/restore evidence and repeat the aggregate preflight after
   drain. A non-true verdict blocks MIGRATE.

Scale-to-zero closes every current linking-state writer:
issue/replace/reconnect/cancel/disconnect and webhook claim. The existing
scheduler only reads linked destinations.

## 2. MIGRATE

This state requires a separately authorized merge of the unchanged PR #74 while
Repetly remains at zero. Its CI updates the active production image tag without
starting an application pod.

1. Confirm the immutable image for commit
   `6cb8a891911d1c194ff7792790689d882b69cf0e` exists as tag `6cb8a89`. Confirm
   the active production image, Job name suffix, Job annotations, and validation
   overlay all identify that same release.
2. Open a new execution change that keeps both STOP patches and **appends only**
   the migration Job to the existing resources list:

   ```diff
    resources:
      # keep every existing base, MinIO, PVC, Service, and SealedSecret entry
   +  - ../operations/secure-telegram-linking/migrate/migration-job.yaml
   ```

3. Render and schema-validate the exact active production overlay. Verify zero
   replicas, the closed Service selector, namespace `prod`, and the same exact
   image on the Deployment and Job. The Job must remain ordinary, not an Argo
   hook; release-specific; `restartPolicy: Never`; `backoffLimit: 0`; deadline
   bounded; and retained for evidence. It receives only the existing
   `DATABASE_URL` Secret key and no service-account token.
4. Merge through normal approval. The Job's wave 3 is defense in depth, not a
   substitute for the already completed STOP and drain proof.
5. Wait for the one named Job to reach `Complete`. Never automatically retry,
   delete, mutate, or reuse a failed Job. Capture only sanitized status,
   termination reason, timestamps, image identity, and migration names.
6. Run `postflight.sql` through `sql-boolean-guard.sh`. It verifies the three
   Prisma migrations, ten validated constraints, exact schema/name/column
   structure for three unique/ready/valid btree indexes with ordinary NULL
   semantics, absence of known plaintext-token columns, and aggregate integrity
   counts. A non-true verdict blocks RESUME-CLOSED.

## 3. RESUME-CLOSED

Only a documented Job and postflight PASS permits this state.

1. Capture retained Job evidence.
2. Open a third reviewed execution change that removes the migration Job and
   both STOP patch entries, then adds only:

   ```diff
    patches:
      # keep every unrelated existing entry
   +  - path: ../operations/secure-telegram-linking/resume-closed/service-traffic-closed-patch.yaml
   ```

3. Render and schema-validate the active production overlay against the
   `resume-closed` contract: one replica, exact image `6cb8a89`, no migration
   Job, and exactly one non-matching Service selector gate.
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
   that removes the maintenance Service patch and changes nothing else.
2. Render and schema-validate against `open`: one replica, exact image
   `6cb8a89`, no migration Job, and no maintenance selector.
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

Every retry requires a new reviewed Git change and Job name. No retry is
automatic, and no failed Job is edited in place.

## Local validation

From the GitOps repository root, before activating any state:

```text
services/repetly/operations/secure-telegram-linking/validate.sh
```

For each execution change, separately render and schema-validate the exact
active `services/repetly/prod` overlay, run shell lint and secret scanning, and
run `git diff --check`. Validation is local and must not contact or mutate
production.
