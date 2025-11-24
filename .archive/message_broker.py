#!/usr/bin/env python3
"""
Multi-Agent Message Broker
Handles bidirectional communication between CLI agents with unique IDs
"""

import json
import time
import threading
import queue
import uuid
from datetime import datetime
from pathlib import Path
import os
import signal
import sys

class MessageBroker:
    def __init__(self):
        self.agents = {}  # agent_id: {name, inbox_queue, last_seen}
        self.message_history = []
        self.running = True
        self.lock = threading.Lock()

        # Create communication directory
        self.comm_dir = Path("/tmp/agent_comm")
        self.comm_dir.mkdir(exist_ok=True)

        # Global message file for monitoring
        self.global_log = self.comm_dir / "global_messages.log"

        # Agent registry file
        self.registry_file = self.comm_dir / "agent_registry.json"

        # Setup signal handler for clean shutdown (only in main thread)
        try:
            signal.signal(signal.SIGINT, self.shutdown)
            signal.signal(signal.SIGTERM, self.shutdown)
        except ValueError:
            # Not in main thread, skip signal handling
            pass

    def register_agent(self, agent_name, agent_id=None):
        """Register a new agent and return its unique ID"""
        if agent_id is None:
            agent_id = str(uuid.uuid4())[:8]

        with self.lock:
            self.agents[agent_id] = {
                'name': agent_name,
                'inbox_queue': queue.Queue(),
                'last_seen': time.time(),
                'inbox_file': self.comm_dir / f"{agent_id}_inbox.json",
                'outbox_file': self.comm_dir / f"{agent_id}_outbox.json"
            }

            # Create agent-specific files
            self.agents[agent_id]['inbox_file'].write_text("[]")
            self.agents[agent_id]['outbox_file'].write_text("[]")

            self.save_registry()

        self.broadcast_system_message(f"🟢 Agent '{agent_name}' ({agent_id}) joined the conversation")
        return agent_id

    def unregister_agent(self, agent_id):
        """Unregister an agent"""
        with self.lock:
            if agent_id in self.agents:
                agent_name = self.agents[agent_id]['name']
                del self.agents[agent_id]
                self.save_registry()
                self.broadcast_system_message(f"🔴 Agent '{agent_name}' ({agent_id}) left the conversation")

    def send_message(self, from_agent_id, content, to_agent_id=None, message_type="chat"):
        """Send a message from one agent to another (or broadcast)"""
        timestamp = datetime.now().isoformat()

        message = {
            'id': str(uuid.uuid4())[:8],
            'timestamp': timestamp,
            'from': from_agent_id,
            'from_name': self.agents.get(from_agent_id, {}).get('name', 'Unknown'),
            'to': to_agent_id,
            'content': content,
            'type': message_type
        }

        with self.lock:
            # Add to global history
            self.message_history.append(message)

            # Write to global log
            self.append_to_global_log(message)

            # Deliver to specific agent or broadcast
            if to_agent_id and to_agent_id in self.agents:
                self.deliver_to_agent(to_agent_id, message)
            else:
                # Broadcast to all agents except sender
                for agent_id in self.agents:
                    if agent_id != from_agent_id:
                        self.deliver_to_agent(agent_id, message)

    def deliver_to_agent(self, agent_id, message):
        """Deliver a message to a specific agent's inbox"""
        if agent_id in self.agents:
            # Add to queue
            self.agents[agent_id]['inbox_queue'].put(message)

            # Write to agent's inbox file
            inbox_file = self.agents[agent_id]['inbox_file']
            try:
                existing_messages = json.loads(inbox_file.read_text())
                existing_messages.append(message)
                inbox_file.write_text(json.dumps(existing_messages, indent=2))
            except:
                inbox_file.write_text(json.dumps([message], indent=2))

    def get_messages(self, agent_id, since_timestamp=None):
        """Get new messages for an agent"""
        messages = []

        if agent_id in self.agents:
            # Update last seen
            with self.lock:
                self.agents[agent_id]['last_seen'] = time.time()

            # Get messages from queue (non-blocking)
            while True:
                try:
                    message = self.agents[agent_id]['inbox_queue'].get_nowait()
                    if since_timestamp is None or message['timestamp'] > since_timestamp:
                        messages.append(message)
                except queue.Empty:
                    break

        return messages

    def broadcast_system_message(self, content):
        """Send a system message to all agents"""
        timestamp = datetime.now().isoformat()

        message = {
            'id': str(uuid.uuid4())[:8],
            'timestamp': timestamp,
            'from': 'SYSTEM',
            'from_name': 'System',
            'to': None,
            'content': content,
            'type': 'system'
        }

        with self.lock:
            self.message_history.append(message)
            self.append_to_global_log(message)

            for agent_id in self.agents:
                self.deliver_to_agent(agent_id, message)

    def append_to_global_log(self, message):
        """Append message to global log file"""
        log_line = f"[{message['timestamp'][:19]}] {message['from_name']}: {message['content']}\n"
        with open(self.global_log, 'a') as f:
            f.write(log_line)

    def save_registry(self):
        """Save current agent registry to file"""
        registry = {
            agent_id: {
                'name': info['name'],
                'last_seen': info['last_seen']
            }
            for agent_id, info in self.agents.items()
        }
        self.registry_file.write_text(json.dumps(registry, indent=2))

    def cleanup_inactive_agents(self):
        """Remove agents that haven't been seen for a while"""
        current_time = time.time()
        inactive_agents = []

        with self.lock:
            for agent_id, info in self.agents.items():
                if current_time - info['last_seen'] > 300:  # 5 minutes
                    inactive_agents.append(agent_id)

        for agent_id in inactive_agents:
            self.unregister_agent(agent_id)

    def get_active_agents(self):
        """Get list of currently active agents"""
        with self.lock:
            return {
                agent_id: {
                    'name': info['name'],
                    'last_seen': info['last_seen']
                }
                for agent_id, info in self.agents.items()
            }

    def shutdown(self, signum=None, frame=None):
        """Shutdown the broker cleanly"""
        print("\nShutting down message broker...")
        self.running = False
        sys.exit(0)

    def start_monitor(self):
        """Start the background monitoring thread"""
        def monitor():
            while self.running:
                self.cleanup_inactive_agents()
                time.sleep(30)  # Check every 30 seconds

        monitor_thread = threading.Thread(target=monitor, daemon=True)
        monitor_thread.start()

def main():
    """Run the message broker as a standalone service"""
    broker = MessageBroker()
    broker.start_monitor()

    print("Multi-Agent Message Broker started")
    print(f"Communication directory: {broker.comm_dir}")
    print(f"Global log: {broker.global_log}")
    print("Press Ctrl+C to stop")

    try:
        while broker.running:
            time.sleep(1)
    except KeyboardInterrupt:
        broker.shutdown()

if __name__ == "__main__":
    main()