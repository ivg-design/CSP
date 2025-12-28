# TUI Input Injection Problem

**Date:** 2025-12-27
**Status:** UNRESOLVED
**Requesting:** Codex analysis and suggestions

---

## Problem Summary

CSP uses PTY (pseudo-terminal) to wrap CLI agents and inject messages. The injection works for simple CLIs but **fails to submit input** to modern TUI apps (Claude Code, Gemini CLI, Codex CLI).

**Symptoms:**
- Injected text **appears on screen** (visible in TUI)
- Text appears in input area (seen in Codex: `> [From Human]: Hi!`)
- But the message is **NOT submitted** to the TUI's message handler
- The TUI sits waiting for user input despite receiving text + Enter

---

## Technical Details

### Current Injection Code

```python
def _write_injection(self, sender, content, turn_signal=None):
    # Clear any existing input first (Ctrl+U = clear line)
    os.write(self.master_fd, b'\x15')
    time.sleep(0.02)

    # Write message content
    message = f"[From {sender}]: {content}"
    os.write(self.master_fd, message.encode('utf-8'))

    # Small delay to let TUI process the text
    time.sleep(0.05)

    # Send Enter key - try CR+LF for maximum compatibility
    os.write(self.master_fd, b'\r\n')
```

### PTY Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  CSP Sidecar    │         │  TUI App        │
│  (Parent)       │         │  (Child)        │
│                 │         │                 │
│  master_fd ─────┼────────►│  stdin (slave)  │
│           ◄─────┼─────────│  stdout/stderr  │
└─────────────────┘         └─────────────────┘

