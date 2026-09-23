#!/bin/sh
# patch_workflows.sh -- Step 5 of devenv:runner-setup: move a repo's GitHub
# Actions workflows onto the self-hosted runner that register_runner.sh set up.
#
# Usage:
#   patch_workflows.sh [--env internal|public] [--apply] [dir]
#   patch_workflows.sh --self-test
#
# dir defaults to .github/workflows. Every *.yml / *.yaml directly in it is
# rewritten per references/workflow-migration.md:
#   all       runs-on: ubuntu-latest      -> runs-on: [self-hosted, Linux, X64]
#   internal  uses: jdx/mise-action@...   -> manual mise install `run:` step
#   internal  self-hosted job env         += UV_NATIVE_TLS: "true"
#
# Without --apply (the default) it writes nothing and prints a `diff -u` per
# file that would change. With --apply it rewrites those files in place.
# The rewrite is idempotent: a second run over its own output changes nothing.
#
# stdout (after any diffs):
#   patched=<file>                      one per changed file (both modes)
#   mode=<dry-run|apply> changed=<n> files=<m>
#
# exit 0  done (with or without changes)
# exit 1  dir missing or holds no workflow files
# exit 2  usage error
# exit 3  done, but a shape was refused (see the warn= lines)
#
# A refused shape is printed before the summary, one per line, and left as is:
#   warn=<file>:<line> <reason>
# They are: runs-on other than ubuntu-latest that still looks Linux-bound
# (ubuntu-22.04, ${{ ... }}, list or block form), a `with:` before
# `uses: jdx/mise-action` in one step, and a job env that is neither a block
# nor a one-line flow mapping (`env: {A: b}` is rewritten in place).
#
# ponytail: line-oriented awk, not a YAML parser -- known shapes are rewritten
# or refused, anything stranger (multi-line flow, anchors) passes through; the
# dry-run diff is where a human catches that. A YAML parser would reorder
# comments and keys; add one only if refusals become common.
#
# Called explicitly, never sourced. POSIX sh only.

set -u

usage() {
    cat <<'EOF'
devenv:runner-setup -- workflow patcher (dry-run unless --apply)

Usage:
  patch_workflows.sh [--env internal|public] [--apply] [dir]
  patch_workflows.sh --self-test

dir defaults to .github/workflows.
EOF
}

