# CSP Deep Analysis: Issues, Fixes, and Detailed Development Plan (Amended)

Date: 2025-12-27
Analyst: Codex (GPT-5)
Sources: `CSP/PROPOSAL_MEMO.md`, `CSP/ANALYSIS_AND_FIXES.md`, code review of `CSP` repo

---

## Purpose

This document consolidates the findings from the memo and prior analysis, validates them against the current codebase, and provides a highly detailed, step-by-step plan to improve CSP without over-engineering.

---

## Current Implementation Review (Verified in Code)

### Gateway (`src/gateway/csp_gateway.js`)
- In-memory `chatHistory` with JSONL append-only persistence.
- HTTP endpoints: `/register`, `/agent-output`, `/message`, `/inbox/:agentId`, `/agents`, `/history`.
- WebSocket broadcast to all clients at `/ws`.
- No orchestration state, no `/mode` endpoints.

### Sidecar (`csp_sidecar.py`)
- Registers agent, injects inbound messages into PTY.
- Flow-control queue (busy/idle) and manual pause/resume.
- Output streaming is intended to be disabled by default, but is re-enabled on any inbound message (bug).
- Command detection supports `@query.log`, `@send.<agent>`, `@all`.

### Human Interface (`src/human-interface/chat-controller.js`)
- Supports `/agents`, `/help`, `@query.log`, `@agent`, `@all`.
- No `/mode` or orchestration commands.

### Launcher (`bin/start-llm-groupchat.sh`, `bin/csp-agent-launcher.sh`)
- tmux session with Human + 3 agents.
- Agent launcher runs `claude` as a command string; if `claude` is an alias, `os.execvp` will fail.

---

## Confirmed Issues (Merged Findings)

1) **Claude fails to start when invoked via alias**
- Root cause: `os.execvp` does not resolve shell aliases.
- References: `csp_sidecar.py:395`, `bin/csp-agent-launcher.sh:59`.

2) **Output feedback loop and ANSI spam**
- Root cause: `share_enabled` set to `True` on any inbound message, contradicting the design intent to keep sharing off by default.
- Additional issue: sanitization misses cursor/erase sequences (e.g., `31;2H`, `K`), so garbage leaks into chat.
- References: `csp_sidecar.py:333-335`, `csp_sidecar.py:774`, `csp_sidecar.py:610`.

3) **Agent ID collisions**
- Root cause: sidecar truncates the ID to a base token (`split('-')[0]`) and gateway uses the requested ID directly.
- Effect: multiple agents of the same type overwrite each other; direct routing and turn targeting fail.
- References: `csp_sidecar.py:345-356`, `src/gateway/csp_gateway.js:68-86`, `bin/csp-agent-launcher.sh:31-47`.

4) **Inconsistent addressing rules**
- Root cause: `@send.(\w+)` disallows dashes and the human controller lowercases targets, breaking any dashed unique IDs.
- References: `csp_sidecar.py:51-77`, `src/human-interface/chat-controller.js:322-334`.

5) **History persistence is write-only**
- Root cause: `/history` reads only in-memory data; JSONL is not loaded on startup, and history is unbounded in RAM.
- References: `src/gateway/csp_gateway.js:12-18`, `src/gateway/csp_gateway.js:309-337`.

6) **No orchestration surfaces exist yet**
- Root cause: Gateway lacks `/mode` or state, and UIs have no mode commands.
- References: `src/gateway/csp_gateway.js`, `src/human-interface/chat-controller.js:279-338`.

---

## Design Constraints (No Over-Engineering)

- Keep changes local to current components; avoid new services.
- Prefer explicit, low-risk options over dynamic behavior.
- Add only the minimum endpoints and data needed to support orchestration modes.
- Keep orchestration enforcement soft unless proven necessary.

---

## Group Chat Flow Goals

