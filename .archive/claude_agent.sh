#!/bin/bash

# Claude Code Agent Wrapper
# Integrates Claude Code CLI with the multi-agent communication system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Claude"
PYTHON_CLIENT="$SCRIPT_DIR/agent_client.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🤖 Starting Claude Code Agent${NC}"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 is required but not installed${NC}"
    exit 1
fi

# Function to handle message broadcasting
broadcast_message() {
    local message="$1"
    if [[ -n "$message" ]]; then
        python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from agent_client import AgentClient
import threading

client = AgentClient('$AGENT_NAME')
client.send_message('$message')
client.shutdown()
"
    fi
}

# Function to announce agent status
announce_status() {
    local status="$1"
    broadcast_message "🔄 Claude Status: $status"
}

# Function to share claude output
share_response() {
    local response="$1"
    if [[ ${#response} -gt 200 ]]; then
        # Truncate long responses
        response="${response:0:200}..."
    fi
    broadcast_message "💡 Claude Response: $response"
}

# Function to start message listener in background
start_listener() {
    python3 "$PYTHON_CLIENT" "$AGENT_NAME" &
    LISTENER_PID=$!
    echo -e "${GREEN}✅ Message listener started (PID: $LISTENER_PID)${NC}"
}

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}🛑 Shutting down Claude agent...${NC}"
    if [[ -n "$LISTENER_PID" ]]; then
        kill $LISTENER_PID 2>/dev/null || true
    fi
    announce_status "Offline"
    exit 0
}

# Set up signal handlers
trap cleanup INT TERM

# Start the message listener
start_listener

# Announce that Claude is ready
announce_status "Online and ready"

echo -e "${GREEN}Claude Code Agent is now connected to the multi-agent system${NC}"
echo -e "${BLUE}Commands:${NC}"
echo -e "  ${YELLOW}/msg <message>${NC}     - Send message to other agents"
echo -e "  ${YELLOW}/list${NC}              - List active agents"
echo -e "  ${YELLOW}/status <status>${NC}   - Update status"
echo -e "  ${YELLOW}/quit${NC}              - Exit agent"
echo -e "  ${YELLOW}<any claude command>${NC} - Execute Claude Code CLI command"
echo ""

# Main interaction loop
while true; do
    read -p "Claude > " input

    case "$input" in
        /msg*)
            message="${input#/msg }"
            if [[ -n "$message" ]]; then
                broadcast_message "$message"
            else
                echo -e "${RED}Usage: /msg <message>${NC}"
            fi
            ;;
        /list)
            python3 -c "
import sys
sys.path.append('$SCRIPT_DIR')
from agent_client import AgentClient
client = AgentClient('$AGENT_NAME')
client.list_agents()
client.shutdown()
"
            ;;
        /status*)
            status="${input#/status }"
            if [[ -n "$status" ]]; then
                announce_status "$status"
            else
                echo -e "${RED}Usage: /status <status_message>${NC}"
            fi
            ;;
        /quit)
            cleanup
            ;;
        "")
            # Empty input, do nothing
            ;;
        *)
            # Execute Claude Code CLI command
            echo -e "${BLUE}🔍 Executing Claude command...${NC}"
            announce_status "Processing: $input"

            # Execute the actual claude command and capture output
            output=$(claude "$input" 2>&1)
            exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                echo "$output"
                share_response "$output"
                announce_status "Ready"
            else
                echo -e "${RED}❌ Command failed:${NC} $output"
                broadcast_message "❌ Claude Error: $output"
                announce_status "Error occurred"
            fi
            ;;
    esac
done