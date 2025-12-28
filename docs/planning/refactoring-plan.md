# CSP Refactoring Plan

**Date:** 2025-12-27
**Goal:** Modularize codebase for maintainability while preserving AI-assisted development efficiency

---

## Current State

| File | Lines | Concerns |
|------|-------|----------|
| `csp_sidecar.py` | 1118 | 5 classes, mixed responsibilities |
| `csp_gateway.js` | 704 | 1 class, growing orchestration logic |
| `chat-controller.js` | 415 | Single purpose, OK as-is |

---

## Target Structure

```
CSP/
├── bin/
│   ├── start-llm-groupchat.sh    # Launcher (sources preflight checks)
│   └── lib/
│       └── preflight.sh          # Startup validation helpers
├── src/
│   ├── gateway/
│   │   ├── index.js                 # Entry point, server setup
│   │   ├── gateway.js               # CSPGateway class (core routing)
│   │   ├── orchestration.js         # Mode/turn state machine
│   │   ├── heartbeat.js             # Heartbeat + timeout logic
│   │   └── validation.js            # Command validation
│   │
│   ├── sidecar/
│   │   ├── __init__.py
│   │   ├── __main__.py              # Entry point
│   │   ├── sidecar.py               # CSPSidecar class (core PTY)
│   │   ├── commands.py              # AgentCommandProcessor
│   │   ├── flow_control.py          # FlowController + queue logic
│   │   ├── stream.py                # StreamCleaner + sanitization
│   │   └── gateway_client.py        # WebSocket/HTTP client
│   │
│   └── human-interface/
│       └── chat-controller.js       # (no change needed)
│
├── csp_sidecar.py                   # Thin wrapper → src/sidecar/__main__.py
└── ...
```

---

## Module Interaction Diagram

```
start-llm-groupchat.sh
  -> bin/lib/preflight.sh
  -> tmux panes
      -> chat-controller.js (human)
      -> csp_sidecar.py (agents, orchestrator)
           -> src/sidecar/__main__.py
           -> sidecar.py
                -> commands.py
                -> flow_control.py
                -> stream.py
                -> gateway_client.py

gateway/index.js
  -> gateway.js (routing, history, WS/HTTP)
       -> orchestration.js (mode, turn state)
       -> heartbeat.js (heartbeat + timeouts)
       -> validation.js (orchestrator allowlist)
```

Notes:
- The orchestrator is just another sidecar instance with a strict command allowlist.
- `gateway.js` remains the source of truth; other modules are helpers.

---

## Refactoring Principles

1. **Domain boundaries** - Split by responsibility, not arbitrary line counts
2. **Preserve imports** - Keep `python csp_sidecar.py` working via thin wrapper
3. **No behavior changes** - Pure refactor, no new features
4. **Test after each module** - Verify functionality preserved
5. **Parallel-safe** - Claude and Codex work on different languages
6. **Keep existing guards** - Orchestrator allowlist stays strict; `@working` remains agent-only

---

## Task Assignment

### Claude Tasks (Python/Sidecar)

| Task | File | Extract To | Lines | Priority |
|------|------|------------|-------|----------|
| **P1** | `csp_sidecar.py` | `src/sidecar/commands.py` | ~200 | High |
| **P2** | `csp_sidecar.py` | `src/sidecar/flow_control.py` | ~100 | High |
| **P3** | `csp_sidecar.py` | `src/sidecar/stream.py` | ~80 | Medium |
| **P4** | `csp_sidecar.py` | `src/sidecar/gateway_client.py` | ~150 | Medium |
| **P5** | `csp_sidecar.py` | `src/sidecar/sidecar.py` | ~500 | Low |
| **P6** | `csp_sidecar.py` | `src/sidecar/__main__.py` | ~50 | Low |

### Codex Tasks (JavaScript/Gateway)

| Task | File | Extract To | Lines | Priority |
|------|------|------------|-------|----------|
| **G1** | `csp_gateway.js` | `src/gateway/orchestration.js` | ~150 | High |
| **G2** | `csp_gateway.js` | `src/gateway/heartbeat.js` | ~80 | High |
| **G3** | `csp_gateway.js` | `src/gateway/validation.js` | ~30 | Medium |
| **G4** | `csp_gateway.js` | `src/gateway/gateway.js` | ~400 | Low |
| **G5** | `csp_gateway.js` | `src/gateway/index.js` | ~50 | Low |

### Launcher/Bootstrap Tasks

