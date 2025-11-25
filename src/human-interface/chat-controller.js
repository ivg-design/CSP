const axios = require('axios');
const readline = require('readline');
const WebSocket = require('ws');

class HumanChatController {
  constructor(gatewayUrl, authToken) {
    this.gatewayUrl = gatewayUrl || 'http://localhost:8765';
    this.authToken = authToken;
    this.agentId = 'Human';
    this.isPolling = false;

    // WebSocket connection management
    this.ws = null;
    this.wsConnected = false;
    this.wsReconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 1; // Start with 1 second

    this.client = axios.create({
      baseURL: this.gatewayUrl,
      headers: {
        'X-Auth-Token': this.authToken,
        'Content-Type': 'application/json'
      },
      timeout: 5000
    });
  }

  async initialize() {
    console.log(`Connecting to ${this.gatewayUrl}...`);
    // Register self
    try {
        await this.client.post('/register', {
            agentId: this.agentId,
            capabilities: { type: 'human' }
        });
        console.log('✅ Connected as Human');

        // Try WebSocket first, fall back to polling
        this.startWebSocketListener();
    } catch (error) {
        console.error('❌ Connection failed:', error.message);
        if (error.response && error.response.status === 401) {
             console.error('   (Invalid Auth Token)');
        }
        process.exit(1);
    }
  }

  async sendMessage(message, targetAgent = null) {
    try {
      await this.client.post('/agent-output', {
        from: this.agentId,
        content: message,
        to: targetAgent
      });
      // Local echo handled by looking at what we typed, but for group chat confirmation:
      // console.log(`(Sent)`);
    } catch (error) {
      console.error('❌ Send failed:', error.message);
    }
  }

  async listAgents() {
    try {
      const res = await this.client.get('/agents');
      const agents = res.data;
      if (agents.length === 0) {
        console.log('\n📋 No agents connected\n');
      } else {
        console.log('\n📋 Connected Agents:');
        agents.forEach(a => {
          const status = a.online ? '🟢' : '🔴';
          console.log(`  ${status} ${a.id} (${a.name})`);
        });
        console.log('');
      }
    } catch (error) {
      console.error('❌ Failed to list agents:', error.message);
    }
  }

  async queryHistory(options = {}) {
    try {
      const params = new URLSearchParams();
      if (options.limit) params.append('limit', options.limit);
      if (options.from) params.append('from', options.from);
      if (options.to) params.append('to', options.to);
      if (options.since) params.append('since', options.since);

      const res = await this.client.get(`/history?${params}`);
      const data = res.data;

      console.log(`\n📜 Chat History (${data.count} messages):`);
      console.log('─'.repeat(70));

      data.messages.forEach(msg => {
        const time = new Date(msg.timestamp).toLocaleTimeString();
        const typeIcon = msg.type === 'system' ? '🔔' : '💬';
        let line = `${typeIcon} [${time}] ${msg.from}`;
        if (msg.to !== 'broadcast') line += ` → ${msg.to}`;
        line += `: ${msg.content}`;
        console.log(line);
      });

      console.log('─'.repeat(70));
      console.log(`Total messages in history: ${data.total}\n`);
    } catch (error) {
      console.error('❌ Failed to query history:', error.message);
    }
  }

  startWebSocketListener() {
    // Try WebSocket first, fall back to HTTP polling
    if (this.tryWebSocketConnection()) {
      this.connectWebSocket();
    } else {
      this.startPollingFallback();
    }
  }

  tryWebSocketConnection() {
    try {
      // Convert HTTP URL to WebSocket URL
      const wsUrl = this.gatewayUrl.replace('http://', 'ws://').replace('https://', 'wss://');
      const wsUrlWithPath = `${wsUrl}/ws`;

      // Add auth via query parameter if available
      const url = this.authToken
        ? `${wsUrlWithPath}?token=${encodeURIComponent(this.authToken)}`
        : wsUrlWithPath;

      console.error(`[Chat] Attempting WebSocket connection to ${wsUrlWithPath}`);

      this.ws = new WebSocket(url, {
        headers: this.authToken ? { 'X-Auth-Token': this.authToken } : {}
      });

      return true;
    } catch (error) {
      console.error(`[Chat] WebSocket connection failed: ${error.message}`);
      return false;
    }
  }

