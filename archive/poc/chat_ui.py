#!/usr/bin/env python3
"""
CSP POC - Multi-Agent Group Chat UI with Tmux Monitor
Uses CPU + Network monitoring for reliable agent completion detection.
Supports multiple agents (Claude, Gemini, Codex, etc.)
"""

import subprocess
import sys
import time
import threading
import argparse
import readline
from enum import Enum, auto
from collections import Counter
from typing import Optional, Callable, Dict, List

# Configure readline for better editing
readline.parse_and_bind('set editing-mode emacs')
readline.parse_and_bind('"\e[A": history-search-backward')
readline.parse_and_bind('"\e[B": history-search-forward')


class AgentState(Enum):
    IDLE = auto()
    WAIT_ACTIVE = auto()
    WAIT_IDLE = auto()


class TmuxPaneMonitor:
    """
    Monitors a tmux pane using CPU + Network detection.
    Works for any CLI agent (Claude, Gemini, Codex, etc.)
    """

    PROMPT_CHARS = frozenset(['>', '$', '#', ':', '❯', '»', '→', '%', '⟩', ')'])
    UI_INDICATOR_CHARS = frozenset(['⏵', '⏸', '⏺', '⏹', '●', '○', '◐', '◓', '◑', '◒', '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'])
    UI_PATTERNS = [
        'bypass permissions', 'shift+tab', 'to cycle', 'tab to autocomplete',
        'press enter', '/ to search', 'esc to cancel', 'enter to select',
        # Gemini patterns
        'type /help', 'gemini>', '/find-docs', 'find relevant documentation',
        'authenticate with', 'oauth-enabled mcp server',
        # Codex patterns
        'codex>',
    ]

    CPU_ACTIVE_THRESHOLD = 2.0
    CPU_IDLE_THRESHOLD = 1.5
    IDLE_SAMPLES = 5
    MAX_WAIT_ACTIVE = 20

    def __init__(self, pane_id: str, agent_name: str, on_response: Callable[[str, str], None]):
        self.pane_id = pane_id
        self.agent_name = agent_name
        self.on_response = on_response

        self._lock = threading.Lock()
        self._state = AgentState.IDLE
        self._snapshot = ""
        self._injected_text = ""
        self._idle_count = 0
        self._wait_active_count = 0
        self._shell_pid: Optional[int] = None
        self._agent_pid: Optional[int] = None

        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

        # Agent-specific tuning
        lower_name = agent_name.lower()
        if 'gemini' in lower_name:
            self.CPU_ACTIVE_THRESHOLD = 1.0  # Gemini uses less CPU
            self.CPU_IDLE_THRESHOLD = 0.5
        elif 'codex' in lower_name:
            self.CPU_ACTIVE_THRESHOLD = 1.5
            self.CPU_IDLE_THRESHOLD = 0.8

        self._init_pane_info()

    def _init_pane_info(self):
        try:
            result = subprocess.run(
                ['tmux', 'display', '-t', self.pane_id, '-p', '#{pane_pid}'],
                capture_output=True, text=True, timeout=5
            )
            self._shell_pid = int(result.stdout.strip())
        except Exception as e:
            print(f"[Error] Failed to get pane PID for {self.agent_name}: {e}")

    def _get_agent_pid(self) -> Optional[int]:
        if not self._shell_pid:
            return None
        try:
            result = subprocess.run(
                ['pgrep', '-P', str(self._shell_pid)],
                capture_output=True, text=True, timeout=5
            )
            if result.stdout.strip():
                return int(result.stdout.strip().split()[0])
        except Exception:
            pass
        return None

    def _get_cpu_usage(self, pid: int) -> float:
        try:
            result = subprocess.run(
                ['ps', '-o', '%cpu=', '-p', str(pid)],
                capture_output=True, text=True, timeout=5
            )
            return float(result.stdout.strip())
        except Exception:
            return 0.0

    def _get_network_connections(self, pid: int) -> int:
        try:
            result = subprocess.run(
                ['lsof', '-n', '-P', '-i', '-a', '-p', str(pid)],
                capture_output=True, text=True, timeout=5
            )
            lines = result.stdout.strip().split('\n')
            connections = sum(1 for line in lines if 'ESTABLISHED' in line or 'SYN_SENT' in line)
            return connections
        except Exception:
            return 0

    def _is_agent_active(self, pid: int) -> bool:
        cpu = self._get_cpu_usage(pid)
        net = self._get_network_connections(pid)
        return cpu > self.CPU_ACTIVE_THRESHOLD or net > 0

    def _is_agent_idle(self, pid: int) -> bool:
        cpu = self._get_cpu_usage(pid)
        net = self._get_network_connections(pid)
        return cpu < self.CPU_IDLE_THRESHOLD and net == 0

    @property
    def state(self) -> AgentState:
        with self._lock:
            return self._state

    def start(self, poll_interval: float = 0.05):
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._monitor_loop, args=(poll_interval,), daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=2.0)

    def inject_message(self, message: str, from_user: str = "You"):
        """Inject a message into the agent's pane."""
        with self._lock:
            self._snapshot = self._capture_pane()
            self._injected_text = message.strip()
            self._agent_pid = self._get_agent_pid()
            self._state = AgentState.WAIT_ACTIVE
            self._idle_count = 0
            self._wait_active_count = 0

        # Format message with sender info for group chat context
        if from_user != "You":
            formatted = f"[From {from_user}] {message}"
        else:
            formatted = message

        self._send_keys(formatted)

    def _monitor_loop(self, poll_interval: float):
        while not self._stop_event.is_set():
            self._tick()
            time.sleep(poll_interval)

    def _tick(self):
        response_to_emit = None

        with self._lock:
            if self._state == AgentState.IDLE:
                return

            if not self._agent_pid:
                self._agent_pid = self._get_agent_pid()
                if not self._agent_pid:
                    return

            if self._state == AgentState.WAIT_ACTIVE:
                if self._is_agent_active(self._agent_pid):
                    self._state = AgentState.WAIT_IDLE
                    self._idle_count = 0
                else:
                    self._wait_active_count += 1
                    if self._wait_active_count >= self.MAX_WAIT_ACTIVE:
                        current = self._capture_pane()
                        if current != self._snapshot:
                            self._state = AgentState.WAIT_IDLE
                            self._idle_count = 0

            elif self._state == AgentState.WAIT_IDLE:
                if self._is_agent_idle(self._agent_pid):
                    self._idle_count += 1
                    if self._idle_count >= self.IDLE_SAMPLES:
                        content = self._capture_pane()
                        response = self._extract_response(self._snapshot, content)

                        self._state = AgentState.IDLE
                        self._snapshot = ""
                        self._injected_text = ""
                        self._idle_count = 0
                        self._wait_active_count = 0

                        if response:
                            response_to_emit = response
                else:
                    self._idle_count = 0

        if response_to_emit:
            self.on_response(self.agent_name, response_to_emit)

    def _capture_pane(self, scrollback: int = 500) -> str:
        try:
            result = subprocess.run(
                ['tmux', 'capture-pane', '-t', self.pane_id, '-p', '-S', f'-{scrollback}'],
                capture_output=True, text=True, errors='replace', timeout=5
            )
            return result.stdout.rstrip('\n')
        except Exception:
            return ""

    def _send_keys(self, text: str):
        try:
            subprocess.run(['tmux', 'send-keys', '-t', self.pane_id, '-l', text],
                          check=True, capture_output=True, timeout=5)
            subprocess.run(['tmux', 'send-keys', '-t', self.pane_id, 'Enter'],
                          check=True, capture_output=True, timeout=5)
        except Exception:
            pass

    def _extract_response(self, snapshot: str, current: str) -> Optional[str]:
        snapshot_lines = snapshot.split('\n')
        current_lines = current.split('\n')
        snapshot_freq = Counter(snapshot_lines)

        response_lines = []
        injected = self._injected_text

        for line in current_lines:
            if snapshot_freq.get(line, 0) > 0:
                snapshot_freq[line] -= 1
                continue

            if injected and injected in line:
                continue

            if self._is_ui_line(line):
                continue

            response_lines.append(line)

        while response_lines and not response_lines[0].strip():
            response_lines.pop(0)
        while response_lines and not response_lines[-1].strip():
            response_lines.pop()

        if response_lines and self._is_prompt_only(response_lines[-1]):
            response_lines.pop()

        result = '\n'.join(response_lines).strip()

        if result and result[0] in self.UI_INDICATOR_CHARS:
            result = result[1:].strip()

        return result if result else None

    def _is_ui_line(self, line: str) -> bool:
        stripped = line.strip()
        if not stripped:
            return False

        if self._is_prompt_only(stripped):
            return True

        if any(c in self.UI_INDICATOR_CHARS for c in stripped):
            if stripped[0] not in self.UI_INDICATOR_CHARS:
                return True

        lower = stripped.lower()
        if any(p in lower for p in self.UI_PATTERNS):
            return True

        if len(stripped) <= 3 and not any(c.isalnum() for c in stripped):
            return True

        return False

    def _is_prompt_only(self, line: str) -> bool:
        stripped = line.strip()
        if not stripped:
            return False
        if len(stripped) <= 20:
            if stripped[-1] in self.PROMPT_CHARS:
                return True
            if len(stripped) > 1 and stripped[-2] in self.PROMPT_CHARS:
                return True
        return False


