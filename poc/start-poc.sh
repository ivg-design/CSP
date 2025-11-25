#!/bin/bash
# poc/start-poc.sh
# POC: Single agent group chat via tmux monitoring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="csp-poc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default agent
AGENT_TYPE="${1:-claude}"

usage() {
    echo -e "${CYAN}CSP Proof of Concept - Single Agent Chat${NC}"
    echo ""
    echo "Usage: $0 [agent]"
    echo ""
    echo "Agents:"
    echo "  claude   - Claude Code (default)"
    echo "  gemini   - Gemini CLI"
    echo "  codex    - Codex CLI"
    echo ""
    echo "Example:"
    echo "  $0 claude"
    echo "  $0 gemini"
}

# Parse args
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Determine agent command
case "$AGENT_TYPE" in
    claude)
        AGENT_CMD="claude --dangerously-skip-permissions"
        AGENT_NAME="Claude"
        ;;
    gemini)
        AGENT_CMD="gemini --yolo"
        AGENT_NAME="Gemini"
        ;;
    codex)
        AGENT_CMD="codex --dangerously-bypass-approvals-and-sandbox"
        AGENT_NAME="Codex"
        ;;
    *)
        echo -e "${RED}Unknown agent: $AGENT_TYPE${NC}"
        usage
        exit 1
        ;;
esac

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          CSP Proof of Concept - Single Agent Chat          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}[1/5] Checking dependencies...${NC}"

if ! command -v tmux &> /dev/null; then
    echo -e "${RED}Error: tmux not found. Install with: brew install tmux${NC}"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 not found${NC}"
    exit 1
fi

# Check if agent CLI exists
AGENT_BIN=$(echo "$AGENT_CMD" | awk '{print $1}')
if ! command -v "$AGENT_BIN" &> /dev/null; then
    echo -e "${RED}Error: $AGENT_BIN not found in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ tmux${NC}"
echo -e "${GREEN}  ✓ python3${NC}"
echo -e "${GREEN}  ✓ $AGENT_BIN${NC}"

# Kill existing session if any
echo -e "${YELLOW}[2/5] Cleaning up existing session...${NC}"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.3

# Create new tmux session
echo -e "${YELLOW}[3/5] Creating tmux session: ${SESSION_NAME}${NC}"

# Unset TMUX to allow nested session creation
unset TMUX

# Create session with first pane (will be group chat)
tmux new-session -d -s "$SESSION_NAME" -n "CSP-POC" -c "$SCRIPT_DIR"

# Split: top pane = group chat (25%), bottom pane = agent (75%)
tmux split-window -v -p 75 -t "$SESSION_NAME:0.0" -c "$SCRIPT_DIR"

# Get pane IDs
CHAT_PANE=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_id}' | head -1)
AGENT_PANE=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_id}' | tail -1)

echo -e "${GREEN}  Chat pane:  $CHAT_PANE${NC}"
echo -e "${GREEN}  Agent pane: $AGENT_PANE${NC}"

# Set pane titles
tmux select-pane -t "$CHAT_PANE" -T "💬 Group Chat"
tmux select-pane -t "$AGENT_PANE" -T "🤖 $AGENT_NAME"

# Launch agent in bottom pane
echo -e "${YELLOW}[4/5] Launching $AGENT_NAME in agent pane...${NC}"
tmux send-keys -t "$AGENT_PANE" "$AGENT_CMD" Enter

# Wait for agent to initialize
echo -e "${YELLOW}  Waiting for agent to start...${NC}"
sleep 2

# Launch chat UI in top pane
echo -e "${YELLOW}[5/5] Launching group chat UI...${NC}"
tmux send-keys -t "$CHAT_PANE" "python3 '$SCRIPT_DIR/chat_ui.py' --pane '$AGENT_PANE' --name '$AGENT_NAME'" Enter

# Select chat pane
tmux select-pane -t "$CHAT_PANE"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                      POC Ready!                            ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Layout:                                                   ║${NC}"
echo -e "${GREEN}║    Top pane:    Group Chat (you type here)                 ║${NC}"
echo -e "${GREEN}║    Bottom pane: $AGENT_NAME (full TUI)                        ║${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}║  Controls:                                                 ║${NC}"
echo -e "${GREEN}║    Ctrl+B ↑/↓   - Navigate between panes                   ║${NC}"
echo -e "${GREEN}║    Ctrl+B z     - Zoom current pane                        ║${NC}"
echo -e "${GREEN}║    /quit        - Exit chat                                ║${NC}"
echo -e "${GREEN}║    /status      - Show monitor status                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Attach to session
if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION_NAME"
else
    tmux attach -t "$SESSION_NAME"
fi
