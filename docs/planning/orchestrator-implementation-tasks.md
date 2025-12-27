# Orchestrator Implementation Tasks (Parallel)

**Date:** 2025-12-27
**Based on:** orchestrator-design.md (Codex-updated version)

---

## API Contract

### Heartbeat Message Format
```javascript
{
  from: 'SYSTEM',
  to: 'orchestrator',
  type: 'heartbeat',
  content: '[HEARTBEAT] Elapsed: 45s, State: debate, Turn: claude',
  context: {
    mode: 'debate',
    round: 1,
    maxRounds: 3,
    currentTurn: 'claude',
    elapsed: 45000,
    recentMessages: [...] // Last 10 messages
  }
}
```

### Orchestrator Response (Command-Only)
```
@mode.status
@send.claude Your turn to respond.
@all [ORCHESTRATOR] Round 1 complete.
NOOP
```

### Valid Orchestrator Commands (Allowlist)
```
@mode.set <mode> "<topic>" --rounds N
@mode.status
@send.<agent> <message>
@all <message>
@query.log [limit]
NOOP
```

---

## Codex Tasks (JavaScript/Gateway)

### Task G1: Add Orchestrator Helper Methods
**File:** `src/gateway/csp_gateway.js`

```javascript
// In class CSPGateway

getOrchestratorId() {
  for (const [agentId] of this.agents) {
    if (agentId.startsWith('orchestrator')) return agentId;
  }
  return null;
}

advanceTurn() {
  const o = this.orchestration;
  if (o.mode === 'freeform') return { skipped: true };

  o.currentTurnIndex++;
  o.lastTurnChange = Date.now();

  if (o.currentTurnIndex >= o.turnOrder.length) {
    o.currentTurnIndex = 0;
    o.round++;

    if (o.round >= o.maxRounds) {
      this.broadcastSystemMessage(`${o.mode.toUpperCase()} complete.`);
      o.mode = 'freeform';
      return { complete: true };
    }
    this.broadcastSystemMessage(`Round ${o.round + 1}`);
  }

  const next = o.turnOrder[o.currentTurnIndex];
  this.broadcastSystemMessage(`@${next} - Your turn.`);
  return { success: true, currentTurn: next, round: o.round };
}
```

**Acceptance:** `this.advanceTurn()` can be called from multiple places.

---

### Task G2: Add lastTurnChange Tracking
**File:** `src/gateway/csp_gateway.js`

In constructor orchestration state:
```javascript
this.orchestration = {
  // ... existing fields
  lastTurnChange: Date.now()
};
```

In `/mode` POST endpoint:
```javascript
this.orchestration.lastTurnChange = Date.now();
```

**Acceptance:** `orchestration.lastTurnChange` is always current.

---

### Task G3: Gateway-Owned Turn Advancement on Agent Response
**File:** `src/gateway/csp_gateway.js` in `routeMessage()`

```javascript
routeMessage(fromAgent, content, targetAgent = null) {
  // ... existing message creation ...

  // Auto-advance turn when current agent responds (gateway-owned)
  const current = this.getCurrentTurnAgent();
  if (current && fromAgent === current && this.orchestration.mode !== 'freeform') {
    // Current-turn agent responded - auto advance
    setTimeout(() => this.advanceTurn(), 100); // Small delay for message to propagate
  }

  // ... rest of routing ...
}
```

**Acceptance:** When `claude` responds during their turn, gateway auto-advances to next agent.

---

### Task G4: Heartbeat Mechanism (Always-On)
**File:** `src/gateway/csp_gateway.js`

```javascript
// In constructor
this.heartbeatInterval = null;
this.missedHeartbeats = 0;

// In setupHTTPServer(), after endpoints
this.heartbeatInterval = setInterval(() => {
  const orchId = this.getOrchestratorId();
  if (!orchId) return;

  const o = this.orchestration;
  const elapsed = Date.now() - (o.lastTurnChange || Date.now());

  // Build context snapshot (last 10 messages)
  const recentMessages = this.chatHistory.slice(-10).map(m => ({
    from: m.from,
    content: m.content.substring(0, 200) // Truncate
  }));

  const msg = {
    id: this.generateMessageId(),
    timestamp: new Date().toISOString(),
    from: 'SYSTEM',
    to: orchId,
    type: 'heartbeat',
    content: `[HEARTBEAT] Elapsed: ${Math.round(elapsed/1000)}s, State: ${o.mode}, Turn: ${this.getCurrentTurnAgent() || 'N/A'}`,
    context: {
      mode: o.mode,
      round: o.round,
      maxRounds: o.maxRounds,
      currentTurn: this.getCurrentTurnAgent(),
      elapsed,
      recentMessages
    }
  };

  if (this.agents.has(orchId)) {
    this.agents.get(orchId).messageQueue.push(msg);
  }
}, 30000); // Every 30 seconds
```

**Acceptance:** Orchestrator receives heartbeat every 30s with context.

---

### Task G5: Timeout Enforcement (Gateway-Owned)
**File:** `src/gateway/csp_gateway.js`

```javascript
// In constructor
this.turnTimeoutInterval = null;

// In setupHTTPServer(), after heartbeat setup
this.turnTimeoutInterval = setInterval(() => {
  if (this.orchestration.mode === 'freeform') return;

  const elapsed = Date.now() - this.orchestration.lastTurnChange;
  if (elapsed > 120000) { // 2 minutes
    const current = this.getCurrentTurnAgent();
    if (current) {
      this.broadcastSystemMessage(`[TIMEOUT] @${current} did not respond. Advancing turn.`);
      this.advanceTurn();
    }
  }
}, 10000); // Check every 10 seconds
```

