# LLM Group Chat: Multi-Agent CLI Orchestration

## 🚀 Quickstart

### 1. Prerequisites
- **Node.js** (v18+)
- **Python** (v3.8+)
- **tmux**
- **Native CLI Agents** installed (e.g., `claude`, `gemini`, `codex`, `gh`)

### 2. Start the System
Run the master orchestrator:

```bash
# Ensure scripts are executable
chmod +x bin/*.sh

# Starts Gateway + tmux session with auto-generated auth
./bin/start-llm-groupchat.sh
```

This will:
1.  Start the **CSP Gateway** (Message Broker) with **WebSocket Push** support.
2.  Generate a secure `CSP_AUTH_TOKEN`.
3.  Launch a **tmux session** with 4 panes:
    *   **Top:** Human Chat Controller (Consuming Push Stream)
    *   **Bottom (x3):** Agent Launchers (Sidecars with Flow Control)

### 3. Environment Variables
The system relies on these variables (automatically set by the launcher):
*   `CSP_AUTH_TOKEN`: Secure key for connecting to the Gateway.
*   `CSP_GATEWAY_URL`: Base URL (e.g., `http://localhost:8765`).

---

## 🏗️ Architecture: CSP v2 (Real-Time Push)

**CLI Sidecar Protocol (CSP)** is an infrastructure layer that enables native CLI tools to participate in a real-time group chat.

### Core Components

1.  **CSP Gateway (`csp_gateway.js`)**:
    *   **Push Transport**: Supports **WebSocket / SSE** (`/ws` or `/events`) for real-time message delivery.
    *   **Authentication**: Requires `X-Auth-Token` header (or `?token=` query param for WS).
    *   **Fallback**: Gracefully downgrades to high-frequency HTTP polling if WS is unavailable.

2.  **CSP Sidecar (`csp_sidecar.py`)**:
    *   **Push Consumer**: Subscribes to Gateway events for instant message injection.
    *   **PTY Proxy**: Wraps the native CLI to capture Output and inject Input.
    *   **Reconnect Logic**: Automatically reconnects with exponential backoff if the Gateway restarts.

3.  **Chat Controller**:
    *   Displays a real-time streaming view of the group chat.
    *   Consumes the same Push API as the sidecars.

---

## 🧠 Flow Control & Safety

CSP v2 ensures that automated messages don't break your interactive CLI sessions.

### 1. Busy vs. Idle State
The Sidecar intelligently monitors the agent's process state:
*   **BUSY** (e.g., `npm install` running): Incoming messages are **QUEUED**.
*   **IDLE** (Waiting at prompt `>`): Queued messages are **INJECTED**.

### 2. Ghost Logging
When messages are queued, you will see a **Ghost Log** in the terminal:
`[CSP queued 2 msg(s) waiting for idle]`
*   *Note:* This text is visible ONLY to you (the human). The agent process does not see it.

### 3. Urgent Commands (`!`)
To force an injection immediately (e.g., to stop a runaway process):
*   Prefix your message with `!`.
*   Example: `!stop` or `!^C`.
*   **Behavior:** Bypasses the Busy check and injects instantly.

### 4. Pause/Resume
Manually control the injection stream:
*   **Pause:** Send `/pause` (locks the input).
*   **Resume:** Send `/resume` (flushes the queue).

---

## 🧩 Usage Guide

### Group Chat
*   **Broadcast:** `@all Hello team` (Sent to everyone).
*   **Direct:** `@claude Check this code` (Sent only to Claude).

### Connecting Manually (for custom tools)
If you want to connect a custom tool to the mesh:

**1. Connect to WebSocket:**
`ws://localhost:8765/ws?token=YOUR_TOKEN`

**2. Listen for Events:**
```json
{
  "type": "message",
  "from": "claude",
  "content": "Hello world",
  "timestamp": "..."
}
```

**3. Send Message (HTTP):**
`POST /agent-output` with `X-Auth-Token` header.

---

## 🛠️ Troubleshooting

*   **No Messages?** Check `gateway.log`. Ensure `CSP_AUTH_TOKEN` is set.
*   **Agent Stuck?** Look for the "Ghost Log". If it says "queued", the sidecar thinks the agent is busy. Use `!stop` to unblock.
*   **Reconnecting...**: If you see this log, the Gateway might be down. The sidecar will retry automatically.