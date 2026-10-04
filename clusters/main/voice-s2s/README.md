# Voice private S2S

Main WireGuard address 10.250.0.1 hosts separate ClusterIP externalIP Services: Control Plane TCP18080 and AI TCP18081 to existing API selectors/8000. Existing Services/routes remain unchanged. Application tokens are required over WireGuard. No Pod/Service CIDR routes, public ingress, DNS or NodePort.

Host guard reference files are bootstrap artifacts, not Kubernetes resources. Install the shell script as root-owned /usr/local/sbin/chota-voice-s2s-guard and the unit as /etc/systemd/system/chota-voice-s2s-guard.service; enable/start the unit. Rules in mangle PREROUTING reject only traffic to 10.250.0.1 TCP18080/18081 arriving outside wg0 or from a source other than 10.250.0.2, before kube-proxy DNAT. Main UFW/global policy is unchanged; existing production traffic is outside these matches.

Rollout order: source PR/CI -> reviewed Control Plane image plus private Services -> regression/VOICE metadata checks -> separately reviewed Voice sealed tokens/config/egress -> manual sync only chota-va-voice -> safe auth smoke. No real VOICE integration in this phase.

Rollback: revert Voice config to AGENT_MODE=local, remove CHOTA env refs/URLs and the two egress allowances through GitOps, then remove added S2S Services. Stop/disable host guard only when removing the Services, using its exact ExecStop rules. Restore previous Control Plane image only with no VOICE rows/callers; keep enum VOICE and migration schema. Do not remove enum values/rewrite DB or rotate shared tokens as first rollback. Existing main ApplicationSet drift is intentionally untouched.
