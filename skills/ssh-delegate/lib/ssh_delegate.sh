#!/bin/sh
# ssh_delegate.sh — manifest-based SSH key delegation + audit log.
#
# Entry point for the devenv:ssh-delegate skill (dEitY719/dotfiles#877). Sub-commands:
#   sync | add | list | test | revoke | doctor | help
#
# This script is called explicitly (never auto-sourced) as
# `bash skills/ssh-delegate/lib/ssh_delegate.sh`. Its helper libs
# are siblings in the same lib/ dir (repo convention dEitY719/dotfiles#699). Self-contained;
# degrades to plain printf when ux_lib is absent. POSIX sh only.

# `set -u` only — several lib helpers (manifest_default, manifest_has,
# ssh_verify_alias, ...) return non-zero as normal control flow, which `set -e`
# would turn into spurious aborts inside command substitutions. Error handling
# is explicit at every call site below.
set -u

LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# shellcheck source=ux.sh
. "${LIB_DIR}/ux.sh"
# shellcheck source=manifest.sh
. "${LIB_DIR}/manifest.sh"
# shellcheck source=audit.sh
. "${LIB_DIR}/audit.sh"
# shellcheck source=ssh_config.sh
. "${LIB_DIR}/ssh_config.sh"
# shellcheck source=install.sh
. "${LIB_DIR}/install.sh"
# shellcheck source=verify.sh
. "${LIB_DIR}/verify.sh"

usage() {
    cat <<'EOF'
devenv:ssh-delegate — manifest-based SSH key delegation + audit log

Usage:
  ssh_delegate.sh sync                       Reconcile manifest with reality
  ssh_delegate.sh add <user>@<host> [alias] [--key-only]
                                             Add + install + verify one entry
  ssh_delegate.sh list [--json]              Show entries + last-verified table
  ssh_delegate.sh test [<alias>|--all]       BatchMode reachability check
  ssh_delegate.sh revoke <alias>             Remove remote key + mark revoked
  ssh_delegate.sh doctor                     Environment + manifest health check
  ssh_delegate.sh -h | --help | help         This usage

Manifest: ${DEVX_SSH_MANIFEST:-~/.ssh/delegations.yml}  (mode 0600)
Audit log: ${DEVX_SSH_AUDIT_LOG:-~/.local/state/devx/ssh-delegations.log}
Add --dry-run to `add` to print actions without touching the remote.
Add --key-only to `add` to install the key without regenerating ssh config
(for hosts that already have a working hand-written alias).
EOF
}

# --- sub-commands ----------------------------------------------------------

