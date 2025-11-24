#!/bin/bash

# Claude Agent - Manual Launcher with Universal Access
# Launch with: ./claude_manual.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Claude"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🤖 Claude Agent with Universal Access${NC}"
echo -e "${YELLOW}⚠️  Running with --dangerously-skip-permissions${NC}"

# Check if Claude CLI is available
if ! command -v claude &> /dev/null; then
    echo -e "${RED}❌ Claude CLI not found. Please install first.${NC}"
    exit 1
fi

# Agent registration and messaging functions
broadcast_message() {
    local message="$1"
    python3 -c "
import sys
import os
sys.path.append('$SCRIPT_DIR')
try:
    from message_broker import MessageBroker
    broker = MessageBroker()
    broker.send_message('$AGENT_ID', '$message')
except Exception as e:
    pass
" 2>/dev/null
}

register_agent() {
    AGENT_ID=$(python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
broker = MessageBroker()
agent_id = broker.register_agent('$AGENT_NAME')
print(agent_id)
" 2>/dev/null)
    echo -e "${GREEN}✅ Registered as Agent ID: $AGENT_ID${NC}"
}

show_interface_help() {
    echo -e "\n${PURPLE}🎛️  Multi-Agent Interface Guide:${NC}"
    echo -e "${YELLOW}Communication Commands:${NC}"
    echo -e "  ${GREEN}/msg <message>${NC}     - Send message to all agents"
    echo -e "  ${GREEN}/to <id> <message>${NC} - Send direct message to specific agent"
    echo -e "  ${GREEN}/list${NC}              - List all active agents"
    echo -e "  ${GREEN}/status <status>${NC}   - Update your status"
    echo -e "  ${GREEN}/quit${NC}              - Exit agent"
    echo -e "\n${YELLOW}Claude Commands:${NC}"
    echo -e "  ${GREEN}<any text>${NC}         - Send to Claude with universal access"
    echo -e "  ${GREEN}analyze <topic>${NC}    - Deep analysis request"
    echo -e "  ${GREEN}help${NC}               - Claude help"
    echo -e "\n${YELLOW}Examples:${NC}"
    echo -e "  ${BLUE}/msg Hey everyone, I'm analyzing the auth module${NC}"
    echo -e "  ${BLUE}/to a1b2c3d4 I found the bug you mentioned${NC}"
    echo -e "  ${BLUE}explain the oauth flow in detail${NC}"
    echo -e "\n${GREEN}💡 All Claude responses are automatically shared with other agents${NC}"
}

# Start message listener in background
start_listener() {
    while true; do
        # Get new messages and check for auto-response triggers
        python3 -c "
import sys
import subprocess
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
from datetime import datetime
import re

broker = MessageBroker()
messages = broker.get_messages('$AGENT_ID')
for msg in messages:
    timestamp = msg['timestamp'][:19]
    from_name = msg['from_name']
    content = msg['content']
    msg_type = msg.get('type', 'chat')
    from_id = msg['from']

    # Display the message
    if msg_type == 'system':
        print(f'\n🔔 [{timestamp}] {content}')
    elif from_name != 'Claude':
        print(f'\n💬 [{timestamp}] {from_name}: {content}')

        # Check if message is directed at Claude (contains @all or @agent_id)
        should_respond = False
        if '@all' in content or '@$AGENT_ID' in content:
            should_respond = True
        elif from_name == 'Human' and '?' in content:
            # Also respond to human questions
            should_respond = True

        if should_respond and msg_type == 'chat':
            # Auto-respond by calling Claude CLI with the message
            try:
                claude_response = subprocess.check_output([
                    'claude', '--dangerously-skip-permissions', content
                ], stderr=subprocess.STDOUT, text=True, timeout=30)

                # Send response back to main chat
                if len(claude_response) > 400:
                    claude_response = claude_response[:400] + '... [truncated]'

                broker.send_message('$AGENT_ID', f'💡 Claude: {claude_response.strip()}')
                print(f'\n🤖 Auto-responded to {from_name}')
            except Exception as e:
                broker.send_message('$AGENT_ID', f'❌ Claude: Error processing request - {str(e)[:100]}')
" 2>/dev/null
        sleep 3
    done &
    LISTENER_PID=$!
}

# Initialize
register_agent
broadcast_message "🟢 Claude Agent online with universal access"
start_listener
show_interface_help

echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Main interaction loop
while true; do
    read -p "$(echo -e "${BLUE}Claude${NC} [${AGENT_ID}] > ")" input

    case "$input" in
        /msg*)
            message="${input#/msg }"
            if [[ -n "$message" ]]; then
                echo -e "${GREEN}📢 Broadcasting:${NC} $message"
                broadcast_message "$message"
            else
                echo -e "${RED}Usage: /msg <message>${NC}"
            fi
            ;;
        /to*)
            # Parse /to <agent_id> <message>
            if [[ $input =~ ^/to[[:space:]]+([a-zA-Z0-9]+)[[:space:]]+(.+)$ ]]; then
                target_id="${BASH_REMATCH[1]}"
                message="${BASH_REMATCH[2]}"
                echo -e "${GREEN}📤 Direct message to $target_id:${NC} $message"
                python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
broker = MessageBroker()
broker.send_message('$AGENT_ID', '$message', '$target_id')
" 2>/dev/null
            else
                echo -e "${RED}Usage: /to <agent_id> <message>${NC}"
            fi
            ;;
        /list)
            echo -e "${CYAN}👥 Active Agents:${NC}"
            python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
from datetime import datetime
broker = MessageBroker()
agents = broker.get_active_agents()
for agent_id, info in agents.items():
    last_seen = datetime.fromtimestamp(info['last_seen']).strftime('%H:%M:%S')
    indicator = '🟢' if agent_id == '$AGENT_ID' else '🔵'
    print(f'  {indicator} {info[\"name\"]} ({agent_id}) - Last seen: {last_seen}')
" 2>/dev/null
            ;;
        /status*)
            status="${input#/status }"
            if [[ -n "$status" ]]; then
                echo -e "${CYAN}🔄 Status update:${NC} $status"
                broadcast_message "🔄 Claude Status: $status"
            else
                echo -e "${RED}Usage: /status <status_message>${NC}"
            fi
            ;;
        /quit)
            echo -e "${YELLOW}👋 Claude signing off...${NC}"
            broadcast_message "🔴 Claude Agent going offline"
            break
            ;;
        "")
            # Empty input
            continue
            ;;
        *)
            # Launch Claude CLI in interactive mode
            echo -e "${GREEN}🚀 Launching Claude CLI in interactive mode...${NC}"
            echo -e "${YELLOW}Use Ctrl-C to return to agent menu${NC}"
            broadcast_message "🔄 Claude entering interactive mode"

            # Launch actual Claude CLI with dangerous permissions
            claude --dangerously-skip-permissions

            echo -e "\n${BLUE}📤 Returned from Claude CLI${NC}"
            broadcast_message "🔄 Claude returned from interactive session"
            ;;
    esac
done

# Cleanup
if [[ -n "$LISTENER_PID" ]]; then
    kill $LISTENER_PID 2>/dev/null || true
fi
python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
broker = MessageBroker()
broker.unregister_agent('$AGENT_ID')
" 2>/dev/null