# transform <env> <file> <warnfile> -- print the patched file on stdout. Two passes over
# the same file: pass 1 learns each job's shape (key indent, whether it has a
# job-level env: block, whether UV_NATIVE_TLS is already set, whether it runs
# on ubuntu-latest / self-hosted), pass 2 emits. A shape it will not rewrite
# is appended to <warnfile> as `warn=<file>:<line> <reason>` and left as is.
transform() {
    awk -v envname="$1" -v warnf="$3" '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function warn(why) { printf "warn=%s:%d %s\n", FILENAME, FNR, why > warnf }
    function blank(s) { return s ~ /^[ \t]*(#.*)?$/ }
    # Track the current job for either pass. Sets job, ki (job key indent).
    function track(line,   i) {
        if (blank(line)) return
        i = ind(line)
        if (line ~ /^jobs:[ \t]*(#.*)?$/) { injobs = 1; ji = -1; job = ""; return }
        if (i == 0) { injobs = 0; job = ""; return }
        if (!injobs) return
        if (ji < 0) ji = i
        if (i == ji) { job = line; sub(/^ */, "", job); sub(/:.*/, "", job); want_ki = 1; return }
        if (job != "" && want_ki) { kind[job] = i; want_ki = 0 }
    }
    FNR == 1 { injobs = 0; job = ""; want_ki = 0; stepcol = -1; envci_job = "" }
    NR == FNR {
        # Step tracking: a with: key seen before uses: jdx/mise-action in the
        # same list item marks that uses: line for refusal in pass 2.
        if (!blank($0)) {
            si = ind($0)
            if ($0 ~ /^ *- / && (stepcol < 0 || si + 2 <= stepcol)) { stepcol = si + 2; stepwith = ($0 ~ /^ *- with:/) }
            else if (stepcol >= 0 && si < stepcol) stepcol = -1
            else if (si == stepcol && $0 ~ /^ *with:/) stepwith = 1
            if (stepcol >= 0 && stepwith && $0 ~ mise) badmise[FNR] = 1
            if (envci_job != "") { envci[envci_job] = si; envci_job = "" }
        }
        track($0)
        if (job != "" && $0 ~ /UV_NATIVE_TLS:/) hasuv[job] = 1
        if (job == "" || !(job in kind) || ind($0) != kind[job]) next
        if ($0 ~ /^ *env:/) hasenv[job] = 1
        if ($0 ~ /^ *env:[ \t]*(#.*)?$/) envci_job = job
        if ($0 ~ ubuntu || $0 ~ /^ *runs-on:.*self-hosted/) selfhost[job] = 1
        next
    }
    {
        line = $0
        track(line)
        i = ind(line)

        # Inside a replaced mise-action step: drop its with: block.
        if (mise_col >= 0) {
            if (!blank(line)) {
                if (i < mise_col || (i == mise_col - 2 && line ~ /^ *- /)) { mise_col = -1; dropping = 0 }
                else if (i == mise_col) dropping = (line ~ /^ *with:[ \t]*(#.*)?$/)
            }
            if (dropping) next
        }

        if (envname == "internal" && line ~ mise) {
            if (FNR in badmise) warn("with: before uses: jdx/mise-action; step left as is")
            else {
                pre = line; sub(/uses:.*/, "", pre)
                mise_col = length(pre); dropping = 0
                pad = sprintf("%" (mise_col + 2) "s", "")
                print pre "run: |"
                print pad "curl -fsSL \"${MISE_INSTALL_URL:-https://mise.run}\" | sh"
                print pad "echo \"$HOME/.local/bin\" >> \"$GITHUB_PATH\""
                print pad "echo \"$HOME/.local/share/mise/shims\" >> \"$GITHUB_PATH\""
                print pad "\"$HOME/.local/bin/mise\" install"
                next
            }
        }

        atkey = (job != "" && (job in kind) && i == kind[job])
        needuv = (envname == "internal" && atkey && selfhost[job] && !hasuv[job])
        if (atkey) { kpad = sprintf("%" kind[job] "s", ""); cpad = sprintf("%" ((job in envci) ? envci[job] : 2 * kind[job] - ji) "s", "") }

        if (atkey && line ~ ubuntu) {
            line = kpad "runs-on: [self-hosted, Linux, X64]"
        } else if (atkey && line ~ /^ *runs-on:/ && line !~ /self-hosted/) {
            v = line; sub(/^ *runs-on:[ \t]*/, "", v); sub(/[ \t]*#.*$/, "", v)
            if (v == "" || v ~ /^[[{]|\$\{\{|ubuntu/)
                warn("runs-on: " (v == "" ? "block form" : v) " is not ubuntu-latest; left as is")
        }
        # One-line flow env (`env: {A: b}`) gains the key inside the braces;
        # any other non-block env value is refused.
        if (needuv && line ~ /^ *env:[ \t]*[^ \t#]/) {
            if (line ~ /^ *env:[ \t]*\{[^{}]*\}[ \t]*(#.*)?$/) {
                p = index(line, "}"); head = substr(line, 1, p - 1); sub(/[ \t]*$/, "", head)
                line = head (head ~ /\{$/ ? "" : head ~ /,$/ ? " " : ", ") "UV_NATIVE_TLS: \"true\"" substr(line, p)
            } else warn("job env: is not a block or one-line flow mapping; add UV_NATIVE_TLS by hand")
            hasuv[job] = 1
        }
        print line
        if (needuv && line ~ /^ *env:[ \t]*(#.*)?$/) { print cpad "UV_NATIVE_TLS: \"true\""; hasuv[job] = 1 }
        else if (needuv && !hasenv[job] && line ~ /^ *runs-on:/) {
            print kpad "env:"; print cpad "UV_NATIVE_TLS: \"true\""; hasuv[job] = 1
        }
    }
    BEGIN { mise_col = -1; ubuntu = "^ *runs-on:[ \t]*[\"\047]?ubuntu-latest[\"\047]?[ \t]*(#.*)?$"; mise = "^ *(- )?uses:[ \t]*jdx/mise-action@" }
    ' "$2" "$2"
}

run() {
    env=internal apply=0 dir=.github/workflows
    while [ $# -gt 0 ]; do
        case "$1" in
            --env) [ $# -ge 2 ] || { usage >&2; return 2; }; env=$2; shift ;;
            --env=*) env=${1#--env=} ;;
            --apply) apply=1 ;;
            --dry-run) apply=0 ;;
            -*) usage >&2; return 2 ;;
            *) dir=$1 ;;
        esac
        shift
    done
    case "$env" in internal|public) ;; *) usage >&2; return 2 ;; esac

    files=0 changed=0 warned=0
    work=$(mktemp) || return 1
    warns=$(mktemp) || { rm -f "$work"; return 1; }
    for f in "$dir"/*.yml "$dir"/*.yaml; do
        [ -f "$f" ] || continue
        files=$((files + 1))
        : > "$warns"
        transform "$env" "$f" "$warns" > "$work" || { rm -f "$work" "$warns"; return 1; }
        if [ -s "$warns" ]; then cat "$warns"; warned=1; fi
        cmp -s "$f" "$work" && continue
        changed=$((changed + 1))
        if [ "$apply" -eq 1 ]; then
            cat "$work" > "$f"
        else
            diff -u "$f" "$work" | sed "2s|^+++ .*|+++ $f (patched)|"
        fi
        printf 'patched=%s\n' "$f"
    done
    rm -f "$work" "$warns"
    if [ "$files" -eq 0 ]; then
        printf 'status=no-workflows dir=%s\n' "$dir"
        return 1
    fi
    [ "$apply" -eq 1 ] && mode=apply || mode=dry-run
    printf 'mode=%s changed=%s files=%s\n' "$mode" "$changed" "$files"
    [ "$warned" -eq 0 ] || return 3
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0
    # ck <label> -- judge the exit status of the command right before it.
    ck() { if [ $? -eq 0 ]; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fail=1; fi; }

    mkdir -p "$tmp/wf"
    cat > "$tmp/wf/ci.yml" <<'EOF'
name: ci
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
        with:
          install: true
      - name: Test
        run: make test
  lint:
    runs-on: "ubuntu-latest"
    env:
      FOO: bar
    steps:
      - name: Setup mise
        uses: jdx/mise-action@v2
        with:
          cache: true
        id: mise
      - run: make lint
  other:
    runs-on: windows-latest
    steps:
      - run: echo hi
EOF
    cp "$tmp/wf/ci.yml" "$tmp/orig.yml"

    out=$(run --env internal "$tmp/wf")
    printf "%s\n" "$out" | grep -q "^mode=dry-run changed=1 files=1$"; ck "dry-run reports the change"
    cmp -s "$tmp/wf/ci.yml" "$tmp/orig.yml"; ck "dry-run writes nothing"

    run --env internal --apply "$tmp/wf" > /dev/null
    got=$tmp/wf/ci.yml
    [ "$(grep -c "runs-on: \[self-hosted, Linux, X64\]" "$got")" -eq 2 ]; ck "runs-on rewritten (bare + quoted)"
    grep -q "runs-on: windows-latest" "$got"; ck "non-ubuntu runner untouched"
    ! grep -q "jdx/mise-action" "$got"; ck "mise-action removed"
    ! grep -q "install: true\|cache: true" "$got"; ck "mise with: blocks dropped"
    grep -q "        id: mise" "$got" && grep -q "name: Setup mise" "$got"; ck "sibling step keys kept"
    [ "$(grep -c "MISE_INSTALL_URL:-https://mise.run}\" | sh" "$got")" -eq 2 ]; ck "manual install inserted twice"
    sed -n "/^  test:/,/^  lint:/p" "$got" | grep -q "^    env:$"; ck "env block added to job without one"
    [ "$(grep -c "^      UV_NATIVE_TLS: \"true\"$" "$got")" -eq 2 ]; ck "UV_NATIVE_TLS in both self-hosted jobs"
    grep -q "^      FOO: bar$" "$got"; ck "existing env kept"
    ! sed -n "/^  other:/,\$p" "$got" | grep -q UV_NATIVE_TLS; ck "no UV_NATIVE_TLS on windows job"
    ! python3 -c "import yaml" 2>/dev/null || python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1]))" "$got"; ck "result is valid YAML (when PyYAML is present)"

    cp "$got" "$tmp/once.yml"
    out=$(run --env internal --apply "$tmp/wf")
    cmp -s "$got" "$tmp/once.yml" && printf "%s\n" "$out" | grep -q "changed=0"; ck "idempotent second run"

    cp "$tmp/orig.yml" "$got"
    run --env public --apply "$tmp/wf" > /dev/null
    [ "$(grep -c "self-hosted" "$got")" -eq 2 ] && grep -q "jdx/mise-action" "$got" && ! grep -q UV_NATIVE_TLS "$got"; ck "public: runs-on only"

    # Issue #30 shapes, one dir each so a warn from one cannot mask another.
    mkdir "$tmp/flow" "$tmp/with" "$tmp/runs" "$tmp/indent"
    cat > "$tmp/flow/ci.yml" <<'EOF'
jobs:
  a:
    runs-on: ubuntu-latest
    env: {FOO: bar}  # note
    steps:
      - run: make
  b:
    runs-on: ubuntu-latest
    env: {}
    steps:
      - run: make
EOF
    run --env internal --apply "$tmp/flow" > /dev/null; rc=$?
    got=$tmp/flow/ci.yml
    [ "$rc" -eq 0 ] && [ "$(grep -c "env:" "$got")" -eq 2 ] &&
        grep -q '^    env: {FOO: bar, UV_NATIVE_TLS: "true"}  # note$' "$got" &&
        grep -q '^    env: {UV_NATIVE_TLS: "true"}$' "$got"; ck "flow-style job env gains UV_NATIVE_TLS in place"
    cp "$got" "$tmp/once.yml"; run --env internal --apply "$tmp/flow" > /dev/null
    cmp -s "$got" "$tmp/once.yml"; ck "flow-style env rewrite is idempotent"

    cat > "$tmp/with/ci.yml" <<'EOF'
jobs:
  a:
    runs-on: [self-hosted, Linux, X64]
    env:
      UV_NATIVE_TLS: "true"
    steps:
      - name: mise
        with:
          install: true
        uses: jdx/mise-action@v2
EOF
    cp "$tmp/with/ci.yml" "$tmp/once.yml"
    out=$(run --env internal --apply "$tmp/with"); rc=$?
    [ "$rc" -eq 3 ] && cmp -s "$tmp/with/ci.yml" "$tmp/once.yml" &&
        printf "%s\n" "$out" | grep -q "^warn=$tmp/with/ci.yml:10 with: before uses: jdx/mise-action"; ck "with: before mise-action is refused with warn + exit 3"

    cat > "$tmp/runs/ci.yml" <<'EOF'
jobs:
  a:
    runs-on: ubuntu-22.04
  b:
    runs-on: ${{ matrix.os }}
  c:
    runs-on: [ubuntu-latest]
  d:
    runs-on:
      - ubuntu-latest
  e:
    runs-on: macos-latest
EOF
    out=$(run --env internal "$tmp/runs"); rc=$?
    [ "$rc" -eq 3 ] && [ "$(printf "%s\n" "$out" | grep -c "^warn=$tmp/runs/ci.yml:")" -eq 4 ] &&
        printf "%s\n" "$out" | grep -q "^warn=$tmp/runs/ci.yml:3 " &&
        printf "%s\n" "$out" | grep -q "^warn=$tmp/runs/ci.yml:9 "; ck "unhandled runs-on shapes warn, other OS stays quiet"

    cat > "$tmp/indent/ci.yml" <<'EOF'
jobs:
    build:
        runs-on: ubuntu-latest
        env:
          FOO: bar
        steps:
          - run: make
EOF
    run --env internal --apply "$tmp/indent" > /dev/null
    grep -q '^          UV_NATIVE_TLS: "true"$' "$tmp/indent/ci.yml" &&
        { ! python3 -c "import yaml" 2>/dev/null || python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1]))" "$tmp/indent/ci.yml"; }; ck "UV_NATIVE_TLS follows the env block's own indent"

    mkdir "$tmp/empty"
    run "$tmp/empty" > /dev/null; rc=$?
    [ "$rc" -eq 1 ]; ck "empty dir exits 1"
    run --env bogus "$tmp/wf" 2> /dev/null; rc=$?
    [ "$rc" -eq 2 ]; ck "bad --env exits 2"

    [ "$fail" -eq 0 ] && printf 'ok    patch_workflows.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
esac

run "$@"