cmd_add() {
    target=""
    alias_=""
    dry=""
    key_only=""
    for a in "$@"; do
        case "$a" in
        --dry-run) dry="--dry-run" ;;
        --key-only) key_only="--key-only" ;;
        *@*) target="$a" ;;
        *) [ -z "$alias_" ] && alias_="$a" ;;
        esac
    done
    if [ -z "$target" ]; then
        ux_error "add requires <user>@<host>"
        return 2
    fi
    user="${target%@*}"
    host="${target#*@}"
    # No user==host rejection: `ubuntu@ubuntu` is valid; the `*@*` parse above
    # already guaranteed a literal @, so empty user/host is the only error.
    if [ -z "$user" ] || [ -z "$host" ]; then
        ux_error "malformed target '$target' — expected <user>@<host>"
        return 2
    fi
    if [ -z "$alias_" ]; then
        alias_="${user}-$(printf '%s' "$host" | tr '.:' '--')"
    fi

    # Identity `add` would install absent any override (manifest default).
    default_idf="$(manifest_default identity_file 2>/dev/null)"
    # shellcheck disable=SC2088  # literal ~; expanded by ssh_config_expand_tilde
    [ -n "$default_idf" ] || default_idf='~/.ssh/id_ed25519'
    want_idf="$(ssh_config_expand_tilde "$default_idf")"

    # Defect A (dEitY719/dotfiles#1132): a hand-written `Host` block may pin a different
    # IdentityFile that shadows our drop-in, so the key we install is never the
    # key ssh offers — a silent mismatch. Detect it via `ssh -G` and adopt the
    # resolved key so install target == connect key. `detected` stays in ~-form.
    detected="$(ssh_config_conflicting_identity "$alias_" "$want_idf" 2>/dev/null || true)"
    eff_idf="$want_idf"
    [ -n "$detected" ] && eff_idf="$(ssh_config_expand_tilde "$detected")"

    port="$(manifest_eff "$alias_" port port)"
    [ -n "$port" ] || port=22
    copyid="${DEVX_SSH_COPY_ID_BIN:-ssh-copy-id}"

    if [ "$dry" = "--dry-run" ]; then
        # Dry-run mutates nothing — no manifest, no remote, no config.
        ux_header "add (dry-run): $alias_ -> ${user}@${host}"
        [ -n "$detected" ] &&
            ux_warning "existing ssh config resolves IdentityFile '$detected' for '$alias_' — add would adopt it (drop-in default '$default_idf' would be shadowed)"
        ux_info "manifest upsert: alias=$alias_ user=$user host=$host identity_file=$eff_idf"
        ux_info "would run: $copyid -i \"${eff_idf}.pub\" -p $port ${user}@${host}"
        if [ -n "$key_only" ]; then
            ux_info "--key-only: would NOT regenerate $(ssh_config_dropin_path)"
        else
            ux_info "would regenerate $(ssh_config_dropin_path) and verify '$alias_'"
        fi
        return 0
    fi

    # Defect C (dEitY719/dotfiles#1132): fail fast — before mutating anything — when ssh-copy-id
    # has no way to read the remote password here. A misleading `Permission
    # denied` in a non-interactive shell is worse than a clear up-front error.
    if ! ssh_install_can_prompt; then
        ux_error "add needs an interactive terminal for the ssh-copy-id password prompt"
        ux_info "no TTY detected (Claude '!' / CI session). Run this in a normal terminal:"
        ux_info "  $copyid -i \"${eff_idf}.pub\" -p $port ${user}@${host}"
        ux_info "then re-run 'add' to record it — or set SSH_ASKPASS + SSH_ASKPASS_REQUIRE=force to supply the password non-interactively."
        return 3
    fi

    manifest_ensure
    manifest_upsert "$alias_" "$user" "$host" "" ""
    if [ -n "$detected" ]; then
        manifest_set_field "$alias_" identity_file "$detected"
        audit_log_event identity-adopt "$alias_" "$detected"
        ux_warning "adopted existing IdentityFile '$detected' for '$alias_' (manifest default '$default_idf' would have been shadowed)"
    fi
    audit_log_event add "$alias_" "${user}@${host}"
    ux_header "add: $alias_ -> ${user}@${host}"
    if ! ssh_install_copy_id "$alias_"; then
        audit_log_event install-fail "$alias_" ""
        return 1
    fi
    audit_log_event install-ok "$alias_" ""
    if [ -n "$key_only" ]; then
        # Defect B (dEitY719/dotfiles#1132): the host already has a working hand-written alias —
        # install the key but leave the user's ssh config untouched (no regen).
        ux_info "--key-only: leaving ssh config untouched (no drop-in regen)"
    else
        ssh_config_regen
        ssh_config_ensure_include
    fi
    if ssh_verify_alias "$alias_"; then
        audit_log_event verify-ok "$alias_" ""
        ux_success "ssh $alias_ now works passwordless"
    else
        audit_log_event verify-fail "$alias_" ""
        ux_warning "key installed but BatchMode verify failed for '$alias_'"
    fi
}

cmd_list() {
    if [ "${1:-}" = "--json" ]; then
        manifest_to_tsv | awk -F'\t' '
            BEGIN { printf "["; first=1 }
            $1=="" { next }
            {
                if (!first) printf ","
                first=0
                rev = ($11=="true") ? "true" : "false"
                printf "{\"alias\":\"%s\",\"user\":\"%s\",\"host\":\"%s\",\"last_verified_at\":\"%s\",\"revoked\":%s}", $1, $2, $3, $9, rev
            }
            END { printf "]\n" }'
        return 0
    fi
    ux_header "delegations ($(manifest_path))"
    printf '%-20s %-12s %-18s %-20s %s\n' ALIAS USER HOST LAST_VERIFIED STATE
    manifest_to_tsv | awk -F'\t' '
        $1=="" { next }
        {
            state = ($11=="true") ? "revoked" : "active"
            lv = ($9=="") ? "-" : $9
            printf "%-20s %-12s %-18s %-20s %s\n", $1, $2, $3, lv, state
        }'
}

cmd_test() {
    arg="${1:---all}"
    rc=0
    if [ "$arg" = "--all" ]; then
        for al in $(manifest_to_tsv | awk -F'\t' '$11!="true" && NF{print $1}'); do
            if ssh_verify_alias "$al"; then
                ux_success "$al reachable"
                audit_log_event verify-ok "$al" ""
            else
                ux_error "$al unreachable"
                audit_log_event verify-fail "$al" ""
                rc=1
            fi
        done
    else
        if ssh_verify_alias "$arg"; then
            ux_success "$arg reachable"
            audit_log_event verify-ok "$arg" ""
        else
            ux_error "$arg unreachable"
            audit_log_event verify-fail "$arg" ""
            rc=1
        fi
    fi
    return "$rc"
}

