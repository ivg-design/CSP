# CSP Sidecar & Plan – Concrete Fixes

## 1) Align Sidecar ↔ Gateway Contract (`csp_sidecar.py`)
- Register with the fields the gateway expects:
  - POST `/register` JSON: `{"agentId": "<id>", "capabilities": { ... }}`
  - Accept 200/201; set `self.agent_id` to `agentId`.
  - Include `X-Auth-Token` on every request.
- Send output with the gateway’s schema:
  - POST `/agent-output` JSON: `{"from": "<agentId>", "to": "broadcast", "content": "<text>"}`.
  - Keep the auth header.
- Do not call unimplemented endpoints (drop DELETE `/agent/{id}` unless added to the gateway).
- Add lifecycle hardening:
  - Track `should_exit = True` on shutdown.
  - `waitpid` the child; close `master_fd`.
  - Join listener thread with timeout.
  - Always restore TTY in `finally`.
  - Time/size-based flush and backoff-aware polling (already sketched in the doc).

## 2) Harden Gateway Validation (`src/gateway/csp_gateway.js`)
- Require `from` to be a registered agent; reject otherwise (400).
- If `to` is set and unknown, return 400 instead of silently dropping.
- Keep localhost bind + rate limit + auth header enforcement.
- Optional: add DELETE `/agent/:id` to support sidecar unregister.

## 3) Propagate Auth Token & Gateway URL in Launch Scripts
- `bin/start-llm-groupchat`:
  - Capture the token the gateway prints: `export CSP_AUTH_TOKEN=<value>` (or generate one upfront and pass via env).
  - Export `CSP_GATEWAY_URL=http://127.0.0.1:8765`.
  - Pass both into tmux panes:
    - Human pane: `node src/human-interface/chat-controller.js "$CSP_AUTH_TOKEN"`.
    - Agent panes: `csp_sidecar.py --gateway-url "$CSP_GATEWAY_URL" --auth-token "$CSP_AUTH_TOKEN" --name "<AgentName>" --cmd …`.
- `csp-agent-launcher.sh`:
  - Accept `--gateway-url` and `--auth-token` (default from env) and forward them to `csp_sidecar.py`.
  - Ensure each invocation sets a unique `--name` or `--agentId`.

## 4) Make the Plan Accurate (LLMGroupChat.md)
- Update the sidecar snippet to show the correct `/register` payload and auth header.
- Note that gateway requires auth; show launching commands that pass `--gateway-url` and `--auth-token`.
- Either:
  - Remove the “Streaming Protocol Enhancement” section, or
  - Implement `/stream_update` in the gateway and wire ANSI stripping/state detection in the sidecar before claiming streaming support.

## 5) Optional Quick Payload Examples
- Register: `curl -X POST -H "X-Auth-Token: $CSP_AUTH_TOKEN" -d '{"agentId":"codex-1","capabilities":{"chat":true}}' http://127.0.0.1:8765/register`
- Send: `curl -X POST -H "X-Auth-Token: $CSP_AUTH_TOKEN" -d '{"from":"codex-1","to":"broadcast","content":"hello"}' http://127.0.0.1:8765/agent-output`
- Poll: `curl -H "X-Auth-Token: $CSP_AUTH_TOKEN" http://127.0.0.1:8765/inbox/codex-1`
