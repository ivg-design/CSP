# Archive - Historical CSP Implementations

This directory contains deprecated/historical implementations of the CSP (CLI Sidecar Protocol) system. These files are preserved for reference but are no longer actively maintained.

## File Categories

### Message Broker System (Deprecated)
- `message_broker.py` - Old Python message broker implementation
- `start_message_broker.sh` - Message broker startup script

### Multi-Agent Terminal (Deprecated)
- `multi_agent_terminal.sh` - Initial multi-agent terminal implementation
- `multi_agent_terminal_v2.sh` - Improved version with better layout
- `multi_agent_layout.sh` - Terminal layout management script

### Agent Scripts (Deprecated)
- `claude_agent.sh` / `claude_manual.sh` - Old Claude agent implementations
- `codex_agent.sh` / `codex_manual.sh` - Old Codex agent implementations
- `gemini_agent.sh` / `gemini_manual.sh` - Old Gemini agent implementations
- `human_agent.sh` - Human interface agent script
- `agent_client.py` - Python agent client implementation
- `agent_communicator.sh` - Agent communication helper
- `agent_menu.sh` - Agent selection menu

### Human Interface (Deprecated)
- `human_command_prompt.sh` - Old human command interface

## Why These Were Replaced

These implementations were replaced by the current CSP v2 architecture because they:

1. **Relied on brittle file-based communication** instead of robust PTY proxy
2. **Lacked intelligent flow control** for safe message injection
3. **Had race conditions** and reliability issues
4. **Couldn't preserve native CLI experience** effectively
5. **Lacked production-grade error handling** and lifecycle management

## Current Implementation

The current production implementation is in:
- `../src/csp_sidecar.py` - Main CSP sidecar with intelligent flow control
- `../docs/current/LLMGroupChat.md` - Complete architecture and usage guide

---
*Files archived: November 24, 2024*