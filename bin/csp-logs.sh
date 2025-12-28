#!/bin/bash
# bin/csp-logs.sh - View CSP session logs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$PROJECT_ROOT/logs"
GATEWAY_LOG="$PROJECT_ROOT/gateway.log"

# Find most recent session log
get_latest_session() {
    if [[ -d "$LOGS_DIR" ]]; then
        ls -t "$LOGS_DIR"/session_*.jsonl 2>/dev/null | head -1
    fi
}

HISTORY_FILE="${CSP_LOG_FILE:-$(get_latest_session)}"

usage() {
    cat <<EOF
CSP Log Viewer

Usage: $0 [command] [options]

Commands:
  sessions         List all session logs
  messages [N]     Show last N messages (default: 50)
  follow           Follow messages in real-time
  gateway          Show gateway log
  export [file]    Export session to readable format
  clear            Clear all logs (with confirmation)

Options:
  --from <agent>   Filter by sender
  --to <agent>     Filter by recipient
  --json           Output raw JSON

Examples:
  $0 messages 20           # Last 20 messages
  $0 messages --from Human # Messages from Human
  $0 follow                # Real-time tail
  $0 export session.txt    # Export readable log
EOF
}

show_messages() {
    local limit="${1:-50}"
    local from_filter=""
    local to_filter=""
    local raw_json=false

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_filter="$2"; shift 2 ;;
            --to) to_filter="$2"; shift 2 ;;
            --json) raw_json=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "No history file found at $HISTORY_FILE"
        exit 1
    fi

    if $raw_json; then
        tail -n "$limit" "$HISTORY_FILE"
    else
        tail -n "$limit" "$HISTORY_FILE" | while read -r line; do
            ts=$(echo "$line" | jq -r '.timestamp // "?"' 2>/dev/null | cut -d'T' -f2 | cut -d'.' -f1)
            from=$(echo "$line" | jq -r '.from // "?"' 2>/dev/null)
            to=$(echo "$line" | jq -r '.to // "broadcast"' 2>/dev/null)
            content=$(echo "$line" | jq -r '.content // ""' 2>/dev/null | head -c 200)

            # Apply filters
            [[ -n "$from_filter" && "$from" != "$from_filter" ]] && continue
            [[ -n "$to_filter" && "$to" != "$to_filter" ]] && continue

            # Color code by sender
            case "$from" in
                Human) color="\033[0;32m" ;;      # Green
                SYSTEM) color="\033[0;33m" ;;     # Yellow
                orchestrator*) color="\033[0;35m" ;; # Magenta
                claude*) color="\033[0;36m" ;;    # Cyan
                codex*) color="\033[0;34m" ;;     # Blue
                gemini*) color="\033[0;31m" ;;    # Red
                *) color="\033[0m" ;;             # Default
            esac

            echo -e "[$ts] ${color}$from${NC} → $to: $content\033[0m"
        done
    fi
}

follow_messages() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "No history file found. Start CSP first."
        exit 1
    fi

    echo "Following messages (Ctrl+C to stop)..."
    echo "---"

    tail -f "$HISTORY_FILE" | while read -r line; do
        ts=$(echo "$line" | jq -r '.timestamp // "?"' 2>/dev/null | cut -d'T' -f2 | cut -d'.' -f1)
        from=$(echo "$line" | jq -r '.from // "?"' 2>/dev/null)
        to=$(echo "$line" | jq -r '.to // "broadcast"' 2>/dev/null)
        content=$(echo "$line" | jq -r '.content // ""' 2>/dev/null | head -c 200)

        echo "[$ts] $from → $to: $content"
    done
}

show_gateway() {
    if [[ -f "$GATEWAY_LOG" ]]; then
        cat "$GATEWAY_LOG"
    else
        echo "No gateway log found at $GATEWAY_LOG"
    fi
}

export_session() {
    local outfile="${1:-csp_session_$(date +%Y%m%d_%H%M%S).txt}"

    {
        echo "CSP Session Export"
        echo "Generated: $(date)"
        echo "================================"
        echo ""

        if [[ -f "$HISTORY_FILE" ]]; then
            cat "$HISTORY_FILE" | while read -r line; do
                ts=$(echo "$line" | jq -r '.timestamp // "?"' 2>/dev/null)
                from=$(echo "$line" | jq -r '.from // "?"' 2>/dev/null)
                to=$(echo "$line" | jq -r '.to // "broadcast"' 2>/dev/null)
                content=$(echo "$line" | jq -r '.content // ""' 2>/dev/null)

                echo "[$ts]"
                echo "From: $from"
                echo "To: $to"
                echo "---"
                echo "$content"
                echo ""
            done
        fi
    } > "$outfile"

    echo "Exported to: $outfile"
}

list_sessions() {
    echo "Session Logs in $LOGS_DIR:"
    echo "---"
    if [[ -d "$LOGS_DIR" ]]; then
        for f in $(ls -t "$LOGS_DIR"/session_*.jsonl 2>/dev/null); do
            count=$(wc -l < "$f" | tr -d ' ')
            basename "$f" | sed 's/session_//' | sed 's/.jsonl//' | while read ts; do
                echo "  $ts  ($count messages)  $f"
            done
        done
    else
        echo "  No logs directory found"
    fi
}

clear_logs() {
    read -p "Clear ALL session logs? This cannot be undone. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$LOGS_DIR"/*.jsonl 2>/dev/null
        echo "All logs cleared."
    else
        echo "Cancelled."
    fi
}

# Main
NC='\033[0m'

case "${1:-messages}" in
    sessions|list) list_sessions ;;
    messages) shift; show_messages "$@" ;;
    follow) follow_messages ;;
    gateway) show_gateway ;;
    export) shift; export_session "$@" ;;
    clear) clear_logs ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
esac
