# CSP Deep Analysis: Issues & Proposed Fixes

**Date:** 2025-12-27
**Analyst:** Claude (Opus 4.5)

---

## Executive Summary

CSP has **three critical bugs** preventing it from working properly, plus **architectural gaps** that need addressing before adding puzld-style orchestration. This document provides root cause analysis with line-number references and concrete fixes.

---

## Issue 1: Claude Fails to Start

### Symptom
```
FileNotFoundError: [Errno 2] No such file or directory
```

### Root Cause
**File:** `csp_sidecar.py`, Line 395

```python
os.execvp(self.cmd[0], self.cmd)
```

The `os.execvp()` function searches the system PATH for executables. However, `claude` is a **shell alias**, not a binary in PATH:

```bash
$ which claude
claude: aliased to /Users/ivg/.claude/local/claude
```

Shell aliases are only resolved by the shell (bash/zsh), not by Python's `os.execvp()`.

### Fix
**Option A: Update launcher to use full paths**

Edit `bin/csp-agent-launcher.sh`:

```bash
# Line 59 - Change:
run_agent "Claude" "claude --dangerously-skip-permissions"

# To:
run_agent "Claude" "/Users/ivg/.claude/local/claude --dangerously-skip-permissions"
```

**Option B: Use shell execution in sidecar**

Edit `csp_sidecar.py`, Line 395:

```python
# Change:
os.execvp(self.cmd[0], self.cmd)

# To:
os.execvp('/bin/zsh', ['/bin/zsh', '-l', '-c', ' '.join(self.cmd)])
```

This launches a login shell that resolves aliases.

**Recommendation:** Option A is safer and more explicit.

---

## Issue 2: Codex ANSI Spam / Feedback Loop

### Symptom
```
💬 [2:03:09 PM] codex: K Tip: You can resume a previous conversation...31;2HK32;2HK33;24HK...
```

The chat is flooded with raw terminal escape sequences.

### Root Cause #1: share_enabled Bug
**File:** `csp_sidecar.py`, Line 774

```python
def inject_message(self, msg_obj):
    # ...
    # Enable sharing for the next outbound chunk when we receive any message
    self.share_enabled = True  # <-- BUG: This should NOT happen automatically
```

**The Design Intent (from comments on lines 332-335):**
```python
# Disable output streaming by default - TUI apps like Claude Code
# produce too much screen refresh garbage that floods the chat.
# Communication is ONE-WAY: Human → Agents (message injection only)
self.share_enabled = False
```

**The Bug:** Line 774 **overrides** this design by enabling sharing whenever ANY message is received. This creates a feedback loop:

1. Human sends message to Agent A
2. Agent A's `share_enabled` becomes `True`
3. Agent A's TUI output (full of ANSI codes) gets broadcast
4. Agent B receives broadcast → its `share_enabled` becomes `True`
5. Agent B's output gets broadcast back
6. **Exponential message explosion**

### Root Cause #2: Inadequate ANSI Filtering
**File:** `csp_sidecar.py`, Lines 195-219 (`StreamCleaner`)

```python
class StreamCleaner:
    """Stateful ANSI stripper that tolerates chunked sequences."""
    def process(self, data: bytes) -> str:
        # Only strips ESC sequences (0x1B followed by params)
        # Does NOT handle:
        # - CSI sequences without ESC prefix (cursor positioning like "31;2H")
        # - OSC sequences (operating system commands)
        # - DCS sequences (device control strings)
```

The additional sanitization in `_sanitize_stream()` (lines 618-633) has regex gaps:
```python
# This regex:
text = re.sub(r'(?:\d{1,3};)*\d{1,3}m', '', text)
# Only catches color codes ending in 'm', not cursor moves ending in 'H', 'K', 'J', etc.
```

The sequences like `31;2HK` are:
- `31;2H` = Move cursor to row 31, column 2
- `K` = Erase to end of line

These leak through because the cleaner strips ESC but leaves the parameter fragments.

### Fix for share_enabled Bug

**File:** `csp_sidecar.py`, Line 774

```python
# DELETE or comment out this line:
# self.share_enabled = True

# Replace with explicit opt-in via command:
if content.strip().lower() == '/share':
    self.share_enabled = True
    print(f"[CSP] Output sharing enabled for {self.agent_id}", file=sys.stderr)
    return
if content.strip().lower() == '/noshare':
    self.share_enabled = False
    print(f"[CSP] Output sharing disabled for {self.agent_id}", file=sys.stderr)
    return
```

### Fix for ANSI Filtering

**Option A: Use pyte library (recommended)**

