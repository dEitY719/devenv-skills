#!/bin/sh
# stale_scan.sh -- Step 3 artifact 4 for devenv:mise-migrate: the read-only
# legacy-workflow reference scan.
#
# The ERE and the history/archive exclusion list used to live in
# references/stale-scan.md as prose the model re-applied from memory on every
# run, which made the "[INFO] N hits excluded" count an estimate. They live
# here now, so both the hit list and the count are computed.
#
# Usage:
#   stale_scan.sh <path>
#   stale_scan.sh --self-test
#
# stdout:
#   <file>:<line>:<match>   one per live (non-excluded) hit, grep's own format
#   excluded=<n>            always last; hits suppressed as history/archive
#
# exit 0  scan completed (with or without hits -- hits are a finding, not an error)
# exit 2  usage error
#
# Never writes. The opt-in --update-docs rewrite is the skill's Step 4.5, and
# uses the replacement table in references/stale-scan.md.
#
# Called explicitly, never sourced. POSIX sh only.

set -u

# SSOT for the legacy-workflow pattern. `requirements\.txt` catches bare prose
# references ("see requirements.txt") that `pip install` alone would miss --
# uv folds those deps into pyproject.toml, so the file reference is stale too.
ERE='python -m venv|python3 -m venv|pip install|\.venv/bin/activate|\.\[dev\]|setuptools|requirements\.txt'

usage() {
    cat <<'EOF'
devenv:mise-migrate -- stale legacy-reference scan (read-only)

Usage:
  stale_scan.sh <path>
  stale_scan.sh --self-test

Prints one <file>:<line>:<match> per live hit, then excluded=<n>.
Excluded as history rather than live instructions: **/archive/**,
**/_archive/**, **/decisions/**, .venv/**, mise.toml, uv.lock, CHANGELOG*,
and *plan*.md / *spec*.md / *design*.md.
EOF
}

# History, not live instructions: these are expected to describe the old flow.
is_excluded() {
    p=$1
    case "/$p" in
        */archive/*|*/_archive/*|*/.venv/*|*/decisions/*) return 0 ;;
    esac
    case "${p##*/}" in
        CHANGELOG*|mise.toml|uv.lock) return 0 ;;
        *plan*.md|*spec*.md|*design*.md) return 0 ;;
    esac
    return 1
}

scan() {
    root=${1%/}
    [ -n "$root" ] || root=/
    if [ ! -d "$root" ]; then
        printf 'stale_scan.sh: not a directory: %s\n' "$1" >&2
        return 2
    fi

    hits=$(mktemp) || return 2
    trap 'rm -f "$hits"' EXIT INT TERM

    # -I skips binaries; .git is never live instructions.
    grep -rEnI --exclude-dir=.git -e "$ERE" -- "$root" > "$hits" 2>/dev/null

    excluded=0
    while IFS= read -r line; do
        file=${line%%:*}
        rel=${file#"$root"/}
        if is_excluded "$rel"; then
            excluded=$((excluded + 1))
        else
            printf '%s\n' "$line"
        fi
    done < "$hits"

    printf 'excluded=%s\n' "$excluded"
    rm -f "$hits"
    trap - EXIT INT TERM
    return 0
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0

    mkdir -p "$tmp/docs" "$tmp/archive" "$tmp/docs/decisions" "$tmp/.venv/bin"
    printf 'run: pip install -e ".[dev]"\n' > "$tmp/README.md"
    printf 'source .venv/bin/activate\n'    > "$tmp/docs/setup.md"
    printf 'we used pip install back then\n' > "$tmp/archive/old.md"
    printf 'the plan was python -m venv\n'   > "$tmp/docs/migration-plan.md"
    printf 'pip install decided here\n'      > "$tmp/docs/decisions/0001.md"
    printf 'pip install\n'                   > "$tmp/.venv/bin/activate"
    printf 'clean file, nothing legacy\n'    > "$tmp/NOTES.md"

    out=$(scan "$tmp") || { printf 'FAIL  scan exited non-zero\n'; return 1; }

    want_live="README.md docs/setup.md"
    for f in $want_live; do
        if printf '%s\n' "$out" | grep -q "^$tmp/$f:"; then
            printf 'ok    reported live hit %s\n' "$f"
        else
            printf 'FAIL  missing live hit %s\n' "$f"; fail=1
        fi
    done

    # README.md carries two matching alternatives on one line -> one grep line.
    live=$(printf '%s\n' "$out" | grep -vc '^excluded=')
    if [ "$live" -eq 2 ]; then
        printf 'ok    exactly 2 live hits\n'
    else
        printf 'FAIL  %s live hits (want 2):\n%s\n' "$live" "$out"; fail=1
    fi

    got=$(printf '%s\n' "$out" | sed -n 's/^excluded=//p')
    if [ "$got" = 4 ]; then
        printf 'ok    excluded=4 (archive, plan, decisions, .venv)\n'
    else
        printf 'FAIL  excluded=%s (want 4)\n%s\n' "$got" "$out"; fail=1
    fi

    if printf '%s\n' "$out" | grep -q 'NOTES.md'; then
        printf 'FAIL  clean file reported\n'; fail=1
    else
        printf 'ok    clean file not reported\n'
    fi

    [ "$fail" -eq 0 ] && printf 'ok    stale_scan.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
    "") usage >&2; exit 2 ;;
esac

scan "$1"
