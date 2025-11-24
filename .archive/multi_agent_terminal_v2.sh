#!/bin/bash

# Advanced Multi-Agent Terminal Environment Setup v2
# Creates tmux session with bidirectional communication and unique agent IDs

SESSION_NAME="multi-agents-v2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Advanced Multi-Agent Terminal Environment${NC}"

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

# Start the message broker
start_message_broker() {
    echo -e "${BLUE}📡 Starting message broker...${NC}"
    python3 "$SCRIPT_DIR/message_broker.py" &
    BROKER_PID=$!
    sleep 3  # Give broker time to start
    echo -e "${GREEN}✅ Message broker started (PID: $BROKER_PID)${NC}"
}

# Create tmux session with agent panes
create_tmux_session() {
    echo -e "${BLUE}🖥️  Creating tmux session...${NC}"

    # Create new tmux session
    tmux new-session -d -s "$SESSION_NAME" -n "agents"

    # Create 1+3 layout: top pane for human command prompt, 3 agent panes below
    tmux split-window -v -p 75  # Split horizontal, top pane gets 25%, bottom gets 75%
    tmux select-pane -t 1
    tmux split-window -h        # Split bottom pane vertically into 2
    tmux split-window -h        # Split right pane again for 3 total agent panes

    # Setup pane 0: Human Command Prompt (top pane)
    tmux send-keys -t "$SESSION_NAME:0.0" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "'$SCRIPT_DIR/human_command_prompt.sh'" C-m

    # Setup pane 1: Claude Agent (bottom-left)
    tmux send-keys -t "$SESSION_NAME:0.1" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "'$SCRIPT_DIR/claude_agent.sh'" C-m

    # Setup pane 2: Codex Agent (bottom-center)
    tmux send-keys -t "$SESSION_NAME:0.2" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "'$SCRIPT_DIR/codex_agent.sh'" C-m

    # Setup pane 3: Gemini Agent (bottom-right)
    tmux send-keys -t "$SESSION_NAME:0.3" "cd '$SCRIPT_DIR'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "'$SCRIPT_DIR/gemini_agent.sh'" C-m

    # Set pane titles
    tmux select-pane -t 0 -T "🎛️  Human Command Center"
    tmux select-pane -t 1 -T "🤖 Claude Agent"
    tmux select-pane -t 2 -T "💻 Codex Agent"
    tmux select-pane -t 3 -T "✨ Gemini Agent"

    # Focus on Human Command Center
    tmux select-pane -t 0
}

# Display usage information
show_usage() {
    echo -e "\n${GREEN}🎉 Multi-Agent Command Center Ready!${NC}"
    echo -e "\n${BLUE}🎛️  Layout:${NC}"
    echo -e "  ${PURPLE}Top Pane${NC}    - Human Command Center (your control interface)"
    echo -e "  ${CYAN}Bottom Left${NC}  - Claude Agent"
    echo -e "  ${CYAN}Bottom Center${NC} - Codex Agent"
    echo -e "  ${CYAN}Bottom Right${NC} - Gemini Agent"
    echo -e "\n${BLUE}🎮 Command Center Usage:${NC}"
    echo -e "  ${YELLOW}<message>${NC}           - Broadcast to all agents"
    echo -e "  ${YELLOW}@all <message>${NC}      - Broadcast to all agents"
    echo -e "  ${YELLOW}@<agent_id> <message>${NC} - Direct message to specific agent"
    echo -e "  ${YELLOW}/list${NC}               - List active agents with IDs"
    echo -e "  ${YELLOW}/history${NC}            - Show recent message history"
    echo -e "  ${YELLOW}/help${NC}               - Show help in command center"
    echo -e "\n${BLUE}🔧 tmux Controls:${NC}"
    echo -e "  ${YELLOW}Ctrl-b + arrow keys${NC} - Switch between panes"
    echo -e "  ${YELLOW}Ctrl-b + d${NC}          - Detach session"
    echo -e "  ${YELLOW}Ctrl-b + x${NC}          - Close pane"
    echo -e "\n${BLUE}💡 How It Works:${NC}"
    echo -e "  • Type commands in the top pane (Command Center)"
    echo -e "  • Agent responses appear in their respective panes below"
    echo -e "  • Switch to agent panes to interact directly with each agent"
    echo -e "  • All communication is logged and synchronized"
}

# Main execution
main() {
    echo -e "${BLUE}Multi-Agent Terminal Environment v2${NC}\n"

    check_dependencies
    make_scripts_executable
    cleanup_session
    start_message_broker
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