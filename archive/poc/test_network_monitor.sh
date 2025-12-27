#!/bin/bash
# Test network monitoring for claude process

SHELL_PID=${1:-18443}
echo "Finding claude process under shell PID: $SHELL_PID"

CLAUDE_PID=$(pgrep -P $SHELL_PID 2>/dev/null | head -1)
if [ -z "$CLAUDE_PID" ]; then
    echo "No claude process found"
    exit 1
fi

echo "Claude PID: $CLAUDE_PID"
echo ""
echo "Monitoring network connections (20 samples at 0.3s intervals):"
echo ""

for i in $(seq 1 20); do
    # Count established connections
    CONNS=$(lsof -n -P -i -a -p $CLAUDE_PID 2>/dev/null | grep -c ESTABLISHED || echo 0)

    # Get CPU
    CPU=$(ps -o %cpu= -p $CLAUDE_PID 2>/dev/null | tr -d ' ')

    # Check for any TCP activity
    TCP_STATE=$(lsof -n -P -i -a -p $CLAUDE_PID 2>/dev/null | grep -oE '(ESTABLISHED|SYN_SENT|CLOSE_WAIT|TIME_WAIT)' | sort | uniq -c | tr '\n' ' ' || echo "none")

    echo "$(date +%H:%M:%S.%N | cut -c1-12) CPU=${CPU}% Established=${CONNS} TCP: ${TCP_STATE}"

    sleep 0.3
done
