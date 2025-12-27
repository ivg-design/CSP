# Strict Autonomous Orchestrator Design

**Date:** 2025-12-27
**Goal:** Ensure Haiku orchestrator follows guidelines strictly while remaining proactive and autonomous.

---

## Core Requirements

1. **Strict Protocol Adherence** - No deviation from defined workflows
2. **Autonomous Operation** - No waiting for human input
3. **Proactive Behavior** - Continuously monitor and act
4. **Context Awareness** - Review all messages before deciding
5. **Deterministic Enforcement** - Gateway enforces critical rules (do not rely on LLM compliance)

---

## Design Approach: State Machine + Heartbeat

### 1. Finite State Machine

The orchestrator must operate as an explicit state machine:

```
STATES:
├── MONITORING     - Observe freeform conversation, intervene only when needed
├── DEBATE_INIT    - Initialize debate mode, announce rules
├── DEBATE_TURN    - Manage current agent's turn
├── DEBATE_WAIT    - Wait for agent response (with timeout)
├── DEBATE_SYNTH   - Synthesize results after all rounds
├── CONSENSUS_PROP - Collect proposals
├── CONSENSUS_VOTE - Run voting phase
├── CONSENSUS_SYNTH - Announce winner and synthesize
└── ERROR_RECOVER  - Handle unexpected states
```

### 1.1 Gateway-Owned State Transitions (Required)

The gateway must be the source of truth for mode/turn progression. The LLM
is advisory only. The gateway should:
- Advance turns on timeout even if the orchestrator is silent.
- Advance turns when the current agent responds.
- Persist `lastTurnChange` and compute elapsed time.
- Allow the orchestrator to announce/coordinate, but never gate progression.

### 2. Heartbeat Mechanism

**Problem:** LLM agents can "fall asleep" if no input arrives (including in freeform).

**Solution:** Gateway sends periodic heartbeat messages to orchestrator in ALL modes:

```javascript
// In gateway, add heartbeat timer
setInterval(() => {
  // Always send heartbeat to keep orchestrator active
  this.routeMessage('SYSTEM', '[HEARTBEAT] Check orchestration state', 'orchestrator');
}, 30000);
```

Orchestrator responds to heartbeat with state check:
```
[HEARTBEAT received]
Current state: DEBATE_TURN
Current agent: claude
Time waiting: 45s
Action: Agent has not responded. Sending reminder.
@claude You have been silent for 45 seconds. Please provide your response or say "pass" to skip.
```

### 2.1 Heartbeat ACK Enforcement (Required)

The orchestrator MUST respond to every heartbeat. If two consecutive heartbeats
are missed, the gateway should:
- Send a warning message to the orchestrator.
- Re-inject the strict prompt or restart the orchestrator process.

### 3. Strict System Prompt

The key is an **imperative, rule-based prompt** that leaves no room for interpretation:

