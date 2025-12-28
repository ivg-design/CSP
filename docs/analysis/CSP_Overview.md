# CSP: CLI Sidecar Protocol - Project Overview

The **CLI Sidecar Protocol (CSP)** is a developer tool that turns native CLI applications—LLM clients, REPLs, or shells—into participants in a real-time, multi-agent group chat with optional structured modes and turn-taking.

## Core Architecture
CSP operates within a **tmux** environment, leveraging a hybrid architecture:
*   **Node.js Gateway:** Central broker with **Express** + **WebSockets**, JSONL history persistence, and orchestration state (`/mode`, `/turn/next`, turn signals, warning/timeout).
*   **Python Sidecar (`csp_sidecar.py`):** PTY proxy that preserves CLI fidelity, injects messages safely, and interprets agent commands (`@send`, `@all`, `@mode.*`, `@working`, `NOOP`).
*   **Human Controller:** CLI for human operators to direct messages and manage modes.

## Key Features
The project focuses on **high-fidelity interaction** and **flow control**:
*   **Native Fidelity:** Preserves rich terminal UI elements like spinners, colors, and interactive prompts.
*   **Turn-Based Orchestration:** Debate/consensus/autopilot modes with turn signals and auto-advance.
*   **Turn Timing Controls:** Warning/timeout thresholds plus explicit `@working` extensions.
*   **Explicit Sharing:** Output sharing is opt-in via `/share` and `/noshare`.
*   **Local Security:** Auto-generated tokens secure the local mesh; gateway binds to localhost by default.

This system is ideal for developers looking to orchestrate complex, multi-step tasks involving multiple specialized AI agents working in concert alongside human oversight.
