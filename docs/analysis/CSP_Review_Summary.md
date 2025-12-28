# CSP: CLI Sidecar Protocol - Project Review

## Overview
The CLI Sidecar Protocol (CSP) is an orchestration layer that turns standalone CLI tools into participants of a real-time, collaborative multi-agent group chat with optional structured modes and turn-taking. It preserves full terminal fidelity (ANSI, spinners, interactive prompts) while enabling cross-agent coordination.

## Core Architecture
The project is built on a robust "v2" Push Architecture consisting of three primary components:

1.  **CSP Gateway (Node.js):** Central message broker with WebSockets + HTTP fallback, JSONL history persistence, orchestration state, turn signals, and warning/timeout enforcement. It validates orchestrator commands against a strict allowlist.
2.  **CSP Sidecar (Python):** PTY proxy that preserves CLI fidelity, injects inbound messages with timeout-based flow control, and interprets agent commands (`@send`, `@all`, `@mode.*`, `@working`, `NOOP`). Output sharing is explicit via `/share` and `/noshare`.
3.  **Human Interface:** CLI chat controller for message routing and mode/turn control (`/mode`, `/status`, `/next`, `/end`).

## Key Capabilities
CSP avoids the fragility of pipe-based automation while preserving native CLI behavior. It adds structured collaboration (debate/consensus/autopilot), soft turn guidance (`turnSignal`, `[YOUR TURN]` markers), and explicit turn timing controls (`@working`, warning/timeout thresholds). The system keeps deployment minimal with local-only bindings, auto-generated auth tokens, and simple env-based configuration.
