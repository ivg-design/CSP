#!/bin/bash

# Gemini Agent - Manual Launcher with Universal Access
# Launch with: ./gemini_manual.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Gemini"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🤖 Gemini Agent with Universal Access${NC}"
echo -e "${YELLOW}⚠️  Running with --yolo${NC}"

# Check if Gemini CLI is available (placeholder - adjust for actual gemini command)
if ! command -v gemini &> /dev/null; then
    echo -e "${YELLOW}⚠️  Gemini CLI not found. Using simulation mode.${NC}"
    SIMULATION_MODE=true
else
    SIMULATION_MODE=false
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
    echo -e "\n${YELLOW}Gemini Commands:${NC}"
    echo -e "  ${GREEN}<any question>${NC}     - Send to Gemini with universal access"
    echo -e "  ${GREEN}analyze <topic>${NC}    - Deep analysis request"
    echo -e "  ${GREEN}research <topic>${NC}   - Research and summarize"
    echo -e "  ${GREEN}creative <task>${NC}    - Creative problem solving"
    echo -e "\n${YELLOW}Examples:${NC}"
    echo -e "  ${BLUE}/msg I'm researching the security implications${NC}"
    echo -e "  ${BLUE}/to a1b2c3d4 I found some relevant information${NC}"
    echo -e "  ${BLUE}analyze the performance bottlenecks in this system${NC}"
    echo -e "\n${GREEN}💡 All Gemini responses are automatically shared with other agents${NC}"
}

simulate_gemini() {
    local input="$1"
    echo "Gemini simulation: Analytical response for '$input'"
    echo "This would be a comprehensive Gemini analysis with multiple perspectives"
    echo "and creative insights. Replace with real Gemini CLI integration."
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

broker = MessageBroker()
messages = broker.get_messages('$AGENT_ID')
for msg in messages:
    timestamp = msg['timestamp'][:19]
    from_name = msg['from_name']
    content = msg['content']
    msg_type = msg.get('type', 'chat')

    # Display the message
    if msg_type == 'system':
        print(f'\n🔔 [{timestamp}] {content}')
    elif from_name != 'Gemini':
        print(f'\n💬 [{timestamp}] {from_name}: {content}')

        # Check if message is directed at Gemini
        should_respond = False
        if '@all' in content or '@$AGENT_ID' in content:
            should_respond = True
        elif from_name == 'Human' and any(word in content.lower() for word in ['analyze', 'research', 'creative', 'think']):
            should_respond = True

        if should_respond and msg_type == 'chat':
            # Auto-respond
            if '$SIMULATION_MODE' == 'true':
                # Simulation response
                response = f'Gemini analysis: {content[:50]}... would provide comprehensive insights here.'
            else:
                # Real Gemini CLI call
                try:
                    response = subprocess.check_output([
                        'gemini', '--yolo', content
                    ], stderr=subprocess.STDOUT, text=True, timeout=30)
                except:
                    response = 'Gemini analysis: Processing your request...'

            # Send response back to main chat
            if len(response) > 400:
                response = response[:400] + '... [truncated]'

            broker.send_message('$AGENT_ID', f'✨ Gemini: {response.strip()}')
            print(f'\n🤖 Auto-responded to {from_name}')
" 2>/dev/null
        sleep 3
    done &
    LISTENER_PID=$!
}

# Initialize
register_agent
broadcast_message "🟢 Gemini Agent online with universal access"
start_listener
show_interface_help

echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Main interaction loop
while true; do
    read -p "$(echo -e "${BLUE}Gemini${NC} [${AGENT_ID}] > ")" input

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
                broadcast_message "🔄 Gemini Status: $status"
            else
                echo -e "${RED}Usage: /status <status_message>${NC}"
            fi
            ;;
        /quit)
            echo -e "${YELLOW}👋 Gemini signing off...${NC}"
            broadcast_message "🔴 Gemini Agent going offline"
            break
            ;;
        "")
            # Empty input
            continue
            ;;
        *)
            if [[ "$SIMULATION_MODE" == "true" ]]; then
                # In simulation mode, show a helpful message
                echo -e "${YELLOW}⚠️  Gemini CLI not found - install it to enable interactive mode${NC}"
                echo -e "${BLUE}For now, simulating response to: $input${NC}"
                output=$(simulate_gemini "$input")
                echo "$output"
                broadcast_message "✨ Gemini (sim): $output"
            else
                # Launch Gemini CLI in interactive mode
                echo -e "${GREEN}🚀 Launching Gemini CLI in interactive mode...${NC}"
                echo -e "${YELLOW}Use Ctrl-C to return to agent menu${NC}"
                broadcast_message "🔄 Gemini entering interactive mode"

                # Launch actual Gemini CLI with YOLO permissions
                gemini --yolo

                echo -e "\n${BLUE}📤 Returned from Gemini CLI${NC}"
                broadcast_message "🔄 Gemini returned from interactive session"
            fi
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