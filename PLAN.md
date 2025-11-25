# CSP Agent POC Implementation Plan

## Objective

Create three separate proof-of-concept implementations, one for each agent (Claude, Codex, Gemini), to validate the structured response retrieval mechanisms before integrating all three into a unified chat system.

Each POC will be a 2-pane tmux setup:
- **Top pane**: Chat UI (send messages, display responses)
- **Bottom pane**: Agent (full TUI)

---

## Phase 1: Claude Code POC

### Mechanism: Claude Code Hooks

Claude Code has a robust hook system. We'll use:
- `UserPromptSubmit` hook: Mark start of processing
- `Stop` hook: Mark end of response, capture output

### Files to Create

```
poc/claude/
├── run.sh                    # Launch script (2-pane tmux)
├── chat.py                   # Chat UI for Claude
└── hooks/
    ├── on_prompt_submit.sh   # Writes start marker
    └── on_stop.sh            # Writes response to file
```

### Hook Configuration

Create/update `~/.claude/settings.json`:
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/ivg/github/csp/poc/claude/hooks/on_prompt_submit.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/ivg/github/csp/poc/claude/hooks/on_stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Response Flow

1. User types message in chat.py
2. chat.py sends message to Claude pane via `tmux send-keys`
3. `on_prompt_submit.sh` fires → writes `/tmp/csp-claude-start` with timestamp
4. Claude processes and responds
5. `on_stop.sh` fires → reads transcript, extracts last response, writes to `/tmp/csp-claude-response`
6. chat.py watches `/tmp/csp-claude-response` for changes
7. chat.py reads response and displays it

### Hook Scripts

**on_prompt_submit.sh**:
```bash
#!/bin/bash
echo "$(date +%s)" > /tmp/csp-claude-start
```

**on_stop.sh**:
```bash
#!/bin/bash
# Read JSON from stdin (Claude passes hook context)
INPUT=$(cat)

# Extract transcript path
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

# Get last assistant message from transcript
if [[ -f "$TRANSCRIPT" ]]; then
    RESPONSE=$(tail -20 "$TRANSCRIPT" | jq -s '[.[] | select(.type == "assistant")] | last | .message.content[] | select(.type == "text") | .text' 2>/dev/null | tr -d '"')
    echo "$RESPONSE" > /tmp/csp-claude-response
fi

echo "$(date +%s)" > /tmp/csp-claude-end
```

### chat.py Logic

```python
class ClaudeChatMonitor:
    def __init__(self, pane_id):
        self.pane_id = pane_id
        self.response_file = "/tmp/csp-claude-response"
        self.start_file = "/tmp/csp-claude-start"

    def send_message(self, message):
        # Clear previous response
        Path(self.response_file).unlink(missing_ok=True)

        # Record current mtime of start file (or 0 if doesn't exist)
        self.last_start = self._get_mtime(self.start_file)

        # Send to Claude
        subprocess.run(['tmux', 'send-keys', '-t', self.pane_id, '-l', message])
        subprocess.run(['tmux', 'send-keys', '-t', self.pane_id, 'Enter'])

    def wait_for_response(self, timeout=300):
        start_time = time.time()

        while time.time() - start_time < timeout:
            # Check if response file exists and was written after we sent
            if Path(self.response_file).exists():
                response_mtime = self._get_mtime(self.response_file)
                if response_mtime > self.last_start:
                    return Path(self.response_file).read_text().strip()
            time.sleep(0.1)

        return None
```

### Validation Criteria

- [ ] Hook scripts execute on prompt submit and stop
- [ ] Response file contains clean text (no ANSI, no UI garbage)
- [ ] Response matches what's visible in Claude's pane
- [ ] Multiple messages work in sequence
- [ ] Long responses are captured completely

---

## Phase 2: Codex CLI POC

### Mechanism: Notify JSON Payload

Codex's `notify` config passes a JSON payload to an external script containing:
```json
{
  "type": "agent-turn-complete",
  "turn-id": "abc123",
  "input-messages": ["User prompt"],
  "last-assistant-message": "The actual response"
}
```

### Files to Create

```
poc/codex/
├── run.sh                    # Launch script (2-pane tmux)
├── chat.py                   # Chat UI for Codex
└── notify_handler.py         # Receives JSON, writes response
```

### Codex Configuration

Create/update `~/.codex/config.toml`:
```toml
notify = ["python3", "/Users/ivg/github/csp/poc/codex/notify_handler.py"]
```

### Response Flow

1. User types message in chat.py
2. chat.py sends message to Codex pane via `tmux send-keys`
3. chat.py writes timestamp to `/tmp/csp-codex-start`
4. Codex processes and responds
5. Codex calls notify_handler.py with JSON payload
6. notify_handler.py extracts `last-assistant-message`, writes to `/tmp/csp-codex-response`
7. chat.py watches for response file update
8. chat.py reads and displays response

