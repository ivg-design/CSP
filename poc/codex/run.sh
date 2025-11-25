#!/bin/bash
# CSP POC - Codex Chat Launcher
# Creates 2-pane tmux: top=chat, bottom=Codex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="csp-codex-poc"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}CSP Codex POC${NC}"
echo "============="
echo ""

# Check dependencies
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux not found"
    exit 1
fi

if ! command -v codex &> /dev/null; then
    echo "Error: codex CLI not found"
    exit 1
fi

# Clean up any existing session
echo -e "${YELLOW}Cleaning up existing session...${NC}"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.3

# Clean up temp files
rm -f /tmp/csp-codex-start /tmp/csp-codex-end /tmp/csp-codex-response /tmp/csp-codex-notify.log

# Create new session
echo -e "${YELLOW}Creating tmux session...${NC}"
unset TMUX
tmux new-session -d -s "$SESSION_NAME" -n "codex-poc"

# Split: top=chat (25%), bottom=codex (75%)
tmux split-window -v -p 75 -t "$SESSION_NAME:0.0"

# Get pane IDs
PANE_IDS=($(tmux list-panes -t "$SESSION_NAME" -F '#{pane_id}'))
CHAT_PANE="${PANE_IDS[0]}"
AGENT_PANE="${PANE_IDS[1]}"

echo -e "${GREEN}Chat pane:  $CHAT_PANE${NC}"
echo -e "${GREEN}Agent pane: $AGENT_PANE${NC}"

# Set pane titles
tmux select-pane -t "$CHAT_PANE" -T "Chat"
tmux select-pane -t "$AGENT_PANE" -T "Codex"

# Launch Codex in bottom pane
echo -e "${YELLOW}Launching Codex...${NC}"
tmux send-keys -t "$AGENT_PANE" "codex --dangerously-bypass-approvals-and-sandbox" Enter

# Wait for Codex to start
sleep 2

# Launch chat UI in top pane
echo -e "${YELLOW}Launching Chat UI...${NC}"
tmux send-keys -t "$CHAT_PANE" "python3 '$SCRIPT_DIR/chat.py' --pane '$AGENT_PANE'" Enter

# Select chat pane
tmux select-pane -t "$CHAT_PANE"

echo ""
echo -e "${GREEN}Ready!${NC}"
echo ""
echo "Layout:"
echo "  Top:    Chat UI (type here)"
echo "  Bottom: Codex (full TUI)"
echo ""
echo "Controls:"
echo "  Ctrl+B Up/Down - Navigate panes"
echo "  /quit          - Exit chat"
echo "  /status        - Show file status"
echo ""

# Attach to session
if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    tmux -CC attach -t "$SESSION_NAME"
else
    tmux attach -t "$SESSION_NAME"
fi
