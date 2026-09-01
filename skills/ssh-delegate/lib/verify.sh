#!/bin/sh
# lib/verify.sh — non-interactive (BatchMode) reachability check per alias.
#
# A success means the delegated key works without a password. On success the
# entry's last_verified_at is refreshed; the manifest stays the SSOT of
# "when did this last work".
#
# ssh is indirected through $DEVX_SSH_BIN (default ssh) so tests can mock it.
#
# Sourced — POSIX sh only. Depends on lib/manifest.sh.

# ssh_verify_alias <alias> [--dry-run]
# Returns 0 if `ssh -o BatchMode=yes <alias> true` succeeds.
ssh_verify_alias() {
    al="$1"
    dry="${2:-}"
    ssh_bin="${DEVX_SSH_BIN:-ssh}"
    timeout="${DEVX_SSH_CONNECT_TIMEOUT:-5}"

    if ! manifest_has "$al"; then
        ux_error "alias '$al' not found in manifest"
        return 1
    fi

    if [ "$(manifest_get "$al" revoked)" = "true" ]; then
        ux_warning "alias '$al' is revoked — skipping verify"
        return 1
    fi

    cmd="$ssh_bin -o BatchMode=yes -o ConnectTimeout=$timeout $al true"
    if [ "$dry" = "--dry-run" ]; then
        printf '%s\n' "$cmd"
        return 0
    fi

    if "$ssh_bin" -o BatchMode=yes -o ConnectTimeout="$timeout" "$al" true >/dev/null 2>&1; then
        manifest_set_field "$al" last_verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 0
    fi
    return 1
}