- Every agent has a dedicated tmux pane with real-time output.
- A lightweight orchestrator controls turn order and mode transitions.
- Human and orchestrator see structured progress and can pull history on demand.
- Sharing is explicit and safe (no ANSI floods).
- Debate/consensus have clear phases and predictable response formats.

---

## Detailed Step-by-Step Plan

### Phase 0: Preflight and Baseline

0.1 Verify current environment assumptions
- Confirm `CSP_AUTH_TOKEN` and `CSP_GATEWAY_URL` are set by the launcher.
- Confirm actual `claude` binary path (e.g., `/Users/ivg/.claude/local/claude`).

0.2 Capture baseline behavior
- Start CSP and note:
  - Claude launch failure (if alias-based).
  - ANSI spam behavior after messaging.
  - Agent ID collisions in `/agents`.
  - `/history` results after restarting gateway.

Acceptance: You have a short baseline log of the current failures.

---

### Phase 1: Launch Reliability and Identity Fixes

1.1 Fix Claude launch path
- Edit `bin/csp-agent-launcher.sh` to use the full `claude` binary path instead of the alias.
- Keep other agents unchanged.

1.2 Normalize agent IDs consistently
- In `csp_sidecar.py`, stop truncating IDs with `split('-')[0]`.
- Keep full `agent_name` (normalized to lowercase and dashes if desired).
- Ensure sidecar uses the `agentId` returned by `/register` as the authoritative ID.

1.3 Enforce unique IDs in the gateway
- In `registerAgent`, if an ID already exists, return a deterministic suffix (e.g., `codex-2`, `codex-3`).
- Return the confirmed ID to the sidecar.

Acceptance:
- Multiple instances of the same agent type appear as distinct IDs in `/agents`.
- Direct messages reach the intended instance reliably.

---

### Phase 2: Stop Output Floods and Add Explicit Sharing Controls

2.1 Remove auto-enable of `share_enabled`
- In `inject_message`, delete or disable `self.share_enabled = True`.

2.2 Add explicit `/share` and `/noshare` commands
- In `inject_message`, detect `/share` and `/noshare` from inbound content.
- Toggle `share_enabled` accordingly with stderr confirmation.

2.3 Improve sanitization for cursor/erase sequences
- Extend `_sanitize_stream` to strip orphaned CSI fragments (e.g., `[0-9;]+[A-Za-z]`).
- Keep it regex-based to avoid new dependencies unless required.

Acceptance:
- Messages do not trigger ANSI floods by default.
- Output is only shared after `/share`.
- Shared output no longer contains cursor/erase artifacts.

---

### Phase 3: Addressing Rules and Command Parser Compatibility

3.1 Expand `@send` parser to allow dashed IDs
- Update regex in `AgentCommandProcessor` to accept `[-a-zA-Z0-9_]+`.

3.2 Align human controller targeting behavior
- Decide one rule: all agent IDs are lowercase in registration.
- If using lowercase normalization, keep `command.toLowerCase()` but document it.

3.3 Update docs to reflect ID format
- Update README or docs to explicitly say: agent IDs are lowercase, dashes allowed.

Acceptance:
- `@send.agent-name` works for dashed IDs.
- Human `@agent-name` works consistently across all agents.

---

### Phase 4: History Persistence That Survives Restarts

4.1 Load last N messages on gateway startup
- Parse the last N lines of `csp_history.jsonl` into `chatHistory`.
- Keep N small (e.g., 1000) to avoid large memory usage.

4.2 Cap `chatHistory` length
- After each append, trim to the max length.

Acceptance:
- `/history` returns recent context after a gateway restart.
- Memory use does not grow without bound.

---

### Phase 5: Orchestration State and Endpoints (Minimal)

5.1 Add orchestration state to gateway
- Add a simple `orchestrationState` in the constructor:
  - `mode`, `topic`, `round`, `maxRounds`, `turnOrder`, `currentTurn`, `proposals`, `votes`, `plan`, `planIndex`.

5.2 Add `/mode` GET/POST with validation
- POST: validate `mode` is in allowed set, ensure `turnOrder` is an array of known agent IDs.
- GET: return current state.

