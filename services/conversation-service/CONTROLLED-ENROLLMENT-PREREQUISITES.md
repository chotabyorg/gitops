# Controlled Text/Handoff prerequisites — draft, not enrollment

This candidate prepares the exact Website and Telegram QA supplier scopes while
keeping Website `COMMON_WEBSITE_MESSAGE_SESSION_ALLOWLIST={}` and Telegram gateway
`TELEGRAM_HANDOFF_INTEGRATION_IDS=[]`. It performs no CP enrollment, session
issuance, provider/model call, grant-generation change or paid admission.

**Release dependencies:** finish and accept Stage B's original-process exit
observer and supervised drain, rebase this branch on its merged fresh main, then
pin the independently accepted Website message-allowlist image. **The Website image in this draft is still the predecessor and does not enforce
the new message fence. A nonempty common map must never deploy with that image.**
The current candidate is not deployable before those dependencies. Retain every Stage B
legacy guard/drain and producer/witness binding. Cross-Application sync waves do
not establish ordering. No rollout or production acceptance is claimed here.

## Exact scope and settings

Owner `dc3dd7eb-536f-45d4-84f2-c8d35575d928`, agent
`0b750714-af8d-4d8c-8fdc-4ddfeda98af9`; Website integration
`8d4a1b73-7973-4dcc-a3d4-1312d871c1d4`, Telegram integration
`9b43e8ab-7afa-4201-8a88-99e8d256180a`.

- CP receives separate enrollment and lifecycle credentials, the CS URL, and the
  exact Website cohort. AI receives its separate lifecycle credential, CS URL and
  the two complete enrolled-scope tuples in the application container only. Its
  migration container retains its original settings and credential exposure.
- CS API receives both lifecycle credentials, verifier URLs, both cohorts,
  Website capabilities, exact catch-up scopes and bounded settling policies.
  The original Telegram 350ms/1500ms policy is unchanged; Website uses the same
  tested bounds. Website worker has only the existing Website processing grant
  and managed binding; Telegram worker retains only its Telegram bindings.
  Each execution worker gets only its own cohort/catch-up/settling configuration.
- Website capability generation is **1**, sourced from the 2026-10-22 17:55:58Z
  fresh CP binding observation. This is not a grant or AI generation. Recheck CP
  binding generation before deployment/enrollment; drift requires a reviewed
  update and later fresh capabilities.
- `WRITER_ATTESTATION_REQUIRED=true` is effective only on the text API Begin
  authorization surface, with the existing Stage A producer registry and proof
  credentials. Execution workers retain false; retirement remains untouched and
  has empty cohorts. Voice deployments/configuration remain unchanged.
- Existing API principals are preserved semantically, with a single additional
  `main-common-website-gateway` WEBSITE principal and the exact owner/integration/
  WEBSITE_WIDGET/`main-chota.website-widget.v1` grant. Existing values were merged
  and sealed remotely in memory. Only ciphertext and equality/scope metadata
  left that process. A separate Website token is never reused from Business,
  lifecycle, CP polling, AI chat, producer, supervisor or retirement credentials.

## Dedicated private transport

The CS API pod gains one rootless, read-only NGINX server sidecar pinned to
`sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe`
(the existing reviewed Business image, verified locally for linux/amd64).
Its certificate/key and CA are newly issued for this transport. Business identity,
certificates, signing, configuration and network edges remain unchanged.

`conversation-service.prod.svc.cluster.local:8443` is an additive ClusterIP port,
allowed only from Website pods by a dedicated ingress policy. There is no public
route, NodePort or externalIP. The Website Python client verifies the chain and
exact DNS name using a read-only public CA mount. Only the TLS sidecar mounts the
server key; API, migrations and workers do not. CA private key stays outside pods
and Git. Public fingerprints, expiry and rotation deadline are recorded beside
`prod/website-transport/nginx.conf`.

The proxy accepts only POST to the eight explicit `/internal/v1/website/sessions`
paths; it forwards only Content-Type and X-Service-Token. Application S2S checking
remains mandatory. It disables retries, cache, request/response disk buffering and
all request-bearing logs, preserves upstream statuses, adds no-store to failures,
and uses 10-second request budgets matching the existing client. Public idle poll
is a sequence of bounded private calls.

Only missing lifecycle policy edges are added: CP API→CS API8000 and CS API /
Website worker / Telegram worker→CP API8000. Existing AI→CS business ingress,
CS→AI execution/proof, and CS API→User8000 already supply the remaining edges;
CP/AI have no selecting isolation policies in the inspected live policy union.
No unnecessary broad egress or Voice rule is introduced.

## Public ingress trust and impact

Observed 2026-10-22 18:05:17Z ingress traffic and Website socket metadata prove
Traefik `10.42.0.95` is the actual peer. Pod
`traefik-747fc5bbb6-gf5ps`, UID `8a0c0a4c-cd84-4f14-ad54-fdaf19421530`, is
not hostNetwork. The separate `10.42.0.1` health-probe traffic is not trusted for
forwarded public credentials. The source-trust CIDR is exactly `10.42.0.95/32`.

