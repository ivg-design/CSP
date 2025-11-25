#!/bin/bash
# Quick tmux 4-pane smoke test (no CSP)
set -euo pipefail

SESSION_NAME="tmux-smoke-test"
TMUX_BIN="$(command -v tmux || true)"

if [[ -z "$TMUX_BIN" ]]; then
  echo "tmux not found; install tmux first."
  exit 1
fi

if [[ -n "${TMUX:-}" ]]; then
  echo "You are already inside tmux. Detach first, then rerun."
  exit 1
fi

# Ensure executable when launched directly
chmod +x "$0" 2>/dev/null || true

# Clean existing
"$TMUX_BIN" kill-session -t "$SESSION_NAME" 2>/dev/null || true

# Create session and layout (top + 3 bottom panes)
"$TMUX_BIN" new-session -d -s "$SESSION_NAME" -n "smoke"
"$TMUX_BIN" split-window -v -p 75 -t "$SESSION_NAME:0.0"   # Top 25%, bottom 75%
"$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1"
"$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.1"
"$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.2"

# Send simple commands to identify panes
"$TMUX_BIN" send-keys -t "$SESSION_NAME:0.0" 'echo "Pane 0 (top-left)"' C-m
"$TMUX_BIN" send-keys -t "$SESSION_NAME:0.1" 'echo "Pane 1 (top-right)"' C-m
"$TMUX_BIN" send-keys -t "$SESSION_NAME:0.2" 'echo "Pane 2 (bottom-left)"' C-m
"$TMUX_BIN" send-keys -t "$SESSION_NAME:0.3" 'echo "Pane 3 (bottom-right)"' C-m

# Attach
exec "$TMUX_BIN" attach -t "$SESSION_NAME"
