# CSP Multi-Agent Implementation Plan (3 CLI Agents + Human, Real-Time Push)

## Goal
implement and build a 100% operational CSP system as per the design spec from  /docs/current/LLMGroupChat.md

## Deliverables
- Gateway with WS/SSE push broadcast for all messages/chunks.
- Chat controller consuming push (fallback poll).
- Sidecars consuming push for inbox, preserving adaptive chunking + flow control.
- tmux launcher exporting token/URL and starting chat + three sidecars with unique names.
- Updated docs/quickstart for multi-agent setup.

## Task Split (for 3 CLI agents)

### Agent A (Gateway Push & Auth)
Tasks:
- Add WS (preferred) or SSE endpoint in gateway:
  - Auth via `X-Auth-Token` (header or query).
  - Broadcast every `routeMessage` result (including `/agent-output` chunks) to connected clients.
  - Heartbeat/ping to keep connections alive; handle disconnect cleanup.
- Keep HTTP API unchanged (`/register`, `/agent-output`, `/inbox/:id`, `/health`).
- Optional: filter by `to` client-side; server may broadcast all.
Prompt:
“Implement a WS/SSE push endpoint in the gateway that broadcasts every routed message (including agent-output chunks) to subscribed clients. Enforce `X-Auth-Token`, add heartbeat/ping, and keep existing HTTP endpoints intact. Document connection params and message shape.”

### Agent B (Sidecar + Client Subscriptions)
Tasks:
- Sidecar:
  - Subscribe to gateway WS/SSE stream and filter messages where `to == agentId` or `to == broadcast`.
  - Fall back to HTTP poll if WS/SSE is unavailable; reconnect with backoff.
  - Keep adaptive chunking, flow control, pause/resume, urgent `!` bypass.
- Chat controller:
  - Subscribe to WS/SSE; fallback to 200ms HTTP poll.
  - Show incoming messages immediately; log reconnect events.
Prompt:
“Update sidecar and chat controller to subscribe to the gateway WS/SSE stream; filter for self/broadcast (sidecar). Keep HTTP polling as fallback with backoff. Preserve adaptive chunking, flow control, pause/resume, and urgent `!` bypass. Add reconnect handling and minimal logging.”

### Agent C (Docs, tmux Launcher, UX)
Tasks:
- Update tmux launcher to:
  - Export `CSP_AUTH_TOKEN` (generate if missing) and `CSP_GATEWAY_URL`.
  - Start chat controller in top pane with token/URL.
  - Start three sidecars in lower panes with unique `--name` and gateway/token.
- Docs:
  - Update `docs/current/LLMGroupChat.md` and `README.md` with multi-agent quickstart, push transport, flow control (pause/resume, urgent `!`), and ghost-logging notes.
  - Note fallback polling and reconnect behavior.
Prompt:
“Update tmux launcher to export token/URL, start chat controller top pane, and three sidecars with unique names in lower panes. Refresh docs (`LLMGroupChat.md`, `README.md`) to reflect WS/SSE push, flow control, pause/resume, urgent `!`, ghost logs, and multi-agent quickstart.”

## Work Plan (Integrated)
1) Gateway push channel (Agent A).
2) Sidecar + chat controller push consumption with fallback (Agent B).
3) tmux launcher and docs updates (Agent C).
4) End-to-end test:
  - @all broadcast reaches all panes immediately (WS/SSE).
  - Direct @agent messages delivered correctly.
  - Long-running command: queued injections, ghost logs, no mid-command corruption.
  - Pause/resume and urgent `!stop` behavior verified.
  - WS/SSE reconnect with fallback to HTTP polling.
5) Optional hardening:
  - Queue overflow/aging already present; keep an eye on max queue tuning per agent.
  - Metrics/logging for WS connections.