| Task | File | Extract To | Priority |
|------|------|------------|----------|
| **L1** | `bin/start-llm-groupchat.sh` | `bin/lib/preflight.sh` | Medium |

---

## Detailed Task Specifications

### P1: Extract AgentCommandProcessor

**Source:** `csp_sidecar.py` lines 44-294
**Target:** `src/sidecar/commands.py`

```python
# src/sidecar/commands.py
"""Agent command detection and execution"""

import re
import requests
from datetime import datetime

class AgentCommandProcessor:
    """Intercepts and handles @-commands in agent output"""

    def __init__(self, agent_id, gateway_url, auth_token):
        ...

    def detect_commands(self, text: str) -> list:
        ...

    def execute_command(self, command_type: str, args: dict) -> str:
        ...

    # All _execute_* methods, including @working / WORKING handling
```

**Acceptance:** Import works; `@send`, `@all`, `@mode.*`, `@working`, and `NOOP` behave identically to the current monolith.

---

### P2: Extract FlowController

**Source:** `csp_sidecar.py` lines 323-402
**Target:** `src/sidecar/flow_control.py`

```python
# src/sidecar/flow_control.py
"""Flow control for safe message injection"""

import re
import time
import collections

class FlowController:
    """Controls when to inject messages to avoid corrupting CLI sessions"""

    def __init__(self, min_silence=0.3, long_silence=2.0, max_queue=50):
        ...

    def on_output(self, data: bytes):
        ...

    def is_idle(self) -> bool:
        ...

    def enqueue(self, sender: str, content: str, priority: str = "normal"):
        ...

    def pop_ready(self):
        ...
```

**Acceptance:** Flow control behavior unchanged, queue works correctly.

---

### P3: Extract StreamCleaner

**Source:** `csp_sidecar.py` lines 296-321
**Target:** `src/sidecar/stream.py`

```python
# src/sidecar/stream.py
"""ANSI escape sequence handling and stream sanitization"""

import re

class StreamCleaner:
    """Stateful ANSI stripper that tolerates chunked sequences"""
    ...

def sanitize_stream(text: str) -> str:
    """Remove ANSI escapes and control characters"""
    ...
```

**Acceptance:** ANSI stripping works, no false positives on legitimate text.

---

### P4: Extract Gateway Client

**Source:** `csp_sidecar.py` lines 755-885 (WebSocket + HTTP polling)
**Target:** `src/sidecar/gateway_client.py`

```python
# src/sidecar/gateway_client.py
"""Gateway communication (WebSocket with HTTP fallback)"""

import websocket
import requests
import urllib.parse

class GatewayClient:
    """Manages connection to CSP Gateway"""

    def __init__(self, gateway_url, agent_id, auth_token, on_message):
        ...

    def connect(self):
        ...

    def run(self):
        """Main listener loop with reconnection"""
        ...
```

**Acceptance:** WebSocket connects, HTTP fallback works, reconnection logic preserved.

---

### G1: Extract Orchestration Module

**Source:** `csp_gateway.js` orchestration-related code
**Target:** `src/gateway/orchestration.js`

```javascript
// src/gateway/orchestration.js
/**
 * Orchestration state machine for structured collaboration modes
 */

class OrchestrationManager {
  constructor() {
    this.state = {
      mode: 'freeform',
      topic: '',
      round: 0,
      maxRounds: 3,
      turnOrder: [],
      currentTurnIndex: 0,
      lastTurnChange: Date.now(),
      warningIssued: false
    };
  }

  setMode(mode, topic, rounds, agents) { ... }
  advanceTurn() { ... }
  resetTurnTimer() { ... }
  getCurrentTurnAgent() { ... }
  getTurnSignal(targetAgent) { ... }
  getStatus() { ... }
}

module.exports = { OrchestrationManager };
```

**Acceptance:** Mode changes work, turn advancement correct, timer reset logic preserved, state queries return expected values.

---

### G2: Extract Heartbeat Module

**Source:** `csp_gateway.js` heartbeat/timeout intervals
**Target:** `src/gateway/heartbeat.js`

```javascript
// src/gateway/heartbeat.js
/**
 * Heartbeat mechanism for orchestrator liveness
 */

class HeartbeatManager {
  constructor(gateway, orchestration, options = {}) {
    this.gateway = gateway;
    this.orchestration = orchestration;
    this.interval = options.interval || 30000;
    this.turnWarnMs = options.turnWarnMs || 90000;
    this.turnTimeoutMs = options.turnTimeoutMs || 120000;
    this.lastOrchestratorResponse = Date.now();
    this.missedHeartbeats = 0;
  }

  start() { ... }
  stop() { ... }
  onOrchestratorResponse() { ... }
  buildHeartbeatMessage() { ... }
}

module.exports = { HeartbeatManager };
```

