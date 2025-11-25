const express = require('express');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

class CSPGateway {
  constructor(options = {}) {
    this.agents = new Map();
    this.chatHistory = [];
    this.messageIdCounter = 0;
    this.wsConnections = new Set(); // Track WebSocket connections

    // JSONL persistence configuration
    this.historyFile = options.historyFile || path.join(process.cwd(), 'csp_history.jsonl');
    this.initializeHistoryFile();

    // Security configuration
    this.config = {
      port: options.port || 8765,
      host: options.host || '127.0.0.1', // Localhost only
      maxMessageSize: options.maxMessageSize || 64 * 1024, // 64KB
      authToken: options.authToken || this.generateToken(),
      rateLimitWindow: options.rateLimitWindow || 15 * 60 * 1000, // 15 min
      rateLimitMax: options.rateLimitMax || 1000, // 1000 requests per window
    };

    console.log(`[Gateway] Auth token: ${this.config.authToken}`);
    console.log(`[Gateway] History file: ${this.historyFile}`);
  }

  generateToken() {
    return crypto.randomBytes(32).toString('hex');
  }

  generateMessageId() {
    return `msg-${Date.now()}-${++this.messageIdCounter}`;
  }

  initializeHistoryFile() {
    try {
      // Create file if it doesn't exist (touches it)
      if (!fs.existsSync(this.historyFile)) {
        fs.writeFileSync(this.historyFile, '', 'utf8');
        console.log(`[Gateway] Created history file: ${this.historyFile}`);
      } else {
        console.log(`[Gateway] Using existing history file: ${this.historyFile}`);
      }
    } catch (error) {
      console.error(`[Gateway] Failed to initialize history file: ${error.message}`);
      // Don't fail startup, just log warning
    }
  }

  appendToHistory(message) {
    try {
      const jsonLine = JSON.stringify(message) + '\n';
      fs.appendFileSync(this.historyFile, jsonLine, 'utf8');
    } catch (error) {
      console.error(`[Gateway] Failed to append to history: ${error.message}`);
      // Don't fail message delivery if persistence fails
    }
  }

  // Agent lifecycle management
  registerAgent(name, capabilities = {}) {
    if (!name || typeof name !== 'string') {
      throw new Error('Invalid agent name');
    }

    // Generate unique agent ID (or use provided if strictly needed, but internal ID is safer)
    // Note: Sidecar sends { agentId: ... } in register, but here we generate/confirm it.
    // Let's support accepting an ID if provided, otherwise generate.
    // But for this implementation, let's stick to the simplified logic:
    // The Sidecar expects the server to return { agentId }.
    
    const agentId = name; // Use the requested name as ID for simplicity in this version, assuming uniqueness handling in launcher

    this.agents.set(agentId, {
      id: agentId,
      name: name,
      capabilities,
      lastSeen: Date.now(),
      messageQueue: []
    });

    this.broadcastSystemMessage(`🟢 ${name} joined the conversation`);
    console.log(`[Gateway] Agent ${name} registered as ${agentId}`);

    return agentId;
  }

  broadcastSystemMessage(content) {
    const message = {
      id: this.generateMessageId(),
      timestamp: new Date().toISOString(),
      from: 'SYSTEM',
      to: 'broadcast',
      content: content,
      type: 'system'
    };

    this.chatHistory.push(message);
    this.appendToHistory(message); // Persist to JSONL

    // Deliver to all agents
    for (const [agentId, agent] of this.agents) {
      agent.messageQueue.push(message);
    }

    // Broadcast via WebSocket
    this.broadcastWebSocket(message);
  }