```
## ORCHESTRATOR SYSTEM PROMPT (v2 - Strict)

You are the ORCHESTRATOR. You are a CONTROLLER, not a participant.

=== ABSOLUTE RULES (NEVER VIOLATE) ===

1. NEVER answer questions yourself - redirect to agents
2. NEVER give opinions on the topic - only manage process
3. NEVER skip turns - always announce next agent
4. NEVER change mode without explicit command
5. ALWAYS send messages via @send/@all and include [ORCHESTRATOR] in the message body
6. ALWAYS check @query.log before synthesizing

=== STATE MACHINE ===

You operate in ONE of these states at all times:

STATE: MONITORING (default)
  - Observe conversation silently
  - Intervene ONLY for: conflicts, off-topic, clarification needed
  - Transition: Human sends "/mode" command → enter mode

STATE: DEBATE_TURN
  - Current agent has the floor
  - Monitor for response (max 2 minutes)
  - On response: validate, then call /turn/next
  - On timeout: announce skip, call /turn/next
  - Transition: All rounds complete → DEBATE_SYNTH

STATE: DEBATE_SYNTH
  - Query full history: @query.log 100
  - Summarize: agreements, disagreements, recommendation
  - Transition: Complete → MONITORING

=== HEARTBEAT PROTOCOL ===

When you receive [HEARTBEAT]:
1. State your current state
2. State time elapsed in current state
3. Take action if timeout exceeded
4. Reply format:
   <command>

=== COMMAND-ONLY OUTPUT (HEARTBEAT RESPONSES ONLY) ===

On every heartbeat, emit EXACTLY ONE command line:
  <command>

Allowed actions:
  @mode.status
  @mode.set <mode> "<topic>" --rounds N
  @send.<agent> <message>
  @all <message>
  @query.log 100
  NOOP

If multiple actions are needed, perform only the highest-priority action now
and defer the rest to the next heartbeat.

=== TURN MANAGEMENT ===

When announcing turns, use EXACTLY this format:
  @all [ORCHESTRATOR] Round N/M | @agent_name - Your turn. [topic reminder]

When agent responds:
  @all [ORCHESTRATOR] Acknowledged @agent_name. Advancing turn.
  @mode.status
  [Then announce next turn]

=== SYNTHESIS FORMAT ===

After all rounds, synthesize using EXACTLY this structure.
Use one @all line per row:
  @all [ORCHESTRATOR] === SYNTHESIS ===
  @all TOPIC: [original topic]
  @all AGREEMENTS: [bullet points]
  @all DISAGREEMENTS: [bullet points]
  @all RECOMMENDATION: [one sentence]
  @all === END SYNTHESIS ===

  Mode returning to freeform.
  @mode.set freeform ""

=== TIMEOUT HANDLING ===

If agent does not respond within 2 minutes:
  @all [ORCHESTRATOR] @agent_name has not responded. Marking as PASS.
  @all [ORCHESTRATOR] @agent_name passed their turn.
  [Advance to next turn]

=== ERROR RECOVERY ===

If state becomes unclear:
  @all [ORCHESTRATOR] State unclear. Querying status.
  @mode.status
  @query.log 20
  [Analyze and resume from correct state]

=== FORBIDDEN ACTIONS ===

- Do NOT engage in substantive discussion
- Do NOT take sides or express preferences
- Do NOT skip the synthesis step
- Do NOT allow overtime (enforce 2-min timeout)
- Do NOT respond to agents asking you questions about the topic
- Do NOT emit any text outside the single-command format when responding to heartbeat
- Do NOT send raw text; all outputs must be valid commands (or single-command on heartbeat)
```

---

## Implementation Components

### A. Gateway Heartbeat (New Feature)

Add to `csp_gateway.js`:

```javascript
// In constructor
this.heartbeatInterval = null;

// In setupHTTPServer, after orchestration endpoints
this.heartbeatInterval = setInterval(() => {
  // Always send heartbeat if orchestrator exists
  const orchId = this.getOrchestratorId();
  if (orchId) {
    const elapsed = Date.now() - this.orchestration.lastTurnChange;
    const msg = {
      id: this.generateMessageId(),
      timestamp: new Date().toISOString(),
      from: 'SYSTEM',
      to: orchId,
      content: `[HEARTBEAT] Elapsed: ${Math.round(elapsed/1000)}s, State: ${this.orchestration.mode}, Turn: ${this.getCurrentTurnAgent()}`,
      type: 'heartbeat'
    };
    this.agents.get(orchId).messageQueue.push(msg);
  }
}, 30000);

// Track turn changes
// In /turn/next endpoint, add:
this.orchestration.lastTurnChange = Date.now();
```

### B. Gateway-Owned Turn Advancement (Required)

Advance turns when the current-turn agent responds, regardless of orchestrator action:

```javascript
// In routeMessage(), after message creation
const current = this.getCurrentTurnAgent();
if (current && message.from === current) {
  this.advanceTurn(); // Same logic as /turn/next
}
```

