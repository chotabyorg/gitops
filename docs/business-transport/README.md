# Business V2 private transport preparation

This is a **local preparation candidate, not production acceptance**. No push or
cluster mutation is performed by preparation. The two promotion steps are separate:

1. CRM first: server sidecar, narrow8443 ingress, actual strict-scope sealed server
   identity and pinned RS256 public key. Existing CRM image/routes/DB stay intact.
2. AI only after CRM acceptance: client sidecar, actual sealed client identity,
   AI-only RS256 signing Secret, loopback URL/key ID and explicit Business=false.

The first branch includes inert AI proxy fixtures/patches for review and isolated
tests; AI prod Kustomization does not reference them and its config/image are unchanged.
The second branch activates them. Merge/promote these independently, CRM first.
Independent Applications do not coordinate sync waves. Missing/unready Secrets must
block promotion; verify each Secret/controller and its sidecar before the next stage.

## Connection and trust

```
AI HTTPX → 127.0.0.1:18081 in the AI pod
  → NGINX client → verified mutual TLS on CRM ClusterIP:8443
  → NGINX server in the CRM pod → 127.0.0.1:8000 → CRM
```

Plaintext exists only on each pod's loopback for this connection. No public
IngressRoute, NodePort, host port, cluster CA installation, cert-manager, public
certificate or browser session is needed. RS256 application authorization remains
mandatory and separate from TLS. Existing gateway → CRM browser API TCP8000 stays
unchanged. The NetworkPolicy adds only same-namespace `app=ai-agent-service` AND
`component=api` on TCP8443; it does not grant AI plaintext access to CRM8000.

The reviewed AI client pins HTTPX0.28.1, uses `trust_env=False`, and has no explicit
CA context option. `SSL_CERT_FILE`/`SSL_CERT_DIR` therefore do not provide private
CA trust. The loopback proxy preserves application source and the public certifi
bundle, while NGINX explicitly verifies the private CA and exact server hostname.

Both sidecars use the operator-provided immutable official NGINX digest
`sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe`.
The actual isolated image reports NGINX1.31.4. Containers run as10001, read-only,
with dropped capabilities, no privilege escalation, RuntimeDefault seccomp,
16Mi/10m requests and64Mi/200m limits each. Writable8Mi tmpfs is sidecar-local.
TLS volumes are mounted only in their proxy container; application, migration,
backfill and MCP children receive neither TLS key mounts nor TLS key env vars.

Only `/internal/agent/v1/` is proxied. Both proxies explicitly disable upstream
retry, cache, response/request disk buffering and error interception; they preserve
HTTP status and required assertion/cookie/owner headers. Connect timeout is2s;
upstream read/send and client body/send timeouts are5s, matching the default
Business client per-phase budget and remaining within its10s dispatch horizon for
normal bounded payloads. These are inactivity limits, not a new whole-operation
retry/deadline guarantee. Client abort closes upstream work; a committed effect
with a lost response remains UNKNOWN for application receipt reconciliation.

Local health probes prove proxy process/config readiness, not upstream TLS or CRM
readiness. Acceptance still requires the authenticated end-to-end transport proof.
Access logs are off; only critical NGINX errors are emitted, avoiding per-request
query/cookie/assertion logging. Rootless startup/config errors remain diagnosable.

## Production Secret contract — ciphertext and public material only

Use a NEW private production CA dedicated to this connection. Keep its private key
out of pods and Git. Issue separate server and client keys, independent of the
Business RS256 key, platform JWT, chat token and every existing credential.

| Secret (`prod`) | `ca.crt` | `tls.crt` / `tls.key` |
| --- | --- | --- |
| `ai-business-tls-v1` | Dedicated root CA PEM | AI leaf, EKU `clientAuth`, exact subject `CN=ai-agent-service-business` with no other subject attributes |
| `crm-business-tls-v1` | Same dedicated root CA PEM | CRM leaf, EKU `serverAuth`, DNS SAN `chota-crm-service.prod.svc.cluster.local` |

Both are type `kubernetes.io/tls`, with exactly `ca.crt`, `tls.crt`, `tls.key`.
Use SHA256 signatures, RSA≥2048 or a suitable supported EC key, proper CA/leaf
BasicConstraints, KeyUsage and EKU. The issuer must not issue other client
identities for this transport. The server checks the verified client's exact
subject in addition to certificate-chain validation. SAN verification is enforced
on the client with the exact upstream DNS name; TLS verification is never disabled.

The authorized production host generated/sealed the identities. Actual strict-scope
ciphertext is tracked as `business-transport/sealed-secret.yaml` and referenced in
each stage's resources. The `.template` files remain inert and must never be applied.
No plaintext private key is present. Public certificates are retained in
`public-certificates/` for chain, EKU, hostname and expiry inspection.
Do not change existing DB SealedSecret bytes. SealedSecret wave−2 precedes CRM
config/service/policy−1 and CRM Deployment1; independent Applications still need
operator sequencing. Confirm both unsealed Secrets exist before pod replacement.

