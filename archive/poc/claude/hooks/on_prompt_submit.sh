#!/bin/bash
# CSP Claude Hook: UserPromptSubmit
# Marks the start of a new prompt being processed

# Write timestamp to indicate processing started
echo "$(date +%s)" > /tmp/csp-claude-start

# Clear previous response to avoid stale data
rm -f /tmp/csp-claude-response 2>/dev/null

exit 0