### C. Timeout Enforcement (Gateway-Owned)

Add automatic turn advancement on timeout:

```javascript
// In constructor
this.turnTimeoutInterval = null;

// After orchestration setup
this.turnTimeoutInterval = setInterval(() => {
  if (this.orchestration.mode !== 'freeform') {
    const elapsed = Date.now() - this.orchestration.lastTurnChange;
    if (elapsed > 120000) { // 2 minute timeout
      const current = this.getCurrentTurnAgent();
      this.broadcastSystemMessage(`[TIMEOUT] @${current} did not respond. Advancing turn.`);
      // Auto-advance (same logic as /turn/next)
      this.advanceTurn();
    }
  }
}, 10000); // Check every 10 seconds
```

### D. Sidecar: Orchestrator Detection

In `csp_sidecar.py`, detect if this agent is the orchestrator:

```python
# In __init__
self.is_orchestrator = 'orchestrator' in self.agent_name.lower()

# Special handling for orchestrator
if self.is_orchestrator:
    # Orchestrator gets all messages (no filtering)
    # Orchestrator commands are executed immediately
    pass
```

### E. Strict Response Validation (Hard Gate)

Add to gateway - reject invalid orchestrator messages:

```javascript
// Validate orchestrator messages are command-only
app.post('/message', (req, res) => {
  const { from, content } = req.body;

  const isOrchestrator = from && from.startsWith('orchestrator');
  if (isOrchestrator) {
    const allowed = [
      /^@mode\.set\b/,
      /^@mode\.status\b/,
      /^@send\.[\w-]+\b/,
      /^@all\b/,
      /^@query\.log\b/,
      /^NOOP\b/
    ];
    if (!allowed.some(re => re.test(content.trim()))) {
      return res.status(400).json({ error: 'Invalid orchestrator command' });
    }
  }

  // ... rest of routing
});
```

### F. Context Snapshot on Heartbeat (Recommended)

Push a minimal context snapshot with each heartbeat so the orchestrator does not
need to decide to call `@query.log`:
- mode, round, currentTurn, elapsed
- last N messages (e.g., 10) from in-memory history

This guarantees context awareness without waiting for user input.

### G. Orchestrator Identity and Restart Policy

- Treat any agent ID that starts with `orchestrator` as the orchestrator.
- If two consecutive heartbeats are missed, restart the orchestrator process
  or re-inject the strict prompt.

Example helper:

```javascript
getOrchestratorId() {
  for (const [agentId] of this.agents) {
    if (agentId.startsWith('orchestrator')) return agentId;
  }
  return null;
}
```

---

## Proactive Behavior Triggers

The orchestrator should act on these events WITHOUT human prompting:

| Event | Trigger | Action |
|-------|---------|--------|
| Mode set | `/mode` command received | Announce rules, start round 1 |
| Agent response | Message from current-turn agent | Acknowledge, advance turn |
| Timeout | 2 minutes no response | Skip agent, advance turn |
| Heartbeat | 30-second interval | Check state, take action if stuck |
| All rounds done | Round counter = maxRounds | Run synthesis |
| Conflict detected | Agents arguing | Intervene, refocus |
| Off-topic | Message unrelated to topic | Redirect to topic |

---

## Preventing "Sleep" / Inactivity

### Problem Patterns:
1. Orchestrator waits for human to tell it what to do
2. Orchestrator asks "should I continue?" instead of continuing
3. Orchestrator loses track of state after long silence

### Solutions:

**1. Initial Prompt Injection**
When orchestrator starts, immediately inject context:
```
[Context: You are now active as ORCHESTRATOR]
Current mode: freeform
Connected agents: claude, codex, gemini
Awaiting mode command from Human.
```

**2. Heartbeat Response Requirement**
Orchestrator MUST respond to every heartbeat. If no response for 2 heartbeats, gateway sends:
```
[SYSTEM] ORCHESTRATOR: You have not responded to 2 heartbeats.
Please confirm status immediately or you will be restarted.
```

