# CSP (CLI Sidecar Protocol) - Multi-Agent CLI Orchestration

## Project Structure

```
csp/
├── README.md                    # This file
├── src/                         # Current/Active Code
│   └── csp_sidecar.py          # Main CSP sidecar implementation
├── docs/                        # Documentation
│   ├── current/                 # Current documentation
│   │   └── LLMGroupChat.md     # Main architecture & implementation guide
│   ├── architecture/            # Architecture documentation
│   │   ├── CSP_ARCH_V2.md      # CSP v2 architecture specification
│   │   └── CSP_REVIEW.md       # Architectural review & analysis
│   ├── analysis/                # Analysis & comparison documents
│   │   ├── CSP_FIXES.md        # Implementation fixes & improvements
│   │   ├── CSP_vs_A2A.md       # CSP vs A2A comparison
│   │   └── A2A_vs_CSP.md       # Alternative comparison perspective
│   └── planning/                # Planning & design documents
│       ├── MULTI_AGENT_SYSTEM_GUIDE.md  # System design guide
│       └── agent_task_split.md  # Task distribution planning
└── .archive/                    # Deprecated/Historical files
    ├── multi_agent_*.sh        # Old terminal implementations
    ├── message_broker.py       # Previous messaging system
    ├── *_agent.sh              # Legacy agent scripts
    ├── *_manual.sh             # Manual implementations
    └── agent_*.py              # Old agent clients
```

## Quick Start

### Main Implementation
- **`src/csp_sidecar.py`** - Production-ready CSP sidecar with intelligent flow control
- **`docs/current/LLMGroupChat.md`** - Complete architecture, setup, and usage guide

### Key Features
- **Real-time multi-agent collaboration** while preserving native CLI experience
- **Intelligent message injection** with flow control to prevent command interruption
- **Production-grade PTY proxy** with ANSI cleaning and adaptive streaming
- **Pause/resume controls** for safe task management
- **Agent-specific tuning** optimized for Claude, Codex, and Gemini

### Usage
```bash
# Start CSP sidecar for an agent
python3 src/csp_sidecar.py --name="Claude" --gateway-url="http://localhost:8765" --auth-token="your-token" --cmd claude --dangerously-skip-permissions
```

## Documentation Organization

### Current Documentation
Latest architecture and implementation details.

### Architecture
Core system design, specifications, and architectural reviews.

### Analysis
Implementation analysis, fixes, and comparison studies.

### Planning
Design documents, system guides, and task planning materials.

### Archive
Historical implementations and deprecated code preserved for reference.

## Development Status

**Status: Production Ready**
- CSP v2 architecture implemented
- Intelligent flow control with adaptive streaming
- Production-grade error handling and lifecycle management
- Multi-agent coordination with pause/resume capabilities

## Contributing

This project represents a foundational infrastructure for multi-agent CLI orchestration. The current implementation in `src/` is production-ready and actively maintained.

---
*Last updated: November 24, 2024*