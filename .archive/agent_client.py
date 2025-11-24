#!/usr/bin/env python3
"""
Agent Client - Interface for CLI agents to communicate through the message broker
"""

import json
import time
import threading
import subprocess
import sys
import os
from datetime import datetime
from pathlib import Path

class AgentClient:
    def __init__(self, agent_name, command=None):
        self.agent_name = agent_name
        self.agent_id = None
        self.command = command
        self.running = True
        self.last_message_time = None

        # Communication directory
        self.comm_dir = Path("/tmp/agent_comm")
        self.broker_script = Path(__file__).parent / "message_broker.py"

        # Ensure message broker is running
        self.ensure_broker_running()

        # Register with broker
        self.register()

        # Start message listener
        self.start_listener()

    def ensure_broker_running(self):
        """Ensure the message broker is running"""
        registry_file = self.comm_dir / "agent_registry.json"

        if not self.comm_dir.exists() or not registry_file.exists():
            print(f"Starting message broker for {self.agent_name}...")
            # Start broker in background
            subprocess.Popen([
                sys.executable, str(self.broker_script)
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # Wait for broker to initialize
            time.sleep(2)

    def register(self):
        """Register this agent with the broker"""
        from message_broker import MessageBroker

        # Create a temporary broker instance to register
        broker = MessageBroker()
        self.agent_id = broker.register_agent(self.agent_name)

        print(f"🤖 Agent '{self.agent_name}' registered with ID: {self.agent_id}")
        return self.agent_id

    def send_message(self, content, to_agent_id=None):
        """Send a message to other agents"""
        if not self.agent_id:
            print("❌ Agent not registered!")
            return

        # Use the broker to send message
        from message_broker import MessageBroker
        broker = MessageBroker()
        broker.send_message(self.agent_id, content, to_agent_id)

        print(f"📤 Sent: {content}")

    def get_new_messages(self):
        """Get new messages for this agent"""
        if not self.agent_id:
            return []

        from message_broker import MessageBroker
        broker = MessageBroker()
        return broker.get_messages(self.agent_id, self.last_message_time)

    def start_listener(self):
        """Start listening for incoming messages"""
        def listener():
            while self.running:
                try:
                    messages = self.get_new_messages()
                    for message in messages:
                        self.handle_message(message)
                        self.last_message_time = message['timestamp']
                    time.sleep(1)  # Poll every second
                except Exception as e:
                    print(f"❌ Error in listener: {e}")
                    time.sleep(5)

        listener_thread = threading.Thread(target=listener, daemon=True)
        listener_thread.start()

    def handle_message(self, message):
        """Handle incoming message"""
        timestamp = message['timestamp'][:19]  # Remove microseconds
        from_name = message['from_name']
        content = message['content']
        msg_type = message.get('type', 'chat')

        if msg_type == 'system':
            print(f"\n🔔 [{timestamp}] {content}")
        else:
            print(f"\n💬 [{timestamp}] {from_name}: {content}")

        # If agent has a command, we could potentially pipe this to it
        if self.command and msg_type == 'chat':
            self.notify_agent_process(message)

    def notify_agent_process(self, message):
        """Notify the agent process of new message (placeholder)"""
        # This could pipe messages to the actual CLI agent
        pass

    def list_agents(self):
        """List all active agents"""
        from message_broker import MessageBroker
        broker = MessageBroker()
        agents = broker.get_active_agents()

        print("\n👥 Active Agents:")
        for agent_id, info in agents.items():
            last_seen = datetime.fromtimestamp(info['last_seen']).strftime('%H:%M:%S')
            indicator = "🟢" if agent_id == self.agent_id else "🔵"
            print(f"  {indicator} {info['name']} ({agent_id}) - Last seen: {last_seen}")

    def interactive_mode(self):
        """Start interactive chat mode"""
        print(f"\n💬 Interactive mode for {self.agent_name} ({self.agent_id})")
        print("Commands:")
        print("  /list       - List active agents")
        print("  /to <id>    - Send message to specific agent")
        print("  /quit       - Exit")
        print("  <message>   - Broadcast message to all agents")
        print()

        try:
            while self.running:
                user_input = input(f"{self.agent_name} > ").strip()

                if user_input.startswith('/'):
                    command_parts = user_input.split(' ', 1)
                    command = command_parts[0][1:]  # Remove '/'

                    if command == 'quit':
                        break
                    elif command == 'list':
                        self.list_agents()
                    elif command == 'to' and len(command_parts) > 1:
                        # Parse /to <agent_id> <message>
                        args = command_parts[1].split(' ', 1)
                        if len(args) >= 2:
                            to_agent_id, message = args
                            self.send_message(message, to_agent_id)
                        else:
                            print("❌ Usage: /to <agent_id> <message>")
                    else:
                        print(f"❌ Unknown command: {command}")
                else:
                    if user_input:
                        self.send_message(user_input)

        except KeyboardInterrupt:
            pass
        finally:
            self.shutdown()

    def shutdown(self):
        """Shutdown the agent client"""
        print(f"\n👋 {self.agent_name} signing off...")
        self.running = False

        # Unregister from broker
        if self.agent_id:
            from message_broker import MessageBroker
            broker = MessageBroker()
            broker.unregister_agent(self.agent_id)

def main():
    if len(sys.argv) < 2:
        print("Usage: python agent_client.py <agent_name> [command]")
        sys.exit(1)

    agent_name = sys.argv[1]
    command = sys.argv[2:] if len(sys.argv) > 2 else None

    client = AgentClient(agent_name, command)

    if command:
        # Run the command and relay its output
        print(f"🚀 Starting {agent_name} with command: {' '.join(command)}")
        # Here you could implement command execution and I/O bridging
        client.interactive_mode()
    else:
        # Interactive mode
        client.interactive_mode()

if __name__ == "__main__":
    main()