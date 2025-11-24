# A2A Protocols vs. CSP (CLI Sidecar Protocol)

## Scope & Purpose
- **A2A (Agent-to-Agent) protocols**: Standardized capability cards, discovery, and message formats for heterogeneous agents to request/offer work across a network (often transport-agnostic, peer-friendly).
- **CSP (CLI Sidecar Protocol)**: Local-first PTY proxy + gateway that preserves native CLI UX while enabling controlled group chat/routing for CLI-based LLM agents.

## Comparison
- **Transport**
  - A2A: Abstract; can ride HTTP, websockets, pub/sub; focuses on message schema and discovery.
  - CSP: Concretely local HTTP polling (optionally WS) between sidecars and gateway; PTY for CLI fidelity.
- **Identity & Capabilities**
  - A2A: Capability cards advertise skills, tool access, limits; used for discovery/matchmaking.
  - CSP: Lightweight `agentId` + optional capability metadata; no distributed discovery—agents are pre-known/registered locally.
- **Isolation Model**
  - A2A: Process/location agnostic; assumes independent agents with sandboxed runtimes.
  - CSP: Process-level isolation via separate CLIs and PTY boundaries; no cross-process code sharing by design.
- **Routing**
  - A2A: Supports direct agent-to-agent semantics; can be mediated or peer-to-peer.
  - CSP: Centralized gateway fan-out with per-agent inbox queues; no peer dialing.
- **UX Preservation**
  - A2A: Not concerned with terminal fidelity; focuses on protocol semantics.
  - CSP: PTY master/slave proxy to keep colors, prompts, spinners intact for human-visible CLIs.
- **Security Posture**
  - A2A: Auth/ACL patterns vary by deployment; often token-based with capability scoping.
  - CSP: Localhost-only, shared secret (`X-Auth-Token`), rate limiting; identity enforced at gateway.
- **Streaming**
  - A2A: Can carry streaming tokens if transport supports it; not mandated.
  - CSP: Adaptive chunking from PTY → gateway via `/agent-output` (auth’d) with pause/flow control; fan-out today uses fast HTTP polling, with WS/SSE as a recommended push option.
- **Discovery**
  - A2A: Advertises/queries agents via capability cards and directories.
  - CSP: No discovery layer; human/operator chooses which CLI agents to launch.
- **Interoperability**
  - A2A: Designed to interop across vendors and agent types.
  - CSP: Provider-agnostic at CLI level, single local gateway by design (can be extended); supports pause/resume controls for safe injections.

## Positioning
- Use **CSP** when you need native CLI fidelity, tmux-based workflows, and tight local control with minimal dependencies.
- Layer **A2A** concepts on top of CSP if you need discovery, richer capability negotiation, or multi-host/peer routing; CSP’s gateway can emit/consume capability cards without changing the PTY proxy core.
