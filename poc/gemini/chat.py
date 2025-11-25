#!/usr/bin/env python3
"""
CSP POC - Gemini Chat UI
Uses Gemini's local telemetry file to detect response completion.
"""

import subprocess
import sys
import time
import argparse
import json
import re
from pathlib import Path
from typing import Optional

# Telemetry file location (configured in ~/.gemini/settings.json)
TELEMETRY_FILE = Path("/tmp/csp-gemini-telemetry.log")

# Marker files for coordination
START_FILE = Path("/tmp/csp-gemini-start")
END_FILE = Path("/tmp/csp-gemini-end")
RESPONSE_FILE = Path("/tmp/csp-gemini-response")

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


class GeminiTelemetryParser:
    """Parses Gemini telemetry for response detection."""

    def __init__(self):
        self.last_prompt_count = 0
        self.last_response_count = 0

    def reset_position(self):
        """Reset to current state before sending a message."""
        if TELEMETRY_FILE.exists():
            try:
                content = TELEMETRY_FILE.read_text()
                self.last_prompt_count = content.count('"gemini_cli.user_prompt"')
                self.last_response_count = content.count('"gemini_cli.api_response"')
            except Exception:
                self.last_prompt_count = 0
                self.last_response_count = 0

    def has_new_response(self) -> bool:
        """Check if a new api_response event appeared after our prompt."""
        if not TELEMETRY_FILE.exists():
            return False

        try:
            content = TELEMETRY_FILE.read_text()
            current_response_count = content.count('"gemini_cli.api_response"')
            return current_response_count > self.last_response_count
        except Exception:
            return False

    def extract_last_response(self) -> Optional[str]:
        """Extract the last response text from api_response events."""
        if not TELEMETRY_FILE.exists():
            return None

        try:
            content = TELEMETRY_FILE.read_text()

            # Find all response_text values
            pattern = r'"response_text":\s*"((?:[^"\\]|\\.)*)"'
            matches = re.findall(pattern, content)

            if not matches:
                return None

            # Get the last response_text (most recent)
            response_json_str = matches[-1]

            # Unescape the JSON string
            response_json_str = response_json_str.encode().decode('unicode_escape')

            # Parse the response JSON
            response_data = json.loads(response_json_str)

            # Handle both streaming (list) and single responses
            text_parts = []
            if isinstance(response_data, list):
                for chunk in response_data:
                    for cand in chunk.get('candidates', []):
                        for part in cand.get('content', {}).get('parts', []):
                            if 'text' in part and not part.get('thought'):
                                text_parts.append(part['text'])
            else:
                for cand in response_data.get('candidates', []):
                    for part in cand.get('content', {}).get('parts', []):
                        if 'text' in part and not part.get('thought'):
                            text_parts.append(part['text'])

            return ''.join(text_parts) if text_parts else None
        except Exception:
            return None


class GeminiChatMonitor:
    """Monitors Gemini responses via telemetry file."""

    def __init__(self, pane_id: str):
        self.pane_id = pane_id
        self.parser = GeminiTelemetryParser()
        self.send_time = 0.0

    def send_message(self, message: str):
        """Send a message to the Gemini pane."""
        # Clear previous files
        RESPONSE_FILE.unlink(missing_ok=True)
        END_FILE.unlink(missing_ok=True)

        # Record start time
        self.send_time = time.time()

        # Reset telemetry parser to current state
        self.parser.reset_position()

        # Exit shell mode with Escape
        for _ in range(3):
            subprocess.run(
                ['tmux', 'send-keys', '-t', self.pane_id, 'Escape'],
                check=True, capture_output=True
            )
            time.sleep(0.1)

        # Strip ! characters to prevent shell mode trigger in Gemini
        safe_message = message.replace('!', '')

        # Send to Gemini via tmux
        subprocess.run(
            ['tmux', 'send-keys', '-t', self.pane_id, '-l', safe_message],
            check=True, capture_output=True
        )
        subprocess.run(
            ['tmux', 'send-keys', '-t', self.pane_id, 'Enter'],
            check=True, capture_output=True
        )

    def wait_for_response(self, timeout: float = 300.0) -> str | None:
        """Wait for Gemini to respond with spinner, return the response text.
        Press Ctrl+C to cancel waiting."""
        start_time = time.time()
        spinner_idx = 0

        try:
            while time.time() - start_time < timeout:
                # Update spinner
                sys.stdout.write(f'\r  {SPINNER[spinner_idx]} ')
                sys.stdout.flush()
                spinner_idx = (spinner_idx + 1) % len(SPINNER)

                # Check if new api_response event appeared
                if self.parser.has_new_response():
                    # Clear spinner
                    sys.stdout.write('\r    \r')
                    sys.stdout.flush()

                    # Extract response from telemetry
                    response = self.parser.extract_last_response()
                    if response:
                        return response

                    # Fallback: capture from pane
                    response = self._capture_pane_response()
                    if response:
                        return response

                time.sleep(0.2)
        except KeyboardInterrupt:
            pass

        # Clear spinner on timeout or cancel
        sys.stdout.write('\r    \r')
        sys.stdout.flush()

        # Last attempt: capture from pane
        return self._capture_pane_response()

    def _capture_pane_response(self) -> Optional[str]:
        """Fallback: capture response from tmux pane."""
        try:
            result = subprocess.run(
                ['tmux', 'capture-pane', '-t', self.pane_id, '-p', '-S', '-50'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                content = result.stdout.strip()
                lines = content.split('\n')
                response_lines = []
                for line in lines:
                    stripped = line.strip()
                    if any(p in stripped.lower() for p in [
                        'gemini>', '/help', '/find-docs', 'shift+tab',
                        'press enter', 'type /', 'authenticate', 'skip the next'
                    ]):
                        continue
                    if stripped and not stripped.startswith('>'):
                        response_lines.append(stripped)

                if response_lines:
                    return '\n'.join(response_lines[-20:])
        except Exception:
            pass
        return None


def main():
    parser = argparse.ArgumentParser(description='CSP Gemini Chat POC')
    parser.add_argument('--pane', required=True, help='tmux pane ID for Gemini')
    args = parser.parse_args()

    monitor = GeminiChatMonitor(args.pane)

    print("CSP Gemini Chat POC")
    print("=" * 40)
    print(f"Pane: {args.pane}")
    print("Ctrl+C to cancel wait, /quit to exit")
    print()

    if not TELEMETRY_FILE.exists():
        print("Note: Telemetry file not found yet.")
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
                print(f"  Telemetry: {TELEMETRY_FILE.exists()}, Response: {RESPONSE_FILE.exists()}")
                if TELEMETRY_FILE.exists():
                    print(f"  Size: {TELEMETRY_FILE.stat().st_size} bytes")
                continue

            # Send message and wait for response
            monitor.send_message(user_input)
            response = monitor.wait_for_response(timeout=300)

            if response:
                clean = strip_markdown(response)
                display = ' '.join(clean.split())
                if len(display) > 300:
                    display = display[:300] + "..."
                print(f"Gemini > {display}")
            else:
                print("  [No response or timeout]")

            print()

    except KeyboardInterrupt:
        print("\n")

    print("Goodbye!")


if __name__ == '__main__':
    main()
