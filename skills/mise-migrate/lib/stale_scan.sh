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
# exit 2  usage error, or grep could not read part of <path>: a scan that
#         skipped files is NOT reported as a clean scan
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

# A literal newline, for the newline-path fixture in self_test().
_NL=$(printf '\nx'); _NL=${_NL%x}

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

scan() {
    root=${1%/}
    [ -n "$root" ] || root=/
    if [ ! -d "$root" ]; then
        printf 'stale_scan.sh: not a directory: %s\n' "$1" >&2
        return 2
    fi

    # Bulk NUL-delimited first pass, same as the old `grep -rlEI`: only
    # files that actually contain a hit are ever touched again, so this
    # keeps the original single-scan efficiency instead of spawning a grep
    # per file in the whole tree. `-Z` NUL-terminates each printed
    # pathname -- unlike the newline it normally prints between paths, a
    # literal newline (POSIX permits one) inside a filename can't be
    # mistaken for the separator. `xargs -0` then hands those names to the
    # classify/print step's argv exactly like `find -exec ... {} +` would:
    # batched, but never round-tripped through a line-oriented stream.
    # -I skips binaries; .git is never live instructions.
    filelist=$(mktemp) || filelist=
    excl_file=$(mktemp) || excl_file=
    if [ -z "$filelist" ] || [ -z "$excl_file" ]; then
        printf 'stale_scan.sh: mktemp failed\n' >&2
        rm -f "${filelist:-}" "${excl_file:-}"
        return 2
    fi
    grep -rlZEI --exclude-dir=.git -e "$ERE" -- "$root" > "$filelist"
    grc=$?
    # 0 = matches, 1 = none, >=2 = a real error (an unreadable path, a bad
    # ERE, a directory grep couldn't even traverse). Never swallowed: a scan
    # that quietly skipped files and still reported success is exactly the
    # silent regression this step exists to surface, one level up.
    if [ "$grc" -ge 2 ]; then
        printf 'stale_scan.sh: grep failed (rc=%s) -- scan incomplete\n' "$grc" >&2
        rm -f "$filelist" "$excl_file"
        return 2
    fi

    printf '0\n' > "$excl_file"
    if [ "$grc" -eq 0 ]; then
        # shellcheck disable=SC2016  # $ere/$excl_file/$root/$f are the child
        # sh -c's own positional params, not meant to expand in this shell.
        xargs -0 sh -c '
            ere=$1; shift
            excl_file=$1; shift
            root=$1; shift
            # Duplicated from the top-level exclusion rules rather than
            # shared: this body runs in a separate sh -c child, and POSIX sh
            # has no way to export a function into it.
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
            # A plain variable is enough here -- this whole for loop runs in
            # one sh -c child for the batch, so the count only needs to
            # reach the shared file once, after the loop, not once per
            # excluded file.
            excl=0
            for f in "$@"; do
                rel=${f#"$root"}
                rel=${rel#/}
                if is_excluded "$rel"; then
                    # Count lines, do not print them. rc>=2 is unreachable --
                    # the first pass already read this same file -- so a
                    # bare fallback is enough here.
                    n=$(grep -cEI -e "$ere" -- "$f") || n=0
                    excl=$((excl + n))
                else
                    grep -nEI -e "$ere" -- "$f" | while IFS= read -r hit; do
                        printf "%s:%s\n" "$f" "$hit"
                    done
                fi
            done
            if [ "$excl" -gt 0 ]; then
                cur=$(cat "$excl_file")
                echo $((cur + excl)) > "$excl_file"
            fi
        ' sh "$ERE" "$excl_file" "$root" < "$filelist"
    fi

    excluded=$(cat "$excl_file")
    rm -f "$filelist" "$excl_file"
    printf 'excluded=%s\n' "$excluded"
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
    # Colons in paths: the reason scan() never splits a grep record at ':'.
    # Splitting would truncate these two to "$tmp/archive/we" and "$tmp/od",
    # flipping BOTH verdicts -- the archived one would be reported as live and
    # the live one would be dropped.
    printf 'pip install, archived\n'         > "$tmp/archive/we:ird.md"
    printf 'pip install, live\n'             > "$tmp/od:d.md"

    out=$(scan "$tmp") || { printf 'FAIL  scan exited non-zero\n'; return 1; }

    want_live="README.md docs/setup.md od:d.md"
    for f in $want_live; do
        if printf '%s\n' "$out" | grep -q "^$tmp/$f:"; then
            printf 'ok    reported live hit %s\n' "$f"
        else
            printf 'FAIL  missing live hit %s\n' "$f"; fail=1
        fi
    done

    # README.md carries two matching alternatives on one line -> one grep line.
    live=$(printf '%s\n' "$out" | grep -vc '^excluded=')
    if [ "$live" -eq 3 ]; then
        printf 'ok    exactly 3 live hits\n'
    else
        printf 'FAIL  %s live hits (want 3):\n%s\n' "$live" "$out"; fail=1
    fi

    got=$(printf '%s\n' "$out" | sed -n 's/^excluded=//p')
    if [ "$got" = 5 ]; then
        printf 'ok    excluded=5 (archive x2, plan, decisions, .venv)\n'
    else
        printf 'FAIL  excluded=%s (want 5)\n%s\n' "$got" "$out"; fail=1
    fi

    if printf '%s\n' "$out" | grep -q 'NOTES.md'; then
        printf 'FAIL  clean file reported\n'; fail=1
    else
        printf 'ok    clean file not reported\n'
    fi

    # A newline in a path (POSIX permits one) must be scanned and reported
    # intact, not refused and not split into two bogus entries. Compare with
    # embedded newlines folded to a sentinel byte, so the check itself does
    # not care whether the record prints across two terminal lines -- only
    # that the file's full name and its hit are one unbroken substring.
    nlfile="$tmp/two${_NL}lines.md"
    printf 'pip install\n' > "$nlfile"
    out=$(scan "$tmp")
    rc=$?
    rm -f "$nlfile"
    want=$(printf '%s:1:pip install' "$nlfile" | tr '\n' '\001')
    got=$(printf '%s' "$out" | tr '\n' '\001')
    if [ "$rc" -eq 0 ] && printf '%s' "$got" | grep -Fq "$want"; then
        printf 'ok    newline in a path is scanned and reported intact\n'
    else
        printf 'FAIL  newline-path hit missing or split (rc=%s):\n%s\n' "$rc" "$out"; fail=1
    fi

    # An unreadable path must fail the scan, not pass it quietly. Skipped as
    # root, where chmod 000 does not deny anything.
    if [ "$(id -u)" -eq 0 ]; then
        printf 'ok    unreadable-path check skipped (running as root)\n'
    else
        mkdir -p "$tmp/locked" && printf 'pip install\n' > "$tmp/locked/x.md"
        chmod 000 "$tmp/locked"
        scan "$tmp" >/dev/null 2>&1
        rc=$?
        chmod 755 "$tmp/locked"
        if [ "$rc" -ne 0 ]; then
            printf 'ok    unreadable path fails the scan (rc=%s)\n' "$rc"
        else
            printf 'FAIL  unreadable path reported a clean scan\n'; fail=1
        fi
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
