#!/usr/bin/env python3
"""
CSP POC - Codex Notify Handler
Receives JSON payload from Codex's notify config and extracts the response.

Codex sends JSON like:
{
  "type": "agent-turn-complete",
  "turn-id": "abc123",
  "input-messages": ["User prompt"],
  "last-assistant-message": "The actual response"
}
"""

import sys
import json
import time
from pathlib import Path

# Output files
RESPONSE_FILE = Path("/tmp/csp-codex-response")
END_FILE = Path("/tmp/csp-codex-end")
LOG_FILE = Path("/tmp/csp-codex-notify.log")


def log(message: str):
    """Append to log file for debugging."""
    with open(LOG_FILE, 'a') as f:
        f.write(f"{time.time()}: {message}\n")


def main():
    # Codex appends JSON as the last argument
    if len(sys.argv) < 2:
        log("No arguments received")
        return

    json_str = sys.argv[-1]
    log(f"Received: {json_str[:200]}...")

    try:
        payload = json.loads(json_str)

        event_type = payload.get("type", "")
        log(f"Event type: {event_type}")

        if event_type == "agent-turn-complete":
            response = payload.get("last-assistant-message", "")

            if response:
                RESPONSE_FILE.write_text(response)
                log(f"Wrote response ({len(response)} chars)")
            else:
                log("No response in payload")

            END_FILE.write_text(str(int(time.time())))
            log("Wrote end marker")

    except json.JSONDecodeError as e:
        log(f"JSON decode error: {e}")
    except Exception as e:
        log(f"Error: {e}")


if __name__ == "__main__":
    main()
