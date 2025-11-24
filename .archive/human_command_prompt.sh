#!/bin/bash

# Human Command Prompt - Central control for multi-agent communication
# Provides enhanced command interface for human participant

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Human"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to send message to all agents
broadcast_message() {
    local message="$1"
    python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker

broker = MessageBroker()
broker.send_message('$AGENT_ID', '$message')
" 2>/dev/null
}

# Function to send message to specific agent
send_direct_message() {
    local agent_id="$1"
    local message="$2"
    python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker

broker = MessageBroker()
broker.send_message('$AGENT_ID', '$message', '$agent_id')
" 2>/dev/null
}

# Function to list agents
list_agents() {
    python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker
from datetime import datetime

broker = MessageBroker()
agents = broker.get_active_agents()
print('👥 Active Agents:')
for agent_id, info in agents.items():
    last_seen = datetime.fromtimestamp(info['last_seen']).strftime('%H:%M:%S')
    indicator = '🟢' if agent_id == '$AGENT_ID' else '🔵'
    print(f'  {indicator} {info[\"name\"]} ({agent_id}) - Last seen: {last_seen}')
" 2>/dev/null
}

# Function to show message history
show_history() {
    echo -e "${CYAN}📜 Recent Message History:${NC}"
    if [[ -f "/tmp/agent_comm/global_messages.log" ]]; then
        tail -n 10 /tmp/agent_comm/global_messages.log
    else
        echo "No messages yet"
    fi
}

# Function to show help
show_help() {
    echo -e "\n${PURPLE}🎛️  Human Command Center - Available Commands:${NC}"
    echo -e "${YELLOW}Communication:${NC}"
    echo -e "  ${GREEN}@all <message>${NC}     - Broadcast to all agents"
    echo -e "  ${GREEN}@<agent_id> <message>${NC} - Direct message to specific agent"
    echo -e "  ${GREEN}<message>${NC}          - Broadcast to all agents (default)"
    echo -e "\n${YELLOW}Information:${NC}"
    echo -e "  ${GREEN}/list${NC}              - Show all active agents"
    echo -e "  ${GREEN}/history${NC}           - Show recent messages"
    echo -e "  ${GREEN}/help${NC}              - Show this help"
    echo -e "  ${GREEN}/clear${NC}             - Clear screen"
    echo -e "\n${YELLOW}Control:${NC}"
    echo -e "  ${GREEN}/quit${NC}              - Exit command center"
    echo -e "\n${CYAN}💡 Tips:${NC}"
    echo -e "  • Messages without commands are broadcast to all agents"
    echo -e "  • Use Ctrl-b + arrow keys to switch to agent panes"
    echo -e "  • Agent responses appear in their respective panes below"
}

# Initialize and register
echo -e "${PURPLE}🎛️  Human Command Center Initializing...${NC}"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 is required but not installed${NC}"
    exit 1
fi

# Register as human agent and get ID
AGENT_ID=$(python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from message_broker import MessageBroker

broker = MessageBroker()
agent_id = broker.register_agent('$AGENT_NAME')
broker.send_message(agent_id, '👤 Human operator has joined the command center')
print(agent_id)
" 2>/dev/null)

echo -e "${GREEN}✅ Connected to multi-agent system${NC}"
show_help

# Main command loop
while true; do
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "$(echo -e "${CYAN}Human Command${NC} > ")" input

    # Skip empty input
    if [[ -z "$input" ]]; then
        continue
    fi

    case "$input" in
        /help)
            show_help
            ;;
        /list)
            list_agents
            ;;
        /history)
            show_history
            ;;
        /clear)
            clear
            echo -e "${PURPLE}🎛️  Human Command Center${NC}"
            show_help
            ;;
        /quit)
            echo -e "${YELLOW}👋 Human operator signing off...${NC}"
            broadcast_message "👤 Human operator has left the command center"
            break
            ;;
        @all*)
            message="${input#@all }"
            if [[ -n "$message" ]]; then
                echo -e "${BLUE}📢 Broadcasting:${NC} $message"
                broadcast_message "$message"
            else
                echo -e "${RED}Usage: @all <message>${NC}"
            fi
            ;;
        @*)
            # Parse @agent_id message format
            if [[ $input =~ ^@([a-zA-Z0-9]+)[[:space:]]+(.+)$ ]]; then
                agent_id="${BASH_REMATCH[1]}"
                message="${BASH_REMATCH[2]}"
                echo -e "${BLUE}📤 → $agent_id:${NC} $message"
                send_direct_message "$agent_id" "$message"
            else
                echo -e "${RED}Usage: @<agent_id> <message>${NC}"
                echo -e "${YELLOW}Use /list to see available agent IDs${NC}"
            fi
            ;;
        /*)
            echo -e "${RED}❌ Unknown command: $input${NC}"
            echo -e "${YELLOW}Use /help to see available commands${NC}"
            ;;
        *)
            # Default: broadcast to all agents
            echo -e "${BLUE}📢${NC} $input"
            broadcast_message "$input"
            ;;
    esac
done