#!/bin/bash
# bin/start-llm-groupchat.sh
# Orchestrator for CSP Multi-Agent System

SESSION_NAME="llm-groupchat"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GATEWAY_LOG="$PROJECT_ROOT/gateway.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}🧹 Shutting down CSP system...${NC}"
    if [[ -n "$GATEWAY_PID" ]]; then
        kill "$GATEWAY_PID" 2>/dev/null
    fi
    # Optional: Kill tmux session on exit? 
    # tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    echo "Done."
}
trap cleanup EXIT

echo -e "${BLUE}🚀 Initializing CSP Multi-Agent System...${NC}"

# 1. Environment & Auth
# CSP_AUTH_TOKEN is required for all clients (sidecars & human controller) to talk to the Gateway.
# This ensures no unauthorized processes can inject messages into the agent swarm.
export CSP_PORT=${CSP_PORT:-8765}
if [[ -z "$CSP_AUTH_TOKEN" ]]; then
    # Generate a random token
    export CSP_AUTH_TOKEN=$(openssl rand -hex 32)
    echo -e "${GREEN}🔑 Generated Auth Token: ${CSP_AUTH_TOKEN:0:8}...${NC}"
fi
export CSP_GATEWAY_URL="http://localhost:$CSP_PORT"

# 2. Start Gateway
# Starts the CSP Gateway which provides WebSocket/SSE Push channels for real-time communication.
# Clients will automatically upgrade to Push or fallback to HTTP polling.
echo -e "${BLUE}📡 Starting Gateway on port $CSP_PORT...${NC}"
node "$PROJECT_ROOT/src/gateway/csp_gateway.js" > "$GATEWAY_LOG" 2>&1 &
GATEWAY_PID=$!
sleep 2

if ! ps -p $GATEWAY_PID > /dev/null; then
    echo -e "${RED}❌ Gateway failed to start. Check $GATEWAY_LOG${NC}"
    exit 1
fi

# 3. Setup tmux Session
echo -e "${BLUE}🖥️  Configuring tmux session '${SESSION_NAME}'...${NC}"

# Kill existing session if it exists
tmux kill-session -t "$SESSION_NAME" 2>/dev/null

# Create new session (Pane 0: Chat Controller)
tmux new-session -d -s "$SESSION_NAME" -n "CSP-Main"
tmux send-keys -t "$SESSION_NAME:0" "export CSP_AUTH_TOKEN='$CSP_AUTH_TOKEN'" C-m
tmux send-keys -t "$SESSION_NAME:0" "export CSP_GATEWAY_URL='$CSP_GATEWAY_URL'" C-m
tmux send-keys -t "$SESSION_NAME:0" "node src/human-interface/chat-controller.js" C-m

# Split layout (1 Top, 3 Bottom) - more balanced
tmux split-window -v -p 60 -t "$SESSION_NAME:0"  # Split top/bottom (40% top, 60% bottom)
sleep 0.1
tmux split-window -h -t "$SESSION_NAME:0.1"      # Split bottom into 2
sleep 0.1
tmux split-window -h -t "$SESSION_NAME:0.2"      # Split bottom right into 2 (Total 3 bottom)
sleep 0.1

# Pane 1 (Bottom Left): Agent Slot 1
tmux send-keys -t "$SESSION_NAME:0.1" "export CSP_AUTH_TOKEN='$CSP_AUTH_TOKEN'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "export CSP_GATEWAY_URL='$CSP_GATEWAY_URL'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-1'" C-m

# Pane 2 (Bottom Center): Agent Slot 2
tmux send-keys -t "$SESSION_NAME:0.2" "export CSP_AUTH_TOKEN='$CSP_AUTH_TOKEN'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "export CSP_GATEWAY_URL='$CSP_GATEWAY_URL'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-2'" C-m

# Pane 3 (Bottom Right): Agent Slot 3
tmux send-keys -t "$SESSION_NAME:0.3" "export CSP_AUTH_TOKEN='$CSP_AUTH_TOKEN'" C-m
tmux send-keys -t "$SESSION_NAME:0.3" "export CSP_GATEWAY_URL='$CSP_GATEWAY_URL'" C-m
tmux send-keys -t "$SESSION_NAME:0.3" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-3'" C-m

# Styling and layout finalization
tmux select-pane -t "$SESSION_NAME:0.0" -T "🎛️ Human Controller"
tmux select-pane -t "$SESSION_NAME:0.1" -T "🤖 Agent Slot 1"
tmux select-pane -t "$SESSION_NAME:0.2" -T "🤖 Agent Slot 2"
tmux select-pane -t "$SESSION_NAME:0.3" -T "🤖 Agent Slot 3"

# Ensure proper layout and make panes more accessible
tmux select-layout -t "$SESSION_NAME" tiled 2>/dev/null || true
tmux select-layout -t "$SESSION_NAME" main-horizontal 2>/dev/null || true
tmux select-pane -t "$SESSION_NAME:0.0"  # Start with Human Controller selected

# Final setup
echo -e "${GREEN}✅ System Ready!"
echo -e "${BLUE}📋 Layout: 1 human controller (top), 3 agent slots (bottom)${NC}"
echo -e "${BLUE}🔧 Use Ctrl+B + arrow keys to navigate panes${NC}"
echo -e "${BLUE}🔧 Use Ctrl+B + z to zoom current pane${NC}"
echo "Attaching to tmux session..."
sleep 1

tmux attach -t "$SESSION_NAME"