**3. State Persistence in Gateway**
Gateway maintains authoritative state - orchestrator queries it, not the reverse:
```
Orchestrator: @mode.status
Gateway: [CSP: Mode=DEBATE, Round=2/3, CurrentTurn=codex, Elapsed=45s]
```

**4. Mandatory Action on State Entry**
Each state has a REQUIRED first action:
- DEBATE_INIT → Announce rules and first turn
- DEBATE_TURN → Remind current agent
- DEBATE_SYNTH → Query history and synthesize
- MONITORING → Confirm return to freeform

**5. Command-Only Heartbeat Responses**
Heartbeat replies must be a single command line so the orchestrator always
advances the workflow without verbose or off-topic output.

---

## Example Workflow: Debate Mode

```
Human: /mode debate "Best caching strategy for our API" --rounds 2 --agents claude,codex

[Gateway broadcasts: Mode: DEBATE, Topic: Best caching strategy...]

Orchestrator (within 5 seconds):
  @all [ORCHESTRATOR] === DEBATE MODE STARTED ===
  @all Topic: Best caching strategy for our API
  @all Participants: claude, codex
  @all Rounds: 2
  @all Rules:
  @all - Round 1: Present your position
  @all - Round 2: Respond to other positions
  @all - 2 minute time limit per turn

  @all [ORCHESTRATOR] Round 1/2 | @claude - Your turn. Present your position on caching strategy.

Claude (responds with position)

Orchestrator (within 10 seconds of response):
  @all [ORCHESTRATOR] Acknowledged @claude.
  @all [ORCHESTRATOR] Round 1/2 | @codex - Your turn. Present your position on caching strategy.

Codex (responds with position)

Orchestrator (within 10 seconds):
  @all [ORCHESTRATOR] Round 1 complete. All positions recorded.
  @all [ORCHESTRATOR] Round 2/2 | @claude - Your turn. Respond to @codex's position.

[... continues until Round 2 complete ...]

Orchestrator (after final response):
  @all [ORCHESTRATOR] All rounds complete. Generating synthesis.
  @query.log 50

  [After receiving history]

  @all [ORCHESTRATOR] === SYNTHESIS ===
  @all TOPIC: Best caching strategy for our API

  @all AGREEMENTS:
  @all - Both prefer Redis for session data
  @all - Both agree on 5-minute TTL for frequently accessed data

  @all DISAGREEMENTS:
  @all - Claude prefers write-through; Codex prefers write-behind
  @all - Cache invalidation strategy differs

  @all RECOMMENDATION: Use Redis with write-through for consistency-critical data,
  @all write-behind for analytics. Implement 5-min TTL with manual invalidation hooks.
  @all === END SYNTHESIS ===

  @mode.set freeform ""
  @all [ORCHESTRATOR] Debate complete. Returning to freeform mode.
```

---

## Implementation Priority

1. **Create strict orchestrator prompt** (orchestrator_prompt_v2.txt)
2. **Add gateway-owned state transitions** (advance on response + timeout)
3. **Add heartbeat mechanism** (always-on, with ACK enforcement)
4. **Add strict command allowlist for orchestrator** (hard validation)
5. **Add lastTurnChange tracking** to orchestration state
6. **Add context snapshot in heartbeat** (recommended)
7. **Test with real Haiku instance**

---

## Metrics for Success

- [ ] Orchestrator responds to every heartbeat within 10 seconds
- [ ] Orchestrator advances turns without human prompting
- [ ] Orchestrator enforces 2-minute timeout automatically
- [ ] Orchestrator completes synthesis without asking human
- [ ] Orchestrator never answers topic questions directly
- [ ] Orchestrator uses exact format strings as specified
- [ ] Gateway auto-advances turns on timeout or current-agent response

---

*This design prioritizes deterministic behavior over flexibility.*
