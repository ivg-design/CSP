# CLI Sidecar Protocol (CSP) - Architectural Review & Enhancement Proposal

## 1. Validation Summary
The proposed **CSP Architecture** effectively addresses a critical gap in the current LLM tooling landscape: **orchestrating native CLI agents without wrapping/crippling them.**

### Strengths
- **Native Experience:** Preserving the `stdin/stdout` of tools like `claude` or `gemini-cli` is the correct approach. Wrappers often lag behind upstream features.
- **Process Isolation:** Using standard OS process isolation (via `tmux` panes) is superior to shared-memory or single-process threading for stability.
- **Protocol-First:** Adopting MCP (Model Context Protocol) ensures future-proofing and interoperability.

### Critical Vulnerabilities in Current Proposal
1. **Input Injection Fragility (`script` + `cat > /dev/tty`)**:
   - *Issue:* Writing directly to `/dev/tty` or injecting via `ioctl` is race-condition prone. It can corrupt the visual state of the terminal (ncurses/spinners) and interleave with actual user typing.
   - *Risk:* High. Agents might "type" over a user's half-finished sentence.

2. **Output Capture Unreliability (`tail -f typescript`)**:
   - *Issue:* Reading a raw `typescript` file is difficult because it contains partial flushes, ANSI escape codes, and lacks semantic boundaries (start/end of turn).
   - *Risk:* Medium. The "Gateway" might broadcast incomplete sentences or raw ANSI junk.

3. **Identity Confusion**:
   - *Issue:* A native CLI tool like `claude` has no concept of "Group Chat". If Agent B says "Run tests", and we inject that into Agent A's stdin, Agent A thinks the *Human* said "Run tests".
   - *Risk:* High. Loss of context ("Who said what?").

## 2. Enhanced Architecture: CSP v2

To solve the vulnerabilities while keeping the "Sidecar" philosophy, we upgrade the **Sidecar** from a passive listener to an **Active PTY Proxy**.

### Core Change: The "Man-in-the-Middle" Sidecar
Instead of running `cli & sidecar &`, the Sidecar *becomes* the parent process.

**Current (Fragile):**
```bash
# Sidecar watches from the side
native_cli <--> TTY
       ^
       |
    Sidecar
```

**Proposed (Robust):**
```bash
# Sidecar owns the PTY
Sidecar (PTY Master) <--> native_cli (PTY Slave)
   ^
   |
   v
Gateway / Real TTY
```

### Technical Stack Upgrades
1.  **Sidecar Engine:** Switch from Bash (`script`) to **Python (`pty` / `pexpect`)** or **Node.js (`node-pty`)**. This allows precise control over the terminal dimensions and signal propagation.
2.  **Semantic Injection:** When Agent B sends a message, the Sidecar injects it into Agent A's input stream **prefixed with context**.
    -   *Injection:* `[Context: Message from Gemini] Check the database schema.`
3.  **State Detection:** The Sidecar monitors the output stream for the agent's specific **Prompt String** (e.g., `> ` or `?`) to know when the agent is "Listening" vs "Thinking".

## 3. Implementation Roadmap (Revised)

### Phase 1: Robust Sidecar (Python Implementation)

We replace `bin/csp-sidecar` with a robust Python proxy.

```python
# src/sidecar/proxy.py
import os
import pty
import select
import sys
import threading
import requests

class SidecarProxy:
    def __init__(self, command, agent_name, gateway_url):
        self.command = command
        self.agent_name = agent_name
        self.gateway_url = gateway_url
        self.master_fd = None
        
    def run(self):
        # Fork the child process with a pseudo-terminal
        pid, self.master_fd = pty.fork()
        
        if pid == 0: # Child
            os.execvp(self.command[0], self.command)
        else: # Parent (Sidecar)
            self.loop(pid)

    def loop(self, child_pid):
        # Set raw mode for exact forwarding
        import tty
        tty.setraw(sys.stdin.fileno())
        
        try:
            while True:
                r, _, _ = select.select([self.master_fd, sys.stdin], [], [])
                
                if self.master_fd in r:
                    # Output from Agent CLI
                    data = os.read(self.master_fd, 1024)
                    if not data: break
                    
                    # 1. Write to real stdout (user sees it)
                    os.write(sys.stdout.fileno(), data)
                    
                    # 2. Stream to Gateway (Debounced/Buffered)
                    self.broadcast_output(data)

                if sys.stdin in r:
                    # Input from Real User
                    data = os.read(sys.stdin.fileno(), 1024)
                    
                    # 1. Write to Agent CLI
                    os.write(self.master_fd, data)
                    
                    # 2. Log User Input to Gateway
                    self.log_input(data)
                    
        finally:
            # Cleanup
            pass

    def inject_message(self, sender, message):
        # Formatted injection so the Agent knows context
        formatted = f"\n(Message from {sender}): {message}\n"
        os.write(self.master_fd, formatted.encode())
```

### Phase 2: The "Group Chat" Overlay
The `Human Command Center` should not just be a chat client, but a **Session Controller**.
- **Mode A (Focus):** User interacts directly with one Agent (Native CLI feel).
- **Mode B (Orchestration):** User types into the Command Center; the Controller routes the prompt to *all* or *specific* agents via their Sidecars.

### Phase 3: Protocol Alignment
- **MCP Server:** The CSP Gateway should expose itself as an MCP Server.
- **Tool Use:** Agents can use a `send_message` tool provided by the Sidecar (via a local MCP endpoint) instead of just relying on stdout scraping. This is much more reliable.

## 4. Strategic Recommendation
1.  **Adopt the "Proxy" pattern** immediately. The `script` approach will fail in complex ncurses apps.
2.  **Standardize on MCP** for the *internal* communication between Sidecar and Agent (if the Agent supports MCP). If not, fall back to the PTY injection.
3.  **Build a "Reference Implementation"** using `node-pty` (excellent cross-platform support) or Python `pty` (built-in, easy).

This architecture turns a "hacky script" into a "Production-Grade Terminal Orchestrator."
