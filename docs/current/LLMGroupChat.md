# LLM Group Chat: Multi-Agent CLI Orchestration

## Overview

**CLI Sidecar Protocol (CSP)** enables native CLI tools (Claude, Gemini, Codex, etc.) to participate in real-time group chat with structured collaboration modes.

---

## Quick Start

### Prerequisites
- **Node.js** (v18+)
- **Python** (v3.8+)
- **tmux**
- **CLI Agents** installed (`claude`, `gemini`, `codex`)

### Launch

```bash
# Basic launch (4 panes: human + 3 agents)
./bin/start-llm-groupchat.sh

# With orchestrator (5 panes: human + orchestrator + 3 agents)
CSP_ORCHESTRATOR=1 ./bin/start-llm-groupchat.sh
```

Preflight CLI validation runs on launch. To fail fast when a configured CLI is missing:

```bash
CSP_STRICT_CLI_CHECK=1 ./bin/start-llm-groupchat.sh
```

### Configuration (Optional)

```bash
cp config/csp.env.example config/csp.env
# Edit to customize CLI commands, ports, etc.
```

Environment variables:
| Variable | Default | Description |
|----------|---------|-------------|
| `CSP_PORT` | 8765 | Gateway port |
| `CSP_AUTH_TOKEN` | auto-generated | Auth token |
| `CSP_GATEWAY_URL` | `http://127.0.0.1:8765` | Gateway base URL |
| `CSP_ORCHESTRATOR` | 0 | Enable orchestrator pane |
| `CSP_ORCH_CMD` | `claude --model haiku --dangerously-skip-permissions` | Orchestrator command |
| `CSP_CLAUDE_CMD` | `claude --dangerously-skip-permissions` | Claude CLI |
| `CSP_GEMINI_CMD` | `gemini` | Gemini CLI |
| `CSP_CODEX_CMD` | `codex` | Codex CLI |
| `CSP_STRICT_CLI_CHECK` | 0 | Fail if CLI missing |
| `CSP_INJECTION_TIMEOUT` | 0.5 | Max wait (seconds) before forced injection |
| `CSP_TURN_WARN_MS` | 90000 | Turn warning threshold (ms) |
| `CSP_TURN_TIMEOUT_MS` | 120000 | Turn timeout threshold (ms) |
| `CSP_CONFIG_FILE` | `config/csp.env` | Config file override |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      tmux Session                           │
├─────────────────────────────────────────────────────────────┤
│  Human Chat Controller          │  Orchestrator (optional)  │
│  (WebSocket consumer)           │  (Claude Haiku)           │
├─────────────────────────────────┴───────────────────────────┤
│  Claude Sidecar  │  Gemini Sidecar  │  Codex Sidecar        │
│  (PTY proxy)     │  (PTY proxy)     │  (PTY proxy)          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │     CSP Gateway         │
              │  (Node.js WebSocket)    │
              │                         │
              │  • Message routing      │
              │  • Orchestration state  │
              │  • Turn management      │
              │  • Heartbeat system     │
              │  • History persistence  │
              └─────────────────────────┘
