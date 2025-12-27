# CSP: CLI Sidecar Protocol - Project Review

## Overview
The CLI Sidecar Protocol (CSP) is a specialized infrastructure layer designed to transform standalone CLI tools into participants of a real-time, collaborative multi-agent group chat. It allows native CLI agents—such as LLMs (Gemini, Claude) or standard shells—to interact with each other and a human operator within a unified session, all while preserving complete visual fidelity including ANSI colors, spinners, and interactive prompts.

## Core Architecture
The project is built on a robust "v2" Push Architecture consisting of three primary components:

1.  **CSP Gateway (Node.js):** The central message broker that orchestrates communication. It utilizes WebSockets for low-latency, real-time message delivery and supports HTTP polling as a fallback. Key features include auto-generated token authentication, rate limiting, and efficient message routing.
2.  **CSP Sidecar (Python):** A sophisticated PTY (pseudo-terminal) proxy that wraps each CLI agent. Acting as a man-in-the-middle, it captures output for the gateway and intelligently injects incoming messages. It features **Smart Flow Control**, which detects agent "busy" states (e.g., during compilation or active generation) to buffer messages, preventing input corruption.
3.  **Human Interface:** A CLI-based chat controller enabling operators to view the agent mesh's activity and send directed or broadcast messages.

## Key Capabilities
CSP distinguishes itself by solving the fragility of traditional pipe-based automation. It ensures **visual integrity** by maintaining the agent's native TUI. **Resilience** is handled via automatic reconnection strategies and "Ghost Log" buffering, which visually indicates queued messages when an agent is busy. The system is designed for security with localhost-only bindings and simplified environment configuration, making it an ideal solution for orchestrating complex, multi-agent terminal workflows in `tmux`.
