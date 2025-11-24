#!/bin/bash

# Generic Multi-Agent Layout - 1+3 tmux setup
# Top pane: Human Command Center
# Bottom panes: Agent 1, Agent 2, Agent 3 (launch any agent in any pane)

SESSION_NAME="multi-agents"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🚀 Setting up Multi-Agent Layout (1+3)${NC}"

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v tmux &> /dev/null; then
        missing_deps+=("tmux")
    fi

    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Install with: brew install ${missing_deps[*]}${NC}"
        exit 1
    fi
}

# Make all scripts executable
make_scripts_executable() {
    chmod +x "$SCRIPT_DIR"/*.sh
    chmod +x "$SCRIPT_DIR"/*.py
}

# Clean up any existing session
cleanup_session() {
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    # Clean up communication files
    rm -rf /tmp/agent_comm 2>/dev/null || true
}

# Start the message broker in background
start_message_broker() {
    echo -e "${BLUE}📡 Starting message broker...${NC}"
    python3 "$SCRIPT_DIR/message_broker.py" &
    BROKER_PID=$!
    sleep 3  # Give broker time to start
    echo -e "${GREEN}✅ Message broker started (PID: $BROKER_PID)${NC}"
}

# Create agent launcher menu
create_agent_menu() {
    cat > "$SCRIPT_DIR/agent_menu.sh" << 'EOF'
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
EOF
    chmod +x "$SCRIPT_DIR/agent_menu.sh"
}

# Create tmux session with flexible layout
create_tmux_session() {
    echo -e "${BLUE}🖥️  Creating flexible tmux layout...${NC}"

    # Create new tmux session
    tmux new-session -d -s "$SESSION_NAME" -n "agents"

    # Create 1+3 layout: top pane for human command center, 3 agent panes below
    tmux split-window -v -p 75  # Split horizontal, top pane gets 25%, bottom gets 75%
    tmux select-pane -t 1
    tmux split-window -h        # Split bottom pane vertically into 2
    tmux split-window -h        # Split right pane again for 3 total agent panes

    # Setup pane 0: Human Command Center (top pane)
    tmux send-keys -t "$SESSION_NAME:0.0" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "'$SCRIPT_DIR/human_command_prompt.sh'" C-m

    # Setup pane 1: Agent 1 (bottom-left) - Show menu
    tmux send-keys -t "$SESSION_NAME:0.1" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "'$SCRIPT_DIR/agent_menu.sh'" C-m

    # Setup pane 2: Agent 2 (bottom-center) - Show menu
    tmux send-keys -t "$SESSION_NAME:0.2" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "'$SCRIPT_DIR/agent_menu.sh'" C-m

    # Setup pane 3: Agent 3 (bottom-right) - Show menu
    tmux send-keys -t "$SESSION_NAME:0.3" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "'$SCRIPT_DIR/agent_menu.sh'" C-m

    # Set pane titles
    tmux select-pane -t 0 -T "🎛️  Human Command Center"
    tmux select-pane -t 1 -T "🤖 Agent 1"
    tmux select-pane -t 2 -T "🤖 Agent 2"
    tmux select-pane -t 3 -T "🤖 Agent 3"

    # Focus on Human Command Center
    tmux select-pane -t 0
}

# Display usage information
show_usage() {
    echo -e "\n${GREEN}🎉 Flexible Multi-Agent Layout Ready!${NC}"
    echo -e "\n${BLUE}🎛️  Layout:${NC}"
    echo -e "  ${PURPLE}Top Pane${NC}      - Human Command Center (your control interface)"
    echo -e "  ${CYAN}Bottom Left${NC}   - Agent 1 (choose any agent)"
    echo -e "  ${CYAN}Bottom Center${NC} - Agent 2 (choose any agent)"
    echo -e "  ${CYAN}Bottom Right${NC}  - Agent 3 (choose any agent)"
    echo -e "\n${BLUE}🎮 Agent Selection:${NC}"
    echo -e "  • Switch to any bottom pane (Ctrl-b + arrow keys)"
    echo -e "  • Select from menu: Claude (1), Codex (2), Gemini (3)"
    echo -e "  • Launch multiple instances of the same agent"
    echo -e "  • Each agent gets unique ID for communication"
    echo -e "\n${BLUE}🔧 tmux Controls:${NC}"
    echo -e "  ${YELLOW}Ctrl-b + arrow keys${NC} - Switch between panes"
    echo -e "  ${YELLOW}Ctrl-b + d${NC}          - Detach session"
    echo -e "  ${YELLOW}Ctrl-b + x${NC}          - Close pane (shows menu again)"
    echo -e "\n${BLUE}💡 Examples:${NC}"
    echo -e "  • Agent 1: Claude, Agent 2: Claude, Agent 3: Gemini"
    echo -e "  • Agent 1: Codex, Agent 2: Gemini, Agent 3: Claude"
    echo -e "  • All three panes running Claude instances"
}

# Main execution
main() {
    echo -e "${BLUE}Multi-Agent Flexible Layout${NC}\n"

    check_dependencies
    make_scripts_executable
    cleanup_session
    start_message_broker
    create_agent_menu
    create_tmux_session
    show_usage

    # Auto-attach based on terminal
    if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
        echo -e "\n${GREEN}🍎 Detected iTerm2 - launching with native integration...${NC}"
        sleep 2
        tmux -CC attach -t "$SESSION_NAME"
    else
        echo -e "\n${GREEN}🖥️  Attaching to tmux session...${NC}"
        sleep 2
        tmux attach -t "$SESSION_NAME"
    fi
}

# Cleanup function for signal handling
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    if [[ -n "$BROKER_PID" ]]; then
        kill "$BROKER_PID" 2>/dev/null || true
    fi
    exit 0
}

# Set up signal handlers
trap cleanup INT TERM

# Run main function
main