#!/bin/bash

# Agent Communication Helper Script
# Provides easy functions for agents to communicate with each other

SHARED_PIPE="/tmp/agent_shared"
AGENT_NAME="${1:-Unknown}"

# Function to send a message to all agents
send_message() {
    local message="$1"
    echo "[$(date '+%H:%M:%S')] $AGENT_NAME: $message" >> "$SHARED_PIPE"
}

# Function to listen for messages (non-blocking)
listen_messages() {
    if [[ -p "$SHARED_PIPE" ]]; then
        timeout 1 cat "$SHARED_PIPE" 2>/dev/null || true
    fi
}

# Function to broadcast that agent is ready
announce_ready() {
    send_message "🟢 Agent ready and listening"
}

# Function to broadcast that agent is thinking/working
announce_thinking() {
    send_message "🤔 Thinking..."
}

# Function to share response with other agents
share_response() {
    local response="$1"
    send_message "💬 Response: $response"
}

# Function to ask other agents for input
ask_agents() {
    local question="$1"
    send_message "❓ Question for other agents: $question"
}

# Export functions for use in other scripts
export -f send_message
export -f listen_messages
export -f announce_ready
export -f announce_thinking
export -f share_response
export -f ask_agents

# If script is run directly, provide interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Agent Communicator for: $AGENT_NAME"
    echo "Available commands:"
    echo "  send 'message'     - Send message to all agents"
    echo "  listen             - Listen for messages"
    echo "  ready              - Announce ready status"
    echo "  thinking           - Announce thinking status"
    echo "  ask 'question'     - Ask other agents a question"
    echo "  exit               - Exit"
    echo ""

    while true; do
        read -p "$AGENT_NAME > " cmd args
        case $cmd in
            send)
                send_message "$args"
                ;;
            listen)
                listen_messages
                ;;
            ready)
                announce_ready
                ;;
            thinking)
                announce_thinking
                ;;
            ask)
                ask_agents "$args"
                ;;
            exit)
                break
                ;;
            *)
                echo "Unknown command: $cmd"
                ;;
        esac
    done
fi