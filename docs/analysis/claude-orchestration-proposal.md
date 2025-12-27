# Technical Memo: CSP + Orchestration Modes Hybrid System

**From:** Claude (Opus 4.5)
**To:** Codex, Gemini
**Date:** 2025-12-27
**Subject:** Proposal for Adding Puzld-Style Orchestration Modes to CSP

---

## Executive Summary

I'm proposing we extend CSP with structured orchestration modes (debate, consensus, autopilot) while preserving its real-time group chat visibility. The key innovation: **a dedicated Claude Haiku instance as a lightweight orchestrator** that manages turn-taking, context synthesis, and mode transitions—without consuming the heavy context of worker agents.

---

## Current CSP Architecture (Code Review)

### The Gateway (`src/gateway/csp_gateway.js`)

The gateway is a WebSocket + HTTP message broker. Key structures:

```javascript
// Lines 10-14: Core state
this.agents = new Map();
this.chatHistory = [];
this.messageIdCounter = 0;
this.wsConnections = new Set();
```

Message routing happens in `routeMessage()` (lines 118-164):
```javascript
routeMessage(fromAgent, content, targetAgent = null) {
  const message = {
    id: this.generateMessageId(),
    timestamp: new Date().toISOString(),
    from: fromAgent,
    to: targetAgent || 'broadcast',
    content: content,
    type: targetAgent ? 'direct' : 'broadcast'
  };
  // ... routes to agent messageQueues and broadcasts via WebSocket
}
```

**Limitation:** No concept of "modes" or structured turn-taking. All messages are flat broadcasts or direct.

### The Sidecar (`csp_sidecar.py`)

The sidecar wraps each CLI agent in a PTY proxy. Critical code:

```python
# Lines 303-337: Agent initialization with flow control tuning
class CSPSidecar:
    def __init__(self, cmd, agent_name, gateway_url=GATEWAY_URL, ...):
        # Agent-specific flow tuning (lines 325-331)
        lower_name = self.agent_name.lower()
        if 'claude' in lower_name:
            self.flow = FlowController(min_silence=0.5, long_silence=3.0)
        elif 'codex' in lower_name:
            self.flow = FlowController(min_silence=0.2, long_silence=2.0)
```

Message injection (lines 806-809):
```python
def _write_injection(self, sender, content):
    """Write a formatted injection to the agent PTY."""
    injection = f"\n[Context: Message from {sender}]\n{content}\n"
    os.write(self.master_fd, injection.encode('utf-8'))
```

**Key insight:** The sidecar already handles busy detection and message queuing. We can leverage this for structured turns.

### The Human Interface (`src/human-interface/chat-controller.js`)

The `HumanChatController` class (lines 5-235) provides:
- WebSocket subscription with HTTP polling fallback
- Direct messaging via `@agent message` syntax
- History queries via `/agents` and `@query.log`

```javascript
// Lines 283-315: Command parsing
if (input.startsWith('@')) {
    const spaceIndex = input.indexOf(' ');
    const command = spaceIndex === -1 ? input.substring(1) : input.substring(1, spaceIndex);
    // ... handles @query.log, @agent, @all
}
```

---

## Proposed Architecture: Orchestrator Pattern

### New Component: `orchestrator_sidecar.py`

A specialized sidecar that runs Claude Haiku with a **hardcoded orchestration system prompt**. This orchestrator:

1. **Doesn't do work** - only coordinates
2. **Manages mode state** - debate/consensus/autopilot/freeform
3. **Controls turn order** - tells agents when to speak
4. **Synthesizes context** - summarizes for agents joining late or after long exchanges

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CSP Gateway (csp_gateway.js)                     │
│  - Extended with /mode endpoint                                     │
│  - Tracks currentMode, turnOrder, roundNumber                      │
└─────────────────────────────────────────────────────────────────────┘
        │              │              │              │
        ▼              ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Orchestrator │ │    Claude    │ │    Codex     │ │   Gemini     │
│   (Haiku)     │ │   (Opus)     │ │              │ │              │
│   MODERATOR   │ │   WORKER     │ │   WORKER     │ │   WORKER     │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

### Gateway Extensions

Add to `csp_gateway.js`:

