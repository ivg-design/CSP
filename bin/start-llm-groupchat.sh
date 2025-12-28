#!/bin/bash
# bin/start-llm-groupchat.sh
# Orchestrator for CSP Multi-Agent System
set -euo pipefail

SESSION_NAME="llm-groupchat"
TMUX_BIN="$(command -v tmux || true)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GATEWAY_LOG="$PROJECT_ROOT/gateway.log"
CONFIG_FILE_DEFAULT="$PROJECT_ROOT/config/csp.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}🧹 Shutting down CSP system...${NC}"
    if [[ -n "${GATEWAY_PID:-}" ]]; then
        kill "$GATEWAY_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}❌ Required command '$1' not found. Install it and retry.${NC}"
        exit 1
    fi
}

load_config() {
    local cfg="${CSP_CONFIG_FILE:-$CONFIG_FILE_DEFAULT}"
    if [[ -f "$cfg" ]]; then
        echo -e "${BLUE}📄 Loading config: $cfg${NC}"
        set -a
        # shellcheck source=/dev/null
        source "$cfg"
        set +a
    fi
}

check_cli_cmd() {
    local label="$1"
    local cmd="$2"
    local strict="${CSP_STRICT_CLI_CHECK:-0}"
    if [[ -z "$cmd" ]]; then
        echo -e "${YELLOW}[preflight] ${label}: not configured${NC}"
        return 0
    fi
    local bin="${cmd%% *}"
    if [[ "$bin" == */* ]]; then
        if [[ -x "$bin" ]]; then
            echo -e "${GREEN}[preflight] ${label}: OK (${bin})${NC}"
            return 0
        fi
    else
        if command -v "$bin" >/dev/null 2>&1; then
            echo -e "${GREEN}[preflight] ${label}: OK (${bin})${NC}"
            return 0
        fi
    fi
    echo -e "${RED}[preflight] ${label}: MISSING (${bin})${NC}"
    if [[ "$strict" == "1" ]]; then
        exit 1
    fi
    return 0
}

preflight_checks() {
    echo -e "${BLUE}🔎 Running preflight checks...${NC}"
    require_cmd tmux
    require_cmd node
    require_cmd python3
    if [[ -z "${CSP_AUTH_TOKEN:-}" ]]; then
        require_cmd openssl
    fi

    check_cli_cmd "Claude" "${CSP_CLAUDE_CMD:-claude --dangerously-skip-permissions}"
    check_cli_cmd "Gemini" "${CSP_GEMINI_CMD:-gemini}"
    check_cli_cmd "Codex" "${CSP_CODEX_CMD:-codex}"

    if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
        check_cli_cmd "Orchestrator" "${CSP_ORCH_CMD:-claude --model haiku --dangerously-skip-permissions}"
    fi
}

echo -e "${BLUE}🚀 Initializing CSP Multi-Agent System...${NC}"
load_config
preflight_checks

# 0. Kill any existing processes
echo -e "${YELLOW}🧹 Cleaning up any existing processes...${NC}"
pkill -f "node.*csp_gateway" 2>/dev/null || true
unset TMUX
"$TMUX_BIN" kill-session -t "$SESSION_NAME" 2>/dev/null || true
sleep 0.5

# 1. Environment & Auth
export CSP_PORT=${CSP_PORT:-8765}
if [[ -z "${CSP_AUTH_TOKEN:-}" ]]; then
    export CSP_AUTH_TOKEN
    CSP_AUTH_TOKEN=$(openssl rand -hex 32)
    echo -e "${GREEN}🔑 Generated Auth Token: ${CSP_AUTH_TOKEN:0:8}...${NC}"
fi
export CSP_GATEWAY_URL="${CSP_GATEWAY_URL:-http://localhost:$CSP_PORT}"

# 2. Start Gateway
echo -e "${BLUE}📡 Starting Gateway on port $CSP_PORT...${NC}"
node "$PROJECT_ROOT/src/gateway/csp_gateway.js" > "$GATEWAY_LOG" 2>&1 &
GATEWAY_PID=$!
sleep 1
if ! ps -p "$GATEWAY_PID" > /dev/null; then
    echo -e "${RED}❌ Gateway failed to start. Check $GATEWAY_LOG${NC}"
    exit 1
fi

# 3. Setup tmux Session
echo -e "${BLUE}🖥️  Configuring tmux session '${SESSION_NAME}'...${NC}"

layout_start=$SECONDS
"$TMUX_BIN" new-session -d -s "$SESSION_NAME" -n "CSP-Main" -c "$PROJECT_ROOT" || { echo -e "${RED}❌ tmux new-session failed${NC}"; exit 1; }
"$TMUX_BIN" split-window -v -p 75 -t "$SESSION_NAME:0.0" -c "$PROJECT_ROOT"   # Top 25%, bottom 75%

if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1"
  "$TMUX_BIN" split-window -h -p 50 -t "$SESSION_NAME:0.1" -c "$PROJECT_ROOT"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1"
  "$TMUX_BIN" split-window -h -p 50 -t "$SESSION_NAME:0.1" -c "$PROJECT_ROOT"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.2"
  "$TMUX_BIN" split-window -h -p 50 -t "$SESSION_NAME:0.2" -c "$PROJECT_ROOT"
else
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1"
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.1" -c "$PROJECT_ROOT"
  "$TMUX_BIN" split-window -h -t "$SESSION_NAME:0.2" -c "$PROJECT_ROOT"
fi

# tmux robustness: verify pane count
expected_panes=4
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  expected_panes=5
fi
pane_count=$("$TMUX_BIN" list-panes -t "$SESSION_NAME" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$pane_count" != "$expected_panes" ]]; then
  echo -e "${RED}❌ tmux pane count mismatch (${pane_count}/${expected_panes}).${NC}"
  exit 1
fi
layout_elapsed=$((SECONDS - layout_start))
echo -e "${BLUE}📊 tmux layout created in ${layout_elapsed}s${NC}"

# Export env to all panes
PANES=(0.0 0.1 0.2 0.3)
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  PANES=(0.0 0.1 0.2 0.3 0.4)
fi

for pane in "${PANES[@]}"; do
  # Set env vars silently and clear screen
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:$pane" "export CSP_AUTH_TOKEN='$CSP_AUTH_TOKEN' CSP_GATEWAY_URL='$CSP_GATEWAY_URL' CSP_CLAUDE_CMD='${CSP_CLAUDE_CMD:-claude --dangerously-skip-permissions}' CSP_GEMINI_CMD='${CSP_GEMINI_CMD:-gemini}' CSP_CODEX_CMD='${CSP_CODEX_CMD:-codex}' && clear" C-m
done

# Launch processes in panes
"$TMUX_BIN" send-keys -t "$SESSION_NAME:0.0" "node src/human-interface/chat-controller.js" C-m

if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  ORCH_CMD="${CSP_ORCH_CMD:-/Users/ivg/.claude/local/claude --model haiku --dangerously-skip-permissions}"
  ORCH_PROMPT_FILE="$PROJECT_ROOT/orchestrator_prompt.txt"
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.1" \
    "python3 \"$PROJECT_ROOT/csp_sidecar.py\" --name Orchestrator --gateway-url \"$CSP_GATEWAY_URL\" --auth-token \"$CSP_AUTH_TOKEN\" --initial-prompt \"\$(cat \"$ORCH_PROMPT_FILE\" 2>/dev/null || echo 'You are the orchestrator.')\" --cmd $ORCH_CMD" C-m
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.2" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-1'" C-m
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.3" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-2'" C-m
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.4" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-3'" C-m
else
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.1" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-1'" C-m
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.2" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-2'" C-m
  "$TMUX_BIN" send-keys -t "$SESSION_NAME:0.3" "$SCRIPT_DIR/csp-agent-launcher.sh 'Agent-3'" C-m
fi

# Titles
"$TMUX_BIN" select-pane -t "$SESSION_NAME:0.0" -T "🎛️ Human Controller"
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1" -T "🎭 Orchestrator"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.2" -T "🤖 Agent Slot 1"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.3" -T "🤖 Agent Slot 2"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.4" -T "🤖 Agent Slot 3"
else
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.1" -T "🤖 Agent Slot 1"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.2" -T "🤖 Agent Slot 2"
  "$TMUX_BIN" select-pane -t "$SESSION_NAME:0.3" -T "🤖 Agent Slot 3"
fi

"$TMUX_BIN" select-pane -t "$SESSION_NAME:0.0"

echo -e "${GREEN}✅ System Ready!"
if [[ "${CSP_ORCHESTRATOR:-0}" == "1" ]]; then
  echo -e "${BLUE}📋 Layout: 1 human controller (top), orchestrator + 3 agent slots (bottom)${NC}"
else
  echo -e "${BLUE}📋 Layout: 1 human controller (top), 3 agent slots (bottom)${NC}"
fi
echo -e "${BLUE}🔧 Use Ctrl+B + arrow keys to navigate panes${NC}"
echo -e "${BLUE}🔧 Use Ctrl+B + z to zoom current pane${NC}"
echo "Attaching to tmux session..."
sleep 1

"$TMUX_BIN" has-session -t "$SESSION_NAME" >/dev/null 2>&1 || { echo -e "${RED}❌ tmux session not found after creation${NC}"; exit 1; }
"$TMUX_BIN" list-sessions

# Attach using iTerm2 native control mode if available, otherwise normal attach
if [ -n "${TMUX:-}" ]; then
  "$TMUX_BIN" switch-client -t "$SESSION_NAME"
elif [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
  "$TMUX_BIN" -CC attach -t "$SESSION_NAME"
else
  "$TMUX_BIN" attach -t "$SESSION_NAME"
fi
