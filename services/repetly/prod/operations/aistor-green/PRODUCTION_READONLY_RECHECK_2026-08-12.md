# Production read-only recheck — 2026-08-12

## Result

**EXTERNAL BLOCKER — SSH timeout.** The supplied read-only SSH endpoint did not
accept a connection on port 22 from either the sandbox or the approved
escalated network path. No production command reached the host.

The prior 2026-08-11 facts remain explicitly historical/carry-forward data;
they are not silently relabeled as a fresh recheck.

## Facts still required before Ready for Review

- exact labels on Traefik Pods, CoreDNS Pods, Repetly Pods, and scanner Pods;
- exact Traefik version and active CRD support for `ServersTransport.rootCAsSecrets`;
- `kubectl top node` and `kubectl top pods -A`;
- allocatable and scheduled CPU, memory, and ephemeral-storage requests/limits;
- exact GREEN Service name/port and generated certificate SANs after a licensed
  disposable reconciliation;
- OIDC discovery URL, JWKS URL, DNS/routing result, and CA trust result.

Until these facts are collected, the NetworkPolicy and Traefik backend TLS
contracts remain reviewed templates only. Production mutation is forbidden.
