#!/usr/bin/env python3
"""
CSP Sidecar - Robust PTY Proxy Implementation (CSP v2)

This script replaces the brittle `script -q` approach. 
It acts as a Man-in-the-Middle between the User (or Gateway) and the Native CLI Agent.

Features:
1. PTY Master/Slave separation (Preserves visual state, spinners, colors).
2. Intercepts STDOUT to stream to Gateway.
3. Intercepts STDIN to allow Gateway to inject messages.
4. Graceful signal handling (SIGWINCH).
"""

import os
import pty
import select
import sys
import termios
import tty
import fcntl
import struct
import signal
import threading
import time
import requests  # type: ignore[import-untyped]
import json
import argparse
import collections
import re
import websocket  # type: ignore[import-untyped]
import urllib.parse
import subprocess
import shutil
from datetime import datetime

# Configuration
GATEWAY_URL = "http://localhost:8765"
POLL_INTERVAL = 0.1
STREAM_FLUSH_INTERVAL = 0.2  # seconds
STREAM_CHUNK_THRESHOLD = 512  # characters
STREAM_MAX_BUFFER = 8192      # characters
INJECTION_TIMEOUT = float(os.environ.get('CSP_INJECTION_TIMEOUT', '0.5'))  # seconds, configurable


class AgentCommandProcessor:
    """Intercepts and handles @-commands in agent output (Phase 2 feature)"""

    def __init__(self, agent_id, gateway_url, auth_token):
        self.agent_id = agent_id
        self.gateway_url = gateway_url
        self.auth_token = auth_token
        # Command pattern: @command.subcommand args... or @agent_name message
        self.command_patterns = [
            re.compile(r'@query\.log(?:\s+(\d+))?(?:\s+from=([^\s]+))?(?:\s+to=([^\s]+))?'),  # @query.log [limit] [from=X] [to=Y]
            re.compile(r'@send\.([\w-]+)\s+(.+)'),  # @send.agent-name message (allows dashes)
            re.compile(r'@all\s+(.+)'),  # @all message
        ]
        # Orchestrator command patterns (Phase 6)
        self.mode_set_pattern = re.compile(
            r'@mode\.set\s+(\w+)\s+"([^"]+)"(?:\s+--rounds\s+(\d+))?'
        )
        self.mode_status_pattern = re.compile(r'@mode\.status')
        # S3: NOOP command for orchestrator heartbeat responses
        self.noop_pattern = re.compile(r'^NOOP\s*$', re.IGNORECASE)
        # Turn timeout extension (explicit command only)
        self.working_at_pattern = re.compile(r'^\s*@working\b(.*)$', re.IGNORECASE)
        self.working_bare_pattern = re.compile(r'^\s*WORKING\b(.*)$')

    def detect_commands(self, text: str) -> list:
        """Detect all @-commands in text. Returns list of (command_type, args)"""
        commands = []
        lines = text.split('\n')

        for line in lines:
            # Check for @query.log
            match = self.command_patterns[0].search(line)
            if match:
                limit = int(match.group(1)) if match.group(1) else 50
                from_agent = match.group(2)
                to_agent = match.group(3)
                commands.append(('query_log', {'limit': limit, 'from': from_agent, 'to': to_agent}))
                continue

            # Check for @send.agent_name
            match = self.command_patterns[1].search(line)
            if match:
                target_agent = match.group(1)
                message = match.group(2).strip()
                commands.append(('send_agent', {'target': target_agent, 'message': message}))
                continue

            # Check for @all
            match = self.command_patterns[2].search(line)
            if match:
                message = match.group(1).strip()
                commands.append(('send_all', {'message': message}))
                continue

            # Check for @mode.set (orchestrator command)
            match = self.mode_set_pattern.search(line)
            if match:
                mode = match.group(1)
                topic = match.group(2)
                rounds = int(match.group(3)) if match.group(3) else 3
                commands.append(('mode_set', {'mode': mode, 'topic': topic, 'rounds': rounds}))
                continue

            # Check for @mode.status (orchestrator command)
            match = self.mode_status_pattern.search(line)
            if match:
                commands.append(('mode_status', {}))
                continue

            # S3: Check for NOOP (orchestrator heartbeat response)
            match = self.noop_pattern.search(line)
            if match:
                commands.append(('noop', {}))
                continue

            # Turn timeout extension
            match = self.working_at_pattern.search(line)
            if not match:
                match = self.working_bare_pattern.search(line)
            if match:
                note = match.group(1).strip()
                commands.append(('working', {'note': note}))
                continue

        return commands

    def execute_command(self, command_type: str, args: dict) -> str:
        """Execute a detected command and return formatted result"""
        try:
            if command_type == 'query_log':
                return self._execute_query_log(args)
            elif command_type == 'send_agent':
                return self._execute_send_agent(args)
            elif command_type == 'send_all':
                return self._execute_send_all(args)
            elif command_type == 'mode_set':
                return self._execute_mode_set(args)
            elif command_type == 'mode_status':
                return self._execute_mode_status(args)
            elif command_type == 'noop':
                # S3: NOOP is a valid no-action command for orchestrator heartbeats
                return "[CSP: NOOP acknowledged]"
            elif command_type == 'working':
                return self._execute_working(args)
            else:
                return f"[CSP: Unknown command type: {command_type}]"
        except Exception as e:
            return f"[CSP Error: {str(e)}]"

    def _execute_query_log(self, args: dict) -> str:
        """Query chat history from gateway"""
        try:
            params = {'limit': args.get('limit', 50)}
            if args.get('from'):
                params['from'] = args['from']
            if args.get('to'):
                params['to'] = args['to']

            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}
            response = requests.get(
                f"{self.gateway_url}/history",
                params=params,
                headers=headers,
                timeout=2
            )

            if response.status_code == 200:
                data = response.json()
                messages = data.get('messages', [])

                if not messages:
                    return "[CSP: No messages in history]"

                result = "[CSP: Recent messages]\n"
                for msg in messages:
                    time_str = datetime.fromisoformat(msg['timestamp']).strftime('%H:%M:%S')
                    sender = msg.get('from', 'unknown')
                    recipient = msg.get('to', 'broadcast')
                    content = msg.get('content', '')[:100]  # Truncate long messages
                    result += f"[{time_str}] {sender}: {content}\n"

                return result.rstrip()
            else:
                return f"[CSP: History query failed ({response.status_code})]"
        except requests.exceptions.Timeout:
            return "[CSP: History query timeout]"
        except Exception as e:
            return f"[CSP: History query error - {str(e)}]"

    def _execute_send_agent(self, args: dict) -> str:
        """Send message to specific agent"""
        try:
            target = args.get('target')
            message = args.get('message', '')

            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}
            payload = {
                'from': self.agent_id,
                'to': target,
                'content': message
            }

            response = requests.post(
                f"{self.gateway_url}/message",
                json=payload,
                headers=headers,
                timeout=2
            )

            if response.status_code in [200, 201]:
                return f"[CSP: Message sent to {target}]"
            else:
                return f"[CSP: Send failed ({response.status_code})]"
        except Exception as e:
            return f"[CSP: Send error - {str(e)}]"

    def _execute_send_all(self, args: dict) -> str:
        """Send message to all agents"""
        try:
            message = args.get('message', '')

            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}
            payload = {
                'from': self.agent_id,
                'to': 'broadcast',
                'content': message
            }

            response = requests.post(
                f"{self.gateway_url}/message",
                json=payload,
                headers=headers,
                timeout=2
            )

            if response.status_code in [200, 201]:
                return "[CSP: Message broadcast to all agents]"
            else:
                return f"[CSP: Broadcast failed ({response.status_code})]"
        except Exception as e:
            return f"[CSP: Broadcast error - {str(e)}]"

    def _execute_mode_set(self, args: dict) -> str:
        """Set orchestration mode (orchestrator command)"""
        try:
            mode = args.get('mode', 'freeform')
            topic = args.get('topic', '')
            rounds = args.get('rounds', 3)

            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}

            # Get list of connected agents (excluding Human)
            agents_response = requests.get(
                f"{self.gateway_url}/agents",
                headers=headers,
                timeout=2
            )

            agent_ids = []
            if agents_response.status_code == 200:
                agents = agents_response.json()
                agent_ids = [a['id'] for a in agents if a['id'] != 'Human' and a['id'] != self.agent_id]

            # Set the mode
            payload = {
                'mode': mode,
                'topic': topic,
                'rounds': rounds,
                'agents': agent_ids
            }

            response = requests.post(
                f"{self.gateway_url}/mode",
                json=payload,
                headers=headers,
                timeout=2
            )

            if response.status_code in [200, 201]:
                return f"[CSP: Mode set to {mode.upper()} - Topic: {topic}]"
            else:
                error = response.json().get('error', 'Unknown error')
                return f"[CSP: Mode set failed - {error}]"
        except Exception as e:
            return f"[CSP: Mode set error - {str(e)}]"

    def _execute_mode_status(self, args: dict) -> str:
        """Get current orchestration mode status (orchestrator command)"""
        try:
            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}

            response = requests.get(
                f"{self.gateway_url}/mode",
                headers=headers,
                timeout=2
            )

            if response.status_code == 200:
                data = response.json()
                mode = data.get('mode', 'freeform')
                topic = data.get('topic', 'N/A')
                round_num = data.get('round', 0) + 1
                max_rounds = data.get('maxRounds', 3)
                turn_order = data.get('turnOrder', [])
                current_idx = data.get('currentTurnIndex', 0)
                current_turn = turn_order[current_idx] if turn_order and current_idx < len(turn_order) else 'N/A'

                if mode == 'freeform':
                    return "[CSP: Mode=FREEFORM (no structured collaboration active)]"
                else:
                    return f"[CSP: Mode={mode.upper()}, Topic={topic}, Round={round_num}/{max_rounds}, CurrentTurn={current_turn}]"
            else:
                return f"[CSP: Status query failed ({response.status_code})]"
        except Exception as e:
            return f"[CSP: Status query error - {str(e)}]"

    def _execute_working(self, args: dict) -> str:
        """Send a working signal to extend the current turn timeout."""
        try:
            note = (args.get('note') or '').strip()
            content = "WORKING" if not note else f"WORKING {note}"

            headers = {'X-Auth-Token': self.auth_token} if self.auth_token else {}
            payload = {
                "from": self.agent_id,
                "to": "broadcast",
                "content": content
            }

            response = requests.post(
                f"{self.gateway_url}/message",
                json=payload,
                headers=headers,
                timeout=2
            )

            if response.status_code == 200:
                return "[CSP: Working acknowledged]"
            return f"[CSP: Working signal failed ({response.status_code})]"
        except Exception as e:
            return f"[CSP: Working signal error - {str(e)}]"