  connectWebSocket() {
    this.ws.on('open', () => {
      this.wsConnected = true;
      this.wsReconnectAttempts = 0;
      this.reconnectDelay = 1;
      console.error('[Chat] WebSocket connected');
    });

    this.ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        this.displayMessage(msg);
      } catch (error) {
        console.error(`[Chat] Invalid WebSocket message: ${error.message}`);
      }
    });

    this.ws.on('error', (error) => {
      console.error(`[Chat] WebSocket error: ${error.message}`);
      this.wsConnected = false;
    });

    this.ws.on('close', (code, reason) => {
      this.wsConnected = false;
      console.error(`[Chat] WebSocket disconnected (code: ${code}), will retry`);

      // Implement exponential backoff capped at 10s
      if (this.wsReconnectAttempts < this.maxReconnectAttempts) {
        this.wsReconnectAttempts++;
        this.reconnectDelay = Math.min(this.reconnectDelay * 2, 10); // Max 10 seconds

        setTimeout(() => {
          if (!this.wsConnected) {
            this.startWebSocketListener(); // Retry connection
          }
        }, this.reconnectDelay * 1000);
      } else {
        // Max attempts reached, fall back to polling
        this.startPollingFallback();
      }
    });
  }

  startPollingFallback() {
    if (this.isPolling) return;
    this.isPolling = true;
    console.error('[Chat] Using HTTP polling fallback');

    const poll = async () => {
        try {
            const res = await this.client.get(`/inbox/${this.agentId}`);
            const messages = res.data;
            messages.forEach(msg => this.displayMessage(msg));
        } catch (err) {
            // Silent fail on poll error to not spam
        }

        if (this.isPolling && !this.wsConnected) {
          setTimeout(poll, 300); // 200-500ms as specified

          // Periodically retry WebSocket
          if (this.wsReconnectAttempts < this.maxReconnectAttempts) {
            setTimeout(() => {
              if (!this.wsConnected) {
                this.isPolling = false;
                this.startWebSocketListener();
              }
            }, 5000); // Retry WebSocket every 5 seconds
          }
        }
    };
    poll();
  }

  displayMessage(msg) {
    const time = new Date(msg.timestamp).toLocaleTimeString();
    if (msg.from === this.agentId) {
      return; // Don't display our own messages
    }

    if (msg.type === 'system') {
        console.log(`
🔔 [${time}] ${msg.content}`);
    } else {
        console.log(`
💬 [${time}] ${msg.from}: ${msg.content}`);
    }
    process.stdout.write('Human > '); // Re-print prompt
  }
}

async function main() {
    const token = process.env.CSP_AUTH_TOKEN;
    const url = process.env.CSP_GATEWAY_URL;

    if (!token) {
        console.error("Error: CSP_AUTH_TOKEN not set.");
        process.exit(1);
    }

    const controller = new HumanChatController(url, token);
    await controller.initialize();

    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
        prompt: 'Human > '
    });

    rl.prompt();

    rl.on('line', async (line) => {
        const input = line.trim();
        if (!input) {
            rl.prompt();
            return;
        }

        // Handle special commands
        if (input === '/agents' || input === '/list') {
            await controller.listAgents();
            rl.prompt();
            return;
        }

        if (input === '/help') {
            console.log('\nCommands:');
            console.log('  @agent message      - Send to specific agent (e.g., @claude hello)');
            console.log('  @all message        - Broadcast to all agents');
            console.log('  message             - Broadcast to all agents');
            console.log('  @query.log [limit]  - Show chat history (default: 50 messages)');
            console.log('  /agents             - List connected agents');
            console.log('  /help               - Show this help\n');
            rl.prompt();
            return;
        }

        if (input.startsWith('@')) {
            // Handle special commands and direct messages
            const spaceIndex = input.indexOf(' ');
            const command = spaceIndex === -1 ? input.substring(1) : input.substring(1, spaceIndex);
            const args = spaceIndex === -1 ? '' : input.substring(spaceIndex + 1);

            // Check for @query.log
            if (command === 'query.log') {
                const limit = args ? parseInt(args) : 50;
                await controller.queryHistory({ limit: Math.min(limit, 1000) });
                rl.prompt();
                return;
            }

            // Regular direct message: @claude hello or @all hello
            if (spaceIndex === -1) {
                console.log('Usage: @agent message or @query.log [limit]');
                rl.prompt();
                return;
            }

            const target = command.toLowerCase();
            const msg = args;

            if (target === 'all') {
                await controller.sendMessage(msg, 'broadcast');
            } else {
                await controller.sendMessage(msg, target);
            }
        } else {
            // Broadcast
            await controller.sendMessage(input, 'broadcast');
        }

        rl.prompt();
    });
}

if (require.main === module) {
    main();
}