  // Message routing with validation
  routeMessage(fromAgent, content, targetAgent = null) {
    // Validate sender exists
    // (Relaxed check: if sender not found, maybe re-register or just allow for robustness)
    // But strictly:
    if (!this.agents.has(fromAgent) && fromAgent !== 'Human') {
       // console.warn(`[Gateway] Warning: Route message from unknown agent ${fromAgent}`);
    }

    const message = {
      id: this.generateMessageId(),
      timestamp: new Date().toISOString(),
      from: fromAgent,
      to: targetAgent || 'broadcast',
      content: content,
      type: targetAgent ? 'direct' : 'broadcast'
    };

    // Store in history (in-memory)
    this.chatHistory.push(message);

    // Persist to JSONL file
    this.appendToHistory(message);

    // Update sender's last seen
    if (this.agents.has(fromAgent)) {
        this.agents.get(fromAgent).lastSeen = Date.now();
    }

    // Route to targets
    if (targetAgent && targetAgent !== 'broadcast') {
      if (this.agents.has(targetAgent)) {
          this.agents.get(targetAgent).messageQueue.push(message);
      }
    } else {
      // Broadcast to all agents except sender
      for (const [agentId, agent] of this.agents) {
        if (agentId !== fromAgent) {
          agent.messageQueue.push(message);
        }
      }
    }

    // Broadcast via WebSocket to all connected clients
    this.broadcastWebSocket(message);

    return message;
  }

