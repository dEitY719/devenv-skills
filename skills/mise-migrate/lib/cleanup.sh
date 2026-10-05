#!/bin/sh
# shellcheck disable=SC2015 # self-test asserts are `cond && ok || ko`, ok never fails
# cleanup.sh -- Step 4.4 for devenv:mise-migrate: remove the legacy `.venv/`
# and `*.egg-info/` directories under <path>, after `uv sync` succeeded.
#
# Usage:
#   cleanup.sh <path> [--keep-venv]
#   cleanup.sh --self-test
#
# stdout: `removed: <dir>` per deleted directory. `--keep-venv` leaves
# `.venv/` alone (egg-info is still removed). Every target is resolved with
# `cd -P` and must sit strictly inside <path>'s own resolved directory -- a
# `.venv` symlink pointing elsewhere is refused, never followed. All targets
# are checked before the first delete, so a refusal deletes nothing.
#
# exit 0  done (nothing to remove is also done)
# exit 1  a target resolves outside <path>, or rm failed (stops there, no
#         rollback -- the caller reports the partial state)
# exit 2  usage error, or <path> is not a directory
# POSIX sh only.

set -u
NL='
'

usage() { sed -n '6,8p' "$0" | sed 's/^# \{0,1\}//'; }

# real <dir>: physical path, symlinks resolved; empty if unresolvable.
real() { (cd -P -- "$1" 2>/dev/null && pwd); }

main() {
    p=""; keep=0
    for a in "$@"; do
        case "$a" in
            --keep-venv) keep=1 ;;
            -*) usage >&2; return 2 ;;
            *) [ -z "$p" ] || { usage >&2; return 2; }; p=$a ;;
        esac
    done
    [ -n "$p" ] || { usage >&2; return 2; }
    root=$(real "$p")
    [ -n "$root" ] || { echo "cleanup.sh: not a directory: $p" >&2; return 2; }
    # ponytail: newline-separated list, a path containing a newline is split.
    list=""
    if [ "$keep" -eq 0 ] && { [ -e "$p/.venv" ] || [ -L "$p/.venv" ]; }; then list="$p/.venv$NL"; fi
    list="$list$(find "$p" -maxdepth 2 \( -name .venv -o -name .git \) -prune -o -type d -name '*.egg-info' -print)"
    _o=$IFS; IFS=$NL
    for t in $list; do
        r=$(real "$t")
        case "$r" in "$root"/?*) ;; *)
            echo "[FAIL] cleanup.sh: refusing $t -- resolves outside $root (${r:-unresolvable})" >&2
            IFS=$_o; return 1 ;;
        esac
    done
    for t in $list; do
        rm -rf -- "$t" || { echo "[FAIL] cleanup.sh: rm failed: $t" >&2; IFS=$_o; return 1; }
        echo "removed: $t"
    done
    IFS=$_o
    return 0
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0
    ok() { printf 'ok    %s\n' "$1"; }
    ko() { printf 'FAIL  %s\n' "$1"; fail=1; }

    d=$tmp/proj; mkdir -p "$d/.venv/bin" "$d/foo.egg-info" "$d/src/bar.egg-info" "$d/src/app"
    o=$(main "$d") && [ ! -e "$d/.venv" ] && [ ! -e "$d/foo.egg-info" ] && [ ! -e "$d/src/bar.egg-info" ] \
        && [ -d "$d/src/app" ] && [ "$(printf '%s\n' "$o" | grep -c '^removed: ')" = 3 ] \
        && ok "removes .venv and *.egg-info, prints each, keeps sources" || ko "default cleanup: $o"

    mkdir -p "$d/.venv" "$d/foo.egg-info"
    o=$(main "$d" --keep-venv) && [ -d "$d/.venv" ] && [ ! -e "$d/foo.egg-info" ] \
        && ok "--keep-venv leaves .venv, still removes egg-info" || ko "--keep-venv: $o"

    rm -rf "$d/.venv"
    o=$(main "$d") && [ -z "$o" ] && ok "nothing to remove -> exit 0, no output" || ko "empty cleanup: $o"

    # A .venv symlink pointing outside <path> is refused, and the refusal
    # comes before any delete: the egg-info next to it survives too.
    mkdir -p "$tmp/outside" "$d/foo.egg-info"; ln -s "$tmp/outside" "$d/.venv"
    main "$d" >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] && [ -d "$tmp/outside" ] && [ -d "$d/foo.egg-info" ] \
        && ok "symlink .venv outside <path> -> exit 1, nothing deleted" || ko "outside symlink: rc=$rc"
    o=$(main "$d" --keep-venv) && [ -d "$tmp/outside" ] && [ ! -e "$d/foo.egg-info" ] \
        && ok "--keep-venv never looks at the outside symlink" || ko "keep-venv + symlink: $o"

    main "$tmp/nope" >/dev/null 2>&1; [ $? = 2 ] && ok "missing <path> -> exit 2" || ko "missing path"
    main "$d" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown flag -> exit 2" || ko "unknown flag"

    [ "$fail" -eq 0 ] && printf 'ok    cleanup.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
    "") usage >&2; exit 2 ;;
esac
main "$@"
