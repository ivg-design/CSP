# Orchestrator Pane Implementation Tasks

**Date:** 2025-12-27
**Status:** READY FOR PARALLEL IMPLEMENTATION
**Context:** Claude (Opus) will work on Python/sidecar changes while Codex works on JavaScript/Bash changes.

---

## Overview

Phase 6 adds an optional 5th tmux pane running a lightweight orchestrator agent (Claude Haiku) that can manage structured collaboration modes.

---

## API Contract

### Orchestrator Commands (sidecar → gateway)

```python
# @mode.set command sends POST /mode
POST /mode
{
  "mode": "debate",
  "topic": "Best approach to...",
  "agents": ["claude", "codex", "gemini"],
  "rounds": 3
}

# @mode.status command sends GET /mode
GET /mode
# Returns orchestration state
```

### System Messages (gateway → all agents)

```
Mode: DEBATE
Topic: Best approach to...
@claude - Your turn.
Round 2
@codex - Your turn.
DEBATE complete.
```

---

## Claude Tasks (Python/Sidecar)

### Task C1: Add Orchestrator Command Patterns
**File:** `csp_sidecar.py` in `AgentCommandProcessor`

Add patterns for orchestrator commands:

```python
# Add to command_patterns list
self.mode_set_pattern = re.compile(
    r'@mode\.set\s+(\w+)\s+"([^"]+)"(?:\s+--rounds\s+(\d+))?'
)
self.mode_status_pattern = re.compile(r'@mode\.status')
```

**Acceptance:** Pattern matches `@mode.set debate "topic" --rounds 3`

---

### Task C2: Add Orchestrator Command Execution
**File:** `csp_sidecar.py` in `AgentCommandProcessor.execute_command()`

```python
def execute_command(self, match, pattern_name):
    if pattern_name == 'mode_set':
        mode = match.group(1)
        topic = match.group(2)
        rounds = int(match.group(3)) if match.group(3) else 3

        # Get agent list
        agents_res = requests.get(
            f"{self.gateway_url}/agents",
            headers={'X-Auth-Token': self.auth_token}
        )
        agent_ids = [a['id'] for a in agents_res.json() if a['id'] != 'Human']

        response = requests.post(
            f"{self.gateway_url}/mode",
            json={'mode': mode, 'topic': topic, 'rounds': rounds, 'agents': agent_ids},
            headers={'X-Auth-Token': self.auth_token}
        )
        return f"[CSP: Mode set to {mode}]"

    if pattern_name == 'mode_status':
        response = requests.get(
            f"{self.gateway_url}/mode",
            headers={'X-Auth-Token': self.auth_token}
        )
        data = response.json()
        return f"[CSP: Mode={data['mode']}, Round={data['round']+1}/{data['maxRounds']}]"
```

**Acceptance:** Orchestrator can run `@mode.set debate "test"` and gateway receives POST

---

### Task C3: Register Command Patterns in Processor
**File:** `csp_sidecar.py` in `AgentCommandProcessor.__init__()`

Ensure patterns are registered and detected:

```python
def __init__(self, gateway_url, auth_token):
    self.gateway_url = gateway_url
    self.auth_token = auth_token

    # Existing patterns...

    # Orchestrator patterns
    self.mode_set_pattern = re.compile(
        r'@mode\.set\s+(\w+)\s+"([^"]+)"(?:\s+--rounds\s+(\d+))?'
    )
    self.mode_status_pattern = re.compile(r'@mode\.status')
```

**Acceptance:** Orchestrator commands are detected in agent output

---

## Codex Tasks (JavaScript/Bash)

### Task X1: Update Launcher for 5-Pane Layout
**File:** `bin/start-llm-groupchat.sh`

Add orchestrator pane option:

```bash
# After existing pane setup, add:
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  echo "[CSP] Setting up 5-pane layout with orchestrator..."

  # Reorganize to: Human (top), Orch + 3 agents (bottom row)
  "$TMUX_BIN" select-layout -t "$SESSION_NAME" tiled

  # Create orchestrator pane
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.1"

  # Set orchestrator command
  ORCH_CMD="${CSP_ORCH_CMD:-/Users/ivg/.claude/local/claude --model haiku --dangerously-skip-permissions}"

  # Launch orchestrator with initial prompt
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.1" \
    "python3 csp_sidecar.py --name Orchestrator --gateway-url \$CSP_GATEWAY_URL --auth-token \$CSP_AUTH_TOKEN --initial-prompt \"\$(cat orchestrator_prompt.txt 2>/dev/null || echo 'You are the orchestrator.')\" --cmd $ORCH_CMD" C-m
fi
```

**Acceptance:** `CSP_ORCHESTRATOR=1 ./bin/start-llm-groupchat.sh` creates 5 panes

---

### Task X2: Create Orchestrator Prompt File
**File:** `orchestrator_prompt.txt` (new file in repo root)

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

**Acceptance:** File exists and is readable by launcher

---

### Task X3: Add --initial-prompt Support to Sidecar
**File:** `csp_sidecar.py` argument parsing

This may already exist. Verify and add if missing:

```python
parser.add_argument('--initial-prompt', type=str, default=None,
                    help='Initial prompt to inject after agent starts')
```

And in the main loop, inject the prompt after connection:

```python
if args.initial_prompt:
    time.sleep(2)  # Wait for agent to initialize
    os.write(master_fd, args.initial_prompt.encode('utf-8') + b'\n')
```

**Acceptance:** `--initial-prompt "Hello"` injects text after agent starts

---

### Task X4: Document Orchestrator Usage
**File:** `README.md`

Add section:

```markdown
## Orchestrator Mode (Optional)

Launch with an AI orchestrator (Claude Haiku) to manage structured collaboration:

\`\`\`bash
CSP_ORCHESTRATOR=1 ./bin/start-llm-groupchat.sh
\`\`\`

The orchestrator can:
- Set collaboration modes: `@mode.set debate "topic"`
- Check status: `@mode.status`
- Coordinate turn-taking across agents
\`\`\`
```

**Acceptance:** README documents orchestrator usage

---

## Coordination Protocol

1. **Claude works on:** Tasks C1-C3 (sidecar command patterns)
2. **Codex works on:** Tasks X1-X4 (launcher, prompt file, docs)
3. **No file conflicts** - different files entirely
4. **Test independently** then integrate

---

## Testing Handoff

After both complete:
1. Run `CSP_ORCHESTRATOR=1 ./bin/start-llm-groupchat.sh`
2. Verify 5 panes appear
3. In orchestrator pane, run `@mode.set debate "test topic"`
4. Verify mode announcement broadcasts to all agents
5. Verify turn signals appear in agent panes

---

*This document splits Phase 6 for parallel implementation.*
