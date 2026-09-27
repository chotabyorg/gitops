# Internal AI agent chat boundary

The AI chat endpoint is an application-level service boundary. Its request and response JSON remain unchanged. Every caller supplies `X-Service-Token` from the dedicated `CHAT_S2S_TOKEN` and a trusted `X-User-Id`; the AI service validates the token and scopes the agent lookup by `AgentTemplate.user_id` before session creation, LLM work, or MCP tool execution.

## Callers and identity sources

| Caller | Path to AI service | Owner identity source |
|---|---|---|
| Public client | JWT-protected KrakenD `POST /v1/chat/completions` | KrakenD validates the JWT and propagates its `sub` claim as `X-User-Id`; KrakenD injects the chat token server-side. The caller's token header is not forwarded. |
| Telegram gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| Instagram gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| WhatsApp gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` in the authenticated control-plane integration poll response. |
| Website gateway | ClusterIP HTTP `POST /v1/chat/completions` | `owner_id` from the authenticated control-plane widget-key validation response. |

The public API JSON remains `{agent_id, external_client_id, channel, message}` and `{session_id, answer}`. A future Voice gateway must validate its integration through control-plane, bind each agent to the returned owner, and send both `X-User-Id` and the dedicated chat token. There is no Voice gateway repository in the current source inventory.

## Separate internal endpoints

The chat token is not `INTERNAL_API_TOKEN` and is not the control-plane polling credential. Keep all existing AI internal endpoints and their callers unchanged:

- `subscription-service` calls `/internal/v1/agents/count` and `/internal/v1/agents/deactivate-all`.
- `control-plane-service` calls `/internal/v1/agents/ownership-check`.
- `knowledge-base-service` calls the AI ownership-validation endpoint.

Those endpoints continue to validate their existing `X-Service-Token` against `INTERNAL_API_TOKEN`; the chat route validates the dedicated `CHAT_S2S_TOKEN` independently.

## Network policy scope

This change does not add a Kubernetes `NetworkPolicy`. The current finding is closed at the chat handler by requiring a service credential and tenant-scoped agent lookup, while KrakenD continues to validate public JWTs. Existing internal endpoints retain their current token checks. A broader NetworkPolicy needs a separate verified ingress inventory and selector review for KrakenD, all four channel gateways, control-plane, subscription, and knowledge-base callers; it is defense in depth and is not needed for the application-level chat boundary change.

## Rollout and rollback

1. Install the strict-scope `chat-s2s-secret` SealedSecret in the AI service's production overlay. It contains only `CHAT_S2S_TOKEN`.
2. Wire that single key into the AI service, KrakenD, and the four channel gateway deployments. KrakenD uses Flexible Configuration and a request-scoped Martian header modifier; do not add the token to the public `input_headers` allowlist.
3. Deploy the service source changes and published images. Keep `CHAT_S2S_AUTH_REQUIRED=false` while old and new callers overlap. Verify owner propagation, successful channel chats, and that an owner mismatch returns 404 before any LLM or tool work.
4. After all five callers are running the updated code and the secret is present in each pod, use a separate GitOps change to set `CHAT_S2S_AUTH_REQUIRED=true`.

To roll back, set `CHAT_S2S_AUTH_REQUIRED=false` through GitOps before rolling back any caller. Keep the token Secret and caller headers in place during rollback; this preserves compatibility while the older AI service ignores the additive headers.
