# ChotaCRM deployment

Complete v0.1 production overlay for `chota-crm-service`, its dedicated PostgreSQL 18.6 database and daily local backups. The frontend is in `../chota-crm-web`; public traffic reaches the API only through the existing gateway. [Release provenance and rollout](RELEASE.md) records the source/image boundary, capacity and acceptance gates. [Backup and recovery](operations/BACKUP.md) is the operating procedure.

## Configuration and isolation

- `prod/config.properties`: exact CRM Origin, internal user-service URL, 3-second identity timeout, email-verification policy false. CRM verifies the access cookie against identity; no JWT signing secret is copied.
- `prod/postgres.properties`: dedicated `chotacrm` database/user, PG18 data directory `/var/lib/postgresql/18/docker`. The 4Gi `chota-crm-service-postgres-data` PVC mounts its parent `/var/lib/postgresql`. No public DB port.
- `prod/sealed-secrets.yaml`: only strict-scope encrypted `POSTGRES_PASSWORD` and matching async `DATABASE_URL`, bound to `prod/chota-crm-service-secret`. Never generate a replacement during redeploy: PostgreSQL initialization does not rotate an existing database password. Rotation is a separate reviewed database/Secret procedure.
- API/PG/component labels are generated in separate base Kustomizations. Their Deployment and Service selectors are disjoint. NetworkPolicies affect only CRM pods: gateway → API; API → PG/user-service/DNS; backup → PG/DNS. PG accepts API/migration and backup only. Node-local kubelet probes remain allowed by Kubernetes policy semantics.
- API runs as 10001, PostgreSQL/backup as Alpine postgres 70. Filesystems are read-only outside explicit mounts, all capabilities dropped, service-account token automount disabled and RuntimeDefault seccomp enabled.
- PostgreSQL local-socket trust applies only inside its pod; TCP initializes with SCRAM authentication. Production has no `POSTGRES_HOST_AUTH_METHOD=trust`. The dedicated password is never in a ConfigMap, CLI argument, plaintext file or report.

## Ordering and schema safety

Argo sync waves within the CRM backend Application: encrypted Secret −2; config, Services and NetworkPolicies −1; PG PVC and Recreate PostgreSQL Deployment 0; API Deployment 1; backup PVC, first-backup Job and daily CronJob 2. PVCs using WaitForFirstConsumer share their wave with a real consumer to avoid a Pending-volume ordering deadlock. These waves do not coordinate separate Applications; brief initial 404/503 while the gateway/frontend/backend converge is possible. Acceptance requires all revisions and the product smoke, not just the merge.

The API initContainer uses exactly the application image. `prod/migrate.py` waits at most 180 seconds for PostgreSQL, obtains CRM database-scoped advisory lock 4348524 (180-second wait), runs that image's `alembic upgrade head` (180-second limit), and monitors the lock connection. Lost lock, child failure or deadline kills the child and prevents API startup. Driver/Alembic output is suppressed to prevent DSN/SQL leakage; only safe phase messages are logged. No migration code is substituted. Failed migration diagnosis uses the reviewed source and safe status checks; never enable unrestricted SQL logging against customer data.

Startup/liveness check `/health`; API readiness checks `/ready` including revision `0001_crm` and the booking exclusion constraint. A successful process probe does not bypass migration compatibility. API and frontend are single replicas with maxSurge 0 / maxUnavailable 1; future updates can briefly interrupt CRM. PostgreSQL uses Recreate and a 60-second termination grace period so two postmasters cannot share its RWO volume.

Both the initial `backup-initial-v02` Job and the daily CronJob run `prod/backup-ready.sh` before the unchanged reviewed archive helper. It tolerates transient PostgreSQL reachability failures with 30 bounded probes, then either executes the helper once or fails without starting a dump. API health and sync waves alone do not establish connectivity from a newly created backup pod. Readiness is not authentication or archive validation; failures in the actual helper still fail the Job. See the [backup runbook](operations/BACKUP.md) for the observed first-release failure, retry bounds and versioned-Job rollout.

## Validation

```sh
python3 services/chota-crm-service/operations/validate.py
python3 services/chota-crm-service/operations/test-backup-readiness.py
# Focused real-PG backup startup/failure proof on disposable local Docker resources.
python3 services/chota-crm-service/operations/verify-backup-readiness.py
kubectl kustomize services/chota-crm-service/prod
kubectl kustomize services/chota-crm-web/prod
# Isolated Docker proof; defaults to the pinned release image (registry access required).
python3 services/chota-crm-service/operations/verify-local.py
# Or pass an independently built image of the reviewed, tree-identical backend source.
python3 services/chota-crm-service/operations/verify-local.py reviewed-local-image
```

The manifest validator requires Python/PyYAML and the available kubectl Kustomize v5. It renders every production overlay and checks collisions, selectors, digest pins, protected storage, references, probes, network boundaries and exact reviewed helper/config hashes. The focused backup proof uses a delayed PG18 server, a never-ready endpoint, real dump/write failures and a separate backup volume with UID70/read-only clients. The broader local proof uses private disposable Docker networks, no host ports and synthetic/empty data; verifies delayed DB startup, concurrent migration serialization, held-lock blocking, hardened API/PG startup, PG persistence, backup mode/archive integrity and isolated restore, then removes only its own resources. Neither proves production image-pull access, CNI enforcement, TLS or SSO.

## Rollback

Use a reviewed GitOps change. For initial-release failure, remove `crm-chota-by` routing, restore prior site/gateway configuration and scale CRM API/web to zero **while retaining both complete service directories, PostgreSQL, credential, network isolation, PVCs and backup schedule**. Reverting the entire initial commit removes the ApplicationSet source directory and risks deleting workload resources; prefer this explicit containment change. Both PVCs and the SealedSecret/template have `Prune=false,Delete=false` as a second safety layer. They do not protect against direct namespace deletion, node loss or an operator deleting a PVC; never do those as rollback.

Future app rollback must be compatible with the installed schema. Never run production Alembic downgrade (initial downgrade destroys all CRM tables). Use a compatible old image, forward repair, or restore to a new isolated database and review a configuration switch after validation. Keep prior data until recovery is accepted. `local-path` has Delete reclaim and no expansion; monitor node capacity and plan storage changes before it fills.

## Business V2 private transport preparation

The prod overlay includes a dedicated rootless mTLS sidecar for AI Business calls
on private TCP8443. The existing browser API remains on8000. Business stays disabled;
real versioned TLS SealedSecrets and independent review are required before deployment.
See the [transport contract, test proof and rollout gates](../../docs/business-transport/README.md).
