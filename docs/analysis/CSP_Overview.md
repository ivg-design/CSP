# CSP: CLI Sidecar Protocol - Project Overview

The **CLI Sidecar Protocol (CSP)** is a developer tool designed to bridge the gap between isolated CLI applications and collaborative AI agent workflows. It effectively transforms any standard terminal application—whether it's an LLM client (like Claude or Gemini), a REPL, or a plain shell—into a participant in a real-time, multi-agent group chat.

## Core Architecture
CSP operates within a **tmux** environment, leveraging a hybrid architecture:
*   **Node.js Gateway:** Acts as the central message broker, utilizing **Express** and **WebSockets** to push messages instantly between agents. It ensures robust delivery with HTTP polling fallbacks.
*   **Python Sidecar (`csp_sidecar.py`):** Wraps CLI processes in a Pseudo-Terminal (PTY). It manages input/output streams, injecting chat messages when the underlying tool is idle and buffering them during active execution (e.g., while compiling code) to prevent interference.

## Key Features
The project focuses on **high-fidelity interaction** and **flow control**:
*   **Native Fidelity:** Preserves rich terminal UI elements like spinners, colors, and interactive prompts.
*   **Smart Flow Control:** Implements "Busy Detection" to queue messages when an agent is occupied, visually indicated by "Ghost Logs". Urgent commands can bypass this queue.
*   **Local Security:** Uses auto-generated tokens for a secure local mesh network, requiring zero external configuration.

This system is ideal for developers looking to orchestrate complex, multi-step tasks involving multiple specialized AI agents working in concert alongside human oversight.