### notify_handler.py

```python
#!/usr/bin/env python3
import sys
import json
from pathlib import Path

def main():
    # Codex appends JSON as last argument
    if len(sys.argv) < 2:
        return

    try:
        payload = json.loads(sys.argv[-1])

        if payload.get("type") == "agent-turn-complete":
            response = payload.get("last-assistant-message", "")
            Path("/tmp/csp-codex-response").write_text(response)
            Path("/tmp/csp-codex-end").write_text(str(int(time.time())))
    except json.JSONDecodeError:
        pass

if __name__ == "__main__":
    main()
```

### Validation Criteria

- [ ] notify_handler.py receives JSON payload
- [ ] `last-assistant-message` contains complete response
- [ ] Response is clean text (no formatting issues)
- [ ] Works for short and long responses
- [ ] Works for multi-turn conversations

---

## Phase 3: Gemini CLI POC

### Mechanism: Local Telemetry File

Gemini can write telemetry to a local file. We'll parse agent run events.

### Files to Create

```
poc/gemini/
├── run.sh                    # Launch script (2-pane tmux)
├── chat.py                   # Chat UI for Gemini
└── telemetry_parser.py       # Parse telemetry for responses
```

### Gemini Configuration

Create/update `~/.gemini/settings.json`:
```json
{
  "telemetry": {
    "enabled": true,
    "target": "local",
    "outfile": "/tmp/csp-gemini-telemetry.log"
  }
}
```

### Response Flow

1. User types message in chat.py
2. chat.py records current position in telemetry file
3. chat.py sends message to Gemini pane via `tmux send-keys`
4. Gemini processes and responds
5. Gemini writes telemetry events to log file
6. chat.py tails telemetry file from recorded position
7. telemetry_parser.py extracts response from agent run completion events
8. chat.py displays response

### Research Required

Before implementation, need to verify:
- Exact format of telemetry file (JSON lines? Binary?)
- Which event types contain the response text
- Whether response content is included or just metadata

### Validation Criteria

- [ ] Telemetry file is written during Gemini usage
- [ ] Response content is captured in telemetry
- [ ] Parser correctly extracts response text
- [ ] Works for various response types (text, code, etc.)

---

## Phase 4: Integration

After all three POCs validate successfully, create unified system:

```
poc/multi/
├── run.sh                    # Launch 4-pane tmux (chat + 3 agents)
├── chat.py                   # Unified chat UI
└── monitors/
    ├── claude_monitor.py     # Claude hook-based monitor
    ├── codex_monitor.py      # Codex notify-based monitor
    └── gemini_monitor.py     # Gemini telemetry-based monitor
```

### Unified Chat Features

- `@claude message` - Send to Claude only
- `@codex message` - Send to Codex only
- `@gemini message` - Send to Gemini only
- `@all message` - Broadcast to all agents
- Display responses as they arrive with agent name prefix

---

## Implementation Order

1. **Claude POC** (most straightforward - hooks are well-documented)
   - Create hook scripts
   - Configure ~/.claude/settings.json
   - Create chat.py
   - Create run.sh
   - Test and validate

2. **Codex POC** (JSON payload is clean)
   - Create notify_handler.py
   - Configure ~/.codex/config.toml
   - Create chat.py
   - Create run.sh
   - Test and validate

3. **Gemini POC** (may need research on telemetry format)
   - Enable telemetry, capture sample output
   - Analyze telemetry format
   - Create telemetry_parser.py
   - Create chat.py
   - Create run.sh
   - Test and validate

4. **Integration** (after all POCs pass)
   - Create unified chat.py
   - Create multi-pane run.sh
   - Test cross-agent scenarios

---

## Success Metrics

Each POC is successful when:

1. **Reliable Detection**: 100% of responses are detected (no missed responses)
2. **Clean Output**: Response text has no ANSI codes, UI elements, or garbage
3. **Complete Capture**: Full response is captured (not truncated)
4. **Low Latency**: Response appears in chat within 1 second of agent finishing
5. **No Side Effects**: Agent TUI remains functional and clean

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Claude hooks don't include response | Read from transcript_path provided in hook context |
| Codex notify doesn't fire | Check config.toml syntax, verify Codex version |
| Gemini telemetry format unknown | Capture sample, analyze before building parser |
| Hook config conflicts with user settings | Use project-local settings where possible |
| Response file race conditions | Use atomic writes, check timestamps |

---

## Timeline Estimate

- Phase 1 (Claude): ~30 minutes
- Phase 2 (Codex): ~30 minutes
- Phase 3 (Gemini): ~45 minutes (includes format research)
- Phase 4 (Integration): ~1 hour

Total: ~3 hours

---

## Next Steps

Begin with Phase 1: Claude POC

1. Create `poc/claude/` directory structure
2. Write hook scripts
3. Configure Claude settings
4. Implement chat.py
5. Create run.sh
6. Test and validate
