#!/bin/bash

# Codex Agent - Manual Launcher with Universal Access
# Launch with: ./codex_manual.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Codex"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🤖 Codex Agent with Universal Access${NC}"
echo -e "${YELLOW}⚠️  Running with --dangerously-bypass-approvals-and-sandbox${NC}"

# Check if Codex CLI is available (placeholder - adjust for actual codex command)
if ! command -v codex &> /dev/null; then
    echo -e "${YELLOW}⚠️  Codex CLI not found. Using simulation mode.${NC}"
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
    echo -e "\n${YELLOW}Codex Commands:${NC}"
    echo -e "  ${GREEN}<any code request>${NC} - Send to Codex with universal access"
    echo -e "  ${GREEN}generate <description>${NC} - Generate code"
    echo -e "  ${GREEN}explain <code>${NC}     - Explain code functionality"
    echo -e "  ${GREEN}debug <issue>${NC}      - Help debug code issues"
    echo -e "\n${YELLOW}Examples:${NC}"
    echo -e "  ${BLUE}/msg I'm generating the auth middleware${NC}"
    echo -e "  ${BLUE}/to a1b2c3d4 Here's the function you requested${NC}"
    echo -e "  ${BLUE}generate a JWT authentication function in Python${NC}"
    echo -e "\n${GREEN}💡 All Codex responses are automatically shared with other agents${NC}"
}

simulate_codex() {
    local input="$1"
    echo "Codex simulation: Generated response for '$input'"
    echo "// This would be actual Codex-generated code"
    echo "// Replace this function with real Codex CLI integration"
}

# Initialize
register_agent
broadcast_message "🟢 Codex Agent online with universal access"
show_interface_help

echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Main interaction loop
while true; do
    read -p "$(echo -e "${BLUE}Codex${NC} [${AGENT_ID}] > ")" input

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
                broadcast_message "🔄 Codex Status: $status"
            else
                echo -e "${RED}Usage: /status <status_message>${NC}"
            fi
            ;;
        /quit)
            echo -e "${YELLOW}👋 Codex signing off...${NC}"
            broadcast_message "🔴 Codex Agent going offline"
            break
            ;;
        "")
            # Empty input
            continue
            ;;
        *)
            if [[ "$SIMULATION_MODE" == "true" ]]; then
                # In simulation mode, show a helpful message
                echo -e "${YELLOW}⚠️  Codex CLI not found - install it to enable interactive mode${NC}"
                echo -e "${BLUE}For now, simulating response to: $input${NC}"
                output=$(simulate_codex "$input")
                echo "$output"
                broadcast_message "💻 Codex (sim): $output"
            else
                # Launch Codex CLI in interactive mode
                echo -e "${GREEN}🚀 Launching Codex CLI in interactive mode...${NC}"
                echo -e "${YELLOW}Use Ctrl-C to return to agent menu${NC}"
                broadcast_message "🔄 Codex entering interactive mode"

                # Launch actual Codex CLI with bypass permissions
                codex --dangerously-bypass-approvals-and-sandbox

                echo -e "\n${BLUE}📤 Returned from Codex CLI${NC}"
                broadcast_message "🔄 Codex returned from interactive session"
            fi
            ;;
    esac
done

# Cleanup
python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
broker = MessageBroker()
broker.unregister_agent('$AGENT_ID')
" 2>/dev/null