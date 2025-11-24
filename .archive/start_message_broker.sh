#!/bin/bash

# Message Broker Standalone Launcher
# Start this first, then launch agents manually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Multi-Agent Message Broker${NC}"

# Clean up old communication files
rm -rf /tmp/agent_comm 2>/dev/null

# Start the message broker
python3 "$SCRIPT_DIR/message_broker.py" &
BROKER_PID=$!

echo -e "${GREEN}✅ Message broker started (PID: $BROKER_PID)${NC}"
echo -e "${BLUE}📡 Communication directory: /tmp/agent_comm/${NC}"
echo -e "${BLUE}📝 Global log: /tmp/agent_comm/global_messages.log${NC}"
echo -e "\n${YELLOW}Now you can manually launch agents:${NC}"
echo -e "  ${GREEN}./claude_manual.sh${NC}   - Claude with --dangerously-skip-permissions"
echo -e "  ${GREEN}./codex_manual.sh${NC}    - Codex with --dangerously-bypass-approvals-and-sandbox"
echo -e "  ${GREEN}./gemini_manual.sh${NC}   - Gemini with --yolo"
echo -e "  ${GREEN}./human_command_prompt.sh${NC} - Human command center"
echo -e "\n${YELLOW}Press Ctrl+C to stop the broker${NC}"

# Wait for broker to finish
wait $BROKER_PID