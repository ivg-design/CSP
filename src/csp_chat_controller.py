#!/usr/bin/env python3
"""
CSP Chat Controller - WebSocket-enabled group chat interface

This controller provides a human interface to the CSP multi-agent system.
It connects to the gateway via WebSocket (with HTTP polling fallback) to:
- Send messages to specific agents (@agent) or all agents (@all)
- Receive and display responses from agents in real-time
- Handle reconnection automatically with exponential backoff
"""

import sys
import threading
import time
import json
import requests
import websocket
import urllib.parse
import signal
from datetime import datetime
import argparse

GATEWAY_URL = "http://localhost:8765"
POLL_INTERVAL = 0.2  # 200ms as specified in the plan


class CSPChatController:
    def __init__(self, gateway_url=GATEWAY_URL, auth_token=None):
        self.gateway_url = gateway_url
        self.auth_token = auth_token
        self.should_exit = False

        # WebSocket connection management
        self.ws = None
        self.ws_connected = False
        self.ws_reconnect_attempts = 0
        self.max_reconnect_attempts = 5
        self.reconnect_delay = 1

        # Human user identification
        self.user_id = "human"

    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        print(f"\nReceived signal {signum}, shutting down...", file=sys.stderr)
        self.should_exit = True
        if self.ws:
            self.ws.close()

    def register_user(self):
        """Register the human user with the gateway"""
        try:
            headers = {"Content-Type": "application/json"}
            if self.auth_token:
                headers["X-Auth-Token"] = self.auth_token

            response = requests.post(
                f"{self.gateway_url}/register",
                json={"agent_id": self.user_id, "agent_type": "human"},
                headers=headers,
                timeout=5
            )

            if response.status_code in [200, 201]:
                print(f"✓ Connected to CSP Gateway as {self.user_id}", file=sys.stderr)
                return True
            else:
                print(f"Registration failed: {response.status_code} - {response.text}", file=sys.stderr)
                return False
        except Exception as e:
            print(f"Registration error: {e}", file=sys.stderr)
            return False

    def try_websocket_connection(self):
        """Attempt to establish WebSocket connection"""
        if self.ws_connected:
            return True

        try:
            # Convert HTTP URL to WebSocket URL
            ws_url = self.gateway_url.replace('http://', 'ws://').replace('https://', 'wss://')
            ws_url = f"{ws_url}/ws"

            # Add authentication via query parameter
            if self.auth_token:
                parsed = urllib.parse.urlparse(ws_url)
                query = urllib.parse.parse_qs(parsed.query)
                query['token'] = [self.auth_token]
                new_query = urllib.parse.urlencode(query, doseq=True)
                ws_url = urllib.parse.urlunparse(parsed._replace(query=new_query))

            # Create WebSocket connection
            self.ws = websocket.WebSocketApp(
                ws_url,
                on_open=self.on_ws_open,
                on_message=self.on_ws_message,
                on_error=self.on_ws_error,
                on_close=self.on_ws_close
            )

            print(f"[Chat] Attempting WebSocket connection to {ws_url}", file=sys.stderr)
            return True

        except Exception as e:
            print(f"[Chat] WebSocket connection failed: {e}", file=sys.stderr)
            return False

    def websocket_listen(self):
        """Run WebSocket event loop"""
        try:
            self.ws.run_forever()
        except Exception as e:
            print(f"[Chat] WebSocket error: {e}", file=sys.stderr)
            self.ws_connected = False

    def on_ws_open(self, ws):
        """WebSocket connection opened"""
        self.ws_connected = True
        self.ws_reconnect_attempts = 0
        self.reconnect_delay = 1
        print(f"[Chat] WebSocket connected", file=sys.stderr)

    def on_ws_message(self, ws, message):
        """Handle incoming WebSocket message"""
        try:
            msg_data = json.loads(message)
            self.display_message(msg_data)

        except json.JSONDecodeError as e:
            print(f"[Chat] Invalid WebSocket message: {e}", file=sys.stderr)
        except Exception as e:
            print(f"[Chat] Message handling error: {e}", file=sys.stderr)

    def on_ws_error(self, ws, error):
        """WebSocket error handler"""
        print(f"[Chat] WebSocket error: {error}", file=sys.stderr)
        self.ws_connected = False

    def on_ws_close(self, ws, close_status_code, close_msg):
        """WebSocket connection closed"""
        self.ws_connected = False
        if not self.should_exit:
            print(f"[Chat] WebSocket disconnected (code: {close_status_code}), will retry", file=sys.stderr)
            # Implement exponential backoff
            if self.ws_reconnect_attempts < self.max_reconnect_attempts:
                self.ws_reconnect_attempts += 1
                self.reconnect_delay = min(self.reconnect_delay * 2, 30)  # Max 30 seconds
                time.sleep(self.reconnect_delay)

    def http_polling_fallback(self):
        """Fallback to HTTP polling when WebSocket is unavailable"""
        print(f"[Chat] Using HTTP polling fallback", file=sys.stderr)

        while not self.should_exit and not self.ws_connected:
            try:
                headers = {}
                if self.auth_token:
                    headers["X-Auth-Token"] = self.auth_token

                resp = requests.get(
                    f"{self.gateway_url}/inbox/{self.user_id}",
                    headers=headers,
                    timeout=1
                )

                if resp.status_code == 200:
                    messages = resp.json()
                    for msg in messages:
                        self.display_message(msg)
                elif resp.status_code not in [404, 401]:
                    print(f"[Chat] Gateway inbox poll failed: {resp.status_code}", file=sys.stderr)

                time.sleep(POLL_INTERVAL)

                # Periodically retry WebSocket connection
                if self.ws_reconnect_attempts < self.max_reconnect_attempts:
                    time.sleep(5)  # Try WebSocket again every 5 seconds
                    break  # Exit fallback to retry WebSocket

            except requests.exceptions.RequestException as e:
                print(f"[Chat] Gateway polling error: {e}", file=sys.stderr)
                time.sleep(1)

    def display_message(self, msg_data):
        """Display incoming message with timestamp and formatting"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        from_agent = msg_data.get('from', 'unknown')
        content = msg_data.get('content', '')

        # Format different message types
        if from_agent == 'human':
            return  # Don't display our own messages

        if from_agent == 'system':
            print(f"[{timestamp}] SYSTEM: {content}")
        else:
            print(f"[{timestamp}] {from_agent}: {content}")

    def send_message(self, content, to="broadcast"):
        """Send message to gateway"""
        try:
            headers = {"Content-Type": "application/json"}
            if self.auth_token:
                headers["X-Auth-Token"] = self.auth_token

            message_data = {
                "from": self.user_id,
                "to": to,
                "content": content,
                "timestamp": datetime.now().isoformat()
            }

            response = requests.post(
                f"{self.gateway_url}/message",
                json=message_data,
                headers=headers,
                timeout=5
            )

            if response.status_code not in [200, 201]:
                print(f"Failed to send message: {response.status_code} - {response.text}", file=sys.stderr)

        except Exception as e:
            print(f"Error sending message: {e}", file=sys.stderr)

    def parse_message(self, user_input):
        """Parse user input for @mentions and return (content, target)"""
        user_input = user_input.strip()

        if user_input.startswith('@'):
            # Extract target agent
            parts = user_input[1:].split(' ', 1)
            target = parts[0].lower()
            content = parts[1] if len(parts) > 1 else ""

            # Handle special cases
            if target == 'all':
                return content, "broadcast"
            else:
                return content, target
        else:
            # No specific target, broadcast to all
            return user_input, "broadcast"

    def gateway_listener(self):
        """Background thread to listen for incoming messages"""
        while not self.should_exit:
            # Try WebSocket first, fall back to HTTP polling
            if self.try_websocket_connection():
                self.websocket_listen()
            else:
                self.http_polling_fallback()

        print("[Chat] Gateway listener thread exiting", file=sys.stderr)

    def run(self):
        """Main chat controller loop"""
        self.setup_signal_handlers()

        # Register with gateway
        if not self.register_user():
            print("Failed to register with gateway", file=sys.stderr)
            return 1

        # Start background listener thread
        listener_thread = threading.Thread(target=self.gateway_listener, daemon=True)
        listener_thread.start()

        # Print usage instructions
        print("\nCSP Group Chat Controller")
        print("Commands:")
        print("  @all <message>     - Send to all agents")
        print("  @agent <message>   - Send to specific agent")
        print("  <message>          - Send to all agents")
        print("  /quit or Ctrl+C    - Exit")
        print("=" * 50)

        # Main chat input loop
        try:
            while not self.should_exit:
                try:
                    user_input = input(">>> ").strip()

                    if not user_input:
                        continue

                    if user_input.lower() in ['/quit', '/exit', '/q']:
                        break

                    content, target = self.parse_message(user_input)
                    if content:
                        self.send_message(content, target)

                except EOFError:
                    break
                except KeyboardInterrupt:
                    break

        except Exception as e:
            print(f"Unexpected error: {e}", file=sys.stderr)

        finally:
            self.should_exit = True
            if self.ws:
                self.ws.close()
            # Wait for listener thread
            if listener_thread.is_alive():
                listener_thread.join(timeout=2)

        return 0


def main():
    parser = argparse.ArgumentParser(description="CSP Chat Controller")
    parser.add_argument("--gateway-url", default=GATEWAY_URL,
                       help=f"Gateway URL (default: {GATEWAY_URL})")
    parser.add_argument("--auth-token",
                       help="Authentication token for gateway")

    args = parser.parse_args()

    # Use environment variables if available
    gateway_url = args.gateway_url
    if 'CSP_GATEWAY_URL' in os.environ:
        gateway_url = os.environ['CSP_GATEWAY_URL']

    auth_token = args.auth_token
    if 'CSP_AUTH_TOKEN' in os.environ:
        auth_token = os.environ['CSP_AUTH_TOKEN']

    controller = CSPChatController(gateway_url=gateway_url, auth_token=auth_token)
    return controller.run()


if __name__ == "__main__":
    import os
    sys.exit(main())