```python
import pyte

class TerminalCleaner:
    def __init__(self, cols=120, rows=24):
        self.screen = pyte.Screen(cols, rows)
        self.stream = pyte.Stream(self.screen)

    def process(self, data: bytes) -> str:
        try:
            self.stream.feed(data.decode('utf-8', errors='ignore'))
            # Extract only visible text from virtual screen
            lines = [line.rstrip() for line in self.screen.display]
            return '\n'.join(line for line in lines if line.strip())
        except Exception:
            return ""
```

**Option B: More comprehensive regex (if pyte not available)**

```python
def _sanitize_stream(self, text: str) -> str:
    # Strip ALL CSI sequences (cursor, colors, erase, etc.)
    # CSI format: ESC [ <params> <final byte>
    # But ESC may already be stripped, so also match orphaned params

    # Remove complete CSI sequences
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)

    # Remove orphaned CSI parameters (no ESC prefix)
    # These end in: A-Z, a-z (cursor moves, colors, etc.)
    text = re.sub(r'(?<![a-zA-Z])[\d;]+[A-Za-z](?![a-zA-Z])', '', text)

    # Remove OSC sequences (ESC ] ... BEL or ESC ] ... ESC \)
    text = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?', '', text)

    # Remove DEC private modes (?NNNNh/l)
    text = re.sub(r'\?\d+[hl]', '', text)

    # Collapse whitespace
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)

    return text.strip()
```

---

## Issue 3: No Structured Orchestration

### Current State
The gateway (`src/gateway/csp_gateway.js`) has no concept of:
- Collaboration modes (debate, consensus, autopilot)
- Turn management
- Round tracking
- Context synthesis

All messages are flat broadcasts with no structure.

### Proposed Architecture

Add these to the gateway:

```javascript
// In CSPGateway constructor (after line 14)
this.orchestration = {
    mode: 'freeform',           // 'freeform' | 'debate' | 'consensus' | 'autopilot'
    topic: null,
    round: 0,
    maxRounds: 3,
    turnOrder: [],              // ['claude', 'codex', 'gemini']
    currentTurnIndex: 0,
    proposals: new Map(),       // agentId -> proposal text
    votes: new Map(),           // agentId -> voted-for agentId
    plan: [],                   // For autopilot: [{step, agent, status}]
    planIndex: 0
};

// New endpoints (after line 306)
app.post('/mode', (req, res) => {
    const { mode, topic, agents, rounds } = req.body;

    this.orchestration = {
        ...this.orchestration,
        mode: mode || 'freeform',
        topic: topic || null,
        round: 0,
        maxRounds: rounds || 3,
        turnOrder: agents || [],
        currentTurnIndex: 0,
        proposals: new Map(),
        votes: new Map()
    };

    this.broadcastSystemMessage(`🎭 Mode: ${mode.toUpperCase()} | Topic: ${topic || 'N/A'}`);

    if (mode === 'debate' && this.orchestration.turnOrder.length > 0) {
        const firstAgent = this.orchestration.turnOrder[0];
        this.broadcastSystemMessage(`📢 Round 1 | @${firstAgent} - Your turn to present your position.`);
    }

    res.json({ success: true, orchestration: this.orchestration });
});

app.get('/mode', (req, res) => {
    res.json(this.orchestration);
});

app.post('/turn/next', (req, res) => {
    if (this.orchestration.mode === 'freeform') {
        return res.status(400).json({ error: 'Not in structured mode' });
    }

    this.orchestration.currentTurnIndex++;

    if (this.orchestration.currentTurnIndex >= this.orchestration.turnOrder.length) {
        // Round complete
        this.orchestration.currentTurnIndex = 0;
        this.orchestration.round++;

        if (this.orchestration.round >= this.orchestration.maxRounds) {
            this.broadcastSystemMessage(`✅ ${this.orchestration.mode.toUpperCase()} complete. Returning to freeform.`);
            this.orchestration.mode = 'freeform';
            return res.json({ complete: true });
        }

        this.broadcastSystemMessage(`📢 Round ${this.orchestration.round + 1}`);
    }

    const currentAgent = this.orchestration.turnOrder[this.orchestration.currentTurnIndex];
    this.broadcastSystemMessage(`📢 @${currentAgent} - Your turn.`);

    res.json({
        success: true,
        currentTurn: currentAgent,
        round: this.orchestration.round
    });
});
```

---

## Issue 4: Human Interface Limitations

### Current State
The human interface (`src/human-interface/chat-controller.js`) only supports:
- `/agents` - List agents
- `/help` - Show help
- `@agent message` - Direct message
- `@query.log` - Show history

### Missing Commands for Orchestration

Add to `chat-controller.js` in the command handler (around line 265):

