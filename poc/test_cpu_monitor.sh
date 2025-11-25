#!/bin/bash
# Test CPU monitoring for agent detection

SHELL_PID=${1:-18443}
echo "Monitoring children of shell PID: $SHELL_PID"

for i in $(seq 1 20); do
    AGENT_PID=$(pgrep -P $SHELL_PID 2>/dev/null | head -1)
    if [ -n "$AGENT_PID" ]; then
        CPU=$(ps -o %cpu= -p $AGENT_PID 2>/dev/null | tr -d ' ')
        STATE=$(ps -o state= -p $AGENT_PID 2>/dev/null | tr -d ' ')
        echo "$(date +%H:%M:%S.%N | cut -c1-12) PID=$AGENT_PID CPU=${CPU}% STATE=$STATE"
    else
        echo "$(date +%H:%M:%S) No agent process found"
    fi
    sleep 0.2
done
