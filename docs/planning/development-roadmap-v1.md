# CSP Definitive Development Plan

**Date:** 2025-12-27
**Contributors:** Claude (Opus 4.5), Codex (GPT-5)
**Status:** Consolidated from PROPOSAL_MEMO.md, ANALYSIS_AND_FIXES.md, ANALYSIS_AND_FIXES_AMENDED.md, and Puzldai code review

---

## Vision

CSP enables **real-time multi-agent group chat** where humans and AI agents (Claude, Codex, Gemini) collaborate visually in tmux panes. Unlike batch orchestration tools, CSP preserves the full interactive experience while adding structured collaboration modes.

---

## Confirmed Issues (All Sources)

| # | Issue | Root Cause | References | Status |
|---|-------|------------|------------|--------|
| 1 | Claude fails to start | `os.execvp` doesn't resolve shell aliases | `csp_sidecar.py:395`, `csp-agent-launcher.sh:59` | **FIXED** |
| 2 | ANSI spam / feedback loop | `share_enabled = True` on every inbound message | `csp_sidecar.py:774` | **FIXED** |
| 3 | Messages never delivered | Flow control `is_idle()` blocks TUI apps | `csp_sidecar.py:812-816`, `csp_sidecar.py:249-267` | **FIXED** |
| 4 | Agent ID collisions | `split('-')[0]` truncation | `csp_sidecar.py:346` | **FIXED** |
| 5 | Dashed IDs fail in `@send` | Regex `\w+` excludes dashes | `csp_sidecar.py:53` | **FIXED** |
| 6 | History not loaded on restart | Write-only JSONL, unbounded RAM | `csp_gateway.js:12-18` | **FIXED** |
| 7 | No orchestration modes | Missing state, endpoints, UI | Entire codebase | **FIXED** |

---

## Lessons from Puzldai (Applied to Interactive Model)

Puzldai uses **batch mode** (`-p` flag) which avoids TUI complexity. CSP keeps **interactive mode** but can learn from Puzldai's orchestration patterns:

### 1. Template Variables for Context Passing
Puzldai builds prompts with previous outputs:
```javascript
prompt: `Respond to: {{claude_round0}} {{gemini_round0}}`
```

**CSP Adaptation:** Gateway accumulates round outputs and the orchestrator injects context summaries:
```
[Orchestrator → Claude]
Round 2: Respond to previous positions.
- Codex said: "The bug is in the async handler..."
- Gemini said: "I disagree, the issue is..."

Your turn. Present your response.
```

### 2. Dependency Graph for Turn Order
Puzldai ensures step order with `dependsOn`:
```javascript
{ id: "step_3", dependsOn: ["step_0", "step_1", "step_2"] }
```

**CSP Adaptation:** Gateway tracks `completedTurns` and only announces next turn when dependencies are met. Broadcast includes turn marker:
```json
{
  "type": "turn_signal",
  "currentAgent": "codex",
  "round": 2,
  "waitingFor": []
}
```

### 3. Structured Response Formats
Puzldai's consensus uses strict vote format:
```
VOTE: [A/B/C]
Reason: [explanation]
```

**CSP Adaptation:** Orchestrator prompt includes response templates. Parse with simple regex.

### 4. Phase-Based Workflows
Puzldai debate phases:
1. Initial positions (parallel)
2. Responses (sequential with context)
3. Synthesis (moderator)

**CSP Adaptation:** Orchestrator manages phase transitions via `/mode` commands.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              TMUX SESSION                               │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    🎛️  Human Controller                          │   │
│  │                    (chat-controller.js)                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
├────────────────┬────────────────┬────────────────┬──────────────────────┤
│ 🎭 Orchestrator│ 🤖 Claude      │ 💻 Codex       │ ✨ Gemini            │
│ (Haiku)        │ (Opus/Sonnet)  │                │                      │
│ [Optional]     │                │                │                      │
└────────────────┴────────────────┴────────────────┴──────────────────────┘
        │                │                │                │
        └────────────────┴────────────────┴────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │      CSP Gateway          │
                    │  - WebSocket broadcast    │
                    │  - Orchestration state    │
                    │  - History persistence    │
                    │  - /mode, /turn endpoints │
                    └───────────────────────────┘