This is a **bounded current-pod contract**, not a permanent IP assignment. Before
credential use, revalidate UID/IP, deployment arguments, actual TCP peer and all
selecting policy rules. Traefik replacement at a new IP fails closed for common
Website sessions; a reviewed CIDR update plus new peer/header proof is required.
Never widen to the node PodCIDR. IP reuse by an unrelated pod is fenced by an
additional Website ingress policy requiring both kube-system namespace and the
Traefik pod label on port8080. The current live policy union has no other policy
selecting Website. Recheck that union after rollout.

**The ingress policy affects the whole Website pod, including legacy routes.**
The existing public `widget.chota.by` route still points to the same Website8080
Service; public legacy callers continue through Traefik. Repository references
and current socket observations found no other application caller requiring direct
Website ingress. This is evidence of the known topology, not exhaustive traffic
history. Node kubelet probes remain permitted by Kubernetes' resident-node
NetworkPolicy exception; the existing probe paths/ports are unchanged. See the
[Kubernetes NetworkPolicy contract](https://kubernetes.io/docs/concepts/services-networking/network-policies/).
After Argo convergence, verify node health probes and public legacy health/config
in addition to common-session negative probes; local Docker tests do not prove
production CNI enforcement. Node/cluster administration remains a trusted boundary.

Actual Traefik arguments show no access logging and no forwarded-header insecure
trust overrides. Native Traefik 3.6.13 tests prove untrusted supplied
X-Forwarded-Proto/X-Real-IP are overwritten. Production credential-bearing paths
still require bounded fake-sentinel logging checks across CP, Website and proxies
before real credentials; no credential probe or enrollment was performed here.

## Inbox response privacy

A higher-priority exact Inbox route applies one response-header middleware and
forwards to the **same KrakenD service**. The five endpoint shapes are preserved;
`casesfoo`, extra suffixes and unrelated routes are excluded. Original route
priority/method handling, OAuth callback precedence, JWT validation, request
headers, bodies and upstream selection are unchanged. The route has no direct CS
backend. Both upstream success and unauthenticated401 receive `Cache-Control:
no-store`. Local native Traefik tests use a synthetic status peer, while structural
checks prove the actual KrakenD configuration is unchanged. Verify real public
unauthenticated401 and legitimate owner responses after deployment.

## Verification and release order

From this repository:

```sh
python3 services/conversation-service/operations/controlled_enrollment/validate.py <accepted-base-sha>
python3 services/conversation-service/operations/controlled_enrollment/settings_check.py --workspace /path/to/chota
python3 services/conversation-service/operations/controlled_enrollment/test_tls.py
python3 services/conversation-service/operations/controlled_enrollment/test_edge.py
```

The Settings harness uses captured public registry shapes with synthetic tokens,
never production values, and the accepted source snapshots/venvs in the workspace.
It validates effective envFrom order and explicit per-container overrides,
including CP/AI migration startup. The live sealing helper separately proved
preservation of all old principals and exact Website managed-binding selection.

Before final freeze: rebase on accepted Stage B, pin accepted Website image, render
all overlays again and independently review exact tree, scope, credentials and
Business safety. Before enrollment: verify normal Argo health/image IDs, schema,
Settings, mounted certificate/CA/fingerprint/expiry, TLS handshake and wrong-token
failures, exact NetworkPolicy behavior and public logs/no-store. Recheck the CP
binding generation and retained writer evidence. Keep external input closed.
Then the orchestrator may execute the separately specified legitimate enrollment
sequence. Paid admission remains a later independently reviewed activation.

Rollback closes the exact new-input flags while retaining forward-compatible
images/schema, TLS trust, lifecycle credentials, drains/attestors and receipts.
Never remove retained evidence, enable raw/v1 fallback or delete integration/DB
rows to manufacture rollback. Input closure is not proof that an acquired writer
has terminated.

## Current preparation evidence (2026-10-22)

All 26 production service overlays plus the edge overlay render successfully.
Nine effective Settings configurations (API/workers and CP/AI migrations) pass
against the source snapshots, including Website PR24 code, using synthetic tokens.
Six real pinned-NGINX tests and three native Traefik 3.6.13 tests pass.

The additional dev-overlay sweep has 9 successful renders and 11 failures from
missing existing sealed-secrets.yaml files; the exact same outcomes occur at base
`eb70cca03b5297c37ddc71bcf08415d298dc42d1`. No dev resource is changed. Historical
Conversation GitOps tests run 34 cases: both the detached baseline and candidate
have the same 4 failures/7 errors and exactly the same failing test identities. These fixture/legacy
expectation failures are not reported as a passing suite and are not changed here.
The dedicated release checks above cover the actual rendered candidate.

A fresh public HTTPS handshake validates both widget.chota.by and api.chota.by
against the system trust store and exact hostnames; their served certificates
expire 2026-12-14. The public unauthenticated Inbox baseline is still401 without
Cache-Control. This draft contains the response-only fix; no production fix is
claimed until normal reviewed rollout and public re-verification.