class MultiAgentGroupChat:
    """Group chat UI supporting multiple agents."""

    def __init__(self):
        self.monitors: Dict[str, TmuxPaneMonitor] = {}
        self._responses: List[tuple] = []
        self._lock = threading.Lock()
        self._pending_responses: Dict[str, bool] = {}  # Track who we're waiting for

    def add_agent(self, name: str, pane_id: str):
        """Add an agent to the group chat."""
        monitor = TmuxPaneMonitor(pane_id, name, self._on_response)
        self.monitors[name.lower()] = monitor
        monitor.start(poll_interval=0.05)

    def _on_response(self, agent_name: str, response: str):
        """Callback when any agent responds."""
        with self._lock:
            self._responses.append((agent_name, response))
            self._pending_responses[agent_name.lower()] = False

    def _show_responses(self) -> bool:
        """Display any pending responses."""
        shown = False
        with self._lock:
            while self._responses:
                agent, text = self._responses.pop(0)
                text_oneline = ' '.join(text.split())
                print(f"{agent} > {text_oneline}")
                shown = True
        return shown

    def _has_pending(self) -> bool:
        """Check if any agents are still processing."""
        with self._lock:
            return any(self._pending_responses.values())

    def send_message(self, message: str, targets: List[str], from_user: str = "You"):
        """Send a message to specified agents."""
        with self._lock:
            for target in targets:
                self._pending_responses[target] = True

        for target in targets:
            if target in self.monitors:
                self.monitors[target].inject_message(message, from_user)

    def run(self):
        """Run the group chat."""
        agent_names = list(self.monitors.keys())

        print("CSP Group Chat")
        print(f"Agents: {', '.join(agent_names)}")
        print("Commands: @all, @agent_name, /status, /quit")
        print("")

        try:
            while True:
                self._show_responses()

                try:
                    user_input = input("You > ").strip()
                except EOFError:
                    break

                if not user_input:
                    continue

                # Commands
                if user_input.lower() == '/quit':
                    break

                if user_input.lower() == '/status':
                    for name, monitor in self.monitors.items():
                        state = monitor.state.name
                        pid = monitor._agent_pid
                        if pid:
                            cpu = monitor._get_cpu_usage(pid)
                            net = monitor._get_network_connections(pid)
                            print(f"  {name}: {state}, PID={pid}, CPU={cpu}%, Net={net}")
                        else:
                            print(f"  {name}: {state}, PID=None")
                    continue

                if user_input.lower() == '/agents':
                    print(f"Agents: {', '.join(agent_names)}")
                    continue

                # Parse target
                targets = []
                message = user_input

                if user_input.startswith('@'):
                    parts = user_input.split(' ', 1)
                    target_spec = parts[0][1:].lower()  # Remove @
                    message = parts[1] if len(parts) > 1 else ""

                    if not message:
                        print("Error: No message provided")
                        continue

                    if target_spec == 'all':
                        targets = agent_names
                    elif target_spec in self.monitors:
                        targets = [target_spec]
                    else:
                        print(f"Error: Unknown agent '{target_spec}'. Available: {', '.join(agent_names)}")
                        continue
                else:
                    # Default to all agents
                    targets = agent_names

                # Send to targets
                self.send_message(message, targets)

                # Wait for responses
                while self._has_pending():
                    self._show_responses()
                    time.sleep(0.1)

                # Show any final responses
                self._show_responses()

        except KeyboardInterrupt:
            print()

        finally:
            for monitor in self.monitors.values():
                monitor.stop()


def main():
    parser = argparse.ArgumentParser(description='CSP Multi-Agent Group Chat')
    parser.add_argument('--agent', action='append', nargs=2, metavar=('NAME', 'PANE'),
                        help='Add agent: --agent Claude %%1 --agent Gemini %%2')
    # Backwards compatibility: single agent mode
    parser.add_argument('--pane', help='Single agent pane ID (legacy)')
    parser.add_argument('--name', default='Agent', help='Single agent name (legacy)')
    args = parser.parse_args()

    chat = MultiAgentGroupChat()

    if args.agent:
        # Multi-agent mode
        for name, pane in args.agent:
            chat.add_agent(name, pane)
    elif args.pane:
        # Single agent mode (backwards compatible)
        chat.add_agent(args.name, args.pane)
    else:
        parser.print_help()
        sys.exit(1)

    chat.run()


if __name__ == '__main__':
    main()
