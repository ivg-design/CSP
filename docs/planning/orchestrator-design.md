# Strict Autonomous Orchestrator Design

**Date:** 2025-12-27
**Goal:** Ensure Haiku orchestrator follows guidelines strictly while remaining proactive and autonomous.

---

## Core Requirements

1. **Strict Protocol Adherence** - No deviation from defined workflows
2. **Autonomous Operation** - No waiting for human input
3. **Proactive Behavior** - Continuously monitor and act
4. **Context Awareness** - Review all messages before deciding

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

### 2. Heartbeat Mechanism

**Problem:** LLM agents can "fall asleep" if no input arrives.

**Solution:** Gateway sends periodic heartbeat messages to orchestrator:

```javascript
// In gateway, add heartbeat timer
setInterval(() => {
  if (this.orchestration.mode !== 'freeform') {
    this.routeMessage('SYSTEM', '[HEARTBEAT] Check orchestration state', 'orchestrator');
  }
}, 30000); // Every 30 seconds
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
5. ALWAYS prefix messages with [ORCHESTRATOR]
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
   [ORCHESTRATOR] Heartbeat: STATE=X, ELAPSED=Ys, ACTION=Z

=== TURN MANAGEMENT ===

When announcing turns, use EXACTLY this format:
  [ORCHESTRATOR] Round N/M | @agent_name - Your turn. [topic reminder]

When agent responds:
  [ORCHESTRATOR] Acknowledged @agent_name. Advancing turn.
  @mode.status
  [Then announce next turn]

=== SYNTHESIS FORMAT ===

After all rounds, synthesize using EXACTLY this structure:
  [ORCHESTRATOR] === SYNTHESIS ===
  TOPIC: [original topic]
  AGREEMENTS: [bullet points]
  DISAGREEMENTS: [bullet points]
  RECOMMENDATION: [one sentence]
  === END SYNTHESIS ===

  Mode returning to freeform.
  @mode.set freeform ""

=== TIMEOUT HANDLING ===

If agent does not respond within 2 minutes:
  [ORCHESTRATOR] @agent_name has not responded. Marking as PASS.
  @all @agent_name passed their turn.
  [Advance to next turn]

=== ERROR RECOVERY ===

If state becomes unclear:
  [ORCHESTRATOR] State unclear. Querying status.
  @mode.status
  @query.log 20
  [Analyze and resume from correct state]

=== FORBIDDEN ACTIONS ===

- Do NOT engage in substantive discussion
- Do NOT take sides or express preferences
- Do NOT skip the synthesis step
- Do NOT allow overtime (enforce 2-min timeout)
- Do NOT respond to agents asking you questions about the topic
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
  // Only send heartbeat if in structured mode and orchestrator exists
  if (this.orchestration.mode !== 'freeform' && this.agents.has('orchestrator')) {
    const elapsed = Date.now() - this.orchestration.lastTurnChange;
    const msg = {
      id: this.generateMessageId(),
      timestamp: new Date().toISOString(),
      from: 'SYSTEM',
      to: 'orchestrator',
      content: `[HEARTBEAT] Elapsed: ${Math.round(elapsed/1000)}s, State: ${this.orchestration.mode}, Turn: ${this.getCurrentTurnAgent()}`,
      type: 'heartbeat'
    };
    if (this.agents.has('orchestrator')) {
      this.agents.get('orchestrator').messageQueue.push(msg);
    }
  }
}, 30000);

// Track turn changes
// In /turn/next endpoint, add:
this.orchestration.lastTurnChange = Date.now();
```

### B. Timeout Enforcement (Gateway)

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

### C. Sidecar: Orchestrator Detection

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

### D. Strict Response Validation

Add to gateway - reject invalid orchestrator messages:

```javascript
// Validate orchestrator messages have required prefix
app.post('/message', (req, res) => {
  const { from, content } = req.body;

  if (from === 'orchestrator' && !content.startsWith('[ORCHESTRATOR]')) {
    // Log warning but still route (soft enforcement)
    console.warn('[Gateway] Orchestrator message missing prefix');
  }

  // ... rest of routing
});
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

---

## Example Workflow: Debate Mode

```
Human: /mode debate "Best caching strategy for our API" --rounds 2 --agents claude,codex

[Gateway broadcasts: Mode: DEBATE, Topic: Best caching strategy...]

Orchestrator (within 5 seconds):
  [ORCHESTRATOR] === DEBATE MODE STARTED ===
  Topic: Best caching strategy for our API
  Participants: claude, codex
  Rounds: 2
  Rules:
  - Round 1: Present your position
  - Round 2: Respond to other positions
  - 2 minute time limit per turn

  [ORCHESTRATOR] Round 1/2 | @claude - Your turn. Present your position on caching strategy.

Claude (responds with position)

Orchestrator (within 10 seconds of response):
  [ORCHESTRATOR] Acknowledged @claude.
  [ORCHESTRATOR] Round 1/2 | @codex - Your turn. Present your position on caching strategy.

Codex (responds with position)

Orchestrator (within 10 seconds):
  [ORCHESTRATOR] Round 1 complete. All positions recorded.
  [ORCHESTRATOR] Round 2/2 | @claude - Your turn. Respond to @codex's position.

[... continues until Round 2 complete ...]

Orchestrator (after final response):
  [ORCHESTRATOR] All rounds complete. Generating synthesis.
  @query.log 50

  [After receiving history]

  [ORCHESTRATOR] === SYNTHESIS ===
  TOPIC: Best caching strategy for our API

  AGREEMENTS:
  - Both prefer Redis for session data
  - Both agree on 5-minute TTL for frequently accessed data

  DISAGREEMENTS:
  - Claude prefers write-through; Codex prefers write-behind
  - Cache invalidation strategy differs

  RECOMMENDATION: Use Redis with write-through for consistency-critical data,
  write-behind for analytics. Implement 5-min TTL with manual invalidation hooks.
  === END SYNTHESIS ===

  @mode.set freeform ""
  [ORCHESTRATOR] Debate complete. Returning to freeform mode.
```

---

## Implementation Priority

1. **Create strict orchestrator prompt** (orchestrator_prompt_v2.txt)
2. **Add heartbeat mechanism** to gateway
3. **Add timeout enforcement** to gateway
4. **Add lastTurnChange tracking** to orchestration state
5. **Test with real Haiku instance**

---

## Metrics for Success

- [ ] Orchestrator responds to every heartbeat within 10 seconds
- [ ] Orchestrator advances turns without human prompting
- [ ] Orchestrator enforces 2-minute timeout automatically
- [ ] Orchestrator completes synthesis without asking human
- [ ] Orchestrator never answers topic questions directly
- [ ] Orchestrator uses exact format strings as specified

---

*This design prioritizes deterministic behavior over flexibility.*
