# Multi-Agent Task Split (3 CLI Agents)

## Agent 1 – Gateway & Transport
- Goal: Add real-time push.
- Tasks:
  - Add WebSocket or SSE endpoint to the gateway that broadcasts every message (including chunks from `/agent-output`) to subscribed agents/human UI.
  - Keep HTTP `/inbox` as fallback.
  - Enforce auth on WS/SSE (`X-Auth-Token` or query token).
  - Add a heartbeat/reconnect policy note.
- Prompt: “Implement WS/SSE push in `csp_gateway.js`; broadcast messages from `routeMessage` to connected clients; auth with `X-Auth-Token`; keep existing HTTP API; document how to subscribe.”

## Agent 2 – Sidecar & Clients
- Goal: Consume push channel and tighten streaming.
- Tasks:
  - Keep adaptive chunking to `/agent-output`.
  - Add WS/SSE subscriber in sidecar to receive inbox messages in real time (fallback to HTTP poll).
  - Reduce perceived latency by tuning flush interval if needed.
  - Ensure auth headers/tokens are sent on all calls.
- Prompt: “Wire sidecar to subscribe to gateway WS/SSE for inbox delivery; keep HTTP poll as backup; ensure adaptive chunking flushes ~200ms; respect `X-Auth-Token`.”

## Agent 3 – Docs & UX
- Goal: Align docs and scripts with reality.
- Tasks:
  - Update `LLMGroupChat.md` and `A2A_vs_CSP.md` to reflect adaptive streaming + push channel.
  - Ensure start scripts show token/URL propagation and sidecar launches.
  - Add quickstart steps for WS/SSE consumers.
- Prompt: “Refresh docs to match current code: adaptive chunking, WS/SSE push, auth-protected token flow, tmux launcher passing env vars; add quickstart commands.”
