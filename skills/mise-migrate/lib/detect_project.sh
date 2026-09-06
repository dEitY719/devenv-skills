#!/bin/sh
# detect_project.sh -- Step 1 detection for devenv:mise-migrate.
#
# The decision tree in references/detection.md, coded once instead of walked by
# hand on every run. Read-only: it stats files and prints, and touches nothing.
#
# Usage:
#   detect_project.sh <path>
#   detect_project.sh --self-test
#
# stdout, always in this order:
#   path=<resolved path>            the (possibly retargeted) project dir
#   status=<ok|nested|already-migrated|no-marker|ambiguous>
#   candidate=<dir>                 one per line, only when status=ambiguous
#
# exit 0  ok / nested / already-migrated  -- proceed (or stop as an idempotent no-op)
# exit 1  no-marker / ambiguous           -- refusal, per references/detection.md
# exit 2  usage error
#
# Called explicitly, never sourced. POSIX sh only.

set -u

usage() {
    cat <<'EOF'
devenv:mise-migrate -- legacy Python project detection (Step 1)

Usage:
  detect_project.sh <path>
  detect_project.sh --self-test

Markers: pyproject.toml, setup.py, requirements*.txt.
No marker at <path> but exactly one direct child dir has one -> retarget to it
(status=nested). Two or more -> status=ambiguous (exit 1). None -> no-marker
(exit 1). A mise.toml at the resolved path -> already-migrated (exit 0).
EOF
}

has_marker() {
    [ -f "$1/pyproject.toml" ] && return 0
    [ -f "$1/setup.py" ] && return 0
    # Plain glob, not `ls`: the nested scan calls this once per child dir, and
    # a fork per child to test a glob the shell can test itself is waste. An
    # unmatched glob stays literal in POSIX sh, so `[ -f ]` rejects it.
    for _m in "$1"/requirements*.txt; do
        [ -f "$_m" ] && return 0
    done
    return 1
}

detect() {
    root=${1%/}
    [ -n "$root" ] || root=/
    if [ ! -d "$root" ]; then
        printf 'path=%s\nstatus=no-marker\n' "$1"
        return 1
    fi

    target=$root
    status=ok
    candidates=""

    if ! has_marker "$root"; then
        n=0
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            d=${d%/}
            has_marker "$d" || continue
            n=$((n + 1))
            target=$d
            candidates="${candidates}candidate=${d}
"
        done
        if [ "$n" -eq 1 ]; then
            status=nested
        else
            target=$root
            [ "$n" -eq 0 ] && status=no-marker || status=ambiguous
        fi
    fi

    case "$status" in
        ok|nested) [ -f "$target/mise.toml" ] && status=already-migrated ;;
    esac

    printf 'path=%s\nstatus=%s\n' "$target" "$status"
    [ "$status" = ambiguous ] && printf '%s' "$candidates"

    case "$status" in
        no-marker|ambiguous) return 1 ;;
        *) return 0 ;;
    esac
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0

    check() { # <label> <dir> <want-status> <want-exit>
        got=$(detect "$2"); rc=$?
        gs=$(printf '%s\n' "$got" | sed -n 's/^status=//p')
        if [ "$gs" != "$3" ] || [ "$rc" -ne "$4" ]; then
            printf 'FAIL  %s: status=%s exit=%s (want %s / %s)\n' "$1" "$gs" "$rc" "$3" "$4"
            fail=1
        else
            printf 'ok    %s (status=%s exit=%s)\n' "$1" "$gs" "$rc"
        fi
    }

    mkdir -p "$tmp/plain" && : > "$tmp/plain/pyproject.toml"
    check "marker at path" "$tmp/plain" ok 0

    mkdir -p "$tmp/req" && : > "$tmp/req/requirements-dev.txt"
    check "requirements*.txt marker" "$tmp/req" ok 0

    mkdir -p "$tmp/done" && : > "$tmp/done/setup.py" && : > "$tmp/done/mise.toml"
    check "already migrated" "$tmp/done" already-migrated 0

    mkdir -p "$tmp/outer/inner" && : > "$tmp/outer/inner/pyproject.toml"
    check "nested retarget" "$tmp/outer" nested 0
    # $got still holds that run's output -- no need to detect() twice.
    got=$(printf '%s\n' "$got" | sed -n 's/^path=//p')
    if [ "$got" != "$tmp/outer/inner" ]; then
        printf 'FAIL  nested retarget path: %s\n' "$got"; fail=1
    else
        printf 'ok    nested retarget path\n'
    fi

    mkdir -p "$tmp/two/a" "$tmp/two/b" && : > "$tmp/two/a/setup.py" && : > "$tmp/two/b/setup.py"
    check "two candidates" "$tmp/two" ambiguous 1
    n=$(detect "$tmp/two" | grep -c '^candidate=')
    [ "$n" -eq 2 ] || { printf 'FAIL  candidate lines: %s (want 2)\n' "$n"; fail=1; }

    mkdir -p "$tmp/empty"
    check "no marker anywhere" "$tmp/empty" no-marker 1
    check "missing dir" "$tmp/nope" no-marker 1

    [ "$fail" -eq 0 ] && printf 'ok    detect_project.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
    "") usage >&2; exit 2 ;;
esac

detect "$1"