class StreamCleaner:
    """Stateful ANSI stripper that tolerates chunked sequences."""
    def __init__(self):
        self.in_ansi = False
        self.ansi_buf = []

    def process(self, data: bytes) -> str:
        out = []
        for b in data:
            if not self.in_ansi:
                if b == 0x1B:  # ESC
                    self.in_ansi = True
                    self.ansi_buf = [b]
                    continue
                out.append(b)
            else:
                self.ansi_buf.append(b)
                # Final bytes for ANSI sequences are in 0x40..0x7E
                if 0x40 <= b <= 0x7E:
                    self.in_ansi = False
                    self.ansi_buf = []
        try:
            return bytes(out).decode('utf-8', errors='ignore')
        except Exception:
            return ""


class FlowController:
    """Controls when to inject messages to avoid corrupting active CLI sessions."""

    def __init__(self, min_silence=0.3, long_silence=2.0, max_queue=50):
        self.min_silence = min_silence
        self.long_silence = long_silence
        self.max_queue = max_queue
        self.urgent_queue = collections.deque()
        self.normal_queue = collections.deque()
        self.last_output_ts = time.time()
        self.recent_buffer = b""
        # Regex prompt patterns
        self.prompt_patterns = [
            re.compile(r'.*[>$#]\s*$'),
            re.compile(r'.*\?\s*$'),
            re.compile(r'.*:\s*$'),
            re.compile(r'.*\[y/n\]\s*$'),
            re.compile(r'Press.*to continue.*$')
        ]

    def on_output(self, data: bytes):
        """Called whenever output arrives from the agent."""
        self.last_output_ts = time.time()
        self.recent_buffer += data
        if len(self.recent_buffer) > 200:
            self.recent_buffer = self.recent_buffer[-200:]

    def is_idle(self) -> bool:
        """Time + tail heuristic to decide if it is safe to inject."""
        silence = time.time() - self.last_output_ts

        # Fast path: too recent => not idle
        if silence < self.min_silence:
            return False

        # Long silence fallback
        if silence > self.long_silence:
            return True

        # Prompt/tail detection
        tail_str = self.recent_buffer.decode('utf-8', errors='ignore')
        for pattern in self.prompt_patterns:
            if pattern.search(tail_str):
                return True

        return False

    def enqueue(self, sender: str, content: str, priority: str = "normal"):
        msg = {"sender": sender, "content": content, "timestamp": time.time()}

        if priority == "urgent":
            queue = self.urgent_queue
        else:
            queue = self.normal_queue

        if len(queue) >= self.max_queue:
            # Drop oldest non-urgent when overflowing
            dropped = queue.popleft()
            sys.stderr.write(f"\r\033[91m[CSP: Queue overflow, dropped message from {dropped['sender']}]\033[0m\n")

        queue.append(msg)

        # Ghost log for the human (stderr only)
        sys.stderr.write(f"\r\033[90m[CSP: {len(self.urgent_queue)+len(self.normal_queue)} queued, waiting]\033[0m")
        sys.stderr.flush()

    def pop_ready(self):
        # Drop stale (>5 minutes)
        cutoff = time.time() - 300
        for queue in (self.urgent_queue, self.normal_queue):
            while queue and queue[0].get("timestamp", 0) < cutoff:
                dropped = queue.popleft()
                sys.stderr.write(f"\r\033[93m[CSP: Dropped stale message from {dropped['sender']}]\033[0m\n")

        for queue in (self.urgent_queue, self.normal_queue):
            if queue:
                sys.stderr.write("\r\033[K")
                sys.stderr.flush()
                return queue.popleft()
        return None

