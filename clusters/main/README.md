# Main cluster

Existing production remains single-node k3s at 153.80.244.178. WireGuard management address is 10.250.0.1/30.

Existing services stay under `services/*/prod`. Existing Applications and their destination `https://kubernetes.default.svc` are unchanged. No production resources are relocated by this proposal.

Host-only WireGuard uses UDP 51820, source-restricted to 185.66.68.64. Main UFW remains inactive and global firewall policies are unchanged. Do not route Pod/Service CIDRs between clusters. Private WireGuard key is generated and retained root-only on main; it is not present in Git.