  // WebSocket broadcasting
  broadcastWebSocket(message) {
    const messageData = JSON.stringify(message);
    this.wsConnections.forEach(ws => {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(messageData);
        } catch (error) {
          console.error('[Gateway] WebSocket send error:', error);
          this.wsConnections.delete(ws);
        }
      } else {
        // Clean up closed connections
        this.wsConnections.delete(ws);
      }
    });
  }

  // Cleanup inactive agents
  cleanupInactiveAgents() {
    const now = Date.now();
    const timeout = 5 * 60 * 1000; // 5 minutes

    for (const [agentId, agent] of this.agents) {
      if (now - agent.lastSeen > timeout) {
        console.log(`[Gateway] Cleaning up inactive agent: ${agentId}`);
        this.agents.delete(agentId);
        this.broadcastSystemMessage(`🔴 ${agentId} disconnected (timeout)`);
      }
    }
  }

  // Authentication middleware
  authenticateToken(req, res, next) {
    const token = req.headers['x-auth-token'] || req.query.token;
    
    // Allow if no token set in config (dev mode)
    if (!this.config.authToken) return next();

    if (token !== this.config.authToken) {
      return res.status(401).json({ error: 'Invalid authentication token' });
    }

    next();
  }

  // HTTP server setup with security
  setupHTTPServer() {
    const app = express();

    app.use(express.json({ limit: `${Math.floor(this.config.maxMessageSize / 1024)}kb` }));
    app.use(this.authenticateToken.bind(this));

    // Health check
    app.get('/health', (req, res) => {
      res.json({
        status: 'ok',
        agents: this.agents.size,
        uptime: process.uptime()
      });
    });

    // Agent registration
    app.post('/register', (req, res) => {
      try {
        const { agentId, capabilities } = req.body; // Sidecar sends agentId as the requested name
        const confirmedId = this.registerAgent(agentId, capabilities);
        res.status(201).json({ success: true, agentId: confirmedId });
      } catch (error) {
        res.status(400).json({ error: error.message });
      }
    });

    // Message sending
    app.post('/agent-output', (req, res) => {
      try {
        const { from, content, to } = req.body;
        const message = this.routeMessage(from, content, to);
        res.json({ success: true, messageId: message.id });
      } catch (error) {
        console.error(error);
        res.status(400).json({ error: error.message });
      }
    });

    // Phase 2: Agent-to-Agent messaging
    app.post('/message', (req, res) => {
      try {
        const { from, to, content } = req.body;

        if (!from || !content) {
          return res.status(400).json({ error: 'Missing from or content' });
        }

        // Route the message (to can be agent_id or 'broadcast')
        const message = this.routeMessage(from, content, to || 'broadcast');
        res.json({ success: true, messageId: message.id });
      } catch (error) {
        console.error('[Gateway] Message routing error:', error);
        res.status(400).json({ error: error.message });
      }
    });

    // Message retrieval (polling)
    app.get('/inbox/:agentId', (req, res) => {
      const agentId = req.params.agentId;

      if (!this.agents.has(agentId)) {
         // If agent not found, it might be the Human polling.
         // For simplicity, we'll just return empty or 404.
         // But wait, Human needs an inbox too.
         if (agentId === 'Human') {
             // Hack: Create ephemeral human agent if not exists
             if (!this.agents.has('Human')) {
                 this.agents.set('Human', { id: 'Human', name: 'Human', messageQueue: [], lastSeen: Date.now() });
             }
         } else {
             return res.status(404).json({ error: 'Agent not found' });
         }
      }

      const agent = this.agents.get(agentId);
      const messages = agent.messageQueue.splice(0); // Drain queue
      agent.lastSeen = Date.now(); // Update activity

      res.json(messages);
    });
    
    // List all registered agents (for discovery)
    app.get('/agents', (req, res) => {
        const agentList = [];
        for (const [agentId, agent] of this.agents) {
            agentList.push({
                id: agentId,
                name: agent.name,
                lastSeen: agent.lastSeen,
                online: (Date.now() - agent.lastSeen) < 60000
            });
        }
        res.json(agentList);
    });

    // Query chat history with filtering
    app.get('/history', (req, res) => {
      try {
        const limit = Math.min(parseInt(req.query.limit) || 100, 1000); // Max 1000
        const from = req.query.from; // Filter by sender
        const to = req.query.to;     // Filter by recipient
        const since = req.query.since; // ISO timestamp

        // Read from in-memory history (JSONL is backup)
        let messages = this.chatHistory.slice();

        // Apply filters
        if (from) {
          messages = messages.filter(m => m.from === from);
        }
        if (to) {
          messages = messages.filter(m => m.to === to || to === 'broadcast');
        }
        if (since) {
          messages = messages.filter(m => new Date(m.timestamp) > new Date(since));
        }

        // Return last 'limit' messages in chronological order
        const result = messages.slice(-limit);

        res.json({
          count: result.length,
          total: this.chatHistory.length,
          messages: result
        });
      } catch (error) {
        console.error('[Gateway] History query error:', error);
        res.status(400).json({ error: error.message });
      }
    });

    // Unregister
    app.delete('/agent/:agentId', (req, res) => {
        const agentId = req.params.agentId;
        if (this.agents.has(agentId)) {
            this.agents.delete(agentId);
            this.broadcastSystemMessage(`🔴 ${agentId} disconnected`);
            res.json({ success: true });
        } else {
            res.status(404).json({ error: 'Not found' });
        }
    });

    // Start cleanup timer
    setInterval(() => {
      this.cleanupInactiveAgents();
    }, 60 * 1000);

    // Create HTTP server
    const server = http.createServer(app);

    // Setup WebSocket server
    const wss = new WebSocket.Server({
      server,
      path: '/ws',
      verifyClient: (info) => {
        // Check authentication for WebSocket connections
        const url = new URL(info.req.url, `http://${info.req.headers.host}`);
        const token = info.req.headers['x-auth-token'] || url.searchParams.get('token');

        // Allow if no token set in config (dev mode)
        if (!this.config.authToken) return true;

        return token === this.config.authToken;
      }
    });

    wss.on('connection', (ws, req) => {
      console.log('[Gateway] WebSocket client connected');
      this.wsConnections.add(ws);

      ws.on('close', () => {
        console.log('[Gateway] WebSocket client disconnected');
        this.wsConnections.delete(ws);
      });

      ws.on('error', (error) => {
        console.error('[Gateway] WebSocket error:', error);
        this.wsConnections.delete(ws);
      });
    });

    // Start server
    server.listen(this.config.port, this.config.host, () => {
      console.log(`[CSP Gateway] HTTP server running on http://${this.config.host}:${this.config.port}`);
      console.log(`[CSP Gateway] WebSocket server running on ws://${this.config.host}:${this.config.port}/ws`);
    });

    return server;
  }
}

if (require.main === module) {
  const gateway = new CSPGateway({
    port: process.env.CSP_PORT || 8765,
    authToken: process.env.CSP_AUTH_TOKEN
  });
  gateway.setupHTTPServer();
}
