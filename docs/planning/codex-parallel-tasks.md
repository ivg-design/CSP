# Codex Parallel Implementation Tasks

**Date:** 2025-12-27
**Status:** ✅ ALL TASKS COMPLETE
**Context:** Claude (Opus) worked on Python/sidecar changes while Codex worked on JavaScript/gateway changes.

---

## API Contract (Agreed Interface)

Before starting, both agents agree on these interfaces:

### 1. Registration Response
```javascript
// POST /register response
{
  "success": true,
  "agentId": "claude-2"  // Gateway-assigned unique ID
}
```

### 2. Orchestration State
```javascript
// GET /mode response
{
  "mode": "debate",           // 'freeform' | 'debate' | 'consensus' | 'autopilot'
  "topic": "Best approach...",
  "round": 0,
  "maxRounds": 3,
  "turnOrder": ["claude", "codex", "gemini"],
  "currentTurnIndex": 0
}
```

### 3. Message Envelope Extension
```javascript
// WebSocket broadcast message
{
  "id": "msg-123",
  "from": "Human",
  "to": "broadcast",
  "content": "Hello agents",
  "turnSignal": "your_turn" | "turn_wait" | null  // NEW FIELD
}
```

---

## Codex Tasks (JavaScript/Bash)

### Task 1: Gateway Unique ID Enforcement ✅ COMPLETE
**File:** `src/gateway/csp_gateway.js`
**Phase:** 1.3

Modify `registerAgent()` to:
1. Normalize ID to lowercase
2. Check if ID exists in `this.agents`
3. If exists, append `-2`, `-3`, etc. until unique
4. Return the confirmed ID in response

```javascript
// In registerAgent():
let finalId = agentId.toLowerCase();
let counter = 1;
while (this.agents.has(finalId)) {
  counter++;
  finalId = `${agentId.toLowerCase()}-${counter}`;
}
// ... register with finalId
return { success: true, agentId: finalId };
```

**Acceptance:** `curl -X POST /register -d '{"agentId":"claude"}'` twice returns `claude`, then `claude-2`.

---

### Task 2: History Persistence ✅ COMPLETE
**File:** `src/gateway/csp_gateway.js`
**Phase:** 3

Add to constructor:
```javascript
this.MAX_HISTORY = 1000;
this.loadHistory();  // New method
```

Implement:
```javascript
loadHistory() {
  if (!fs.existsSync(this.historyPath)) return;
  const lines = fs.readFileSync(this.historyPath, 'utf-8')
    .split('\n').filter(l => l.trim()).slice(-this.MAX_HISTORY);
  for (const line of lines) {
    try { this.chatHistory.push(JSON.parse(line)); } catch {}
  }
}

appendHistory(message) {
  this.chatHistory.push(message);
  if (this.chatHistory.length > this.MAX_HISTORY) {
    this.chatHistory.shift();
  }
  fs.appendFileSync(this.historyPath, JSON.stringify(message) + '\n');
}
```

**Acceptance:** Restart gateway, `/history` returns previous messages.

---

### Task 3: Orchestration State and Endpoints ✅ COMPLETE
**File:** `src/gateway/csp_gateway.js`
**Phase:** 4

Add to constructor:
```javascript
this.orchestration = {
  mode: 'freeform',
  topic: null,
  round: 0,
  maxRounds: 3,
  turnOrder: [],
  currentTurnIndex: 0
};
```

Add endpoints:
```javascript
app.get('/mode', (req, res) => {
  res.json(this.orchestration);
});

app.post('/mode', (req, res) => {
  const { mode, topic, agents, rounds } = req.body;
  if (!['freeform', 'debate', 'consensus', 'autopilot'].includes(mode)) {
    return res.status(400).json({ error: 'Invalid mode' });
  }
  this.orchestration = {
    mode,
    topic: topic || null,
    round: 0,
    maxRounds: rounds || 3,
    turnOrder: agents || [],
    currentTurnIndex: 0
  };
  this.broadcastSystemMessage(`🎭 Mode: ${mode.toUpperCase()}`);
  if (topic) this.broadcastSystemMessage(`📋 Topic: ${topic}`);
  if (mode !== 'freeform' && this.orchestration.turnOrder.length > 0) {
    this.broadcastSystemMessage(`📢 @${this.orchestration.turnOrder[0]} - Your turn.`);
  }
  res.json({ success: true, orchestration: this.orchestration });
});

app.post('/turn/next', (req, res) => {
  const o = this.orchestration;
  if (o.mode === 'freeform') {
    return res.status(400).json({ error: 'Not in structured mode' });
  }
  o.currentTurnIndex++;
  if (o.currentTurnIndex >= o.turnOrder.length) {
    o.currentTurnIndex = 0;
    o.round++;
    if (o.round >= o.maxRounds) {
      this.broadcastSystemMessage(`✅ ${o.mode.toUpperCase()} complete.`);
      o.mode = 'freeform';
      return res.json({ complete: true });
    }
    this.broadcastSystemMessage(`📢 Round ${o.round + 1}`);
  }
  const next = o.turnOrder[o.currentTurnIndex];
  this.broadcastSystemMessage(`📢 @${next} - Your turn.`);
  res.json({ success: true, currentTurn: next, round: o.round });
});
```

