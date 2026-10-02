# ChotaCRM frontend deployment

`prod` pins the reviewed final frontend image. `crm.chota.by` is exposed only through the established Traefik websecure/Let's Encrypt resolver in `platform/traefik-routes/ingressroute-crm.yaml`. The API remains `https://api.chota.by`; its public URL is baked into the published image, not rewritten through runtime environment.

Runtime configuration keeps `EMAIL_VERIFICATION_REQUIRED=false`, aligned with identity, CRM API and Agents. No passwords, API cookies, JWT signing secret or backend credentials enter this Deployment. All API/auth fetches happen in the browser with existing API-host cookies. No cookie Domain widening or token query-string handoff is introduced.

One non-root UID1001 replica, read-only root filesystem, writable bounded `/tmp`, 128Mi memory request / 256Mi limit, three `/health` probes and no service-account token. NetworkPolicy allows only the existing Traefik pods in kube-system to port3000 and no outbound pod traffic; the browser's API/external-image requests do not originate in this pod. CRM rollout maxSurge0 bounds memory and accepts a brief update interruption.

See [release procedure](../chota-crm-service/RELEASE.md) and [backend rollback/storage procedure](../chota-crm-service/README.md). Health confirms the web process only; final acceptance requires real browser login, product switching, CRM business flow and persistence.
