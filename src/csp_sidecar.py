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
import requests
import json
import argparse
import collections
import re

# Configuration
GATEWAY_URL = "http://localhost:8765"
POLL_INTERVAL = 0.1
STREAM_FLUSH_INTERVAL = 0.2  # seconds
STREAM_CHUNK_THRESHOLD = 512  # characters
STREAM_MAX_BUFFER = 8192      # characters


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
            re.compile(rb'.*[>$#]\s*$'),
            re.compile(rb'.*\?\s*$'),
            re.compile(rb'.*:\s*$'),
            re.compile(rb'.*\[y/n\]\s*$'),
            re.compile(rb'Press.*to continue.*$')
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
        # Agent-specific flow tuning
        lower_name = self.agent_name.lower()
        if 'claude' in lower_name:
            self.flow = FlowController(min_silence=0.5, long_silence=3.0)
        elif 'codex' in lower_name:
            self.flow = FlowController(min_silence=0.2, long_silence=2.0)
        else:
            self.flow = FlowController()
        
    def register_agent(self):
        """Register this agent with the gateway"""
        if not self.auth_token:
            print("Error: No auth token provided - gateway requires authentication", file=sys.stderr)
            return False

        # Generate unique agent ID
        self.agent_id = f"{self.agent_name.lower().replace(' ', '-')}-{int(time.time())}"

        headers = {"X-Auth-Token": self.auth_token}

        try:
            response = requests.post(
                f"{self.gateway_url}/register",
                json={
                    "agentId": self.agent_id,
                    "capabilities": {"chat": True, "respond": True}
                },
                headers=headers,
                timeout=5
            )

            if response.status_code in [200, 201]:
                data = response.json()
                print(f"Successfully registered as agent {self.agent_id}", file=sys.stderr)
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
        except:
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
                    except:
                        pass

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
        except:
            pass

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

            if self.master_fd in r:
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

                # 2. Adaptive chunking for Gateway
                clean_chunk = self.cleaner.process(data)
                if clean_chunk:
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
        if not self.stream_buffer or not self.agent_id:
            self.last_flush_time = time.time()
            return

        headers = {}
        if self.auth_token:
            headers["X-Auth-Token"] = self.auth_token

        payload = {
            "from": self.agent_id,
            "to": "broadcast",
            "content": self.stream_buffer
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

    def gateway_listener(self):
        """Poll gateway for messages to inject"""
        while not self.should_exit:
            try:
                if self.agent_id and not self.should_exit:
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
                            if not self.should_exit:  # Check again before injecting
                                self.inject_message(msg)
                    elif resp.status_code not in [404, 401]:  # Ignore expected auth/not-found errors
                        print(f"Gateway inbox poll failed: {resp.status_code}", file=sys.stderr)
                time.sleep(POLL_INTERVAL)
            except requests.exceptions.RequestException as e:
                print(f"Gateway polling error: {e}", file=sys.stderr)
                time.sleep(1)
            except Exception as e:
                print(f"Unexpected error in gateway_listener: {e}", file=sys.stderr)
                time.sleep(1)

        print("Gateway listener thread exiting", file=sys.stderr)

    def inject_message(self, msg_obj):
        """Inject a message into the Agent's stdin as if the user typed it"""
        if not self.master_fd:
            return

        sender = msg_obj.get('from', 'Unknown') # Gateway sends 'from' field
        content = msg_obj.get('content', '')

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

        # Flow control: only inject when idle, otherwise queue (priority normal)
        if self.flow.is_idle():
            self._write_injection(sender, content)
        else:
            self.flow.enqueue(sender, content, priority="normal")

    def _write_injection(self, sender, content):
        """Write a formatted injection to the agent PTY."""
        injection = f"\n[Context: Message from {sender}]\n{content}\n"
        os.write(self.master_fd, injection.encode('utf-8'))

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

    if not args.cmd:
        print("Error: No command specified")
        sys.exit(1)

    sidecar = CSPSidecar(
        args.cmd,
        args.name,
        gateway_url=args.gateway_url,
        initial_prompt=args.initial_prompt,
        auth_token=args.auth_token
    )
    sidecar.run()
