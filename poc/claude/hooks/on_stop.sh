#!/bin/bash
# CSP Claude Hook: Stop
# Extracts the last assistant response from the transcript

LOG="/tmp/csp-claude-hook.log"

# Read JSON from stdin (Claude passes hook context)
INPUT=$(cat)

echo "=== Stop hook fired at $(date) ===" >> "$LOG"

# Extract transcript path from the hook context
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
echo "TRANSCRIPT: $TRANSCRIPT" >> "$LOG"

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
    echo "No transcript or file not found" >> "$LOG"
    echo "$(date +%s)" > /tmp/csp-claude-end
    exit 0
fi

# Get the last assistant message with text content
# Use tail to get last 50 lines, then find the last assistant message with text
RESPONSE=$(tail -50 "$TRANSCRIPT" | \
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
    tail -1)

echo "RESPONSE length: ${#RESPONSE}" >> "$LOG"
echo "RESPONSE preview: ${RESPONSE:0:100}" >> "$LOG"

if [[ -n "$RESPONSE" ]]; then
    echo "$RESPONSE" > /tmp/csp-claude-response
    echo "Wrote response to file" >> "$LOG"
else
    echo "No response extracted" >> "$LOG"
fi

# Mark completion
echo "$(date +%s)" > /tmp/csp-claude-end
echo "=== Hook complete ===" >> "$LOG"

exit 0
