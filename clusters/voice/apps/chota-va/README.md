# Inert Voice pilot

Destination: registered cluster `voice`, namespace `voice`, private API
`https://10.250.0.2:6443`. Source: `clusters/voice/apps/chota-va`.
One replica, Recreate rollout, digest-pinned GHCR image; no automated sync.

The separate bootstrap manifests in `../../argocd/` create only the `voice`
AppProject and `chota-va-voice` Application in main ArgoCD. They do not belong
to the Voice application's Kustomization. Bootstrap those explicit resources
after merge, then manually sync only `chota-va-voice` when private pull readiness
is confirmed. Existing production ApplicationSet must remain untouched.

HTTP is ClusterIP-only on 8080. AudioSocket 9092, Twilio, Verto, outbound/AMI,
final transcription and TTS warmup are disabled. `AGENT_MODE=local` and
`ECHO_MODE=true`; no production Chota env values or provider credentials exist.
NetworkPolicy denies all Pod egress. Only a same-namespace Pod labelled
`app.kubernetes.io/name=chota-va-smoke` may access HTTP; node probes retain the
standard Kubernetes node-origin exception. No public ingress or firewall
change is needed. The application SA token is not mounted.

The randomly generated `API_TOKEN` is stored only as a Voice-sealed Secret.
`/health` is public within this private boundary; `/api/status` and
`/api/readiness` require bearer auth. Readiness probe reads the token from the
Pod environment, checks authenticated local worker status and temporary PVC
read/write, and never prints request headers/credentials. `/api/readiness`
will report `configuration_ready=false` because provider keys are intentionally
absent; HTTP200 from that diagnostic does not prove production-call readiness.

ConfigMap is provided through both environment and a read-only `/app/config`
mount. UID/GID/fsGroup10001; root filesystem read-only, capabilities dropped,
RuntimeDefault seccomp. `/tmp` is disposable; `/app/data` is persistent.
All SQLite files/WAL/SHM, recording PCM/WAV/metadata/index/cache belong under
that PVC. Requested 2Gi is not a local-path filesystem quota. Local-path is
node-local, and recording retention/off-node backup/restore are prerequisites
for future production calls, handled in a separate task.

Initial requests 100m CPU/256Mi RAM, limits500m/768Mi. Record idle usage using
metrics-server after activation; no load test. Image stop signal SIGINT follows
the existing asyncio cleanup path; termination grace30s.

Activation and verification gates:

1. CI tests/container smoke succeed; publish full-SHA tag and record digest.
2. Replace pending digest before merge; server dry-run rendered manifests.
3. Bootstrap explicit Project/Application; leave it OutOfSync while pull readiness
   is pending. No resource sync or Pod creation is required for registration.
4. Before manual sync: minimal `read:packages` classic PAT plus package read ACL,
   sealed for Voice as `ghcr-pull-secret`; default ServiceAccount references it.
   Broad production pull token is not allowed to be copied. Sync only this app
   once that credential gate is satisfied.
5. Verify Pod Ready/imageID, PVC Bound, config/secret references, Service endpoint,
   authenticated safe GETs, 401 without auth, network isolation and nonroot state.
6. Write a synthetic marker directly to PVC (no business API mutation), controlled
   restart, verify the same PVC and marker, then delete the marker.
7. Existing production specs/destinations/AppSet, public firewall/DNS/SIP remain
   unchanged. No control-plane/AI/gateway S2S integration in this phase.

Source deployment contract:
`https://github.com/chotabyorg/chota-va/blob/main/docs/deployment-contract.md`.
