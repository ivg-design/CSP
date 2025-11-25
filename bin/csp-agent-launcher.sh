#!/bin/bash
# bin/csp-agent-launcher.sh
# Interactive menu for launching agents in tmux panes

SLOT_NAME="${1:-Agent}"
PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${CYAN}🤖 CSP Agent Launcher [${SLOT_NAME}]${NC}"
    echo "--------------------------------"
    echo -e "Gateway: ${GREEN}$CSP_GATEWAY_URL${NC}"
    echo "--------------------------------"
    echo "1. Claude (--dangerously-skip-permissions)"
    echo "2. Gemini (--yolo)"
    echo "3. Codex (--dangerously-bypass-approvals)"
    echo "4. Custom Command..."
    echo "q. Quit (Close Pane)"
    echo ""
}

run_agent() {
    NAME="$1"
    CMD="$2"
    
    # Generate unique name based on slot and time to avoid collisions
    UNIQUE_NAME="${NAME}-$(date +%s)"
    
    echo -e "${GREEN}🚀 Launching ${NAME}...${NC}"
    echo "Command: $CMD"
    echo "--------------------------------"
    
    # Execute Sidecar
    # Connects to Gateway using CSP_AUTH_TOKEN.
    # Enables WebSocket Push / HTTP Polling for real-time inbox.
    # Handles Flow Control (Busy/Idle) and Ghost Logging automatically.
    # Note: --cmd must be LAST argument, $CMD is intentionally unquoted to allow word splitting
    python3 "$PROJECT_ROOT/csp_sidecar.py" \
        --name "$UNIQUE_NAME" \
        --gateway-url "$CSP_GATEWAY_URL" \
        --auth-token "$CSP_AUTH_TOKEN" \
        --cmd $CMD
        
    echo -e "\n${CYAN}Agent exited. Press Enter to return to menu...${NC}"
    read
}

while true; do
    show_menu
    read -p "Select Agent > " choice
    
    case $choice in
        1)
            run_agent "Claude" "claude --dangerously-skip-permissions"
            ;;
        2)
            run_agent "Gemini" "gemini --yolo"
            ;;
        3)
            run_agent "Codex" "codex --dangerously-bypass-approvals-and-sandbox"
            ;;
        4)
            read -p "Enter Agent Name: " custom_name
            read -p "Enter Command: " custom_cmd
            run_agent "$custom_name" "$custom_cmd"
            ;;
        q)
            echo "Closing pane..."
            exit 0
            ;;
        *)
            echo "Invalid selection."
            sleep 1
            ;;
    esac
done