```javascript
// Mode commands
if (input.startsWith('/mode ')) {
    const parts = input.substring(6).trim().split(' ');
    const mode = parts[0];
    const topic = parts.slice(1).join(' ');

    await this.client.post('/mode', {
        mode,
        topic,
        agents: ['claude', 'codex', 'gemini'],  // Or parse from input
        rounds: 3
    });
    console.log(`\n🎭 Switched to ${mode} mode\n`);
    rl.prompt();
    return;
}

if (input === '/status') {
    const res = await this.client.get('/mode');
    const o = res.data;
    console.log(`\n📊 Mode: ${o.mode}`);
    console.log(`   Topic: ${o.topic || 'N/A'}`);
    console.log(`   Round: ${o.round + 1}/${o.maxRounds}`);
    if (o.turnOrder.length > 0) {
        console.log(`   Current turn: ${o.turnOrder[o.currentTurnIndex]}`);
    }
    console.log('');
    rl.prompt();
    return;
}

if (input === '/next') {
    await this.client.post('/turn/next');
    rl.prompt();
    return;
}

if (input === '/end') {
    await this.client.post('/mode', { mode: 'freeform' });
    console.log('\n🔄 Returned to freeform mode\n');
    rl.prompt();
    return;
}
```

---

## Implementation Priority

### Phase 1: Critical Bug Fixes (Do First)

1. **Fix Claude path** - Edit `bin/csp-agent-launcher.sh` line 59
2. **Remove share_enabled auto-enable** - Delete line 774 in `csp_sidecar.py`
3. **Add /share command** - Explicit opt-in for output sharing

### Phase 2: ANSI Filtering (High Priority)

4. Install pyte: `pip3 install pyte`
5. Replace `StreamCleaner` with `TerminalCleaner` using pyte

### Phase 3: Orchestration (New Feature)

6. Add `orchestration` state to gateway
7. Add `/mode`, `/turn/next` endpoints
8. Update human interface with mode commands

### Phase 4: Haiku Orchestrator (Advanced)

9. Create `orchestrator_sidecar.py` with hardcoded moderation prompt
10. Auto-launch orchestrator in 5-pane layout
11. Implement debate/consensus/autopilot flows

---

## Quick Fix Script

Run this to apply the critical fixes immediately:

```bash
cd /Users/ivg/github/CSP

# Fix 1: Claude path in launcher
sed -i '' 's|"claude --dangerously-skip-permissions"|"/Users/ivg/.claude/local/claude --dangerously-skip-permissions"|' bin/csp-agent-launcher.sh

# Fix 2: Disable auto-share (comment out line 774)
sed -i '' '774s/^/        # DISABLED: /' csp_sidecar.py

# Verify changes
grep -n "claude" bin/csp-agent-launcher.sh | head -3
grep -n "share_enabled = True" csp_sidecar.py
```

---

## Testing After Fixes

```bash
# 1. Kill any existing gateway
pkill -f csp_gateway

# 2. Start fresh
cd /Users/ivg/github/CSP && ./bin/start-llm-groupchat.sh

# 3. In agent pane, select Claude (should now work)

# 4. In human pane, send a message
# Codex should NOT flood with ANSI garbage anymore

# 5. Messages should be one-way: Human → Agents
# Agents should NOT auto-broadcast output
```

---

## Appendix: Message Flow Diagrams

### Current (Broken) Flow
```
Human → Gateway → Agent A (injects message)
                      ↓
              share_enabled = True
                      ↓
              Agent A output → Gateway → Agent B, Agent C
                                              ↓
                                    share_enabled = True
                                              ↓
                                    Agent B/C output → Gateway → ...
                                              ↓
                                    EXPONENTIAL FLOOD
```

### Fixed Flow
```
Human → Gateway → Agent A (injects message)
                      ↓
              Agent A processes
              (share_enabled stays False)
                      ↓
              No auto-broadcast

Human can enable sharing explicitly:
Human: /share
       ↓
Gateway → Agent A
       ↓
share_enabled = True
       ↓
Agent A intentional output → Gateway → Others
```

### Orchestrated Flow (Future)
```
Human: /mode debate "Best fix for trace-o-matic"
       ↓
Gateway sets mode=debate, turnOrder=[claude, codex, gemini]
       ↓
Gateway: "📢 Round 1 | @claude Your turn"
       ↓
Claude responds
       ↓
Human: /next (or auto-detected turn completion)
       ↓
Gateway: "📢 @codex Your turn"
       ↓
... continues until maxRounds ...
       ↓
Gateway: "✅ DEBATE complete. Synthesis: ..."
```

---

*This analysis is based on CSP commit HEAD as of 2025-12-27.*
