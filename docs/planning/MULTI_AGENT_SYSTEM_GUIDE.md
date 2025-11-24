# Multi-Agent Communication System Guide

## 🎯 Overview
This system enables real-time bidirectional communication between multiple CLI agents (Claude, Codex, Gemini) and a human operator through a centralized message broker.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                🎛️  Human Command Center                    │
│                    (Top Pane - 25%)                        │
└─────────────────────────────────────────────────────────────┘
┌─────────────────┬─────────────────┬─────────────────────────┐
│   🤖 Claude     │   💻 Codex      │      ✨ Gemini         │
│     Agent       │     Agent       │       Agent             │
│ (Bottom-Left)   │ (Bottom-Center) │   (Bottom-Right)        │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## 🚀 Getting Started

### 1. Launch the System
```bash
./multi_agent_terminal_v2.sh
```

### 2. System Components
- **Message Broker** (`message_broker.py`) - Central communication hub
- **Human Command Center** - Your control interface (top pane)
- **Agent Wrappers** - Individual agent interfaces (bottom panes)

## 🎮 Human Operator Guide

### Command Center Usage (Top Pane)

#### Basic Communication
```bash
# Broadcast to all agents
Hello everyone, I need help with authentication

# Explicit broadcast
@all Can someone review this code?

# Direct message to specific agent
@a1b2c3d4 Claude, can you explain this function?
```

#### Information Commands
```bash
/list           # Show all active agents with their unique IDs
/history        # Display recent message history
/help           # Show command reference
/clear          # Clear screen and show help
/quit           # Exit command center
```

### Agent Interaction Methods

#### Method 1: Command Center (Recommended)
- Stay in top pane and use commands above
- All agent responses appear in their respective panes
- Maintains conversation flow visibility

#### Method 2: Direct Agent Interaction
- Use `Ctrl-b + arrow keys` to switch to agent panes
- Interact directly with each agent's CLI
- Use agent-specific commands like `/msg`, `/status`

## 🤖 Agent Developer Guide

### Integrating New Agents

#### 1. Create Agent Wrapper Script
```bash
#!/bin/bash
# my_agent.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="MyAgent"

# Function to broadcast messages
broadcast_message() {
    local message="$1"
    python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from agent_client import AgentClient

client = AgentClient('$AGENT_NAME')
client.send_message('$message')
client.shutdown()
"
}

# Main interaction loop
while true; do
    read -p "MyAgent > " input
    case "$input" in
        /msg*)
            message="${input#/msg }"
            broadcast_message "$message"
            ;;
        *)
            # Execute your agent's commands here
            # my_agent_cli "$input"
            ;;
    esac
done
```

#### 2. Agent Communication Protocol

##### Sending Messages
```python
from agent_client import AgentClient

client = AgentClient('MyAgent')
client.send_message('Hello from MyAgent!')
client.send_message('Direct message', 'target_agent_id')
client.shutdown()
```

##### Receiving Messages
- Messages automatically appear via the listener thread
- Implement `handle_message()` in your agent wrapper
- Messages include: `id`, `timestamp`, `from`, `from_name`, `to`, `content`, `type`

#### 3. Agent Registration
- Agents auto-register with unique 8-character IDs
- IDs are persistent during session
- Registration broadcasts join/leave notifications

### Message Types
- **`chat`** - Normal conversation messages
- **`system`** - System notifications (join/leave, status)
- **`status`** - Agent status updates

## 🔧 System Administration

### Files Structure
```
/Users/ivg/
├── multi_agent_terminal_v2.sh    # Main launcher
├── message_broker.py             # Central message broker
├── agent_client.py               # Agent communication interface
├── human_command_prompt.sh       # Human command center
├── claude_agent.sh               # Claude wrapper
├── codex_agent.sh                # Codex wrapper
├── gemini_agent.sh               # Gemini wrapper
└── /tmp/agent_comm/              # Communication directory
    ├── global_messages.log       # All message history
    ├── agent_registry.json       # Active agents
    └── *_inbox.json             # Individual agent inboxes
```

### Monitoring and Debugging
```bash
# View live message feed
tail -f /tmp/agent_comm/global_messages.log

# Check active agents
cat /tmp/agent_comm/agent_registry.json

# Monitor specific agent
cat /tmp/agent_comm/{agent_id}_inbox.json
```

### tmux Session Management
```bash
# Attach to existing session
tmux attach -t multi-agents-v2

# List sessions
tmux list-sessions

# Kill session
tmux kill-session -t multi-agents-v2
```

## 💡 Best Practices

### For Human Operators
1. **Use `/list`** regularly to track active agents
2. **Use direct messages** (`@agent_id`) for specific tasks
3. **Check `/history`** to understand conversation context
4. **Switch panes** to see agent outputs in real-time

### For Agents
1. **Announce status** when starting/stopping tasks
2. **Use descriptive messages** that include context
3. **Acknowledge requests** before starting work
4. **Share results** after completing tasks
5. **Ask clarifying questions** when requests are unclear

### Communication Etiquette
- **Prefix messages** with purpose (e.g., "🔍 Analysis:", "💡 Suggestion:")
- **Tag relevant agents** in complex discussions
- **Summarize findings** for group visibility
- **Use status updates** to show progress

## 🚨 Troubleshooting

### Common Issues
1. **Python not found**: Install Python 3: `brew install python3`
2. **tmux not found**: Install tmux: `brew install tmux`
3. **Agents not responding**: Check `/tmp/agent_comm/` permissions
4. **Messages not appearing**: Restart message broker
5. **Session conflicts**: Kill existing sessions before starting

### Recovery Commands
```bash
# Clean restart
tmux kill-session -t multi-agents-v2
rm -rf /tmp/agent_comm
./multi_agent_terminal_v2.sh

# Manual broker restart
python3 message_broker.py &
```

## 🔮 Advanced Features

### Custom Agent Integration
- Modify agent wrapper scripts to integrate with your CLI tools
- Implement custom message filtering and routing
- Add agent-specific status indicators and health checks

### Extending the Protocol
- Add new message types for specialized communication
- Implement agent-to-agent private channels
- Create persistent conversation threads and topics

---

**Happy Multi-Agent Collaboration! 🚀**