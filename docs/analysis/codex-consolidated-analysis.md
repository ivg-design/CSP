# CSP Deep Analysis: Issues, Fixes, and Detailed Development Plan (Amended)

Date: 2025-12-27
Analyst: Codex (GPT-5)
Sources: `CSP/PROPOSAL_MEMO.md`, `CSP/ANALYSIS_AND_FIXES.md`, code review of `CSP` repo

---

## Purpose

This document consolidates the findings from the memo and prior analysis, validates them against the current codebase, and provides a highly detailed, step-by-step plan to improve CSP without over-engineering.

---

## Current State Update (2025-12-27)

- Structured orchestration is implemented (`/mode`, `/turn/next`, turn signals, auto-advance).
- Turn timing includes warning/timeout plus explicit `@working`/`WORKING` extensions.
- Orchestrator pane is supported; strict command allowlist is enforced.
- History persists across restarts (JSONL load/cap).
- Agent IDs are unique and returned from the gateway; dashed IDs are supported.
- Output sharing is explicit (`/share`, `/noshare`) and ANSI sanitization is conservative.

---

## Current Implementation Review (Verified in Code)

### Gateway (`src/gateway/csp_gateway.js`)
- In-memory `chatHistory` backed by JSONL persistence (load on startup, cap in memory).
- HTTP endpoints: `/register`, `/agent-output`, `/message`, `/inbox/:agentId`, `/agents`, `/history`, `/mode`, `/turn/next`.
- WebSocket broadcast to all clients at `/ws`.
- Orchestration state (mode, round, turn order) with `turnSignal` and `currentTurn`.
- Turn warning/timeout enforcement with `@working`/`WORKING` extensions.
- Heartbeat context snapshots and strict orchestrator allowlist enforcement.

### Sidecar (`csp_sidecar.py`)
- Registers agent and uses gateway-returned `agentId`.
- Flow-control with timeout-based injection and queueing, plus manual pause/resume.
- Output sharing is opt-in via `/share` and `/noshare`.
- Command detection supports `@query.log`, `@send.<agent>`, `@all`, `@mode.set`, `@mode.status`, `@working`, `NOOP`.
- Turn markers (`[YOUR TURN]`) and waiting notices are shown on turn signals.

### Human Interface (`src/human-interface/chat-controller.js`)
- Supports `/agents`, `/help`, `@query.log`, `@agent`, `@all`.
- Supports `/mode`, `/status`, `/next`, `/end` for orchestration control.

### Launcher (`bin/start-llm-groupchat.sh`, `bin/csp-agent-launcher.sh`)
- tmux session with Human + 3 agents, plus optional orchestrator pane.
- Preflight CLI validation, config file support, and explicit `CSP_*_CMD` env overrides.

---

## Resolved Issues (Implemented)

1) **Claude launch via alias**
- Resolved by using explicit CLI command overrides in launcher.

2) **Output feedback loop and ANSI spam**
- Resolved by keeping sharing opt-in and improving ANSI sanitization.

3) **Agent ID collisions**
- Resolved with gateway-enforced unique IDs and sidecar adoption of the returned ID.

4) **Inconsistent addressing rules**
- Resolved with dashed ID support in `@send` and consistent lowercasing.

5) **History persistence write-only**
- Resolved by loading JSONL history on startup and capping memory use.

6) **Missing orchestration surfaces**
- Resolved with `/mode`, `/turn/next`, and turn signal support.

---

## Remaining Risks / Open Items

- Flow control is still heuristic; forced injection can collide with heavy TUI redraws.
- Turn timing depends on agents sending `@working` during long tasks.
- Orchestrator compliance relies on allowlist enforcement and a strict prompt; regression tests would help.

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

Status: Plan executed. The steps below are retained for historical traceability; current behavior is reflected in the update sections above.

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
- Turn warnings/timeouts trigger at configured thresholds.
- `@working` or `WORKING` extends the current turn timer.
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
