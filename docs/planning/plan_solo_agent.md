# CSP Solo Agent Implementation Plan (Real-Time Push + Flow Control)

## Goal
Enable a single CLI agent + human chat with real-time push (WS/SSE), adaptive streaming, and safe injections (flow control, pause/resume, urgent bypass).

## Deliverables
- Gateway push channel (WS or SSE) broadcasting all messages.
- Chat controller consuming push (fallback to fast HTTP poll).
- Sidecar consuming push for inbox (fallback to HTTP poll), retaining adaptive chunking and flow control.
- Updated docs/quickstart and sanity tests for streaming/injection safety.

## Work Plan
1) Gateway Push Channel
- Implement WS (preferred) or SSE endpoint:
  - On agent registration, allow clients to subscribe to a broadcast stream of routed messages (including `/agent-output` chunks).
  - Authenticate with `X-Auth-Token` (header or query param).
  - Broadcast every message produced by `routeMessage` to connected clients.
  - Add heartbeat/ping (e.g., every 20s) to keep connections alive.
- Keep existing HTTP endpoints as fallback (`/inbox/:agentId`).

2) Chat Controller (Human UI)
- Add WS/SSE client to subscribe to gateway push; on message receipt, render immediately.
- Keep 200ms HTTP poll as backup if WS is unavailable.
- Handle reconnect with exponential backoff capped (e.g., 10s).

3) Sidecar Inbox Listener
- Add WS/SSE subscription to the gateway push stream filtered by `to == agentId || to == broadcast`.
- Keep existing HTTP poll as fallback.
- Preserve flow control (adaptive chunking, idle detection, pause/resume, urgent `!` bypass).

4) Testing / Validation
- Manual:
  - Long-running command (e.g., `sleep 5 && echo done`), inject messages: ensure queued + ghost log, no mid-command corruption.
  - Prompt variations (y/n, colon prompts, pager text) still inject safely.
  - Urgent `!stop` injects immediately.
  - Pause/resume queues and flushes correctly.
  - WS disconnect/reconnect recovers; fallback poll works.
- Add a minimal smoke script or notes to reproduce.

5) Docs / Quickstart
- Update `docs/current/LLMGroupChat.md` and `README.md` with:
  - How to start gateway with WS push.
  - How to run chat controller with token/URL.
  - Sidecar launch command with `--auth-token/--gateway-url` and push support.
  - Note on flow control, pause/resume, urgent `!`.

## Proposed Agent Prompt (Solo Implementation)
“Implement WS (or SSE) push in the CSP gateway to broadcast all messages; protect with X-Auth-Token. Update the chat controller to consume WS/SSE with reconnect and keep HTTP poll as backup. Update the sidecar to subscribe to WS/SSE for inbox messages (filter to self/broadcast) with fallback poll. Preserve adaptive chunking/flow control (pause/resume, urgent ! bypass). Add minimal smoke instructions and doc updates in `docs/current/LLMGroupChat.md` and `README.md` for single-agent use. Keep existing HTTP API intact.”