5.3 Add `/turn/next`
- Advance to the next agent; increment rounds; return to freeform after maxRounds.

5.4 Broadcast mode changes
- Use `broadcastSystemMessage` to announce mode changes and turns.

Acceptance:
- `/mode` and `/turn/next` work via curl or the human controller.
- Mode changes are visible to all clients.

---

### Phase 6: Human Interface Orchestration Commands

6.1 Add `/mode`, `/status`, `/next`, `/end`
- Implement the commands in `chat-controller.js`.
- `/mode debate <topic> --rounds N` parses topic and rounds.

6.2 Update `/help` output
- Document new commands and syntax.

Acceptance:
- Human CLI can switch modes and advance turns.

---

### Phase 7: Orchestrator Integration (Haiku, Minimal)

7.1 Use existing sidecar for orchestrator
- Do not create a new sidecar; reuse `csp_sidecar.py` with `--initial-prompt`.

7.2 Add an orchestrator launch option (dedicated pane)
- Update `bin/start-llm-groupchat.sh` to optionally spawn a 5th pane running a lightweight model (Claude Haiku).
- Use an environment variable like `CSP_ORCH_CMD` to avoid hardcoding the binary or model flags.
- Example intent: `CSP_ORCH_CMD="claude --model haiku --dangerously-skip-permissions"`.

7.3 Add orchestrator command helpers
- Add `@mode.set` and `@mode.status` to `AgentCommandProcessor` so the orchestrator can drive `/mode` without changes to the model binary.

7.4 Adopt Puzld-style debate/consensus flow templates
- In the orchestrator prompt, define phase scripts:
  - Debate: Round 1 (positions), Rounds 2..N (responses), final synthesis.
  - Consensus: Proposal phase, Vote phase (strict vote format), Synthesis phase.
- Use fixed response formats so the orchestrator can parse winners with simple string matching.

7.5 Turn-based output sharing
- Treat `/share` and `/noshare` as control commands (handled by sidecar, not injected).
- Orchestrator sends `/share` to the current agent and `/noshare` to others at each turn change.
- Keeps real-time output in each pane while preventing cross-pane ANSI flooding.

Acceptance:
- Orchestrator can set mode and request status using chat commands.
- Orchestrator can run a debate/consensus flow without manual prompting between turns.
- Only the active agent shares output to the group stream when in structured modes.

---

### Phase 8: Soft Turn Enforcement (No Hard Blocking)

8.1 Add `mode_signal` support in gateway message envelope
- For structured modes, tag messages for non-current agents as `turn_wait` and for current agent as `your_turn`.

8.2 Respect `mode_signal` in sidecar
- If `turn_wait`, queue a local notice without injecting into the agent.
- If `your_turn`, prepend a short marker before injection.

Acceptance:
- Agents are visually guided without forcibly blocking output.

---

### Phase 9: Documentation Updates

9.1 Update docs to reflect new commands and behaviors
- `README.md` and `docs/current/LLMGroupChat.md`:
  - `/mode`, `/status`, `/next`, `/end`, `/share`, `/noshare`.
  - Agent ID format.
  - Orchestrator optional launch.

Acceptance:
- Docs reflect the actual feature set and commands.

---

## Validation Checklist

- Claude launches successfully from the launcher.
- Three agents can run simultaneously without ID collisions.
- No ANSI spam after a normal message.
- `/share` explicitly enables output sharing; `/noshare` disables it.
- `/history` returns recent messages after a gateway restart.
- `/mode` and `/turn/next` work end-to-end.
- Orchestrator can set and query modes.
- Debate/consensus flow works with structured phases and visible, turn-based output.

---

## Notes on Scope

This plan intentionally avoids:
- Hard enforcement of turn-taking (kept soft).
- New storage layers or databases.
- Extensive new UI work.

The goal is to make CSP stable and orchestration-ready without adding complexity beyond the current architecture.

---
