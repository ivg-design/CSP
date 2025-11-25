#!/usr/bin/env python3
"""
CSP POC - Codex Chat UI
Uses Codex's notify config to receive JSON payload with responses.
"""

import subprocess
import sys
import time
import argparse
import re
from pathlib import Path

# Response detection files (written by notify_handler.py)
RESPONSE_FILE = Path("/tmp/csp-codex-response")
START_FILE = Path("/tmp/csp-codex-start")
END_FILE = Path("/tmp/csp-codex-end")

# Spinner characters
SPINNER = ['|', '/', '—', '\\']


def strip_markdown(text: str) -> str:
    """Remove common markdown formatting."""
    # Bold: **text** or __text__
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'__(.+?)__', r'\1', text)
    # Italic: *text* or _text_
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'(?<!\w)_(.+?)_(?!\w)', r'\1', text)
    # Code: `text`
    text = re.sub(r'`(.+?)`', r'\1', text)
    # Headers: # text
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Links: [text](url)
    text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)
    return text


class CodexChatMonitor:
    """Monitors Codex responses via notify handler files."""

    def __init__(self, pane_id: str):
        self.pane_id = pane_id
        self.send_time = 0.0

    def send_message(self, message: str):
        """Send a message to the Codex pane."""
        # Clear previous files - this is critical!
        RESPONSE_FILE.unlink(missing_ok=True)
        END_FILE.unlink(missing_ok=True)

        # Record current time as our reference point
        self.send_time = time.time()

        # Send to Codex via tmux
        subprocess.run(
            ['tmux', 'send-keys', '-t', self.pane_id, '-l', message],
            check=True, capture_output=True
        )
        subprocess.run(
            ['tmux', 'send-keys', '-t', self.pane_id, 'Enter'],
            check=True, capture_output=True
        )

    def wait_for_response(self, timeout: float = 300.0) -> str | None:
        """Wait for Codex to respond with spinner, return the response text.
        Press Ctrl+C to cancel waiting."""
        start_time = time.time()
        spinner_idx = 0

        try:
            while time.time() - start_time < timeout:
                # Update spinner
                sys.stdout.write(f'\r  {SPINNER[spinner_idx]} ')
                sys.stdout.flush()
                spinner_idx = (spinner_idx + 1) % len(SPINNER)

                # Check if end file exists (we deleted it before sending)
                if END_FILE.exists():
                    # Clear spinner line
                    sys.stdout.write('\r    \r')
                    sys.stdout.flush()

                    # Notify handler has fired, check for response
                    if RESPONSE_FILE.exists():
                        response = RESPONSE_FILE.read_text().strip()
                        if response:
                            return response
                    # Handler fired but no response - wait a bit more
                    time.sleep(0.2)
                    if RESPONSE_FILE.exists():
                        response = RESPONSE_FILE.read_text().strip()
                        if response:
                            return response
                    return None

                time.sleep(0.1)
        except KeyboardInterrupt:
            # User pressed Ctrl+C to cancel
            pass

        # Clear spinner on timeout or cancel
        sys.stdout.write('\r    \r')
        sys.stdout.flush()
        return None


def main():
    parser = argparse.ArgumentParser(description='CSP Codex Chat POC')
    parser.add_argument('--pane', required=True, help='tmux pane ID for Codex')
    args = parser.parse_args()

    monitor = CodexChatMonitor(args.pane)

    print("CSP Codex Chat POC")
    print("=" * 40)
    print(f"Pane: {args.pane}")
    print("Ctrl+C to cancel wait, /quit to exit")
    print()

    try:
        while True:
            try:
                user_input = input("You > ").strip()
            except EOFError:
                break

            if not user_input:
                continue

            if user_input.lower() == '/quit':
                break

            if user_input.lower() == '/status':
                print(f"  Start: {START_FILE.exists()}, End: {END_FILE.exists()}, Response: {RESPONSE_FILE.exists()}")
                log_file = Path("/tmp/csp-codex-notify.log")
                if log_file.exists():
                    lines = log_file.read_text().strip().split('\n')[-3:]
                    for line in lines:
                        print(f"    {line}")
                continue

            # Send message and wait for response
            monitor.send_message(user_input)
            response = monitor.wait_for_response(timeout=300)

            if response:
                # Strip markdown and format for display
                clean = strip_markdown(response)
                display = ' '.join(clean.split())
                if len(display) > 300:
                    display = display[:300] + "..."
                print(f"Codex > {display}")
            else:
                print("  [No response or timeout]")

            print()

    except KeyboardInterrupt:
        print("\n")

    print("Goodbye!")


if __name__ == '__main__':
    main()
