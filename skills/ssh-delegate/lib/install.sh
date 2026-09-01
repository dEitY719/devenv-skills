#!/bin/sh
# lib/install.sh — install a public key on a remote and pin its host key.
#
# Layer L2 (issue #877): first install accepts the host key with
# `accept-new`, captures the SHA256 fingerprint, and pins it in the manifest.
# Subsequent installs/verifies compare against the pinned value — a mismatch
# is an ALERT, never an automatic re-trust.
#
# Binaries are indirected through env vars so tests can mock them:
#   $DEVX_SSH_COPY_ID_BIN  (default ssh-copy-id)
#   $DEVX_SSH_KEYSCAN_BIN  (default ssh-keyscan)
#   $DEVX_SSH_KEYGEN_BIN   (default ssh-keygen)
#
# Sourced — POSIX sh only. Depends on lib/manifest.sh, lib/ssh_config.sh.

# Capture the remote host's SHA256 fingerprint, or empty on failure.
ssh_install_capture_fingerprint() {
    host="$1"
    port="${2:-22}"
    keyscan="${DEVX_SSH_KEYSCAN_BIN:-ssh-keyscan}"
    keygen="${DEVX_SSH_KEYGEN_BIN:-ssh-keygen}"
    command -v "$keyscan" >/dev/null 2>&1 || return 1
    # ssh-keyscan returns each host-key type in network-dependent order; sort
    # first so the same fingerprint is picked every run (else spurious MISMATCH).
    "$keyscan" -p "$port" "$host" 2>/dev/null |
        "$keygen" -lf - 2>/dev/null |
        sort |
        awk '/SHA256:/ {for(i=1;i<=NF;i++) if($i ~ /^SHA256:/){print $i; exit}}'
}

# Can ssh-copy-id obtain the remote password in this environment? (issue #1132
# defect C.) `ssh-copy-id` needs a TTY for its single password prompt; a
# non-interactive shell (a Claude `!` session, CI) without a usable SSH_ASKPASS
# makes it die as `ssh_askpass: No such file or directory` -> `Permission
# denied`, which reads as a wrong password. Returns 0 when a prompt is possible.
# The TTY check is overridable via $DEVX_SSH_ASSUME_TTY (1=yes, 0=no) so tests
# can exercise both branches deterministically.
ssh_install_can_prompt() {
    case "${DEVX_SSH_ASSUME_TTY:-}" in
    1) return 0 ;;
    0) : ;; # forced non-interactive — still allow a force-enabled askpass below
    *) [ -t 0 ] && return 0 ;;
    esac
    # No TTY: OpenSSH only consults SSH_ASKPASS without a TTY when REQUIRE=force.
    if [ -n "${SSH_ASKPASS:-}" ] && [ -x "${SSH_ASKPASS}" ] &&
        [ "${SSH_ASKPASS_REQUIRE:-}" = "force" ]; then
        return 0
    fi
    return 1
}

# ssh_install_copy_id <alias> [--dry-run]
# Resolves the entry, copies the identity's .pub to the remote (one password
# prompt), then pins installed_at + fingerprint. Returns the command line on
# --dry-run without executing it.
ssh_install_copy_id() {
    al="$1"
    dry="${2:-}"
    user="$(manifest_get "$al" user)"
    host="$(manifest_get "$al" host)"
    port="$(manifest_eff "$al" port port)"
    [ -n "$port" ] || port=22
    idf="$(manifest_eff "$al" identity_file identity_file)"
    idf="$(ssh_config_expand_tilde "$idf")"
    pub="${idf}.pub"
    copyid="${DEVX_SSH_COPY_ID_BIN:-ssh-copy-id}"

    if [ -z "$user" ] || [ -z "$host" ]; then
        ux_error "alias '$al' has no user/host in the manifest"
        return 1
    fi

    cmd="$copyid -i $pub -p $port ${user}@${host}"
    if [ "$dry" = "--dry-run" ]; then
        printf '%s\n' "$cmd"
        return 0
    fi

    if [ ! -f "$pub" ]; then
        ux_error "public key not found: $pub (run ssh-keygen first)"
        return 1
    fi

    ux_info "installing key on ${user}@${host}:${port} (password prompt once)"
    if "$copyid" -o StrictHostKeyChecking=accept-new -i "$pub" -p "$port" "${user}@${host}"; then
        fp="$(ssh_install_capture_fingerprint "$host" "$port")"
        manifest_set_field "$al" installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        [ -n "$fp" ] && manifest_set_field "$al" fingerprint_sha256 "$fp"
        return 0
    fi
    ux_error "ssh-copy-id failed for alias '$al'"
    return 1
}

# Compare the live remote fingerprint against the pinned one.
# Echoes: ok | first-pin | MISMATCH | unknown
ssh_install_check_fingerprint() {
    al="$1"
    host="$(manifest_get "$al" host)"
    port="$(manifest_eff "$al" port port)"
    [ -n "$port" ] || port=22
    pinned="$(manifest_get "$al" fingerprint_sha256)"
    live="$(ssh_install_capture_fingerprint "$host" "$port")"
    if [ -z "$live" ]; then
        echo unknown
        return 2
    fi
    if [ -z "$pinned" ]; then
        echo first-pin
        return 0
    fi
    if [ "$pinned" = "$live" ]; then
        echo ok
        return 0
    fi
    echo MISMATCH
    return 1
}
