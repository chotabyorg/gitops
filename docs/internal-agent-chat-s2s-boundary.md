# Internal AI agent chat boundary

The AI chat endpoint is an application-level service boundary. Its request and response JSON remain unchanged. Tracked production callers use the dedicated `CHAT_S2S_TOKEN` and a trusted `X-User-Id`; the AI service validates a supplied token and scopes the agent lookup by `AgentTemplate.user_id` before session creation, LLM work, or MCP tool execution. Strict rejection of a missing token is controlled by `CHAT_S2S_AUTH_REQUIRED`.

## Tracked production callers

These callers have production paths in GitOps and are in scope for the staged rollout:

| Caller | Path to AI service | Owner identity source |
|---|---|---|
| Public client | JWT-protected KrakenD `POST /v1/chat/completions` | KrakenD validates the JWT and propagates its `sub` claim as `X-User-Id`; KrakenD injects the chat token server-side. The caller's token header is not forwarded. |
| Telegram gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| Instagram gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| WhatsApp gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| Website gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` from the authenticated control-plane widget-key validation response. |

The public API JSON remains `{agent_id, external_client_id, channel, message}` and `{session_id, answer}`.

## Local and non-production callers

`chota-metrics` includes a local/dev E2E harness that calls `ai-agent-service` directly without the chat token or owner header. It is not a supported production caller and will fail against strict production AI chat auth. Do not copy or distribute the production chat token to this harness. Production smoke must use the authenticated public KrakenD route or a supported channel gateway.

No tracked production GitOps deployment for `instagram-gateway-gray-service` was found in this repository. It is not included in the production caller set; verify its deployment status before treating it as a production caller.

## Future Voice caller

A future Voice gateway must validate its integration through control-plane, bind the agent to the returned owner, and send both `X-User-Id` and the dedicated chat token. It must be added to the production caller inventory and pass positive and cross-owner tests before strict mode is enabled. There is no Voice gateway repository in the current source inventory.

## Separate internal endpoints

The chat token is not `INTERNAL_API_TOKEN` and is not the control-plane polling credential. Keep all existing AI internal endpoints and their callers unchanged:

- `subscription-service` calls `/internal/v1/agents/count` and `/internal/v1/agents/deactivate-all`.
- `control-plane-service` calls `/internal/v1/agents/ownership-check`.
- `knowledge-base-service` calls the AI ownership-validation endpoint.

Those endpoints continue to validate their existing `X-Service-Token` against `INTERNAL_API_TOKEN`; the chat route validates the dedicated `CHAT_S2S_TOKEN` independently.

## Network policy scope

This change does not add a Kubernetes `NetworkPolicy`. The current finding is closed at the chat handler by requiring a service credential and tenant-scoped agent lookup, while KrakenD continues to validate public JWTs. Existing internal endpoints retain their current token checks. A broader NetworkPolicy needs a separate verified ingress inventory and selector review for KrakenD, all four channel gateways, control-plane, subscription, and knowledge-base callers; it is defense in depth and is not needed for the application-level chat boundary change.

## Staged rollout and release gate

1. Merge Stage A first. It installs the strict-scope `chat-s2s-secret` SealedSecret in the production namespace; it contains only `CHAT_S2S_TOKEN`.
2. Merge and deploy Stage B while `CHAT_S2S_AUTH_REQUIRED=false`. Stage B wires the Secret key into AI and the four channel gateways, and adds `FC_ENABLE=1` plus the Secret reference to KrakenD. Stage B deliberately leaves the GitOps KrakenD JSON unchanged. Wait for the Stage B gateway rollout and verify `FC_ENABLE=1` and that the token environment variable is present without printing its value.
3. Merge the AI, control-plane, and supported channel caller service PRs. Wait for each image build to publish and for the production GitOps image tags to advance. Confirm the production AI tag contains chat token/owner enforcement and the caller tags contain the updated token/owner propagation.
4. Only after Stage B's gateway environment is running, merge the chota-gateway source PR. Its documented `sync-config.yaml` workflow copies `krakend.json` to the GitOps production mirror. Confirm the deployed config has the backend-only chat token modifier and the running gateway has Flexible Configuration enabled and the Secret environment present. The token value must not be printed or exposed.
5. While strict mode remains false, run a successful production chat smoke through the authenticated public route or a supported channel gateway. This checks product availability. Before Stage C, separately inspect the live KrakenD ConfigMap for the backend-only token modifier, confirm `FC_ENABLE=1`, confirm the gateway and AI pods reference the same Secret key without reading its value, and confirm both rollouts are healthy. These are configuration and readiness checks; compatibility-mode success does not prove that AI received and accepted the token.
6. Stage C is a release gate. Do not merge/apply it until all service PRs are merged, their image builds are published, production GitOps tags show the new AI auth implementation and updated callers, Stage B and the KrakenD config are deployed, the live Secret references and rollouts are healthy, and the compatibility-mode product smoke succeeds.
7. Immediately after Stage C deploys, verify the running AI pod's image tag/digest matches the published image with the new auth implementation. Then issue a controlled direct AI chat request without the chat token and confirm it returns 401 before session, LLM, or tool side effects. Run a positive supported production chat through KrakenD or a channel gateway; success with strict mode enabled proves the injected token was accepted. Do not infer enforcement from `CHAT_S2S_AUTH_REQUIRED=true` in Git alone. If the positive smoke fails, set `CHAT_S2S_AUTH_REQUIRED=false` through GitOps immediately and wait for ArgoCD to complete that rollback before rolling back any caller.

Keep the token Secret and caller headers in place during rollback; this preserves compatibility while an older AI service ignores the additive headers.
