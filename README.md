# CSP: CLI Sidecar Protocol

**Turn any CLI tool into a collaborative Multi-Agent Group Chat participant.**

## 🌟 Overview

CSP allows you to run native CLI agents (Claude, Gemini, Codex, plain Bash) in a **tmux** session where they can:
1.  **Talk to each other** (Agent-to-Agent collaboration).
2.  **Talk to you** (via Real-Time Push Chat).
3.  **Retain full native fidelity** (Spinners, Colors, Interactive Prompts work perfectly).

## 🚀 Quick Start

```bash
# 1. Clone & Install
git clone https://github.com/your-repo/csp.git
cd csp
npm install

# 2. Launch the Orchestrator
# Generates CSP_AUTH_TOKEN and starts Gateway + tmux
./bin/start-llm-groupchat.sh
```

## ⚡ Key Features (v2)

### 📡 Real-Time Push Architecture
*   **WebSockets / SSE**: Gateway pushes messages instantly to all agents.
*   **Auto-Reconnect**: Clients handle network blips with exponential backoff.
*   **HTTP Fallback**: Robust polling ensures delivery even if WS fails.

### 🛡️ Smart Flow Control
*   **Busy Detection**: Prevents injecting text while an agent is running a command (e.g., compilation).
*   **Ghost Logs**: Visual indicator `[CSP queued 3 msgs]` shows you when messages are buffered.
*   **Urgent Bypass**: Prefix `!` (e.g., `!stop`) to interrupt a busy agent.
*   **Manual Control**: `/pause` and `/resume` commands.

### 🔐 Secure & Simple
*   **Auth**: Auto-generated `CSP_AUTH_TOKEN` secures the local mesh.
*   **Env Config**: `CSP_GATEWAY_URL` automatically propagated to all panes.

## 📚 Documentation

*   [**Architecture & Guide**](docs/current/LLMGroupChat.md): Full system design.
*   [**Protocol Comparison**](docs/current/CSP_vs_A2A.md): CSP vs. A2A.

## 📂 Project Structure

*   `bin/`: Launcher scripts (`start-llm-groupchat.sh`).
*   `src/gateway/`: Node.js Message Broker (WS/HTTP).
*   `src/human-interface/`: Human Chat CLI.
*   `csp_sidecar.py`: Python PTY Proxy (Push Consumer).