```

### Components

1. **CSP Gateway** (`src/gateway/csp_gateway.js`)
   - WebSocket + HTTP message broker with JSONL history load/cap
   - Orchestration state and `/mode`, `/turn/next` endpoints
   - Turn signals (`turnSignal`, `currentTurn`) and auto-advance on response
   - Turn warning/timeout with configurable thresholds
   - Heartbeat context snapshots (30s interval)
   - Strict command validation for orchestrator and WORKING signal handling

2. **CSP Sidecar** (`csp_sidecar.py`)
   - PTY proxy wrapping native CLI
   - WebSocket subscription with HTTP fallback
   - Flow control (timeout-based injection with idle heuristic)
   - Agent command processing (`@send`, `@all`, `@mode.*`, `@working`, `NOOP`)
   - Turn markers (`[YOUR TURN]`) and waiting notices
   - Explicit sharing control (`/share`, `/noshare`)
   - ANSI scrubber tuned for chunked output

3. **Chat Controller** (`src/human-interface/chat-controller.js`)
   - Human CLI interface
   - Real-time message display
   - `/mode`, `/status`, `/next`, `/end`, `/agents`

---

## Orchestration Modes

### Freeform (default)
Agents communicate freely. Orchestrator observes silently.

### Debate
Structured rounds with turn-based responses:
```
/mode debate "Best caching strategy" --rounds 3 --agents claude,codex
```

Flow:
1. Round 1: Each agent presents position
2. Round 2+: Agents respond to each other
3. Final: Orchestrator synthesizes agreements/disagreements

### Consensus
Proposal and voting phases:
```
/mode consensus "Which database to use?"
```

Flow:
1. Phase 1: Each agent proposes solution
2. Phase 2: Agents vote (format: `VOTE: [A/B/C]`)
3. Phase 3: Orchestrator announces winner

---

## Turn Management

The **gateway is the source of truth** for turn progression:

| Event | Action |
|-------|--------|
| Agent responds during their turn | Gateway auto-advances |
| No response by `CSP_TURN_WARN_MS` | Gateway broadcasts warning |
| No response by `CSP_TURN_TIMEOUT_MS` | Gateway auto-advances with timeout message |
| Agent sends `@working` or `WORKING` | Gateway resets the current turn timer |
| Heartbeat (every 30s) | Orchestrator receives state context |

### Turn Signals
Messages include `turnSignal` field:
- `your_turn` - Agent should respond
- `turn_wait` - Not this agent's turn

Sidecar behavior:
- `your_turn`: injects `[YOUR TURN]` marker
- `turn_wait`: prints a waiting notice to stderr

---

## Commands

### Human Commands
| Command | Description |
|---------|-------------|
| `@agent message` | Send to specific agent |
| `@all message` | Broadcast to all |
| `/mode <mode> "<topic>"` | Start structured mode |
| `/status` | Show current mode/turn |
| `/next` | Advance turn manually |
| `/end` | Return to freeform |
| `/agents` | List connected agents |
| `@query.log [limit]` | Show chat history |

### Agent Commands (in sidecar)
| Command | Description |
|---------|-------------|
| `@send.<agent> message` | Send to specific agent |
| `@all message` | Broadcast to all |
| `@mode.set <mode> "<topic>"` | Set orchestration mode |
| `@mode.status` | Query current mode |
| `@query.log [limit]` | Query chat history |
| `@working [note]` | Extend current turn timeout |
| `NOOP` | No-op (orchestrator heartbeat response) |
| `/share` | Enable output sharing |
| `/noshare` | Disable output sharing |
| `/pause` | Pause message injection |
| `/resume` | Resume message injection |

### Urgent Commands
Prefix with `!` to bypass flow control:
```
!stop     # Immediate injection
!^C       # Send interrupt
```

---

## Flow Control

The sidecar uses timeout-based flow control to avoid corrupting active CLI sessions:

1. **Wait for idle** (up to 500ms, configurable via `CSP_INJECTION_TIMEOUT`)
2. **Inject if idle** or timeout reached
3. **Queue overflow protection** (max 50 messages, drops oldest)
4. **Stale message cleanup** (drops messages older than 5 minutes)

---

## Heartbeat System

The gateway sends heartbeats every 30 seconds to the orchestrator:

```json
{
  "type": "heartbeat",
  "content": "[HEARTBEAT] Elapsed: 45s, State: debate, Turn: claude",
  "context": {
    "mode": "debate",
    "round": 1,
    "maxRounds": 3,
    "currentTurn": "claude",
    "elapsed": 45000,
    "recentMessages": [...]
  }
}
```

The orchestrator must respond with exactly one command:
- `@mode.status` - Check state
- `@send.<agent> message` - Prompt agent
- `@all message` - Broadcast
- `@query.log [limit]` - Inspect recent history
- `NOOP` - No action needed

If 2 consecutive heartbeats are missed (60s), gateway warns about unresponsive orchestrator.

---

## Agent IDs

All IDs are lowercase, dashes allowed. Gateway enforces uniqueness:
- First instance: `claude`
- Second instance: `claude-2`
- Third instance: `claude-3`

---

## Security

- **Auth Token**: Auto-generated `CSP_AUTH_TOKEN` required for all API calls
- **Command Validation**: Orchestrator messages must match strict allowlist
- **Local Only**: Gateway binds to localhost by default

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No messages arriving | Check `gateway.log`, verify `CSP_AUTH_TOKEN` |
| Agent stuck/busy | Use `!stop` to force injection |
| "Reconnecting..." logs | Gateway may be down, sidecar retries automatically |
| Orchestrator unresponsive | Check for missed heartbeat warnings |
| Turn not advancing | Check `@working` usage and `CSP_TURN_TIMEOUT_MS` |

---

## File Structure

```
CSP/
├── bin/
│   ├── start-llm-groupchat.sh    # Main launcher
│   └── csp-agent-launcher.sh     # Agent menu
├── src/
│   ├── gateway/
│   │   └── csp_gateway.js        # Message broker
│   └── human-interface/
│       └── chat-controller.js    # Human CLI
├── csp_sidecar.py                # PTY proxy
├── orchestrator_prompt.txt       # Orchestrator system prompt
├── config/
│   └── csp.env.example           # Config template
└── docs/
    ├── current/                  # Architecture docs
    ├── planning/                 # Development plans
    └── analysis/                 # Bug analysis
```
