# Goal4A temporary AI release and cleanup gates

Every numbered release is a separate frozen exact-reviewed GitOps PR. Natural Argo
is the sole mutation mechanism. No manual apply/sync/restart/production SQL, image
substitution, AI source change, stored Agent setting change or cross-App wave
assumption is permitted. Important → separate fix → NEW complete review → NEW
verification. Existing partial acceptance does not clear this active topology.

1. **Provider first, dark topology.** Freeze exact current Main cluster identity,
   production AI source/index/amd64-child/config/cache, all DB/function/ACL/audit
   baseline and schema head. Changed AI provenance STOPs for human cross-track
   confirmation. Use reviewed `role.py inventory` in a bounded readonly collection
   against the same accepted artifact to obtain its complete nonsecret snapshot;
   it changes only its own audit session settings, never roles/ACLs/data. Put that
   exact baseline into `release-inputs.json`, along with fixed source/index/scope,
   `release_id=goal4a-...` and absolute UTC `valid_until` (1–48h ahead at provisioning;
   preferably >=24h at release). Do not extend expiry on resync. Root generates and
   strictly seals the previously fixed one AI token/one role password in memory.
   Copy reviewed base/release inputs into `prod/` only after complete source/security
   and exact-release CLEAN. Include finite provision Job and fixed IP relay policy.
   No temporary resource uses retained Conversation annotations.

   Kubernetes 1.35 verifies credentials for kubelet-pulled private cached images.
   AI canary/provision/cleanup Pod specs must reference exactly the existing
   `ghcr-pull-secret` in `imagePullSecrets`, never container inputs or mounts.
   Confirm its metadata-only UID/type/key names match normal AI and the native
   accepted-image pull record. Keep immutable images, IfNotPresent, node pin and
   kubelet verification settings unchanged. Standalone public relay needs no secret.

   PR116's provision Job v1 never started: anonymous GHCR401, then DeadlineExceeded.
   Independent predeadline/event/cache proof and complete readonly catalog equality
   establish temporary-role absence and no ACL mutation. Only after resolving that
   zero-effect failure may a separately reviewed revision replace it declaratively
   with `goal4a-ai-readonly-provision-v2`. Recheck terminal old Job/no residual Pod,
   role absence/complete baseline and accepted live AI immediately before merge.
   Preserve role.py, release_id, baseline, ciphertexts and absolute expiry. Observe
   old Job pruning and exactly one successful v2; never manually retry/delete/sync.
   This correction needs NEW full cumulative source/release reviews and NEW native
   observer verification; original stage1 clearance is not clearance for the fix.

   The network-only `conversation-network-patch.yaml.template` replaces normal AI
   egress with temporary guard8080 for API/worker while worker0, admission bindings[]
   and cohorts{} stay unchanged. It is required for an actual CSAPI positive guard
   reachability check. Wait for **both** temporary App and Conversation App to
   naturally converge; local waves cannot order separate Applications. The ordinary
   production AI, Business transport, schema ownership and registry remain unchanged.

   Independent native stage verifier must prove role Job one successful finite run,
   readonly default plus full privilege census/zero-impact rejection, schema head,
   EMPTY/raw-MCP behavior, no business credentials, actual image/PID/env/mounts,
   private selectors/routes, guard aliases/legacy denial, fixed relay TLS/no redirects,
   effective additive policies and controlled positive/negative reachability. Verify
   password privacy through safe sentinels/log-counts without exporting SQL/log lines.
   Do not enable a worker/admission on desired YAML or health alone.

2. **Exact grants, still no admission.** Add matching Website S2S and preserved exact
   expected-agent guard, Conversation WEBSITE_BINDINGS and temporary managed binding.
   Worker0/cohorts{} remain. Revalidate widget privately through protected CP; exact
   owner/integration/Agent/channel mismatch STOPs. Privately prove public config sees
   rotated key without model dispatch. Validate actual matching principal grants.

3. **Exact worker, then one session.** Independently reviewed worker-only enable
   (API processing flag stays false), one replica and exact processing scope. Prove
   native worker readiness/schema/heartbeat/security/policy with no admitted work.
   Then separately reviewed SESSION_ALLOWLIST admits only the fixed trusted
   integration AND existing technical UUID. Ordinary same-integration and every
   other Website session remain LEGACY; no global/integration-wide switch.