```

---

## Phased Implementation Plan

### Phase 0: Verify Fixes Already Applied ✅ COMPLETE

| Task | Status |
|------|--------|
| Claude path in launcher | ✅ Fixed |
| `share_enabled` auto-enable disabled | ✅ Fixed |
| Flow control bypass for TUI apps | ✅ Fixed (timeout-based: 500ms max wait) |
| `/share` and `/noshare` commands added | ✅ Fixed |

**Verify:** Run CSP, send message from Human, confirm agents receive it.

---

### Phase 1: Agent Identity ✅ COMPLETE

#### 1.1 Stop ID Truncation
**File:** `csp_sidecar.py:346`

```python
# BEFORE:
self.agent_id = self.agent_name.lower().replace(' ', '-').split('-')[0]

# AFTER:
self.agent_id = self.agent_name.lower().replace(' ', '-')
```

#### 1.2 Gateway Enforces Unique IDs
**File:** `src/gateway/csp_gateway.js` in `registerAgent()`

```javascript
registerAgent(agentId, capabilities) {
  let finalId = agentId.toLowerCase();
  let counter = 1;

  // Ensure uniqueness
  while (this.agents.has(finalId)) {
    counter++;
    finalId = `${agentId.toLowerCase()}-${counter}`;
  }

  this.agents.set(finalId, {
    id: finalId,
    name: agentId,
    capabilities,
    lastSeen: Date.now(),
    online: true
  });

  return { success: true, agentId: finalId };  // Return confirmed ID
}
```

#### 1.3 Sidecar Uses Returned ID
**File:** `csp_sidecar.py` in `register_agent()`

```python
if response.status_code in [200, 201]:
    data = response.json()
    self.agent_id = data.get('agentId', self.agent_id)  # Use gateway's confirmed ID
```

**Acceptance:** `/agents` shows `claude`, `claude-2`, `claude-3` for multiple instances.

---

### Phase 2: Addressing Fixes ✅ COMPLETE

#### 2.1 Allow Dashes in `@send` Regex
**File:** `csp_sidecar.py:53`

```python
# BEFORE:
re.compile(r'@send\.(\w+)\s+(.+)')

# AFTER:
re.compile(r'@send\.([\w-]+)\s+(.+)')
```

#### 2.2 Document ID Format
All agent IDs are lowercase with optional dashes. Examples: `claude`, `codex-2`, `gemini`.

**Acceptance:** `@send.claude-2 hello` works.

---

### Phase 3: History Persistence ✅ COMPLETE

#### 3.1 Load History on Startup
**File:** `src/gateway/csp_gateway.js` constructor

```javascript
const MAX_HISTORY = 1000;

loadHistory() {
  if (!fs.existsSync(this.historyPath)) return;

  const lines = fs.readFileSync(this.historyPath, 'utf-8')
    .split('\n')
    .filter(line => line.trim())
    .slice(-MAX_HISTORY);

  for (const line of lines) {
    try {
      this.chatHistory.push(JSON.parse(line));
    } catch (e) {
      // Skip malformed lines
    }
  }

  console.log(`[Gateway] Loaded ${this.chatHistory.length} messages from history`);
}
```

#### 3.2 Cap In-Memory History
```javascript
appendHistory(message) {
  this.chatHistory.push(message);
  if (this.chatHistory.length > MAX_HISTORY) {
    this.chatHistory.shift();  // Remove oldest
  }
  // Append to JSONL file
  fs.appendFileSync(this.historyPath, JSON.stringify(message) + '\n');
}
```

**Acceptance:** Restart gateway, `/history` returns previous messages.

---

### Phase 4: Orchestration State ✅ COMPLETE

#### 4.1 Add State to Gateway
**File:** `src/gateway/csp_gateway.js` constructor

```javascript
this.orchestration = {
  mode: 'freeform',           // 'freeform' | 'debate' | 'consensus' | 'autopilot'
  topic: null,
  round: 0,
  maxRounds: 3,
  turnOrder: [],              // ['claude', 'codex', 'gemini']
  currentTurnIndex: 0,
  completedTurns: new Set(),  // Track who has responded this round
  roundOutputs: {},           // { claude: { round0: "...", round1: "..." } }
  proposals: new Map(),       // For consensus
  votes: new Map()            // For consensus
};
```

#### 4.2 Add `/mode` Endpoint

```javascript
app.post('/mode', (req, res) => {
  const { mode, topic, agents, rounds } = req.body;

  if (!['freeform', 'debate', 'consensus', 'autopilot'].includes(mode)) {
    return res.status(400).json({ error: 'Invalid mode' });
  }

  this.orchestration = {
    ...this.orchestration,
    mode,
    topic: topic || null,
    round: 0,
    maxRounds: rounds || 3,
    turnOrder: agents || [],
    currentTurnIndex: 0,
    completedTurns: new Set(),
    roundOutputs: {}
  };

  this.broadcastSystemMessage(`🎭 Mode: ${mode.toUpperCase()}`);
  if (topic) this.broadcastSystemMessage(`📋 Topic: ${topic}`);

  if (mode !== 'freeform' && this.orchestration.turnOrder.length > 0) {
    const first = this.orchestration.turnOrder[0];
    this.broadcastSystemMessage(`📢 Round 1 | @${first} - Your turn.`);
  }

  res.json({ success: true, orchestration: this.orchestration });
});

