# Zot production read-only recheck — 2026-08-12

**External blocker: SSH timeout.** The supplied read-only SSH endpoint timed
out on port 22 from both sandbox and escalated network paths. No production
command, kubeconfig, Secret value, or mutation was attempted after the
timeout.

The 2026-08-11 preflight remains historical carry-forward evidence. Before
activating Zot, collect and independently verify:

- exact Traefik Pod labels and version;
- exact CoreDNS labels and DNS path;
- registry namespace/Service selectors and kubelet/containerd HTTPS path;
- current node requests/limits including ephemeral storage;
- Traefik `ServersTransport` CRD support and public ACME trust.

The new k3s CI workflow tests policy semantics with synthetic Pods only; it
does not claim production label verification or production enforcement.