4. **Bounded real smoke.** Root uses private file-only widget access, exact candidate
   and fresh stable message UUID. Genuine managed model credential is decrypted only
   inside temporary app. At most two successful model calls absent genuine failure:
   first message, exact replay, changed-text same-ID conflict, identical text NEW ID.
   Evidence links public HTTP → sticky MANAGED admission → InboundEvent → Message →
   Conversation → stable Turn/selection/claim/marker → temporary AI/real LLM →
   DRAFT_READY refs[] → honest delivery/HTTP. Count actual relay upstream attempts,
   not fake dedup or only final Turns. Before/after scoped safe hashes/counts plus
   transport/structural barriers prove no Agent/config/BusinessOperation/CRM effect,
   legacy Session or Redis history. No private prompt/body/key is logged. A failed or
   UNKNOWN dispatch is never blindly retried or rerouted; preserve recovery authority.

5. **Native retained-data restart.** Only after both technical Turns terminal, finite
   separately reviewed API AND worker pod-template restart annotations. Wait for new
   UIDs/Ready and prove same Message/Turn/draft, same DBidentifier/PVC/schema and exact
   public replay without another LLM attempt. Do not repeat empty PG recreation or
   deliberately induce real external business ambiguity.

6. **Sticky rollback.** Set cohorts{} through reviewed GitOps. Keep expected-agent
   guard, Website S2S, Conversation Website grants/bindings and compatible images.
   Existing public MANAGED replay returns same retained draft with new physical
   response evidence and zero AI/legacy dispatch. Prove new admission LEGACY via
   actual serving policy/journal and safe predispatch observation; do not perform
   normal Business-enabled legacy AI execution solely to test routing. Do not call an
   isolated fixture/direct CS admission a real serving public legacy request.

   **Already accepted managed messages are never replayed through legacy AI.**
   That statement requires actual retained public replay evidence.

7. **Deactivate, revoke and close.** All work must be terminal with no ambiguity
   requiring evidence. Worker0/flagfalse, cohorts{}, managed AI bindings explicitly
   empty/baseURL removed; never redirect accepted work to ordinary AI. Remove
   canary/relay/principal only after these gates. Preserve Website guard/S2S/CSWebsite
   bindings for retained completed replay. Wait for canary gone and zero role sessions.

   Materialize separate finite `cleanup-job.yaml.template` with the same lifecycle
   source/owned baseline and a `cleanup_gate` containing true `all_work_terminal`,
   `worker_inactive`, `canary_absent` plus SHA256 of the independent native evidence.
   These input assertions reference external proof and do not replace it. Keep role
   network policy/admin keyRef until successful cleanup. Job verifies original owned
   marker, zero role sessions/no unexpected dependency, removes only known grants/
   role and restores exact normalized original ACLs atomically. Drift blocks cleanup;
   never use DROP OWNED/CASCADE or delete application evidence to make it pass.
   After successful independent restoration verification, prune temporary credentials,
   operations Job/ConfigMaps/policies. Retain only sanitized closure Kustomization so
   Argo `allowEmpty=false` cannot block pruning the last temporary resources.

   Conversation API/PG/PVC and canonical/admission/Turn/draft/delivery evidence stay.
   Independent final verifier must demonstrate zero temporary workloads/principal/
   role/credential, restored original effective ACLs, new traffic LEGACY and retained
   public MANAGED replay with zero AI dispatch after cleanup. Full report/Business
   handoff, PASS/Done only after all smoke/retry/restart/rollback/final gates; then STOP.

## New validator boundary

Use `operations/validate.py --fixture` for schema-only staged source proof or
`operations/validate.py --prod <materialized-prod>` for nonfixture desired-state
checks. Neither proves runtime/release safety. The old Conversation validator keeps
its accepted normal-AI/dark semantics intact and intentionally does not clear this
temporary8080 topology. Each root-authored stage must validate its actual affected
Conversation/Website manifests and complete temporary service, all existing service
renders, secrets/references/selectors/policies/images, and exact external proof record.
No new stage may be cleared by a fixture flag or stale partial verdict.
