#!/bin/bash

# Human User Agent
# Allows the human to participate directly in the multi-agent chat

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="Human"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}👤 Human User joining the conversation${NC}"

# Start interactive chat mode directly using the Python client
python3 "$SCRIPT_DIR/agent_client.py" "$AGENT_NAME"