app.get('/mode', (req, res) => {
  res.json(this.orchestration);
});
```

#### 4.3 Add `/turn/next` Endpoint

```javascript
app.post('/turn/next', (req, res) => {
  const o = this.orchestration;

  if (o.mode === 'freeform') {
    return res.status(400).json({ error: 'Not in structured mode' });
  }

  // Mark current agent as completed
  const currentAgent = o.turnOrder[o.currentTurnIndex];
  o.completedTurns.add(`${currentAgent}_round${o.round}`);

  // Advance turn
  o.currentTurnIndex++;

  if (o.currentTurnIndex >= o.turnOrder.length) {
    // Round complete
    o.currentTurnIndex = 0;
    o.round++;
    o.completedTurns.clear();

    if (o.round >= o.maxRounds) {
      this.broadcastSystemMessage(`✅ ${o.mode.toUpperCase()} complete.`);
      o.mode = 'freeform';
      return res.json({ complete: true });
    }

    this.broadcastSystemMessage(`📢 Round ${o.round + 1}`);
  }

  const nextAgent = o.turnOrder[o.currentTurnIndex];
  this.broadcastSystemMessage(`📢 @${nextAgent} - Your turn.`);

  res.json({
    success: true,
    currentTurn: nextAgent,
    round: o.round
  });
});
```

**Acceptance:** `curl -X POST localhost:8765/mode -d '{"mode":"debate","topic":"test","agents":["claude","codex"]}'` works.

---

### Phase 5: Human Interface Commands ✅ COMPLETE

**File:** `src/human-interface/chat-controller.js`

Add to command handler:

```javascript
// /mode <mode> <topic>
if (input.startsWith('/mode ')) {
  const parts = input.substring(6).trim().split(' ');
  const mode = parts[0];
  const topic = parts.slice(1).join(' ');

  const agentsRes = await this.client.get('/agents');
  const agentIds = agentsRes.data.filter(a => a.id !== 'Human').map(a => a.id);

  await this.client.post('/mode', { mode, topic, agents: agentIds, rounds: 3 });
  rl.prompt();
  return;
}

// /status
if (input === '/status') {
  const res = await this.client.get('/mode');
  const o = res.data;
  console.log(`\n📊 Mode: ${o.mode}`);
  console.log(`   Topic: ${o.topic || 'N/A'}`);
  if (o.mode !== 'freeform') {
    console.log(`   Round: ${o.round + 1}/${o.maxRounds}`);
    console.log(`   Current: ${o.turnOrder[o.currentTurnIndex]}`);
  }
  console.log('');
  rl.prompt();
  return;
}

// /next
if (input === '/next') {
  await this.client.post('/turn/next');
  rl.prompt();
  return;
}