Record CA fingerprint, leaf serials/notAfter and next rotation date without private
keys. For a90-day leaf, plan rotation at least30 days before expiry. NGINX loads
certificates at startup; updating a Secret alone is insufficient. Rotate through
new versioned Secret names plus reviewed Deployment references, confirming the
new handshake before retiring old certificates. CA rotation requires temporary
old+new CA trust, issuer migration and then removal. A certificate/transport failure
must remain closed; never switch the URL back to inter-pod HTTP to recover service.

## Rollout and rollback boundaries

Safe code-only deployment is independent of Conversation readiness while
`BUSINESS_CAPABILITIES_ENABLED=false` and managed grants remain unregistered.
Confirm migrations and health and run legacy regression: PromptComposer V2 also
changes legacy prompt composition, so flag=false does not imply zero legacy risk.
After these TLS gates, CRM RS256 trust and authenticated owner-route verification,
the user explicitly authorizes enabling Business before Conversation is deployed.
Managed production smoke and Website cutover remain blocked until the real managed
Conversation path/canary exists. Never synthesize Conversation ownership to bypass it.

CRM current old release expects exact schema0001 in readiness and its Alembic does
not know0005. After additive schema upgrade, simple rollback to that old image is
not compatible. Retain the new healthy CRM browser runtime and disable Business,
or use a separately reviewed compatible forward repair. Never downgrade the DB.

Transport rollback is reviewed GitOps restoration of earlier proxy config/image or
certificate references with Business disabled. Preserve DB, application receipt
and UNKNOWN evidence, existing Secrets and unrelated channel ownership. Do not
remove encrypted transport while Business can dispatch.

## Verification

Run from repository root:

```
python3 services/chota-crm-service/operations/validate.py
# CRM-first candidate:
python3 docs/business-transport/verify.py --stage=crm --require-secrets
# AI-followup candidate (both transport overlays present):
python3 docs/business-transport/verify.py --require-secrets
```

The first existing validator renders all production overlays and checks existing
storage, migration, image, selector and backup invariants. The focused verifier
checks exact new policy/Service ports, flag=false and sidecar-only key mounts. It
creates a unique internal Docker network, no host ports, hardened real NGINX
containers and a Python counter backend, using temporary synthetic CA/leaf keys.
It proves one dispatch for success,503, lost response and timeout; exact JSON body and required headers; uncached repeated reads;
missing/untrusted/wrong-identity client rejection; wrong server issuer and hostname
rejection; non-Agent route rejection; and absence of synthetic credentials in logs.
It removes its own containers/network/temporary certificates in `finally`.

Docker proof does not establish production CNI enforcement, current leaf expiry,
SealedSecret synchronization, application-level S2S authorization, real managed
Conversation execution or live Website support. Those remain production gates.

Primary behavior references: [HTTPX0.28.1 SSL context source](https://github.com/encode/httpx/blob/0.28.1/httpx/_config.py),
[NGINX upstream TLS/retry directives](https://nginx.org/en/docs/http/ngx_http_proxy_module.html),
[NGINX client certificate verification](https://nginx.org/en/docs/http/ngx_http_ssl_module.html).

### Local preparation evidence — 2026-10-08

Existing whole-repository CRM validator passed before and after the change,
rendering23 service overlays. Focused real-image proof passed every case above,
including dropped-response and timeout request-count checks, exact body/header
preservation and uncached reads. Temporary test resources were removed. The initial scaffold correctly rejected missing SealedSecrets. Updated staged
candidates include only the explicitly authorized ciphertext/public material and
require the stage-specific Secret gate before promotion. No production traffic,
application image, GitHub branch or cluster resource was changed by these tests.

### Public certificate verification and rotation

The transferred leaves validate against the dedicated CA. AI subject is exactly
`CN=ai-agent-service-business`, EKU clientAuth. CRM EKU serverAuth and DNS SAN is
`chota-crm-service.prod.svc.cluster.local`. CA BasicConstraints is critical
CA:TRUE,pathlen:0. Leaf expiry is2027-01-06; rotate by2026-12-07. CA expiry is2028-10-07.
CA SHA256 fingerprint:
`C5:BB:AD:0A:BB:68:E4:2C:BC:37:44:4C:A3:7A:2B:FD:EB:E4:EF:19:71:B8:03:F1:71:4B:49:D0:90:5F:4E:76`.
Signing key ID is `chota-business-prod-20261008-01`. Its sealed private value is
referenced only by the main AI container, never migrations, backfill or TLS sidecars.
The matching public key is CRM ConfigMap content. Ciphertext inspection cannot
prove successful decryption or matching live keys; production S2S verification does.
