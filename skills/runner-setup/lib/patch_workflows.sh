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
#
# ponytail: line-oriented awk, not a YAML parser. It assumes block-style YAML
# with consistent indentation (what `actions/starter-workflows` emits). Flow
# style (`env: {A: b}`) or a `with:` placed before `uses:` is left untouched;
# the dry-run diff is where a human catches that.
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

# transform <env> <file> -- print the patched file on stdout. Two passes over
# the same file: pass 1 learns each job's shape (key indent, whether it has a
# job-level env: block, whether UV_NATIVE_TLS is already set, whether it runs
# on ubuntu-latest / self-hosted), pass 2 emits.
transform() {
    awk -v envname="$1" '
    function ind(s) { match(s, /^ */); return RLENGTH }
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
    FNR == 1 { injobs = 0; job = ""; want_ki = 0 }
    NR == FNR {
        track($0)
        if (job == "" || !(job in kind) || ind($0) != kind[job]) {
            if (job != "" && $0 ~ /UV_NATIVE_TLS:/) hasuv[job] = 1
            next
        }
        if ($0 ~ /^ *env:[ \t]*(#.*)?$/) hasenv[job] = 1
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

        if (envname == "internal" && match(line, /^ *(- )?uses:[ \t]*jdx\/mise-action@/)) {
            pre = line; sub(/uses:.*/, "", pre)
            mise_col = length(pre); dropping = 0
            pad = sprintf("%" (mise_col + 2) "s", "")
            print pre "run: |"
            print pad "curl -fsSL https://mise.run | sh"
            print pad "echo \"$HOME/.local/bin\" >> \"$GITHUB_PATH\""
            print pad "echo \"$HOME/.local/share/mise/shims\" >> \"$GITHUB_PATH\""
            print pad "\"$HOME/.local/bin/mise\" install"
            next
        }

        atkey = (job != "" && (job in kind) && i == kind[job])
        needuv = (envname == "internal" && atkey && selfhost[job] && !hasuv[job])
        if (atkey) { kpad = sprintf("%" kind[job] "s", ""); cpad = sprintf("%" (2 * kind[job] - ji) "s", "") }

        if (atkey && line ~ ubuntu) {
            line = kpad "runs-on: [self-hosted, Linux, X64]"
        }
        print line
        if (needuv && line ~ /^ *env:[ \t]*(#.*)?$/) { print cpad "UV_NATIVE_TLS: \"true\""; hasuv[job] = 1 }
        else if (needuv && !hasenv[job] && line ~ /^ *runs-on:/) {
            print kpad "env:"; print cpad "UV_NATIVE_TLS: \"true\""; hasuv[job] = 1
        }
    }
    BEGIN { mise_col = -1; ubuntu = "^ *runs-on:[ \t]*[\"\047]?ubuntu-latest[\"\047]?[ \t]*(#.*)?$" }
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

    files=0 changed=0
    work=$(mktemp) || return 1
    for f in "$dir"/*.yml "$dir"/*.yaml; do
        [ -f "$f" ] || continue
        files=$((files + 1))
        transform "$env" "$f" > "$work" || { rm -f "$work"; return 1; }
        cmp -s "$f" "$work" && continue
        changed=$((changed + 1))
        if [ "$apply" -eq 1 ]; then
            cat "$work" > "$f"
        else
            diff -u "$f" "$work" | sed "2s|^+++ .*|+++ $f (patched)|"
        fi
        printf 'patched=%s\n' "$f"
    done
    rm -f "$work"
    if [ "$files" -eq 0 ]; then
        printf 'status=no-workflows dir=%s\n' "$dir"
        return 1
    fi
    [ "$apply" -eq 1 ] && mode=apply || mode=dry-run
    printf 'mode=%s changed=%s files=%s\n' "$mode" "$changed" "$files"
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
    [ "$(grep -c "mise.run | sh" "$got")" -eq 2 ]; ck "manual install inserted twice"
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
