#!/bin/bash

# Multi-Agent Terminal Environment Setup
# Creates a tmux session with multiple CLI agents that can communicate

SESSION_NAME="multi-agents"
SHARED_PIPE="/tmp/agent_shared"
LOG_DIR="/tmp/agent_logs"

# Check if tmux is available
if ! command -v tmux &> /dev/null; then
    echo "tmux is not installed. Please install it first: brew install tmux"
    exit 1
fi

# Clean up any existing session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# Create log directory and shared communication pipe
mkdir -p "$LOG_DIR"
rm -f "$SHARED_PIPE"
mkfifo "$SHARED_PIPE"

echo "Setting up multi-agent terminal environment..."

# Create new tmux session with first pane for Claude Code
tmux new-session -d -s "$SESSION_NAME" -n "agents"

# Split into 3 panes
tmux split-window -h
tmux split-window -v
tmux select-pane -t 0
tmux split-window -v

# Set up each pane with different agents
# Pane 0: Claude Code CLI
tmux send-keys -t "$SESSION_NAME:0.0" "echo 'Claude Code CLI Ready'; echo 'Type messages to communicate with other agents via: echo \"message\" > $SHARED_PIPE'" C-m

# Pane 1: Codex (placeholder - adjust command as needed)
tmux send-keys -t "$SESSION_NAME:0.1" "echo 'Codex CLI Ready'; echo 'Shared pipe: $SHARED_PIPE'" C-m

# Pane 2: Gemini CLI (placeholder - adjust command as needed)
tmux send-keys -t "$SESSION_NAME:0.2" "echo 'Gemini CLI Ready'; echo 'Shared pipe: $SHARED_PIPE'" C-m

# Pane 3: Shared communication monitor
tmux send-keys -t "$SESSION_NAME:0.3" "echo 'Shared Communication Monitor'; echo 'Monitoring: $SHARED_PIPE'; tail -f $SHARED_PIPE" C-m

# Set pane titles
tmux select-pane -t 0 -T "Claude Code"
tmux select-pane -t 1 -T "Codex"
tmux select-pane -t 2 -T "Gemini"
tmux select-pane -t 3 -T "Shared Chat"

# Focus on first pane
tmux select-pane -t 0

echo "Multi-agent environment created!"
echo "To attach: tmux attach -t $SESSION_NAME"
echo "To use with iTerm2 integration: tmux -CC attach -t $SESSION_NAME"
echo ""
echo "Communication:"
echo "- Send messages via: echo 'your message' > $SHARED_PIPE"
echo "- All agents can see messages in the 'Shared Chat' pane"
echo ""
echo "Controls:"
echo "- Switch panes: Ctrl-b + arrow keys"
echo "- Detach: Ctrl-b + d"

# Auto-attach with iTerm2 integration if possible
if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    echo "Detected iTerm2 - launching with native integration..."
    tmux -CC attach -t "$SESSION_NAME"
else
    echo "Attaching to tmux session..."
    tmux attach -t "$SESSION_NAME"
fi