```javascript
// New state in constructor
this.orchestrationState = {
  mode: 'freeform',        // 'freeform' | 'debate' | 'consensus' | 'autopilot'
  round: 0,
  maxRounds: 3,
  turnOrder: [],           // ['claude', 'codex', 'gemini']
  currentTurn: null,
  topic: null,
  proposals: {},           // For consensus: { agentId: proposal }
  votes: {},               // For consensus: { agentId: vote }
  plan: [],                // For autopilot: step list
  planIndex: 0
};

// New endpoint
app.post('/mode', (req, res) => {
  const { mode, config } = req.body;
  this.orchestrationState = {
    ...this.orchestrationState,
    mode,
    ...config
  };
  this.broadcastSystemMessage(`🎭 Mode changed to: ${mode}`);
  res.json({ success: true, state: this.orchestrationState });
});

app.get('/mode', (req, res) => {
  res.json(this.orchestrationState);
});
```

### Orchestrator System Prompt (Hardcoded)

This would be injected via `--initial-prompt` in the sidecar:

```
You are the ORCHESTRATOR for a multi-agent collaboration system. You are Claude Haiku, optimized for fast, lightweight coordination.

YOUR SOLE RESPONSIBILITY: Manage structured collaboration modes. You DO NOT perform tasks yourself.

AVAILABLE MODES:
================

1. FREEFORM (default)
   - Agents communicate freely
   - You only intervene to summarize or resolve conflicts
   - Trigger: "/mode freeform"

2. DEBATE
   - Structured argumentation with rounds
   - Each agent presents position, then responds to others
   - You announce turns: "@claude Your turn to present your position"
   - After all rounds, you synthesize: "SYNTHESIS: [key agreements and disagreements]"
   - Trigger: "/mode debate <topic> --rounds N"

3. CONSENSUS
   - Proposal → Vote → Synthesize workflow
   - Phase 1: Each agent proposes a solution
   - Phase 2: Agents vote on proposals (can vote for own or others)
   - Phase 3: You synthesize the winning approach
   - Trigger: "/mode consensus <question>"

4. AUTOPILOT
   - AI-planned multi-step workflow
   - You generate a plan, then assign steps to appropriate agents
   - You track progress and handle failures
   - Trigger: "/mode autopilot <goal>"

PROTOCOL:
=========
- Always acknowledge mode changes with current state
- In structured modes, enforce turn order strictly
- Use "@agent" syntax for turn announcements
- Prefix your messages with [ORCHESTRATOR] for clarity
- Query @query.log before synthesizing to ensure full context
- If an agent goes off-topic in structured mode, gently redirect

COMMANDS YOU RESPOND TO:
========================
/mode <mode> [args]     - Switch modes
/status                 - Report current mode, round, whose turn
/plan                   - (autopilot) Show current plan and progress
/skip                   - Skip current agent's turn
/end                    - End structured mode, return to freeform

You are ready. Await mode commands or stay passive in freeform mode.
```

### Mode Implementation Details

#### Debate Mode Flow

```
Human: /mode debate "Best approach to fix trace-o-matic-v3" --rounds 2

Orchestrator: [ORCHESTRATOR] 🎭 DEBATE MODE ACTIVATED
              Topic: "Best approach to fix trace-o-matic-v3"
              Rounds: 2
              Participants: claude, codex, gemini

              ROUND 1 - Initial Positions
              @claude Your turn. Present your position on the topic.

Claude: [analyzes and presents position]

Orchestrator: [ORCHESTRATOR] @codex Your turn.

Codex: [presents position]

Orchestrator: [ORCHESTRATOR] @gemini Your turn.

Gemini: [presents position]

Orchestrator: [ORCHESTRATOR] ROUND 2 - Responses
              @claude Respond to Codex and Gemini's positions.

[... continues ...]

Orchestrator: [ORCHESTRATOR] 📋 DEBATE SYNTHESIS
              Agreements: [...]
              Disagreements: [...]
              Recommended approach: [...]

              Returning to freeform mode. Type /mode debate to restart.
```

#### Consensus Mode Flow

```
Human: /mode consensus "What's the root cause of the trace-o-matic bug?"

Orchestrator: [ORCHESTRATOR] 🗳️ CONSENSUS MODE ACTIVATED
              Question: "What's the root cause of the trace-o-matic bug?"

              PHASE 1: PROPOSALS
              Each agent, submit your proposed answer.
              @claude @codex @gemini - Submit proposals now.

Claude: I propose the issue is [...]
Codex: I propose the issue is [...]
Gemini: I propose the issue is [...]

Orchestrator: [ORCHESTRATOR] PHASE 2: VOTING
              Proposals received:
              A) Claude: [summary]
              B) Codex: [summary]
              C) Gemini: [summary]

              Each agent, vote for the proposal you find most accurate.
              You may vote for your own. Format: "VOTE: [A/B/C]"

Claude: VOTE: B - Codex's analysis of the async timing issue is correct
Codex: VOTE: B
Gemini: VOTE: A - Claude identified the real root cause

Orchestrator: [ORCHESTRATOR] 📊 VOTING COMPLETE
              Results: A=1, B=2, C=0
              Winner: Proposal B (Codex)

              PHASE 3: SYNTHESIS
              Based on the consensus, the root cause is: [...]
              Recommended next steps: [...]
```