class CSPSidecar:
    def __init__(self, cmd, agent_name, gateway_url=GATEWAY_URL, initial_prompt=None, auth_token=None):
        self.cmd = cmd
        self.agent_name = agent_name
        self.gateway_url = gateway_url
        self.initial_prompt = initial_prompt
        self.auth_token = auth_token
        self.master_fd = None
        self.should_exit = False
        self.agent_id = None
        self.cleaner = StreamCleaner()
        self.stream_buffer = ""
        self.last_flush_time = time.time()
        self.paused = False
        self.pending_msgs = []
        # WebSocket connection management
        self.ws = None
        self.ws_connected = False
        self.ws_reconnect_attempts = 0
        self.max_reconnect_attempts = 5
        self.reconnect_delay = 1  # Start with 1 second
        # Agent-specific flow tuning
        lower_name = self.agent_name.lower()
        if 'claude' in lower_name:
            self.flow = FlowController(min_silence=0.5, long_silence=3.0)
        elif 'codex' in lower_name:
            self.flow = FlowController(min_silence=0.2, long_silence=2.0)
        else:
            self.flow = FlowController()
        # Disable output streaming by default - TUI apps like Claude Code
        # produce too much screen refresh garbage that floods the chat.
        # Communication is ONE-WAY: Human → Agents (message injection only)
        self.share_enabled = False
        # Phase 2: Agent command processor (will be initialized after agent_id is set)
        self.command_processor = None
        # S1: Orchestrator detection - used for special handling of heartbeat context
        self.is_orchestrator = 'orchestrator' in self.agent_name.lower()
        
    def register_agent(self):
        """Register this agent with the gateway"""
        if not self.auth_token:
            print("Error: No auth token provided - gateway requires authentication", file=sys.stderr)
            return False

        # Normalize agent name: lowercase, spaces to dashes, keep full name (no truncation)
        requested_id = self.agent_name.lower().replace(' ', '-')

        headers = {"X-Auth-Token": self.auth_token}

        try:
            response = requests.post(
                f"{self.gateway_url}/register",
                json={
                    "agentId": requested_id,
                    "capabilities": {"chat": True, "respond": True}
                },
                headers=headers,
                timeout=5
            )

            if response.status_code in [200, 201]:
                data = response.json()
                # Use gateway-assigned ID (may differ if duplicates exist, e.g., claude-2)
                self.agent_id = data.get('agentId', requested_id)
                print(f"Successfully registered as agent {self.agent_id}", file=sys.stderr)
                # Initialize command processor now that we have agent_id
                self.command_processor = AgentCommandProcessor(
                    self.agent_id,
                    self.gateway_url,
                    self.auth_token
                )
                return True
            else:
                print(f"Registration failed: {response.status_code} - {response.text}", file=sys.stderr)
                return False
        except Exception as e:
            print(f"Registration error: {e}", file=sys.stderr)
            return False

    def run(self):
        # Save original tty settings
        try:
            old_tty = termios.tcgetattr(sys.stdin)
        except (termios.error, OSError):
            old_tty = None

        # Register with gateway first
        if not self.register_agent():
            print("Warning: Failed to register with gateway, continuing in standalone mode", file=sys.stderr)

        # Fork process
        pid, self.master_fd = pty.fork()

        if pid == 0:
            # CHILD PROCESS (The Agent)
            # execute the command
            os.execvp(self.cmd[0], self.cmd)
        else:
            # PARENT PROCESS (The Sidecar)
            self.setup_signal_handlers()

            # Inject system prompt if configured
            if self.initial_prompt:
                # Give the process a moment to initialize
                time.sleep(0.5)
                os.write(self.master_fd, f"{self.initial_prompt}\n".encode('utf-8'))

            # Start background thread to poll gateway for incoming messages
            if self.agent_id:
                self._listener_thread = threading.Thread(target=self.gateway_listener, daemon=True)
                self._listener_thread.start()

            try:
                if old_tty:
                    tty.setraw(sys.stdin.fileno())
                self.loop(pid)
            except OSError:
                pass # Child exited
            except KeyboardInterrupt:
                print("\nReceived interrupt, shutting down...", file=sys.stderr)
                self.should_exit = True
            finally:
                # Cleanup sequence
                self.should_exit = True

                # Final stream flush
                self.maybe_flush_stream(force=True)

                # Wait for listener thread to exit
                if hasattr(self, '_listener_thread') and self._listener_thread.is_alive():
                    self._listener_thread.join(timeout=2)
                    if self._listener_thread.is_alive():
                        print("Warning: Listener thread did not exit cleanly", file=sys.stderr)

                # Close PTY master
                if self.master_fd is not None:
                    try:
                        os.close(self.master_fd)
                    except OSError:
                        pass
                    self.master_fd = None

                # Restore TTY settings
                if old_tty:
                    try:
                        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
                    except (termios.error, OSError):
                        pass  # TTY may already be gone

                # Clean up agent registration
                self.unregister_agent()

                # Final child cleanup
                try:
                    os.waitpid(pid, 0)  # Final wait for child
                except OSError:
                    pass  # Already reaped

    def set_winsize(self):
        """Propagate window size changes to child"""
        if not self.master_fd: return
        try:
            rows, cols, x, y = struct.unpack('HHHH', fcntl.ioctl(sys.stdin, termios.TIOCGWINSZ, struct.pack('HHHH', 0, 0, 0, 0)))
            fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, x, y))
        except (OSError, IOError):
            pass  # Window size not available

    def setup_signal_handlers(self):
        signal.signal(signal.SIGWINCH, lambda s, f: self.set_winsize())
        self.set_winsize()

    def loop(self, child_pid):
        stdin_fd = sys.stdin.fileno() if sys.stdin.isatty() else -1

        while not self.should_exit:
            # Check if child process is still alive
            try:
                pid, status = os.waitpid(child_pid, os.WNOHANG)
                if pid != 0:  # Child exited
                    print(f"\nChild process exited with status {status}", file=sys.stderr)
                    self.should_exit = True
                    break
            except OSError:
                # Child already reaped or other error
                self.should_exit = True
                break

            # Set up file descriptors for select
            read_fds = [self.master_fd]
            if stdin_fd >= 0:
                read_fds.append(stdin_fd)

            try:
                r, _, _ = select.select(read_fds, [], [], 0.1)  # 100ms timeout
            except OSError:
                break # Interrupted system call

            if self.master_fd is not None and self.master_fd in r:
                # Data from Agent -> User
                try:
                    data = os.read(self.master_fd, 1024)
                except OSError:
                    break

                if not data:
                    break

                # 1. Forward to real stdout
                os.write(sys.stdout.fileno(), data)
                # 1b. Update flow controller with fresh output
                self.flow.on_output(data)

                # 2. Adaptive chunking for Gateway + Phase 2: Command detection
                clean_chunk = self.cleaner.process(data)
                if clean_chunk:
                    # Phase 2: Check for @-commands in agent output
                    if self.command_processor:
                        commands = self.command_processor.detect_commands(clean_chunk)
                        for cmd_type, cmd_args in commands:
                            # Execute the command
                            result = self.command_processor.execute_command(cmd_type, cmd_args)
                            # Inject result back to agent with slight delay to avoid buffer issues
                            self.flow.enqueue('CSP', result, priority='normal')
                            print(f"[CSP] Detected {cmd_type} command, enqueued response", file=sys.stderr)

                    self.stream_buffer += clean_chunk
                    boundary = ('\n' in clean_chunk) or ('. ' in clean_chunk)
                    self.maybe_flush_stream(boundary=boundary)

            if stdin_fd in r:
                # Data from User -> Agent
                try:
                    data = os.read(stdin_fd, 1024)
                except OSError:
                    break

                if not data:
                    break

                # 1. Forward to Agent
                if self.master_fd is not None:
                    os.write(self.master_fd, data)

                # 2. Optional: Log to Gateway (so others see what Human typed)
                # self.send_to_gateway({"type": "human_input", "content": data.decode('utf-8', errors='ignore')})

            # Opportunistically deliver queued messages when idle and not paused
            if not self.paused and self.flow.is_idle():
                ready = self.flow.pop_ready()
                if ready:
                    self._write_injection(ready['sender'], ready['content'])

    def maybe_flush_stream(self, boundary: bool = False, force: bool = False):
        """Decide when to flush based on time, size, or detected boundaries."""
        now = time.time()

        if force:
            self.flush_stream()
            return

        if len(self.stream_buffer) >= STREAM_MAX_BUFFER:
            self.flush_stream()
            return

        if boundary or len(self.stream_buffer) >= STREAM_CHUNK_THRESHOLD or (now - self.last_flush_time) >= STREAM_FLUSH_INTERVAL:
            self.flush_stream()

    def flush_stream(self):
        """Send buffered clean text to the gateway with auth."""
        # Only share if explicitly enabled by an inbound message
        if not self.share_enabled:
            self.stream_buffer = ""
            self.last_flush_time = time.time()
            return

        if not self.stream_buffer or not self.agent_id:
            self.last_flush_time = time.time()
            return

        cleaned = self._sanitize_stream(self.stream_buffer)
        if not cleaned or len(cleaned.strip()) < 10:
            self.stream_buffer = ""
            self.last_flush_time = time.time()
            return

        # Require a minimum signal-to-noise ratio (printables)
        printable_chars = sum(ch.isalnum() for ch in cleaned)
        if printable_chars == 0 or (printable_chars / max(len(cleaned), 1)) < 0.3:
            self.stream_buffer = ""
            self.last_flush_time = time.time()
            return

        headers = {}
        if self.auth_token:
            headers["X-Auth-Token"] = self.auth_token

        payload = {
            "from": self.agent_id,
            "to": "broadcast",
            "content": cleaned
        }

        try:
            response = requests.post(
                f"{self.gateway_url}/agent-output",
                json=payload,
                headers=headers,
                timeout=0.2
            )
            if response.status_code not in [200, 201]:
                print(f"Gateway output failed: {response.status_code}", file=sys.stderr)
        except requests.exceptions.RequestException as e:
            print(f"Gateway communication error: {e}", file=sys.stderr)
        except Exception as e:
            print(f"Unexpected error in flush_stream: {e}", file=sys.stderr)
        finally:
            self.stream_buffer = ""
            self.last_flush_time = time.time()
            # Keep sharing enabled for continuous communication

    def _sanitize_stream(self, text: str) -> str:
        """
        Remove ANSI escape sequences and control characters from terminal output.
        Handles complete CSI sequences and orphaned fragments from TUI apps.
        """
        # 1. Strip complete ANSI CSI sequences: ESC [ <params> <final>
        text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)

        # 2. Strip complete OSC sequences: ESC ] ... (BEL or ESC \)
        text = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?', '', text)

        # 3. Strip orphaned CSI parameters (no ESC prefix, leaked after ESC stripping)
        # These are cursor/erase commands: A-H, J, K, S, T, f, m, s, u
        # CONSERVATIVE: Only strip patterns with semicolons (definitely CSI params)
        # This avoids false positives like "3m" (3 meters) or "10K" (10 thousand)
        # Examples matched: "31;2H", "1;31m", ";0m" (but NOT "3m", "31m", "2J" alone)
        text = re.sub(r'(?<![a-zA-Z\x1b])\d*;\d*[A-HJKSTfmsu](?![a-zA-Z])', '', text)

        # 4. Strip DEC private modes: ?NNNNh or ?NNNNl
        text = re.sub(r'\?\d+[hl]', '', text)

        # 5. Strip remaining standalone escape character
        text = re.sub(r'\x1b', '', text)

        # 6. Strip other control characters (except newline, tab)
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)

        # 7. Collapse excessive whitespace
        text = re.sub(r'[ \t]+', ' ', text)
        text = re.sub(r'\n{3,}', '\n\n', text)

        return text.strip()

    def gateway_listener(self):
        """WebSocket subscription with HTTP polling fallback"""
        while not self.should_exit:
            # Try WebSocket first, fall back to HTTP polling
            if self.try_websocket_connection():
                self.websocket_listen()
            else:
                self.http_polling_fallback()

        print("Gateway listener thread exiting", file=sys.stderr)

    def try_websocket_connection(self):
        """Attempt to establish WebSocket connection"""
        if self.ws_connected or not self.agent_id:
            return self.ws_connected

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

            print(f"[CSP] Attempting WebSocket connection to {ws_url}", file=sys.stderr)
            return True

        except Exception as e:
            print(f"[CSP] WebSocket connection failed: {e}", file=sys.stderr)
            return False

    def websocket_listen(self):
        """Run WebSocket event loop"""
        try:
            if self.ws is not None:
                self.ws.run_forever()
        except Exception as e:
            print(f"[CSP] WebSocket error: {e}", file=sys.stderr)
            self.ws_connected = False

    def on_ws_open(self, ws):
        """WebSocket connection opened"""
        self.ws_connected = True
        self.ws_reconnect_attempts = 0
        self.reconnect_delay = 1
        print(f"[CSP] WebSocket connected for agent {self.agent_id}", file=sys.stderr)

    def on_ws_message(self, ws, message):
        """Handle incoming WebSocket message"""
        try:
            msg_data = json.loads(message)

            # Filter messages for this agent
            to = msg_data.get('to', '')
            if to == self.agent_id or to == 'broadcast':
                if not self.should_exit:
                    self.inject_message(msg_data)

        except json.JSONDecodeError as e:
            print(f"[CSP] Invalid WebSocket message: {e}", file=sys.stderr)
        except Exception as e:
            print(f"[CSP] WebSocket message handling error: {e}", file=sys.stderr)

    def on_ws_error(self, ws, error):
        """WebSocket error handler"""
        print(f"[CSP] WebSocket error: {error}", file=sys.stderr)
        self.ws_connected = False

    def on_ws_close(self, ws, close_status_code, close_msg):
        """WebSocket connection closed"""
        self.ws_connected = False
        if not self.should_exit:
            print(f"[CSP] WebSocket disconnected (code: {close_status_code}), will retry", file=sys.stderr)
            # Implement exponential backoff capped at 10s
            if self.ws_reconnect_attempts < self.max_reconnect_attempts:
                self.ws_reconnect_attempts += 1
                self.reconnect_delay = min(self.reconnect_delay * 2, 10)  # Max 10 seconds
                time.sleep(self.reconnect_delay)

    def http_polling_fallback(self):
        """Fallback to HTTP polling when WebSocket is unavailable"""
        print(f"[CSP] Using HTTP polling fallback for agent {self.agent_id}", file=sys.stderr)

        while not self.should_exit and not self.ws_connected:
            try:
                if self.agent_id:
                    headers = {}
                    if self.auth_token:
                        headers["X-Auth-Token"] = self.auth_token

                    resp = requests.get(
                        f"{self.gateway_url}/inbox/{self.agent_id}",
                        headers=headers,
                        timeout=1
                    )
                    if resp.status_code == 200:
                        messages = resp.json()
                        for msg in messages:
                            if not self.should_exit:
                                self.inject_message(msg)
                    elif resp.status_code not in [404, 401]:
                        print(f"Gateway inbox poll failed: {resp.status_code}", file=sys.stderr)

                time.sleep(POLL_INTERVAL)

                # Periodically retry WebSocket connection
                if self.ws_reconnect_attempts < self.max_reconnect_attempts:
                    time.sleep(5)  # Try WebSocket again every 5 seconds
                    break  # Exit fallback to retry WebSocket

            except requests.exceptions.RequestException as e:
                print(f"Gateway polling error: {e}", file=sys.stderr)
                time.sleep(1)
            except Exception as e:
                print(f"Unexpected error in http_polling_fallback: {e}", file=sys.stderr)
                time.sleep(1)

    def inject_message(self, msg_obj):
        """Inject a message into the Agent's stdin as if the user typed it"""
        if not self.master_fd:
            return

        sender = msg_obj.get('from', 'Unknown') # Gateway sends 'from' field
        content = msg_obj.get('content', '')
        turn_signal = msg_obj.get('turnSignal')  # 'your_turn' | 'turn_wait' | None
        current_turn = msg_obj.get('currentTurn')  # Who currently has the turn

        # S2: Extract heartbeat context if present (orchestrator only)
        # Format as single line for TUI compatibility
        context = msg_obj.get('context')
        if context and self.is_orchestrator:
            mode = context.get('mode', 'freeform')
            round_num = context.get('round', 0) + 1
            max_rounds = context.get('maxRounds', 3)
            current = context.get('currentTurn', 'N/A')
            elapsed = context.get('elapsed', 0) / 1000

            # Compact single-line format for TUI apps
            context_str = f"[STATE: {mode} R{round_num}/{max_rounds} Turn={current} {elapsed:.0f}s] "
            content = context_str + content

        # FIXED: Do NOT auto-enable sharing - it causes feedback loops with TUI apps
        # Output sharing is ONE-WAY by design: Human → Agents only
        # Use /share command to explicitly enable if needed
        # self.share_enabled = True  # DISABLED - was causing ANSI spam flood

        # Handle turn signals (soft enforcement - always inject, but notify)
        # For broadcasts, turnSignal is null - derive from currentTurn instead
        if turn_signal == 'your_turn':
            print(f"\n[CSP] YOUR TURN - You are the active agent", file=sys.stderr)
        elif turn_signal == 'turn_wait':
            print(f"\n[CSP] WAITING (current turn: {current_turn or 'unknown'})", file=sys.stderr)
        elif turn_signal is None and current_turn is not None:
            # Broadcast message - derive turn status from currentTurn field
            if current_turn.lower() == self.agent_id.lower():
                turn_signal = 'your_turn'
                print(f"\n[CSP] YOUR TURN - You are the active agent", file=sys.stderr)
            elif current_turn:
                turn_signal = 'turn_wait'
                print(f"\n[CSP] WAITING (current turn: {current_turn})", file=sys.stderr)

        # Handle /share and /noshare commands
        if content.strip().lower() == '/share':
            self.share_enabled = True
            print(f"[CSP] Output sharing ENABLED for {self.agent_id}", file=sys.stderr)
            return
        if content.strip().lower() == '/noshare':
            self.share_enabled = False
            print(f"[CSP] Output sharing DISABLED for {self.agent_id}", file=sys.stderr)
            return

        # Control channel: pause/resume
        if self._is_control_pause(content):
            self.paused = True
            print(f"[CSP] Paused injections for {self.agent_id}", file=sys.stderr)
            return
        if self._is_control_resume(content):
            self.paused = False
            print(f"[CSP] Resumed injections for {self.agent_id}", file=sys.stderr)
            # deliver backlog
            while self.pending_msgs:
                pending = self.pending_msgs.pop(0)
                self._write_injection(pending['sender'], pending['content'])
            return

        if self.paused:
            # queue until resume
            self.pending_msgs.append({"sender": sender, "content": content})
            return

        # Urgent bypass (leading "!") always injects
        if content.strip().startswith("!"):
            self._write_injection(sender, content.lstrip("!").strip())
            return

        # Timeout-based flow control: wait for idle, then inject
        # Configurable via CSP_INJECTION_TIMEOUT env var (default 0.5s)
        # This balances safety (not corrupting active CLI) with reliability (messages get delivered)
        max_wait = INJECTION_TIMEOUT
        check_interval = 0.05  # 50ms between checks
        waited = 0.0

        while waited < max_wait:
            if self.flow.is_idle():
                self._write_injection(sender, content, turn_signal)
                return
            time.sleep(check_interval)
            waited += check_interval

        # Timeout reached - inject anyway with warning (TUI apps rarely go idle)
        print(f"[CSP] Warning: injecting message while agent may be busy", file=sys.stderr)
        self._write_injection(sender, content, turn_signal)

    def _write_injection(self, sender, content, turn_signal=None):
        """Write a formatted injection to the agent PTY.

        Strategy: Use tmux send-keys if available (more reliable for TUI apps),
        fall back to PTY master write if not in tmux.
        """
        # Add turn marker if this is a turn signal
        turn_marker = ""
        if turn_signal == 'your_turn':
            turn_marker = "[YOUR TURN] "

        # Format the message
        message = f"{turn_marker}[From {sender}]: {content}"

        # Try tmux send-keys first (more reliable for TUI apps)
        if self._try_tmux_sendkeys(message):
            return

        # Fallback to PTY master write
        if self.master_fd is None:
            print(f"[CSP] Cannot inject: PTY not initialized", file=sys.stderr)
            return

        # Clear line, write message, send Enter
        os.write(self.master_fd, b'\x15')  # Ctrl+U
        time.sleep(0.02)
        os.write(self.master_fd, message.encode('utf-8'))
        time.sleep(0.05)
        os.write(self.master_fd, b'\r')

    def _try_tmux_sendkeys(self, message):
        """Try to inject using tmux send-keys (works better for TUI apps).

        Returns True if successful, False if tmux not available.
        """
        # Check if tmux is available
        if not shutil.which('tmux'):
            return False

        # Check if we're in a tmux session
        tmux_pane = os.environ.get('TMUX_PANE')
        if not tmux_pane:
            return False

        try:
            # Send the message text literally (-l flag)
            subprocess.run(
                ['tmux', 'send-keys', '-t', tmux_pane, '-l', message],
                check=True,
                capture_output=True,
                timeout=2
            )

            # Small delay before Enter
            time.sleep(0.05)

            # Send Enter key (C-m or Enter)
            subprocess.run(
                ['tmux', 'send-keys', '-t', tmux_pane, 'Enter'],
                check=True,
                capture_output=True,
                timeout=2
            )

            print(f"[CSP] Injected via tmux send-keys", file=sys.stderr)
            return True

        except subprocess.SubprocessError as e:
            print(f"[CSP] tmux send-keys failed: {e}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"[CSP] tmux injection error: {e}", file=sys.stderr)
            return False

    def _is_control_pause(self, content: str) -> bool:
        if not content:
            return False
        lower = content.strip().lower()
        return lower.startswith("csp_ctrl:pause") or lower == "/pause"

    def _is_control_resume(self, content: str) -> bool:
        if not content:
            return False
        lower = content.strip().lower()
        return lower.startswith("csp_ctrl:resume") or lower == "/resume"

    def unregister_agent(self):
        """Cleanup agent state on exit"""
        if not self.agent_id:
            return

        print(f"Agent {self.agent_id} shutting down", file=sys.stderr)
        self.should_exit = True

        # Attempt to unregister from gateway
        if self.auth_token:
            try:
                response = requests.delete(
                    f"{self.gateway_url}/agent/{self.agent_id}",
                    headers={"X-Auth-Token": self.auth_token},
                    timeout=2
                )
                if response.status_code == 200:
                    print(f"Successfully unregistered from gateway", file=sys.stderr)
                else:
                    print(f"Gateway unregister failed: {response.status_code}", file=sys.stderr)
            except requests.exceptions.RequestException as e:
                print(f"Gateway unregister error: {e}", file=sys.stderr)
            except Exception as e:
                print(f"Unexpected error in unregister: {e}", file=sys.stderr)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CSP Sidecar Proxy")
    parser.add_argument("--name", required=True, help="Agent Name")
    parser.add_argument("--gateway-url", default=GATEWAY_URL, help="Gateway URL")
    parser.add_argument("--auth-token", help="Authentication token")
    parser.add_argument("--initial-prompt", help="System instructions to inject at startup")
    parser.add_argument("--cmd", required=True, nargs=argparse.REMAINDER, help="Command to run")
    args = parser.parse_args()

    # Filter out '--' if present (argparse.REMAINDER doesn't handle it well)
    cmd = [arg for arg in args.cmd if arg != '--']

    if not cmd:
        print("Error: No command specified")
        sys.exit(1)

    sidecar = CSPSidecar(
        cmd,
        args.name,
        gateway_url=args.gateway_url,
        initial_prompt=args.initial_prompt,
        auth_token=args.auth_token
    )
    sidecar.run()