**Acceptance:** After 2 minutes of silence, gateway auto-advances.

---

### Task G6: Strict Orchestrator Command Validation
**File:** `src/gateway/csp_gateway.js` in message endpoints

```javascript
// Add validation helper
isValidOrchestratorCommand(content) {
  const allowlist = [
    /^@mode\.set\s+\w+\s+"[^"]+"/,
    /^@mode\.status\s*$/,
    /^@send\.[\w-]+\s+.+/,
    /^@all\s+.+/,
    /^@query\.log(\s+\d+)?$/,
    /^NOOP\s*$/
  ];
  return allowlist.some(re => re.test(content.trim()));
}

// In /message or /agent-output endpoint
app.post('/message', (req, res) => {
  const { from, content } = req.body;

  // Strict validation for orchestrator
  if (from && from.startsWith('orchestrator')) {
    if (!this.isValidOrchestratorCommand(content)) {
      console.warn(`[Gateway] Rejected invalid orchestrator command: ${content.substring(0, 50)}`);
      return res.status(400).json({ error: 'Invalid orchestrator command' });
    }
  }

  // ... rest of routing
});
```

**Acceptance:** Non-command orchestrator messages are rejected with 400.

---

### Task G7: Heartbeat ACK Tracking
**File:** `src/gateway/csp_gateway.js`

```javascript
// In constructor
this.lastOrchestratorResponse = Date.now();

// In routeMessage, track orchestrator responses
if (fromAgent && fromAgent.startsWith('orchestrator')) {
  this.lastOrchestratorResponse = Date.now();
  this.missedHeartbeats = 0;
}

// In heartbeat interval, check for missed responses
// After sending heartbeat:
const timeSinceResponse = Date.now() - this.lastOrchestratorResponse;
if (timeSinceResponse > 60000) { // 60s = 2 missed heartbeats
  this.missedHeartbeats++;
  if (this.missedHeartbeats >= 2) {
    this.broadcastSystemMessage('[SYSTEM] Orchestrator unresponsive. Consider restart.');
    // Could trigger restart via sidecar command
  }
}
```

**Acceptance:** Gateway detects unresponsive orchestrator.

---

## Claude Tasks (Python/Sidecar)

### Task S1: Orchestrator Detection
**File:** `csp_sidecar.py`

In `CSPSidecar.__init__()`:
```python
# After agent_name is set
self.is_orchestrator = 'orchestrator' in self.agent_name.lower()
```

**Acceptance:** `self.is_orchestrator` is True for orchestrator agent.

---

### Task S2: Extract Heartbeat Context
**File:** `csp_sidecar.py` in `inject_message()`

```python
def inject_message(self, msg_obj):
    # ... existing code ...

    # Extract heartbeat context if present
    context = msg_obj.get('context')
    if context and self.is_orchestrator:
        # Format context for injection
        mode = context.get('mode', 'freeform')
        round_num = context.get('round', 0) + 1
        max_rounds = context.get('maxRounds', 3)
        current = context.get('currentTurn', 'N/A')
        elapsed = context.get('elapsed', 0) / 1000

        context_str = f"\n[STATE] Mode={mode}, Round={round_num}/{max_rounds}, Turn={current}, Elapsed={elapsed:.0f}s"

        # Include recent messages summary
        recent = context.get('recentMessages', [])
        if recent:
            context_str += f"\n[RECENT] {len(recent)} messages"
            for m in recent[-3:]:  # Show last 3
                context_str += f"\n  {m['from']}: {m['content'][:50]}..."

        content = context_str + "\n" + content

    # ... rest of injection
```

**Acceptance:** Orchestrator sees formatted context with each heartbeat.

---

### Task S3: NOOP Command Support
**File:** `csp_sidecar.py` in `AgentCommandProcessor`

Add NOOP pattern:
```python
# In __init__, add to patterns or as separate check
self.noop_pattern = re.compile(r'^NOOP\s*$', re.IGNORECASE)

# In detect_commands()
match = self.noop_pattern.search(line)
if match:
    commands.append(('noop', {}))
    continue

# In execute_command()
elif command_type == 'noop':
    return "[CSP: NOOP acknowledged]"
```

**Acceptance:** Orchestrator can output `NOOP` as valid no-action command.

---

### Task S4: Update Orchestrator Prompt File
**File:** `orchestrator_prompt.txt`

Replace with the strict v2 prompt from orchestrator-design.md (Section 3).

Key changes:
- Add `=== COMMAND-ONLY OUTPUT ===` section
- Add `NOOP` to allowed actions
- Specify `@all` with `[ORCHESTRATOR]` in message body
- Add `=== FORBIDDEN ACTIONS ===` with new rules

**Acceptance:** Prompt file matches design doc.

---

## Coordination

| Agent | Tasks | Files |
|-------|-------|-------|
| **Codex** | G1-G7 | `src/gateway/csp_gateway.js` |
| **Claude** | S1-S4 | `csp_sidecar.py`, `orchestrator_prompt.txt` |

**No conflicts** - different files entirely.

---

## Testing Checklist

After both complete:

- [ ] Start CSP with `CSP_ORCHESTRATOR=1`
- [ ] Verify heartbeat arrives every 30s
- [ ] Verify heartbeat includes context snapshot
- [ ] Verify orchestrator responds with single command
- [ ] Start debate with `/mode debate "test"`
- [ ] Verify gateway auto-advances when agent responds
- [ ] Wait 2+ minutes - verify timeout auto-advance
- [ ] Verify invalid orchestrator messages are rejected
- [ ] Verify NOOP command works
- [ ] Complete full debate and verify synthesis

---

*This document splits orchestrator implementation for parallel work.*