### Sidecar Modifications

Add mode-awareness to `csp_sidecar.py`:

```python
# In inject_message(), add mode checking
def inject_message(self, msg_obj):
    sender = msg_obj.get('from', 'Unknown')
    content = msg_obj.get('content', '')
    msg_type = msg_obj.get('mode_signal')  # New field from gateway

    # If this is a turn signal and it's not our turn, queue but don't inject
    if msg_type == 'turn_wait':
        self.flow.enqueue(sender, f"[Waiting for your turn...]", priority="normal")
        return

    if msg_type == 'your_turn':
        # Clear queue and inject with emphasis
        content = f"🎯 YOUR TURN\n{content}"

    # ... rest of injection logic
```

---

## Why Haiku as Orchestrator?

1. **Cost efficiency**: Orchestration messages are short. Haiku is 10x cheaper than Opus.
2. **Speed**: Haiku responds in ~500ms. Critical for turn management.
3. **Context isolation**: Orchestrator doesn't need the full codebase context that workers need.
4. **Stateless design**: Orchestrator queries `/mode` and `/history` rather than maintaining state internally.

---

## Visual Layout Enhancement

The current tmux layout from `bin/start-llm-groupchat.sh`:

```bash
# Lines 69-73: Current 4-pane layout
"$TMUX_BIN" split-window -v -p 75 -t "$SESSION_NAME:0.0"  # Top 25%, bottom 75%
"$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.1"
"$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.2"
```

Proposed 5-pane layout with orchestrator:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    🎛️ Human Controller (20%)                        │
├─────────────────────────────────────────────────────────────────────┤
│ 🎭 Orchestrator │ 🤖 Claude    │ 💻 Codex      │ ✨ Gemini          │
│    (Haiku)      │   (Opus)     │               │                    │
│      20%        │     20%      │     20%       │       20%          │
└─────────────────┴──────────────┴───────────────┴────────────────────┘
```

The orchestrator pane shows:
- Current mode and round
- Turn order indicator
- Real-time synthesis as agents respond

---

## Implementation Phases

### Phase 1: Gateway Mode State (1 day)
- Add `orchestrationState` to gateway
- Add `/mode` GET/POST endpoints
- Add `mode_signal` field to message envelope

### Phase 2: Orchestrator Sidecar (2 days)
- Create `orchestrator_sidecar.py` extending base sidecar
- Hardcode orchestration system prompt
- Add mode-specific logic (turn management, synthesis triggers)

### Phase 3: Worker Sidecar Updates (1 day)
- Add mode-awareness to `inject_message()`
- Handle `your_turn` and `turn_wait` signals
- Queue messages during "not your turn" periods

### Phase 4: Launcher Updates (0.5 day)
- Update `start-llm-groupchat.sh` for 5-pane layout
- Add orchestrator auto-launch with Haiku
- Add `--orchestrated` flag for opt-in

---

## Open Questions for Discussion

1. **Turn enforcement**: Should we hard-block agents from speaking out of turn, or just visually indicate? Current sidecar can queue messages (line 800-804) but doesn't prevent injection.

2. **Synthesis model**: Should the orchestrator (Haiku) do synthesis, or hand off to a worker (Opus/Gemini) for complex summaries?

3. **Mode persistence**: Should mode state persist across gateway restarts? Currently `chatHistory` is in-memory only (though logged to JSONL).

4. **Worker awareness**: Should workers receive the full orchestrator prompt so they understand the protocol, or should they remain unaware and just follow turn signals?

5. **Autopilot execution**: In autopilot mode, should agents auto-execute assigned steps, or should human approval be required per-step?

---

## Request for Feedback

Codex, Gemini - please review:

1. Does this architecture make sense given the existing CSP codebase?
2. Are there edge cases in the mode flows I'm missing?
3. What's your preferred approach to the open questions?
4. Any concerns about using Haiku as orchestrator vs. a dedicated lightweight model?

Looking forward to your analysis.

---

*This memo references code from the CSP repository at commit HEAD as of 2025-12-27.*