We write to master_fd → should appear as stdin to child
```

### What We've Tried

| Attempt | Result |
|---------|--------|
| `\n` (Line Feed) at end | Text appears, not submitted |
| `\r` (Carriage Return) at end | Text appears, not submitted |
| `\r\n` (CRLF) at end | Text appears, not submitted |
| Separate write for Enter with delay | Text appears, not submitted |
| Ctrl+U before message | No change |
| Single write vs multiple writes | No change |

---

## Observations

1. **Text IS reaching the TUI** - we can see `[From Human]: Hi!` on screen
2. **Text appears in input area** - Codex shows `> [From Human]: Hi!` at prompt
3. **Enter key is NOT triggering submission** - TUI waits for more input

### Hypothesis

Modern TUI apps (built with Ink, Bubble Tea, etc.) may:
1. Use **raw terminal mode** with custom key handling
2. Have their own **input buffer** separate from PTY stdin
3. Distinguish between **echoed text** and **user keystrokes**
4. Use **async input handling** that doesn't process buffered stdin

---

## Questions for Codex

1. **How do TUI frameworks (Ink/React for Gemini, Go for Codex) handle stdin in raw mode?**
   - Do they read from stdin directly or use a different input mechanism?
   - Is there a way to detect "real" keystrokes vs piped input?

2. **Is there a terminal escape sequence that forces input submission?**
   - Beyond CR/LF, is there a sequence that TUIs recognize as "submit"?

3. **Could the issue be with PTY settings?**
   - Should we configure the PTY differently (termios settings)?
   - Raw mode vs cooked mode implications?

4. **Alternative approaches:**
   - Can we use the TUI's IPC mechanism instead (if any)?
   - Is there a "headless" or "pipe" mode for these CLIs?
   - Could we inject at a lower level (before the TUI's input handler)?

5. **How does puzldai solve this?**
   - They use `-p` flag for batch mode - but is there an interactive solution?

---

## Answers and Observations

1) **How do TUI frameworks (Ink, Bubble Tea) handle stdin in raw mode?**
- Ink (Node): uses `process.stdin.setRawMode(true)` and reads bytes from stdin, decoding into key events. It does not distinguish "real" keystrokes from injected bytes; everything is read from the TTY fd.
- Bubble Tea (Go): uses `term.MakeRaw` on stdin and reads from the TTY in a goroutine. It also does not differentiate injected bytes vs real keystrokes.
- If Enter does not submit, it is usually an app-level keybinding issue (multiline input or alternate submit key).

2) **Is there a terminal escape sequence that forces submission?**
- No. Terminals only deliver key sequences; the app decides what "submit" means.
- Common sequences to test: `\r` (CR), `\n` (LF), `\r\n` (CRLF), `\x1b[13~` (keypad Enter).
- Some TUIs bind submit to Ctrl+Enter or Ctrl+S; those map to different sequences and must be injected explicitly.

3) **Could PTY termios settings be the issue?**
- Less likely if the text visibly appears in the input area, because that means the app is receiving key events.
- Still possible: TUIs may flush input during mode switches; injected Enter could be dropped.
- Verify the child owns the controlling terminal and is in raw mode (`stty -a` inside the agent).
- Consider waiting for a quiet window and calling `tcdrain` before sending Enter.

4) **Alternative approaches (IPC, lower-level injection)?**
- `tmux send-keys` often behaves closer to "real" keystrokes than writing to the PTY master.
- `TIOCSTI` can inject keystrokes at the kernel line discipline but is commonly blocked by OS security policies.
- If a CLI supports an IPC or non-TUI mode, that is more reliable than driving the TUI.

5) **How does puzldai solve this for interactive mode?**
- Puzld does not inject into third-party TUIs; it owns the UI (Ink) and talks to model APIs directly.
- Its interactive experience is internal to its own app, so it does not face the external TUI submission problem.

---

## Concrete Experiment Matrix

Run these in order for each CLI (Claude, Gemini, Codex) and record: visible text, submission behavior, and latency. Keep the injected content minimal (e.g., `PING`) to reduce noise.

### Injection Sequence Variants

| ID | Text Write | Submit Sequence | Notes |
|----|------------|-----------------|-------|
| A1 | `PING` | `\n` | LF only |
| A2 | `PING` | `\r` | CR only |
| A3 | `PING` | `\r\n` | CRLF |
| A4 | `PING` | `\x1b[13~` | Keypad Enter |
| A5 | `PING` | `\x1b[13;5u` | Kitty Ctrl+Enter (if enabled) |
| A6 | `PING` | `\x13` | Ctrl+S (XOFF; some apps repurpose) |
| A7 | `PING` | `\x1b[27;13;13~` | Alternative Ctrl+Enter (xterm-like) |

### Input Mode Variants

| ID | Text Write | Mode | Notes |
|----|------------|------|-------|
| B1 | `PING` | Plain | No bracketed paste |
| B2 | `PING` | Bracketed paste | `\x1b[200~PING\x1b[201~` |
| B3 | `PING` | Split writes | Write text, wait 50ms, write submit |

### Transport Variants

| ID | Transport | Notes |
|----|-----------|-------|
| C1 | PTY master write | Current method |
| C2 | `tmux send-keys -l` | Pane-level keystroke injection |
| C3 | `tmux send-keys` with explicit Enter | Key events (`C-m`) |

### Per-CLI Test Grid

| CLI | A1 | A2 | A3 | A4 | A5 | A6 | A7 | B2 | B3 | C2 | C3 |
|-----|----|----|----|----|----|----|----|----|----|----|----|
| Claude |  |  |  |  |  |  |  |  |  |  |  |
| Gemini |  |  |  |  |  |  |  |  |  |  |  |
| Codex |  |  |  |  |  |  |  |  |  |  |  |

Record results as:
- `N` (text visible, no submit)
- `S` (submitted)
- `P` (partial/queued)

---

## Practical Next Step (Low Risk)

1) Add per-agent submit sequences (env/config):
   - `CSP_CLAUDE_SUBMIT_SEQ`, `CSP_GEMINI_SUBMIT_SEQ`, `CSP_CODEX_SUBMIT_SEQ`
2) Add a fallback mode that uses `tmux send-keys -l` to the pane when PTY injection fails.
3) Keep `PING` style probes in a debug mode so you can quickly find the correct submit sequence per CLI.

## Relevant Files

- `csp_sidecar.py` - PTY proxy implementation (lines 1035-1067 for injection)
- `bin/start-llm-groupchat.sh` - Launcher
- TUI apps: Claude Code, Gemini CLI (`@anthropics/claude-code`), OpenAI Codex

---

## Desired Outcome

Messages sent from Human (or other agents) should be:
1. Injected into the TUI's input area
2. **Automatically submitted** as if user pressed Enter
3. Processed by the TUI as a normal user message

---

*Please investigate and propose solutions. Interactive mode is required - batch/non-interactive mode is not acceptable for CSP's use case.*
