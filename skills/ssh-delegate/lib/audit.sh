#!/bin/sh
# lib/audit.sh — append-only JSONL audit trail for every delegation event.
#
# Path: $DEVX_SSH_AUDIT_LOG, else ${XDG_STATE_HOME:-~/.local/state}/devx/
# ssh-delegations.log (issue #877 L3). Concurrent writes are serialized with
# flock when available; the append itself is atomic on POSIX for small lines.
#
# Sourced — POSIX sh only.

audit_log_path() {
    if [ -n "${DEVX_SSH_AUDIT_LOG:-}" ]; then
        printf '%s\n' "$DEVX_SSH_AUDIT_LOG"
    else
        printf '%s/devx/ssh-delegations.log\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
    fi
}

# JSON-escape a string for embedding in a "..." value (no jq dependency).
_audit_json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { ORS="" }
        {
            gsub(/\\/, "\\\\"); gsub(/"/, "\\\"")
            gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
            if (NR>1) printf "\\n"
            printf "%s", $0
        }'
}

# audit_log_event <event> <alias> [detail]
audit_log_event() {
    event="$1"
    alias_="$2"
    detail="${3:-}"
    log="$(audit_log_path)"
    dir="$(dirname "$log")"
    [ -d "$dir" ] || mkdir -p "$dir"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    actor="${USER:-$(id -un 2>/dev/null || echo unknown)}"
    line="$(printf '{"ts":"%s","event":"%s","alias":"%s","actor":"%s","detail":"%s"}' \
        "$ts" \
        "$(_audit_json_escape "$event")" \
        "$(_audit_json_escape "$alias_")" \
        "$(_audit_json_escape "$actor")" \
        "$(_audit_json_escape "$detail")")"
    if command -v flock >/dev/null 2>&1; then
        (
            flock 9
            printf '%s\n' "$line" >>"$log"
        ) 9>>"$log"
    else
        printf '%s\n' "$line" >>"$log"
    fi
}