**Acceptance:** `curl -X POST /mode -d '{"mode":"debate","topic":"test","agents":["a","b"]}'` works.

---

### Task 4: Turn Signal in Message Envelope ✅ COMPLETE
**File:** `src/gateway/csp_gateway.js`
**Phase:** 7.1

Add helper:
```javascript
getTurnSignal(targetAgent) {
  const o = this.orchestration;
  if (o.mode === 'freeform') return null;
  const current = o.turnOrder[o.currentTurnIndex];
  if (targetAgent === current) return 'your_turn';
  if (o.turnOrder.includes(targetAgent)) return 'turn_wait';
  return null;
}
```

In `routeMessage()` or message broadcast, add:
```javascript
message.turnSignal = this.getTurnSignal(targetAgent);
```

**Acceptance:** Messages to current-turn agent have `turnSignal: "your_turn"`.

---

### Task 5: Human Interface Commands ✅ COMPLETE
**File:** `src/human-interface/chat-controller.js`
**Phase:** 5

Add command handlers (see development-roadmap-v1.md Phase 5 for full code):
- `/mode <mode> <topic>` - POST to `/mode`
- `/status` - GET `/mode` and display
- `/next` - POST to `/turn/next`
- `/end` - POST `/mode` with `freeform`

Update `/help` output.

**Acceptance:** Human can type `/mode debate "test"` and see turn announcements.

---

### Task 6: Orchestrator Pane (Optional) ⏳ NOT IMPLEMENTED
**Files:** `bin/start-llm-groupchat.sh`, `orchestrator_prompt.txt`
**Phase:** 6

Add optional 5th pane with Haiku. See development-roadmap-v1.md Phase 6 for details.
**Note:** This is optional and not required for core functionality.

---

## Coordination Protocol

1. **Claude works on:** `csp_sidecar.py` (Phases 1.2, 2.1, 7.2, 8)
2. **Codex works on:** Gateway + Human Interface + Launcher (Tasks 1-6 above)
3. **No file conflicts** - different files entirely
4. **Test independently** then integrate
5. **Merge via:** Each agent commits to main (or use branches if preferred)

---

## Testing Handoff

After Codex completes Tasks 1-4:
1. Claude tests sidecar against new gateway endpoints
2. Verify: registration returns unique ID, sidecar uses it
3. Verify: `/mode` changes broadcast correctly
4. Verify: `turnSignal` appears in WebSocket messages

---

## Implementation Summary

**Completed:** 2025-12-27

### Claude (Sidecar) Tasks:
- ✅ Phase 1.2: Stop ID truncation, use gateway-returned ID
- ✅ Phase 2.1: Fix @send regex to allow dashed IDs
- ✅ Phase 7.2: Add turn signal display in sidecar
- ✅ Phase 8: Comprehensive ANSI sanitization

### Codex (Gateway) Tasks:
- ✅ Task 1: Unique ID enforcement
- ✅ Task 2: History persistence (load/cap)
- ✅ Task 3: Orchestration state and endpoints
- ✅ Task 4: Turn signal in message envelope
- ✅ Task 5: Human interface commands
- ⏳ Task 6: Orchestrator pane (optional, not implemented)

### Post-Review Fixes (joint):
- ✅ Added `currentTurn` field to message envelope
- ✅ Replaced emoji markers with ASCII
- ✅ Fixed ANSI scrubber false positives
- ✅ Added timeout-based flow control (500ms max wait)

---

*This document was used for parallel implementation between Claude and Codex.*
