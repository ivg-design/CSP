# CSP Development Roadmap

## Vision

**CSP (CLI Sidecar Protocol)** enables real-time multi-agent collaboration where humans and AI agents work together visually in tmux panes. Unlike batch orchestration tools, CSP preserves the full interactive CLI experience while adding structured collaboration modes.

**Core Principles:**
- Native CLI fidelity (spinners, colors, interactive prompts)
- Real-time communication (WebSocket-first)
- Minimal overhead (thin PTY proxy)
- Human-in-the-loop by default

---

## Current State: v0.1 (Foundation) ✅

Released: 2025-12-27

### Completed Features
- **Gateway**: WebSocket + HTTP message broker with JSONL persistence
- **Sidecar**: PTY proxy with flow control and ANSI sanitization
- **Orchestration**: Freeform, Debate, Consensus modes
- **Turn Management**: Gateway-owned with timeout enforcement
- **Heartbeat System**: 30s interval with context snapshots
- **Identity**: Unique agent IDs with collision handling
- **Security**: Token-based auth, command validation for orchestrator
- **Configuration**: Environment variables + config file support

### Known Limitations
- Monolithic codebase (~1100 LOC sidecar, ~700 LOC gateway)
- No test suite
- Limited error recovery
- No plugin system

---

## v0.2 - Robustness (Next)

**Goal:** Production-quality codebase with tests and better error handling.

### Milestones

#### 0.2.1 - Modularization
- [ ] Split `csp_sidecar.py` into modules (commands, flow, stream, client)
- [ ] Split `csp_gateway.js` into modules (orchestration, heartbeat, validation)
- [ ] Preserve backward compatibility (`python csp_sidecar.py` still works)

#### 0.2.2 - Testing
- [ ] Unit tests for command parsing
- [ ] Unit tests for flow control logic
- [ ] Integration tests for message routing
- [ ] End-to-end test for debate mode

#### 0.2.3 - Error Recovery
- [ ] Graceful agent reconnection
- [ ] Orphan turn detection and recovery
- [ ] Gateway restart preserves active mode
- [ ] Sidecar crash recovery

#### 0.2.4 - Developer Experience
- [ ] `--dry-run` flag for launcher
- [ ] Verbose logging mode
- [ ] Health check endpoint
- [ ] Metrics endpoint (message counts, latencies)

---

## v0.3 - Extensibility

**Goal:** Enable customization without forking.

### Planned Features

#### Custom Modes
- Plugin interface for new orchestration modes
- Mode definition via YAML/JSON
- Example: `brainstorm`, `code-review`, `planning`

#### MCP Integration
- CSP as MCP server (expose gateway API)
- CSP as MCP client (connect to external tools)
- Tool discovery and routing

#### Web Dashboard (Optional)
- Real-time message visualization
- Mode control UI
- Agent status monitoring
- History browser

---

## v1.0 - Production Ready

**Goal:** Stable, documented, publishable.

### Requirements
- [ ] Semantic versioning
- [ ] Comprehensive documentation
- [ ] npm package (`@anthropic/csp-gateway`)
- [ ] PyPI package (`csp-sidecar`)
- [ ] Homebrew formula
- [ ] CI/CD pipeline
- [ ] Security audit

---

## Backlog (Unprioritized)

Ideas for future consideration:

| Feature | Description | Complexity |
|---------|-------------|------------|
| Token tracking | Count tokens per agent per session | Low |
| Rate limiting | Prevent agent flood | Low |
| Session persistence | Resume after restart | Medium |
| Agent profiles | Preset prompts and configs | Medium |
| Batch mode | Non-interactive execution | Medium |
| Remote agents | Agents on different machines | High |
| Multi-session | Multiple concurrent group chats | High |
| Voice integration | Speech-to-text input | High |

---

## Non-Goals

Things we explicitly won't pursue:

- **Replacing native CLIs** - CSP wraps, not replaces
- **Cloud hosting** - CSP is local-first
- **GUI-only interface** - CLI is primary
- **Agent-specific logic** - CSP is agent-agnostic
- **Prompt engineering** - Orchestrator prompt is user's responsibility

---

## Contributing

### Current Priorities
1. Modularization (see `docs/planning/refactoring-plan.md`)
2. Test coverage
3. Documentation improvements

### How to Help
- Report bugs via GitHub Issues
- Submit PRs for backlog items
- Improve documentation
- Share use cases and feedback

### Development Setup
```bash
git clone https://github.com/ivg-design/CSP.git
cd CSP
npm install
./bin/start-llm-groupchat.sh
```

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| v0.1 | 2025-12-27 | Initial release with core features |

---

## Related Documents

- [Architecture Guide](docs/current/LLMGroupChat.md) - System design and components
- [Refactoring Plan](docs/planning/refactoring-plan.md) - Code modularization tasks
- [Implementation Log](docs/planning/implementation-log-2025-12-27.md) - Detailed session notes

---

*Last updated: 2025-12-27*
