# CSP: CLI Sidecar Protocol

**Turn any CLI tool into a collaborative Multi-Agent Group Chat participant.**

## Overview

CSP allows you to run native CLI agents (Claude, Gemini, Codex, plain Bash) in a **tmux** session where they can:
1. **Talk to each other** (Agent-to-Agent collaboration)
2. **Talk to you** (via Real-Time Push Chat)
3. **Collaborate in structured modes** (Debate, Consensus, Autopilot)
4. **Retain full native fidelity** (Spinners, Colors, Interactive Prompts work perfectly)

## Quick Start

```bash
# 1. Clone & Install
git clone https://github.com/ivg-design/CSP.git
cd CSP
npm install

# 2. Launch the Group Chat
# Generates CSP_AUTH_TOKEN and starts Gateway + tmux
./bin/start-llm-groupchat.sh
```

## Orchestrator Mode (Optional)

Launch with a dedicated orchestrator pane (lightweight Claude Haiku by default):

```bash
CSP_ORCHESTRATOR=1 ./bin/start-llm-groupchat.sh
```

You can override the orchestrator command:

```bash
CSP_ORCHESTRATOR=1 CSP_ORCH_CMD="claude --model haiku --dangerously-skip-permissions" ./bin/start-llm-groupchat.sh
```

The orchestrator can:
- Set collaboration modes: `@mode.set debate "topic"`
- Check status: `@mode.status`
- Coordinate turn-taking across agents

## Key Features

### Real-Time Push Architecture
- **WebSockets**: Gateway pushes messages instantly to all agents
- **Auto-Reconnect**: Clients handle network blips with exponential backoff
- **HTTP Fallback**: Robust polling ensures delivery even if WS fails

### Orchestration Modes
- **Freeform** (default): Agents communicate freely
- **Debate**: Structured rounds with turn-based responses
- **Consensus**: Proposal and voting phases
- **Autopilot**: Agent-driven task execution

### Smart Flow Control
- **Timeout-Based Injection**: Waits up to 500ms for idle, then injects safely
- **Urgent Bypass**: Prefix `!` (e.g., `!stop`) to interrupt immediately
- **Manual Control**: `/pause` and `/resume` commands

### Unique Agent Identity
- Gateway enforces unique IDs: `claude`, `claude-2`, `claude-3`
- Dashed IDs fully supported in addressing

### Secure & Simple
- **Auth**: Auto-generated `CSP_AUTH_TOKEN` secures the local mesh
- **Env Config**: `CSP_GATEWAY_URL` automatically propagated to all panes

## Commands

### Human Controller
| Command | Description |
|---------|-------------|
| `@agent message` | Send to specific agent (e.g., `@claude hello`) |
| `@all message` | Broadcast to all agents |
| `message` | Broadcast to all agents (default) |
| `/agents` | List connected agents |
| `/mode <mode> <topic>` | Start structured mode (debate/consensus) |
| `/status` | Show current mode and turn |
| `/next` | Advance to next turn |
| `/end` | Return to freeform mode |
| `@query.log [limit]` | Show chat history |
| `/help` | Show all commands |

### Mode Command Examples
```bash
# Start a debate with 3 rounds
/mode debate "Best approach to implement caching" --rounds 3 --agents claude,codex,gemini

# Check current status
/status

# Advance to next turn
/next

# End structured mode
/end
```

### Agent Commands (in sidecar)
| Command | Description |
|---------|-------------|
| `@send.<agent> message` | Send to specific agent |
| `@all message` | Broadcast to all |
| `/share` | Enable output sharing |
| `/noshare` | Disable output sharing |
| `/pause` | Pause message injection |
| `/resume` | Resume message injection |

## Agent IDs
All IDs are lowercase, dashes allowed. Multiple instances get suffixes:
- First instance: `claude`
- Second instance: `claude-2`
- Third instance: `claude-3`

## Documentation

- [**Development Roadmap**](docs/planning/development-roadmap-v1.md): Implementation plan and status
- [**Architecture Guide**](docs/current/LLMGroupChat.md): Full system design
- [**Analysis Documents**](docs/analysis/): Bug analysis and proposals

## Project Structure

```
CSP/
├── bin/                    # Launcher scripts
│   └── start-llm-groupchat.sh
├── src/
│   ├── gateway/            # Node.js Message Broker (WS/HTTP)
│   │   └── csp_gateway.js
│   └── human-interface/    # Human Chat CLI
│       └── chat-controller.js
├── csp_sidecar.py          # Python PTY Proxy
└── docs/
    ├── planning/           # Development plans
    ├── analysis/           # Bug analysis docs
    └── current/            # Architecture docs
```

## Recent Updates (2025-12-27)

- Fixed Claude launch (full binary path instead of alias)
- Fixed ANSI spam with conservative CSI stripping
- Added timeout-based flow control for TUI apps
- Added orchestration modes (debate, consensus)
- Added turn signals with ASCII markers
- Gateway enforces unique agent IDs
- History persists across gateway restarts
- Human interface supports `/mode`, `/status`, `/next`, `/end`
