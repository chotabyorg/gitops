# Goal4A temporary private AI canary candidate

PR116 materialized `prod/` and started a dark Main rollout. The relay became Ready,
but provision Job v1 never launched its container: native Kubernetes 1.35 rejected
anonymous access to the credential-bound cached private AI image. The finite Job
reached its deadline; no temporary role or ACL change occurred. This separate fix
adds the existing kubelet-only pull-secret reference and ordinary finite Job v2.
It requires NEW full reviews and native verification before any activation.
The Main ApplicationSet discovers `services/*/prod` automatically. Each later
release remains separately frozen and independently reviewed.
Normal `ai-agent-service`, its source, schema ownership, Business V2 configuration,
secrets and current image are unchanged. No Goal4B is included.

The human approved a separate private runtime using the exact accepted production
AI source `4fa17597b8083d2e09428c9c1ac949aa42f5990d`, immutable image index
`sha256:5eba680cf018acf0f8062bbc1b0909e8c09ff157795e5a7f79ac4232a863ef4c`.
Fresh native production source/index/amd64-child/config/cache checks remain required
before every affected release. Changed production provenance requires cross-track
confirmation; never substitute an older image. `IfNotPresent` is pinned to
`chota.by`/amd64. Kubernetes 1.35 also verifies authorization for credential-bound
private cached images. AI lifecycle/canary Pod specs therefore reference only the
existing `ghcr-pull-secret` in `imagePullSecrets`; kubelet consumes it and no
container receives a registry credential, mount, environment value or API token.
The standalone public nginx relay has no pull-secret reference. See the
[versioned Kubernetes rule](https://v1-35.docs.kubernetes.io/docs/concepts/containers/images/#ensure-image-pull-credential-verification).

The new design received fresh independent architecture/security clearance at
design v2 SHA256 `8f78675f1e47865389872bcec9cd7e0cd13018cba26f2f9fc39228fd8ab8a7d6`.
That is implementation permission only. New complete correctness/security review,
exact release review and independent native stage verification remain mandatory.
See [release procedure](RELEASE.md).

## Fixed topology and decisive barriers

Private `ai-agent-service-goal4a-canary:8080` reaches the accepted app through a
mandatory nginx guard; app Uvicorn binds only `127.0.0.1:8000`. Guard exposes exactly
POST managed execute/evidence and GET health, rejects raw-URI aliases/query/other
methods, and forwards only fixed upstream URIs. No legacy/config/model-key API is
reachable through it. The app receives only individual keyRefs for the existing
`ENCRYPTION_KEY`, temporary DB password and one temporary managed registry. No
normal secret envFrom, signing/mTLS/MCP/provider write material, default model key,
internal/chat token, Redis or service-account token enters the pod.

`BUSINESS_CAPABILITIES_ENABLED=false` selects the accepted exact
`EMPTY_BUSINESS_REGISTRY`; raw MCP remains quarantined by unchanged managed source.
`REDIS_HOST=` and disabled KB/subscription/privacy proxy preserve the previously
proved direct managed path. No stored Agent/CRM/capability/prompt setting is changed.
Actual EMPTY behavior/source, credentials absence and readonly DB authority need
independent native proof on the new pod. An isolated helper import does not inspect
the serving Python process's in-memory registry.

The canary can reach only AI PostgreSQL, DNS and the **separate** private
`ai-agent-service-goal4a-llm-relay:8080`. Separate Pod egress prevents relay bypass.
Relay accepts only the exact OpenAI completion path; verified TLS/Host/SNI and fixed
reviewed IPv4 force `openrouter.ai`. No retry, CONNECT, caller-selected target,
redirect forwarding or X-Accel-Redirect is allowed. Relay logs only generated request
ID, status/upstream status/address and timing; guard has no request log. Nginx error
contexts are discarded at `/dev/null`, including malformed/critical request cases.
Counting actual upstream attempts requires neither prompt nor credential logging.

All workloads use nonroot UID1000 for accepted AI or UID10001 for nginx, RuntimeDefault,
no capabilities/escalation/SA, root read-only, bounded memory/tmp/CPU and probes.
NetworkPolicy is defense in depth. Native additive-policy/endpoint/reachability
proof is still required; it does not replace the four decisive barriers.

## Controlled database lifecycle

`operations/role.py` runs in a finite ordinary Argo Job, using accepted AI/asyncpg,
only admin DB password and temporary password, no ENCRYPTION_KEY/provider material.
No Alembic, backfill, HTTP service, TTL, hook recreation or manual SQL is used.
Privileged work is advisory-serialized and atomic. A fixed role ownership comment
retains original raw and normalized ACLs plus exact release/source/scope/expiry.
Idempotent resync verifies the same marker/catalog/credential; it never resets an
unrelated role, rotates a password or extends expiry.

The target role `goal4a_smoke_read` has no superuser/createDB/createRole/replication/
bypassRLS/inheritance/membership/ownership/grant option. Only target DB CONNECT,
public USAGE and SELECT on 11 AgentTemplate, 8 BusinessScope and 1 migration-head
column are granted. No application DML/DDL/sequence/TEMP authority is granted.
Default transaction read-only is on, but tests explicitly override that default
to demonstrate that actual ACLs still reject zero-row UPDATE and schema/TEMP DDL.
The accepted LLM auth/credit error path's Agent UPDATE therefore cannot change it.

V2 corrects the accepted I1: target PUBLIC TEMP is temporarily revoked; PUBLIC
CONNECT is revoked on the other connectable databases (`postgres`, `template1`),
while `template0` remains nonconnectable and unchanged. PUBLIC EXECUTE is revoked
on the exact three LO-creation and two logical-WAL-emit signatures. Existing sole
admin superuser retains effective authority. Any extra login, changed database/
owner/ACL/function/schema/head/extension/preload/ownership invalidates release.
The role's DSN alone would not restrict cluster-wide access.

Before password-bearing SQL, the privileged session asserts no preload hooks and
suppresses statement/error/duration/sample/transaction-sample/debug parse/rewrite/
plan/parameter logging. SQL/driver exceptions never leave the CLI wrapper. No global
logging setting is changed. Native sink/privacy proof remains required. The readonly
role cannot see privileged preload GUC rows; startup deliberately does not infer
absence or grant `pg_read_all_settings`. Privileged Job and independent native
inspection establish that separate audit gate.

Readonly startup verifies existing head `bv2_20261008_01`, owned marker, role
attributes, exact column reads, application write/DDL/ownership/membership denials,
other-connectable-DB denial and five-function EXECUTE denial. `prove` adds bounded
zero-row UPDATE and schema/TEMP probes, always rollback, including unexpected DDL
success. Production never invokes irreversible WAL emit. Ordinary PostgreSQL
session/statistics effects and public `pg_settings` session controls are not business
table mutation; no side-effect-free-server claim is made.

Cleanup requires independent evidence of terminal managed work, worker inactive,
canary gone and zero role sessions. It rejects marker/catalog/dependency drift,
revokes only known explicit grants, drops the role without DROP OWNED/CASCADE and
restores exactly original **effective** PUBLIC ACLs. Default NULL versus explicit
default ACL storage may differ; normalized grantee/privilege/grant-option/grantor
sets must match. No application row, Conversation evidence or PVC is deleted.

## Scope and secrets

| Item | Exact nonsecret identity |
| --- | --- |
| Owner / agent owner | `dc3dd7eb-536f-45d4-84f2-c8d35575d928` |
| Integration | `8d4a1b73-7973-4dcc-a3d4-1312d871c1d4` |
| Channel | `WEBSITE_WIDGET` |
| Agent | `0b750714-af8d-4d8c-8fdc-4ddfeda98af9` |
| Technical session | `5074470b-e568-4828-be24-f7c815c6bf16` |
| Temporary AI principal | `main-conversation-website-ai-canary` |
| Caller / namespace | `conversation-service` / `main-chota.conversation.v1` |

Exactly one in-memory generated token is sealed into
`ai-goal4a-managed-secret/MANAGED_AI_AUTH_PRINCIPALS` and
`conversation-goal4a-managed-ai-secret/MANAGED_AI_BINDINGS`. The latter binds this
processing scope only to `http://ai-agent-service-goal4a-canary:8080`. Normal AI's
registry remains empty. `ai-goal4a-readonly-secret/POSTGRES_PASSWORD` is separate.
All three temporary credentials are strict Main/prod/name scoped and prunable.
No token, DB password, provider key or widget credential belongs in source,
ConfigMap, CLI/history, issue, PR, report or logs. Existing Encryption key remains a
keyRef only. Templates are not usable credentials or production seals.

## Focused verification

Local dependencies: Python, asyncpg, PyYAML, cryptography, kubectl/Kustomize, Docker.
Runtime Jobs use only Python/asyncpg already in the accepted AI artifact.

```sh
python3 services/ai-agent-service-goal4a-canary/operations/validate.py --fixture
python3 -m unittest discover -s services/ai-agent-service-goal4a-canary/operations -p 'test_*.py' -v
```

Tests create and remove only new labelled local containers. Disposable PG18 alone
reproduces original TEMP/otherDB/LO/nontransactional WAL escape, then verifies
corrected privileges, explicit READ WRITE denial, atomic failure, finite idempotence,
foreign-role/drift/session cleanup refusal, restoration and synthetic-secret logging.
Actual immutable nginx index tests use a synthetic HTTP/TLS backend in the same
container network namespace. Guard config is unchanged. Relay fixture substitutes
only loopback fixed target/test CA (plus intentional wrong-hostname negative test),
keeping fixed path, verified Host/SNI, redirects, retries and logging semantics.
Local cached PG/nginx children are ARM64; this is artifact behavior, not native
Main AMD64 enforcement. Prior accepted 404/96/117 service suites are not repeated.
Fixture renders never establish ciphertext validity, current provenance, native
CNI/DB/credential safety, release approval or real model execution.
