# bash completion for ssh_delegate.sh / `devenv:ssh-delegate`.
# Source this file, or symlink it into your bash-completion.d.
#
#   source /path/to/ssh-delegate.bash

_ssh_delegate_aliases() {
    local manifest="${DEVX_SSH_MANIFEST:-$HOME/.ssh/delegations.yml}"
    [ -f "$manifest" ] || return 0
    awk '
        /^entries:/ { in_e=1; next }
        /^[^ ]/     { in_e=0 }
        in_e && /^[ ]+-[ ]+alias:/ { sub(/.*alias:[ ]*/, ""); gsub(/"/, ""); print }
    ' "$manifest"
}

_ssh_delegate() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    local subcmds="sync add list test revoke doctor help -h --help"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$subcmds" -- "$cur"))
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        revoke|test)
            COMPREPLY=($(compgen -W "$(_ssh_delegate_aliases) --all" -- "$cur"))
            ;;
        list)
            COMPREPLY=($(compgen -W "--json" -- "$cur"))
            ;;
        add)
            COMPREPLY=($(compgen -W "--dry-run" -- "$cur"))
            ;;
    esac
    return 0
}

complete -F _ssh_delegate ssh_delegate.sh ssh-delegate