// /end
if (input === '/end') {
  await this.client.post('/mode', { mode: 'freeform' });
  console.log('\n🔄 Returned to freeform mode\n');
  rl.prompt();
  return;
}
```

Update `/help` to include new commands.

**Acceptance:** Human can run `/mode debate "Best approach to fix X"` and see turn announcements.

---

### Phase 6: Orchestrator Pane (2 hours)

#### 6.1 Update Launcher for 5 Panes
**File:** `bin/start-llm-groupchat.sh`

```bash
# Add orchestrator pane (optional via CSP_ORCHESTRATOR=1)
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  # 5-pane layout: Human (top), Orch + 3 agents (bottom)
  "$TMUX_BIN" split-window -v -p 80 -t "$SESSION_NAME:0.0"
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.1"
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.2"
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.3"

  # Orchestrator in first bottom pane
  ORCH_CMD="${CSP_ORCH_CMD:-/Users/ivg/.claude/local/claude --model haiku --dangerously-skip-permissions}"
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.1" "python3 csp_sidecar.py --name Orchestrator --gateway-url \$CSP_GATEWAY_URL --auth-token \$CSP_AUTH_TOKEN --initial-prompt \"\$(cat orchestrator_prompt.txt)\" --cmd $ORCH_CMD" C-m
fi
```

#### 6.2 Create Orchestrator Prompt
**File:** `orchestrator_prompt.txt`

```
You are the ORCHESTRATOR for a multi-agent collaboration system. You are Claude Haiku, optimized for fast, lightweight coordination.

YOUR ROLE: Manage structured collaboration. You DO NOT perform tasks yourself.

AVAILABLE COMMANDS:
- @mode.set debate "<topic>" --rounds N
- @mode.set consensus "<question>"
- @mode.status
- @send.<agent> <message>
- @all <message>

MODES YOU MANAGE:

1. FREEFORM (default)
   - Agents communicate freely
   - Intervene only to summarize or resolve conflicts

2. DEBATE
   - Round 1: Each agent presents position
   - Rounds 2+: Agents respond to each other
   - Final: You synthesize key points
   - Announce turns: "@claude Your turn to present your position"

3. CONSENSUS
   - Phase 1: Each agent proposes solution
   - Phase 2: Agents vote (format: "VOTE: [A/B/C]")
   - Phase 3: You synthesize winning approach

PROTOCOL:
- Announce mode changes clearly
- For structured modes, announce each turn: "@<agent> Your turn"
- Summarize at end of each round
- Use @query.log to review context if needed

RESPONSE FORMAT FOR VOTING:
When asking agents to vote, require this format:
  VOTE: [A/B/C]
  REASON: [one sentence]

You are ready. Await mode commands or observe in freeform mode.
```

#### 6.3 Add Orchestrator Commands to Sidecar
**File:** `csp_sidecar.py` in `AgentCommandProcessor.detect_commands()`

```python
# Add patterns for orchestrator commands
self.command_patterns.append(
    re.compile(r'@mode\.set\s+(\w+)\s+"([^"]+)"(?:\s+--rounds\s+(\d+))?')
)
self.command_patterns.append(
    re.compile(r'@mode\.status')
)

# In execute_command:
if command_type == 'mode_set':
    mode, topic, rounds = args['mode'], args['topic'], args.get('rounds', 3)
    response = requests.post(f"{self.gateway_url}/mode", json={
        'mode': mode, 'topic': topic, 'rounds': int(rounds),
        'agents': self._get_agent_list()
    }, headers={'X-Auth-Token': self.auth_token})
    return f"[CSP: Mode set to {mode}]"

if command_type == 'mode_status':
    response = requests.get(f"{self.gateway_url}/mode",
        headers={'X-Auth-Token': self.auth_token})
    return f"[CSP: {response.json()}]"
```

**Acceptance:** Orchestrator can run `@mode.set debate "topic"` and turn announcements appear.

---

### Phase 7: Soft Turn Signals ✅ COMPLETE

#### 7.1 Gateway Tags Messages
```javascript
routeMessage(fromAgent, content, targetAgent) {
  const message = {
    // ... existing fields
    turnSignal: this.getTurnSignal(targetAgent)
  };
}

