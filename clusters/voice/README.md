# Voice cluster bootstrap and future GitOps boundary

Infrastructure bootstrap is independent of production. No chota-va or current Chota application is deployed.

- Host: voice.chota.internal, 185.66.68.64, Ubuntu 24.04.5 LTS.
- Access: `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -p 52222 chota-admin@185.66.68.64`.
- WireGuard: wg0, 10.250.0.2/30, peer 10.250.0.1/32; UDP51820 accepts main public IP only.
- k3s: v1.35.9+k3s1, node voice, PodCIDR10.52.0.0/16, ServiceCIDR10.53.0.0/16, DNS10.53.0.10.
- Private API: https://10.250.0.2:6443, CA validation enabled and IP in TLS SAN. API is bound to WireGuard/loopback and UFW permits management access only from10.250.0.1 on wg0.
- k3s requires wg-quick@wg0.service at boot; PartOf propagates an explicit WireGuard restart to k3s, preserving the required startup order. No production join token is used.
- Default Traefik retained as ClusterIP with `service.spec.type` for chart40; ServiceLB disabled. No public80/443 or NodePorts.
- Storage: default local-path, single-node local disk; PVC provisioning and Pod restart persistence are smoke-tested.

## Bootstrap ownership

`bootstrap/` contains reference infrastructure manifests and host configuration. They are not an application source and must only be applied by an explicitly reviewed infrastructure/bootstrap process with administrative access. The Sealed Secrets controller is installed from pinned official v0.39.0 controller.yaml (SHA256 58ac159cd05e5fd19c77befe7c47d2a254973d3d6d812ed037cec30eafffa705), namespace kube-system, deployment sealed-secrets-controller. Requests50m/64Mi and limits200m/256Mi are set on the new controller. Its private key stays in voice kube-system, separate from production.

Argo registration is a Secret in main argocd, name voice-cluster, cluster name voice, endpoint https://10.250.0.2:6443, namespaces=voice, clusterResources=false, insecure=false with the voice CA. Actual token and Secret config are never committed.

Manager ServiceAccount lives in argocd-access, outside the application namespace. Its RoleBinding only targets voice. It can read namespaced resources there and write explicitly enumerated workload types; it cannot manage cluster infrastructure, roles, rolebindings, or secrets in other namespaces. Token rotation must replace the generated token and main registration Secret through an authorized operation; avoid printing either credential.

ArgoCD v3.3.9 normally reports Unknown for a registered cluster with no Applications; no monitoring cache is started yet. Actual HTTPS access from the Argo pod network and positive/negative RBAC checks are the readiness checks. Do not manufacture a Successful status or add an Application solely for a status badge.

## Sealing and image pulls

Fetch only the public voice sealing certificate on voice:

```sh
sudo /root/chota-voice-bootstrap/kubeseal --kubeconfig=/etc/rancher/k3s/k3s.yaml --controller-name=sealed-secrets-controller --controller-namespace=kube-system --fetch-cert
```

The checked-in certificate is PUBLIC and belongs to voice, fingerprint SHA256 D7:33:B2:25:59:D5:1B:14:99:EE:3D:AA:49:73:FB:EE:5D:61:2A:0B:F8:73:87:4D:5F:93:EA:53:2B:44:65:EE. Refresh from the controller before sealing. Never copy the production private sealing key or reuse production ciphertext. Use strict binding to namespace voice and the intended Secret name.

The existing operational pattern is namespaced ghcr-pull-secret (kubernetes.io/dockerconfigjson), backed by SealedSecret. Voice default ServiceAccount references that name. Credential installation and private-image pull readiness remain pending: no GHCR credential has been copied or minted. The attempt to inspect production credential scope through api.github.com was rejected by automatic approval review, so its scope is unverified. Obtain approval for that exact check/reuse, or provide a dedicated package-read credential through a secure local file. Prefer classic PAT with only read:packages and required package access; do not grant repo/write:packages for pulling.

`secrets/ghcr-pull-secret.yaml.template` is a ciphertext-only template. Replace it with output sealed for voice; do not apply the placeholder. No plaintext credential belongs in this repository.

## Future application

The examples define the intended boundary, not live resources. After repository review and explicit deployment authorization, chota-va must use project voice, destination cluster voice/private API, and namespace voice. Source must be outside existing `services/*/prod`, e.g. `clusters/voice/apps/chota-va`, to avoid production auto-discovery. That application directory is not created in this PR. Do not enable automated sync or change the current ApplicationSet in this bootstrap PR.

Verify node/system Deployments, DNS, PVC, sealing roundtrip, private API TLS, WireGuard, SSH/UFW and production hashes before any next-stage deployment. Temporary smoke namespace/resources must be removed after testing.
