# LLM Group Chat: CSP Architecture v2

## Executive Summary
The **CSP (CLI Sidecar Protocol) v2** represents a mature architectural evolution for orchestrating multi-agent CLI sessions. Unlike v1 which relied on fragile file scraping, v2 employs a **PTY Proxy Pattern** to strictly manage the lifecycle, I/O, and visual state of native CLI agents.

## Core Architecture

### 1. The PTY Sidecar (The "proxy")
Instead of running alongside the process, the Sidecar **wraps** the process.

```
┌──────────────────────┐
│  Tmux Pane           │
│                      │
│  ┌────────────────┐  │
│  │ CSP Sidecar    │  │  <-- Controls PTY Master
│  │ (Python/Node)  │  │
│  │       │        │  │
│  │   (PTY IO)     │  │
│  │       │        │  │
│  │ ┌────────────┐ │  │
│  │ │ Native CLI │ │  │  <-- Runs as PTY Slave
│  │ │ (Claude)   │ │  │
│  │ └────────────┘ │  │
│  └───────┬────────┘  │
│          │           │
│      WebSocket       │
│          │           │
└──────────┼───────────┘
           │
    ┌──────▼──────┐
    │ CSP Gateway │
    └─────────────┘
```

### 2. Communication Flow

#### Human Input
1. Human types in **Agent A's** pane.
2. Sidecar captures raw keystrokes.
3. Sidecar passes keystrokes to Agent A (Native experience).
4. Sidecar *also* logs input to Gateway (Context sharing).

#### Agent-to-Agent Message
1. **Agent A** generates output: "I need Agent B to check the logs."
2. Agent A's Sidecar detects this intent (via keyword or MCP tool call).
3. Sidecar sends message to Gateway.
4. Gateway routes to **Agent B**.
5. Agent B's Sidecar receives message.
6. Agent B's Sidecar **injects** text into Agent B's PTY:
   ```text
   [Context: Agent A sent a message]
   I need you to check the logs.
   ```
7. Agent B processes this as if the user typed it.

## Technical Specification

### 1. The Sidecar (`csp_sidecar.py`)
See `csp_sidecar.py` for reference implementation.
- **Tech:** Python `pty` (standard lib) or Node `node-pty`.
- **Role:** Terminal Emulator shim.
- **Key Capability:** Can pause user input while injecting agent messages to prevent race conditions.

### 2. The Gateway (`csp_gateway.js`)
A lightweight MCP (Model Context Protocol) server.
- **Endpoints:**
  - `POST /register`: New sidecar connects.
  - `WS /events`: Real-time message bus.
- **State:** Maintains "Room" state and "Chat History".

### 3. Protocol (JSON-RPC / MCP)
Standardized message envelope:
```json
{
  "jsonrpc": "2.0",
  "method": "chat.message",
  "params": {
    "from": "claude-1",
    "to": "broadcast",
    "content": "Analyzing database schema...",
    "meta": {
      "confidence": 0.9
    }
  }
}
```

## Deployment Strategy (Updated)

1. **Install Dependencies**:
   ```bash
   pip install requests
   npm install -g @modelcontextprotocol/sdk
   ```

2. **Launch Gateway**:
   ```bash
   node src/gateway.js &
   ```

3. **Launch Agents (via wrapper)**:
   ```bash
   # Instead of: claude
   python3 csp_sidecar.py --name="Claude" --cmd claude
   ```

## Advantages over v1
| Feature | v1 (Script/Tail) | v2 (PTY Proxy) |
|---------|------------------|----------------|
| **Reliability** | Low (Race conditions) | High (Kernel PTY) |
| **Visuals** | Broken (Spinners fail) | Perfect (Passthrough) |
| **Injection** | `echo > /dev/tty` (Messy) | `os.write(master_fd)` (Clean) |
| **Control** | Passive Observer | Active Gatekeeper |
