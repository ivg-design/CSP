#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_menu() {
    echo -e "${PURPLE}🤖 Agent Launcher Menu${NC}"
    echo -e "${YELLOW}Available Agents:${NC}"
    echo -e "  ${GREEN}1${NC} - Claude (with --dangerously-skip-permissions)"
    echo -e "  ${GREEN}2${NC} - Codex (with --dangerously-bypass-approvals-and-sandbox)"
    echo -e "  ${GREEN}3${NC} - Gemini (with --yolo)"
    echo -e "  ${GREEN}h${NC} - Human Command Center"
    echo -e "  ${GREEN}q${NC} - Quit (leave pane empty)"
    echo ""
    echo -e "${BLUE}💡 You can launch multiple instances of the same agent${NC}"
    echo -e "${BLUE}💡 Each agent gets a unique ID for communication${NC}"
}

while true; do
    show_menu
    read -p "$(echo -e "${PURPLE}Select agent${NC} [1/2/3/h/q]: ")" choice

    case $choice in
        1)
            echo -e "${GREEN}🚀 Starting Claude...${NC}"
            exec "$SCRIPT_DIR/claude_manual.sh"
            ;;
        2)
            echo -e "${GREEN}🚀 Starting Codex...${NC}"
            exec "$SCRIPT_DIR/codex_manual.sh"
            ;;
        3)
            echo -e "${GREEN}🚀 Starting Gemini...${NC}"
            exec "$SCRIPT_DIR/gemini_manual.sh"
            ;;
        h)
            echo -e "${GREEN}🚀 Starting Human Command Center...${NC}"
            exec "$SCRIPT_DIR/human_command_prompt.sh"
            ;;
        q)
            echo -e "${YELLOW}👋 Pane left empty${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid choice. Please select 1, 2, 3, h, or q${NC}"
            ;;
    esac
done
