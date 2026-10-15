# Controlled Voice runtime

Only +375173820015 is authorized. Its prepared VOICE integration is
`3d241be9-d9c3-431f-9d46-5c8781b48b38`; preparation does not activate routing.

The existing Conversation image `d7118849fb7883afb920c71402a3c4b8dcf01845`
(`sha256:3ab7179ccf1850609e6a9d358e4b840230afec6f9fb574fdd36e538501a53f08`)
runs separate Voice API and Voice worker processes. Voice Gateway native source
is `dfa5a1aab243183ae0ca6c12985ae02d1a58709b`. No local Docker is required.

The API has only the VOICE principal, and the worker only VOICE_PROCESSING.
Both grants and managed AI binding target the one prepared integration.
Existing Website/Telegram pod specifications, configuration, grants and settling
policy remain unchanged. Text queue behavior remains with its platform owner.
The AI registry retains its two existing grants and adds the one Voice grant.
The Control Plane receives a separate routing credential and an exact DID cohort.

Private ingress is `10.250.0.1:18082` over WireGuard from `10.250.0.2` only.
The host's existing S2S mangle guard must cover port 18082 before Argo deployment.
The Service uses `externalTrafficPolicy: Local`; its API is pinned to `chota.by`
to preserve the peer address for the NetworkPolicy. No public ingress is added.
Voice workers can reach only DNS, Conversation PostgreSQL and the existing
managed AI service; the API can reach only DNS and PostgreSQL.

Validation: native Kustomize renders for all three changed overlays; existing
resource comparison; server-side dry-run of the private Service; controller
validation of all four encrypted secrets. Secrets remain encrypted in Git.

After Argo sync, verify readiness, exact grants, private access and negative auth
checks. Install the exact Voice source as a native Python/systemd service.
Before route activation retain evidence of trusted called DID provenance from
the actual PBX, matching source pair and boundary readiness. Then activate only
the controlled number through `scripts.manage_voice_routes`, and separately run
the real inbound call, STT/AI/TTS, interruption and hangup acceptance.

If the controlled route fails, revoke its admission and stop its native Voice
service. Keep canonical history and the reservation. Do not roll back Goal5
schema, text channel runtimes, or restore a database snapshot over newer events.