**Acceptance:** Heartbeats sent every 30s, warning/timeout enforced at configured thresholds, missed heartbeat warnings work.

---

### G3: Extract Validation Module

**Source:** `csp_gateway.js` isValidOrchestratorCommand
**Target:** `src/gateway/validation.js`

```javascript
// src/gateway/validation.js
/**
 * Message validation for orchestrator commands
 */

const ORCHESTRATOR_ALLOWLIST = [
  /^@mode\.set\s+\w+\s+"[^"]+"/,
  /^@mode\.status\s*$/,
  /^@send\.[\w-]+\s+.+/,
  /^@all\s+.+/,
  /^@query\.log(\s+\d+)?$/,
  /^NOOP\s*$/
];

function isValidOrchestratorCommand(content) {
  return ORCHESTRATOR_ALLOWLIST.some(re => re.test((content || '').trim()));
}

module.exports = { isValidOrchestratorCommand, ORCHESTRATOR_ALLOWLIST };
```

**Acceptance:** Valid commands pass, invalid commands rejected with 400.

---

### L1: Extract Preflight Checks

**Source:** `bin/start-llm-groupchat.sh` preflight functions
**Target:** `bin/lib/preflight.sh`

```bash
# bin/lib/preflight.sh
preflight_checks() {
  require_cmd tmux
  require_cmd node
  require_cmd python3
  if [[ -z "${CSP_AUTH_TOKEN:-}" ]]; then
    require_cmd openssl
  fi

  check_cli_cmd "Claude" "${CSP_CLAUDE_CMD:-claude --dangerously-skip-permissions}"
  check_cli_cmd "Gemini" "${CSP_GEMINI_CMD:-gemini}"
  check_cli_cmd "Codex" "${CSP_CODEX_CMD:-codex}"
  if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
    check_cli_cmd "Orchestrator" "${CSP_ORCH_CMD:-claude --model haiku --dangerously-skip-permissions}"
  fi

  # Permissions/paths
  assert_readable "${CSP_CONFIG_FILE:-config/csp.env}"
  assert_writable "$PROJECT_ROOT/gateway.log"
}
```

Checks to include:
- Required binaries: `tmux`, `node`, `python3`, `openssl` (only if token not set)
- Configured CLIs: Claude, Gemini, Codex, Orchestrator
- Basic permissions: config readable (if present), log path writable

**Acceptance:** `start-llm-groupchat.sh` sources `bin/lib/preflight.sh`, prints missing dependency warnings (or exits when `CSP_STRICT_CLI_CHECK=1`).

---

## Implementation Order

### Phase 0: Bootstrap Preflight (Sequential)

```
Codex: L1 (preflight.sh extraction)
```

### Phase 1: High Priority (Parallel)

```
Claude: P1 (commands.py) + P2 (flow_control.py)
Codex:  G1 (orchestration.js) + G2 (heartbeat.js)
```

### Phase 2: Medium Priority (Parallel)

```
Claude: P3 (stream.py) + P4 (gateway_client.py)
Codex:  G3 (validation.js)
```

### Phase 3: Low Priority (Sequential)

```
Claude: P5 (sidecar.py) + P6 (__main__.py)
Codex:  G4 (gateway.js) + G5 (index.js)
```

---

## Testing Checklist

After each module extraction:

- [ ] Unit: New module imports without errors
- [ ] Integration: `./bin/start-llm-groupchat.sh` launches successfully
- [ ] Integration: Preflight warnings are accurate; strict mode fails fast
- [ ] Functional: Message routing works
- [ ] Functional: Orchestration modes work
- [ ] Functional: Heartbeat/timeout work
- [ ] Functional: `@working` resets turn timer for current agent

---

## Rollback Plan

Keep original files until all tests pass:

```bash
# Before starting
cp csp_sidecar.py csp_sidecar.py.backup
cp src/gateway/csp_gateway.js src/gateway/csp_gateway.js.backup

# If refactor fails
git checkout csp_sidecar.py src/gateway/csp_gateway.js
```

---

## Notes

- **No new features** during refactor - pure structural change
- **Preserve thin wrapper** - `python csp_sidecar.py` must still work
- **Avoid circular imports** - Plan dependency graph carefully
- **Document exports** - Each module should have clear public API

---

*This plan enables parallel work without file conflicts.*