cmd_sync() {
    manifest_ensure
    ux_header "sync ($(manifest_path))"
    for al in $(manifest_to_tsv | awk -F'\t' '$11!="true" && NF{print $1}'); do
        verdict="$(ssh_install_check_fingerprint "$al" 2>/dev/null || true)"
        case "$verdict" in
        MISMATCH)
            ux_alert "$al: host fingerprint changed — sync ABORTED (no auto re-trust)"
            audit_log_event fingerprint-mismatch "$al" ""
            return 1
            ;;
        first-pin)
            fp="$(ssh_install_capture_fingerprint "$(manifest_get "$al" host)" "$(manifest_eff "$al" port port)")"
            [ -n "$fp" ] && manifest_set_field "$al" fingerprint_sha256 "$fp"
            ux_info "$al: pinned fingerprint"
            ;;
        unknown)
            ux_warning "$al: host unreachable for fingerprint check"
            ;;
        esac
        if ssh_verify_alias "$al"; then
            ux_success "$al verified"
            audit_log_event verify-ok "$al" ""
        else
            ux_warning "$al verify failed"
            audit_log_event verify-fail "$al" ""
        fi
    done
    ssh_config_regen
    ssh_config_ensure_include
    audit_log_event sync "" ""
    ux_success "ssh config drop-in regenerated"
}

cmd_revoke() {
    al="${1:-}"
    if [ -z "$al" ]; then
        ux_error "revoke requires <alias>"
        return 2
    fi
    if ! manifest_has "$al"; then
        ux_error "unknown alias '$al'"
        return 2
    fi
    idf="$(manifest_eff "$al" identity_file identity_file)"
    idf="$(ssh_config_expand_tilde "$idf")"
    pub="${idf}.pub"
    ssh_bin="${DEVX_SSH_BIN:-ssh}"
    remote_key="unreachable"
    if [ -f "$pub" ]; then
        keytext="$(awk '{print $1" "$2}' "$pub")"
        ux_info "removing key from remote authorized_keys for '$al'"
        # Portable mktemp (template + TMPDIR fallback) and a non-empty $t guard
        # so a mktemp failure can never truncate the remote authorized_keys.
        if "$ssh_bin" -o BatchMode=yes "$al" \
            "f=\$HOME/.ssh/authorized_keys; [ -f \"\$f\" ] && { t=\$(mktemp \"\${TMPDIR:-/tmp}/ssh-delegate.XXXXXX\") && [ -n \"\$t\" ] && { grep -vF '$keytext' \"\$f\" >\"\$t\" || true; } && cat \"\$t\" >\"\$f\" && rm -f \"\$t\"; }" \
            >/dev/null 2>&1; then
            remote_key="removed"
        else
            ux_warning "could not reach remote — marking revoked locally anyway"
        fi
    fi
    manifest_set_field "$al" revoked true
    ssh_config_regen
    audit_log_event revoke "$al" ""
    if [ "$remote_key" = "removed" ]; then
        ux_success "revoked '$al' (remote key removed, manifest revoked:true)"
    else
        ux_success "revoked '$al' (manifest revoked:true, remote_key=unreachable)"
    fi
}

cmd_doctor() {
    ux_header "doctor"
    rc=0
    file="$(manifest_path)"
    if [ -f "$file" ]; then
        perm="$(stat -c '%a' "$file" 2>/dev/null)"
        case "$perm" in
        600) ux_success "manifest perms OK ($file)" ;;
        *)
            ux_warning "manifest is not 0600: $perm ($file)"
            rc=1
            ;;
        esac
    else
        ux_info "no manifest yet ($file) — run \`add\` to create one"
    fi
    idf="$(manifest_default identity_file 2>/dev/null)"
    # shellcheck disable=SC2088  # literal ~; expanded by ssh_config_expand_tilde
    [ -n "$idf" ] || idf='~/.ssh/id_ed25519'
    idf="$(ssh_config_expand_tilde "$idf")"
    if [ -f "$idf" ]; then ux_success "default identity present ($idf)"; else
        ux_error "default identity missing ($idf)"
        rc=1
    fi
    if command -v "${DEVX_SSH_BIN:-ssh}" >/dev/null 2>&1; then
        ux_success "ssh present"
    else
        ux_error "ssh missing"
        rc=1
    fi
    if command -v yq >/dev/null 2>&1; then ux_success "yq present (optional validator)"; else ux_info "yq absent — using built-in awk parser (OK)"; fi
    log="$(audit_log_path)"
    logdir="$(dirname "$log")"
    if [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null; then ux_success "audit log writable ($log)"; else
        ux_warning "audit log dir not writable ($logdir)"
        rc=1
    fi
    today="$(date -u +%Y-%m-%d)"
    manifest_to_tsv |
        awk -F'\t' -v today="$today" '$1!="" && $7!="" && $11!="true" && $7<today {print $1"\t"$7}' |
        while IFS="$(printf '\t')" read -r al ex; do
            ux_warning "$al expired on $ex"
        done
    return "$rc"
}

# --- main -------------------------------------------------------------------

main() {
    sub="${1:-help}"
    if [ "$#" -gt 0 ]; then shift; fi
    case "$sub" in
    sync) cmd_sync "$@" ;;
    add) cmd_add "$@" ;;
    list) cmd_list "$@" ;;
    test) cmd_test "$@" ;;
    revoke) cmd_revoke "$@" ;;
    doctor) cmd_doctor "$@" ;;
    -h | --help | help) usage ;;
    *)
        ux_error "unknown sub-command: $sub"
        usage
        return 2
        ;;
    esac
}

main "$@"