getTurnSignal(targetAgent) {
  const o = this.orchestration;
  if (o.mode === 'freeform') return null;

  const currentAgent = o.turnOrder[o.currentTurnIndex];
  if (targetAgent === currentAgent) return 'your_turn';
  if (o.turnOrder.includes(targetAgent)) return 'turn_wait';
  return null;
}
```

#### 7.2 Sidecar Displays Turn Signals
```python
def inject_message(self, msg_obj):
    turn_signal = msg_obj.get('turnSignal')

    if turn_signal == 'your_turn':
        content = f"🎯 YOUR TURN\n{content}"
    elif turn_signal == 'turn_wait':
        # Show notice but still inject (soft enforcement)
        print(f"[CSP] Waiting for your turn (current: {msg_obj.get('currentTurn')})", file=sys.stderr)

    self._write_injection(sender, content)
```

**Acceptance:** Agents see "🎯 YOUR TURN" when it's their turn.

---

### Phase 8: Improved ANSI Filtering ✅ COMPLETE

If shared output still contains artifacts, upgrade `_sanitize_stream()`:

```python
def _sanitize_stream(self, text: str) -> str:
    # Strip complete CSI sequences (ESC [ ... letter)
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)

    # Strip orphaned CSI parameters (no ESC prefix)
    text = re.sub(r'(?<![a-zA-Z\x1b])[\d;]+[A-HJKSTfmsu](?![a-zA-Z])', '', text)

    # Strip OSC sequences
    text = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?', '', text)

    # Strip DEC private modes
    text = re.sub(r'\?\d+[hl]', '', text)

    # Collapse whitespace
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)

    return text.strip()
```

---

### Phase 9: Documentation (30 min)

Update `README.md`:

```markdown
## Commands

### Human Controller
- `@agent message` - Send to specific agent
- `@all message` - Broadcast to all
- `/agents` - List connected agents
- `/mode <mode> <topic>` - Start structured mode (debate/consensus)
- `/status` - Show current mode and turn
- `/next` - Advance to next turn
- `/end` - Return to freeform
- `/share` - Enable output sharing for an agent
- `/noshare` - Disable output sharing

### Orchestrator Commands
- `@mode.set debate "topic" --rounds N`
- `@mode.set consensus "question"`
- `@mode.status`

### Agent IDs
All IDs are lowercase, dashes allowed. Multiple instances get suffixes: `claude`, `claude-2`.
```

---

## Validation Checklist

- [x] Claude launches without alias errors
- [x] Messages delivered to agents (timeout-based flow control)
- [x] No ANSI spam after messaging (conservative CSI stripping)
- [x] `/share` and `/noshare` work
- [x] Multiple agents have unique IDs (gateway enforces uniqueness)
- [x] `@send.agent-name` works with dashes
- [x] History survives gateway restart (JSONL loaded on startup)
- [x] `/mode debate "topic"` starts debate
- [x] Turn announcements appear
- [ ] Orchestrator can drive mode changes (Phase 6 - Optional, not yet implemented)
- [x] Soft turn signals display correctly (ASCII markers: [YOUR TURN], [WAITING])

---

## Implementation Order

| Priority | Phase | Effort | Dependencies | Status |
|----------|-------|--------|--------------|--------|
| 🔴 Critical | 0: Verify fixes | 10 min | None | ✅ DONE |
| 🟠 High | 1: Agent identity | 1-2 hr | Phase 0 | ✅ DONE |
| 🟠 High | 2: Addressing fixes | 30 min | Phase 1 | ✅ DONE |
| 🟡 Medium | 3: History persistence | 1 hr | None | ✅ DONE |
| 🟡 Medium | 4: Orchestration state | 2 hr | None | ✅ DONE |
| 🟡 Medium | 5: Human commands | 1 hr | Phase 4 | ✅ DONE |
| 🟢 Low | 6: Orchestrator pane | 2 hr | Phase 4, 5 | ⏳ Optional |
| 🟢 Low | 7: Turn signals | 1 hr | Phase 4 | ✅ DONE |
| ⚪ Optional | 8: Better ANSI filter | 1 hr | None | ✅ DONE |
| ⚪ Optional | 9: Documentation | 30 min | All | ✅ DONE |

**Status:** 9/10 phases complete. Phase 6 (Orchestrator pane) is optional and not yet implemented.

---

## Future Enhancements (Out of Scope)

- Web UI for visualization
- Persistent agent sessions across restarts
- Plugin system for custom modes
- Token usage tracking
- Rate limiting between agents

---

*This document supersedes all previous analysis documents.*
