#!/bin/bash
# poc/start-multi.sh - CSP Multi-Agent Group Chat Launcher
# Launches CSP Gateway + Chat Controller + Multiple Agents with proper pane layout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSP_ROOT="$(dirname "$SCRIPT_DIR")"
SESSION_NAME="csp-multi"
LOG_FILE="/tmp/csp-multi-setup.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    log "$1"
    echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
}

usage() {
    echo "CSP Multi-Agent Group Chat"
    echo ""
    echo "Usage: $0 agent1 [agent2] [agent3]"
    echo ""
    echo "Available agents: claude, gemini, codex"
    echo ""
    echo "Examples:"
    echo "  $0 claude gemini"
    echo "  $0 claude gemini codex"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

# Clear log
> "$LOG_FILE"

log_section "CSP Multi-Agent Group Chat Starting"
log "Script Dir: $SCRIPT_DIR"
log "CSP Root: $CSP_ROOT"

# Collect agents
AGENTS=()
for arg in "$@"; do
    case "$arg" in
        claude) AGENTS+=("Claude:claude --dangerously-skip-permissions") ;;
        gemini) AGENTS+=("Gemini:gemini") ;;
        codex)  AGENTS+=("Codex:codex") ;;
        *) log "Unknown agent: $arg"; exit 1 ;;
    esac
done

NUM_AGENTS=${#AGENTS[@]}
log "Agents: $NUM_AGENTS"

# Setup CSP
export CSP_AUTH_TOKEN=$(openssl rand -hex 32)
export CSP_GATEWAY_URL="http://localhost:8765"
log "Token: ${CSP_AUTH_TOKEN:0:16}..."

# Start Gateway
log_section "Starting Gateway"
cd "$CSP_ROOT"
node src/gateway/csp_gateway.js > /tmp/csp-gateway.log 2>&1 &
GATEWAY_PID=$!
sleep 2
log "Gateway PID: $GATEWAY_PID"

# Kill existing session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.3

# Create session
unset TMUX
tmux new-session -d -s "$SESSION_NAME" -n "GroupChat" -c "$SCRIPT_DIR"
log "Session created"

# Create panes
tmux split-window -v -p 25 -t "$SESSION_NAME:0.0" -c "$SCRIPT_DIR"

if [[ $NUM_AGENTS -ge 2 ]]; then
    tmux select-pane -t "$SESSION_NAME:0.1"
    tmux split-window -h -p 50 -t "$SESSION_NAME:0.1" -c "$SCRIPT_DIR"
fi

if [[ $NUM_AGENTS -ge 3 ]]; then
    tmux select-pane -t "$SESSION_NAME:0.2"
    tmux split-window -h -p 50 -t "$SESSION_NAME:0.2" -c "$SCRIPT_DIR"
fi

log_section "Launching Agents"

# Pane mapping
declare -a PANES
PANES[0]="$SESSION_NAME:0.0"
PANES[1]="$SESSION_NAME:0.1"
PANES[2]="$SESSION_NAME:0.2"
PANES[3]="$SESSION_NAME:0.3"

# Launch agents
for i in "${!AGENTS[@]}"; do
    PANE_NUM=$((i + 1))
    PANE="${PANES[$PANE_NUM]}"
    IFS=':' read -r NAME CMD <<< "${AGENTS[$i]}"
    
    PRIMER_FILE="$SCRIPT_DIR/primers/${NAME}.txt"
    PRIMER=""
    if [ -f "$PRIMER_FILE" ]; then
        PRIMER="--initial-prompt \"$(cat "$PRIMER_FILE" | sed 's/"/\\"/g')\""
    fi
    
    CMD_SIDECAR="python3 \"$CSP_ROOT/csp_sidecar.py\" --name \"$NAME\" --gateway-url \"$CSP_GATEWAY_URL\" --auth-token \"$CSP_AUTH_TOKEN\" $PRIMER --cmd $CMD"
    
    tmux send-keys -t "$PANE" "$CMD_SIDECAR" Enter
    log "Launched $NAME to $PANE"
done

# Wait for initialization
sleep 4

# Launch chat controller
log_section "Starting Chat Controller"
CHAT_PANE="${PANES[0]}"
tmux send-keys -t "$CHAT_PANE" "export CSP_AUTH_TOKEN=\"$CSP_AUTH_TOKEN\"" Enter
tmux send-keys -t "$CHAT_PANE" "export CSP_GATEWAY_URL=\"$CSP_GATEWAY_URL\"" Enter
sleep 1
tmux send-keys -t "$CHAT_PANE" "node \"$CSP_ROOT/src/human-interface/chat-controller.js\"" Enter

tmux select-pane -t "$CHAT_PANE"

log_section "Ready!"
log "Gateway: $CSP_GATEWAY_URL"
log "Token: ${CSP_AUTH_TOKEN:0:16}..."
log ""

# Show info
cat <<EOF

╔═══════════════════════════════════════════════════════════╗
║    CSP Multi-Agent Group Chat Ready!                    ║
╠═══════════════════════════════════════════════════════════╣
║  Commands:                                                ║
║    @all message           - Send to all agents           ║
║    @agent_name message    - Send to specific agent       ║
║    @query.log [N]         - Show chat history            ║
║    /agents                - List agents                  ║
║    /help                  - Show help                    ║
║                                                           ║
║  Tmux: Ctrl+B → arrows to switch panes                   ║
╚═══════════════════════════════════════════════════════════╝

EOF

# Attach
if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION_NAME"
else
    tmux attach -t "$SESSION_NAME"
fi

# Cleanup
kill $GATEWAY_PID 2>/dev/null || true
