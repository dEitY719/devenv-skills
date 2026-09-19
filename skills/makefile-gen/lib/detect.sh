#!/bin/sh
# detect.sh -- Step 1 stack detection for devenv:makefile-gen.
#
# Read-only: stats and greps files under <path>, prints key=value facts, and
# touches nothing. No network. The signal matrix and what each key maps to
# live in references/detection.md; this script is the SSOT for the rules.
#
# Usage:
#   detect.sh <path>
#   detect.sh --self-test
#
# stdout, in this order (repeatable keys print one line each, may be absent):
#   path=<dir>                      status=<ok|no-stack|no-path>
#   makefile=<present|absent>       lang=<ko|en>
#   mise_task=<name>                (repeat) [tasks.<name>] in mise.toml
#   js=<dir>|<runner>|<s1,s2,...>   (repeat) package.json dir, runner, scripts
#   py=<uv|pip>  py_version=<v>  py_reqs=<file>  py_test=pytest  py_lint=ruff
#   subapp=<dir>|<uv|pip|->|<pytest,ruff,req:F>|<mise tasks>  (repeat)
#                                   Python and/or mise.toml in an immediate
#                                   subdir (only when the root has no Python)
#   script=<rel>|<bash|sh>          (repeat) run-*.sh, scripts/{dev,start,run}.sh
#   script_sub=<rel>|<bash|sh>|<test|lint|fmt>  (repeat) case arm in one of
#                                   those scripts or tools/dev.sh; first wins
#   port=<n>                        (repeat) every port in the first server
#                                   script, then vite.config server.port
#   port_var=<NAME>  log=<path>     from the first server script
#   script_stop=<stop|down>         first script has that case arm (teardown)
#   devserver=<signal>              first script starts a dev server (vite, ...)
#   go=yes  cargo=yes  compose=<file>
#   artifact=<rel>                  (repeat) allowlist entry that is gitignored
#   warn=<text>                     (repeat) e.g. lockfile conflict
#
# exit 0 ok / no-stack; exit 1 no-path; exit 2 usage. POSIX sh only.

set -u

# The only names `clear` may ever delete (Decision 3). Anything else -- .env*,
# node_modules, .venv, .git, data dirs -- is unreachable by construction.
ALLOW='dist build out coverage .pytest_cache __pycache__ test-results playwright-report target .next .turbo'

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

# ignored <root> <rel>: is <rel> matched by <root>/.gitignore or by the
# .gitignore of its own parent dir? Plain-line matching after stripping a
# leading `**/` and trailing `/`; a leading `/` anchors the line to the dir
# of that .gitignore (root `/build` never matches `src/app/build`).
# ponytail: no negation/glob semantics; swap for `git check-ignore` if needed.
ignored() {
    _base=${2##*/}
    _par=${2%/*}; [ "$_par" = "$2" ] && _par=.
    _an=/$2
    for _gi in "$1/.gitignore" "$1/$_par/.gitignore"; do
        [ "$_gi" != "$1/./.gitignore" ] && [ -f "$_gi" ] || continue
        sed -e 's/[[:space:]]*$//' -e 's|^\*\*/||' -e 's|/$||' "$_gi" \
            | grep -qxF -e "$2" -e "$_base" -e "$_an" && return 0
        _an=/$_base
    done
    return 1
}

# py_mentions <root> <ere>: does pyproject.toml or any requirements*.txt match?
# Iterates the glob instead of word-splitting a file list, so paths with
# spaces survive and an unmatched glob is skipped rather than grepped.
py_mentions() {
    for _pf in "$1"/pyproject.toml "$1"/requirements*.txt; do
        [ -f "$_pf" ] && grep -qE "$2" "$_pf" && return 0
    done
    return 1
}

# pkg_scripts <package.json>: comma list of the "scripts" object's keys.
# jq when present; the awk fallback assumes the usual one-key-per-line layout
# and can truncate at a `}` inside a script string (e.g. `${VAR}`).
# mise_tasks <dir>: [tasks.X] names from its mise.toml / .mise.toml, one per line.
mise_tasks() {
    for _m in "$1/mise.toml" "$1/.mise.toml"; do
        [ -f "$_m" ] && sed -n 's/^\[tasks\.\"\{0,1\}\([A-Za-z0-9_:-]*\)\"\{0,1\}\][[:space:]]*$/\1/p' "$_m"
    done
}
# has_arm <script> <name>: a `name)` case arm (also `a|name)`, quoted).
has_arm() { grep -qE "^[[:space:]]*\(?([^)]*\|)?[\"']?$2[\"']?(\|[^)]*)?\)" "$1"; }
has_pytest() { [ -f "$1/pytest.ini" ] || [ -f "$1/conftest.py" ] || py_mentions "$1" 'pytest'; }
has_ruff() { [ -f "$1/ruff.toml" ] || [ -f "$1/.ruff.toml" ] || py_mentions "$1" '(^|[^a-z])ruff'; }
py_kind() { # <dir>: uv | pip | "" -- uv.lock alone is enough for uv
    _k=""
    [ -f "$1/pyproject.toml" ] || [ -f "$1/setup.py" ] && _k=pip
    for _f in "$1"/requirements*.txt; do [ -f "$_f" ] && _k=pip; done
    [ -f "$1/uv.lock" ] && _k=uv
    printf '%s' "$_k"
}
py_reqs() { for _f in requirements-dev.txt requirements.txt; do [ -f "$1/$_f" ] && { printf '%s' "$_f"; return; }; done; }

pkg_scripts() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '(.scripts // {}) | keys_unsorted | join(",")' "$1" 2>/dev/null && return
    fi
    awk '/"scripts"[[:space:]]*:/ {on=1} on {buf = buf $0} on && /}/ {exit} END {print buf}' "$1" \
        | sed 's/.*"scripts"[[:space:]]*:[[:space:]]*{//; s/}.*//' \
        | grep -o '"[^"]*"[[:space:]]*:' | sed 's/"\([^"]*\)".*/\1/' | paste -sd, -
}

runner_of() { # <dir> <label>: sets RUNNER (not echoed -- WARNS must survive)
    _r=""; _all=""
    for _p in bun:bun.lock bun:bun.lockb pnpm:pnpm-lock.yaml yarn:yarn.lock npm:package-lock.json; do
        [ -f "$1/${_p#*:}" ] || continue
        case " $_all " in *" ${_p%%:*} "*) continue ;; esac
        _all="${_all:+$_all }${_p%%:*}"
        [ -n "$_r" ] || _r=${_p%%:*}
    done
    case "$_all" in *" "*) WARNS="${WARNS}warn=lockfile conflict in $2: $_all (using $_r)
" ;; esac
    RUNNER=${_r:-npm}
}

detect() {
    root=${1%/}; [ -n "$root" ] || root=/
    if [ ! -d "$root" ]; then
        printf 'path=%s\nstatus=no-path\n' "$1"
        return 1
    fi
    WARNS=""; out=""; found=0
    add() { out="${out}$1
"; }

    [ -f "$root/Makefile" ] && mk=present || mk=absent

    lang=en
    for r in "$root"/README*; do
        [ -f "$r" ] || continue
        # Hangul lead bytes 0xEA-0xED; byte match so the locale does not matter.
        LC_ALL=C grep -q "$(printf '[\352-\355]')" "$r" && lang=ko
        break
    done

    for t in $(mise_tasks "$root"); do add "mise_task=$t"; found=1; done

    # A root package.json owns the workspace; sub-apps count only without one.
    if [ -f "$root/package.json" ]; then jsdirs=.
    else jsdirs=""; for d in "$root"/*/ "$root"/apps/*/ "$root"/src/*/; do
        d=${d%/}; case "$d" in */node_modules) continue ;; esac
        [ -f "$d/package.json" ] || continue
        case " $jsdirs " in *" ${d#"$root"/} "*) ;; *) jsdirs="$jsdirs ${d#"$root"/}" ;; esac
    done; fi
    for d in $jsdirs; do
        runner_of "$root/$d" "$d"
        add "js=$d|$RUNNER|$(pkg_scripts "$root/$d/package.json")"; found=1
    done

    py=""; pyt=""; subdirs=""
    # uv.lock alone at the root is not Python (pre-existing rule): needs a manifest.
    [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] && py=pip
    for f in "$root"/requirements*.txt; do [ -f "$f" ] && py=pip; done
    [ -n "$py" ] && [ -f "$root/uv.lock" ] && py=uv
    if [ -n "$py" ]; then
        found=1; add "py=$py"
        [ -f "$root/.python-version" ] && add "py_version=$(head -n1 "$root/.python-version")"
        rq=$(py_reqs "$root"); [ -n "$rq" ] && add "py_reqs=$rq"
        has_pytest "$root" && { add "py_test=pytest"; pyt=" . "; }
        has_ruff "$root" && add "py_lint=ruff"
    else
        # Sub-apps: an immediate subdir with Python and/or mise tasks, the way
        # frontend/ is a JS sub-app. A root Python project owns the env instead.
        for d in "$root"/*/; do
            d=${d%/}; n=${d##*/}
            case " $jsdirs " in *" $n "*) continue ;; esac
            sp=$(py_kind "$d"); mt=$(mise_tasks "$d" | paste -sd, -)
            [ -n "$sp$mt" ] || continue
            fl=""
            if [ -n "$sp" ]; then
                has_pytest "$d" && { fl=pytest; pyt="$pyt $n "; }
                has_ruff "$d" && fl="${fl:+$fl,}ruff"
                rq=$(py_reqs "$d"); [ -n "$rq" ] && fl="${fl:+$fl,}req:$rq"
            fi
            add "subapp=$n|${sp:--}|$fl|$mt"; found=1; subdirs="$subdirs $n"
        done
    fi

    first=""; subs=""
    for s in "$root"/run-*.sh "$root"/scripts/dev.sh "$root"/scripts/start.sh "$root"/scripts/run.sh "$root"/tools/dev.sh; do
        [ -f "$s" ] || continue
        head -n1 "$s" | grep -q bash && sh_='bash' || sh_='sh'
        # tools/dev.sh is a subcommand dispatcher, not a run script.
        case "$s" in "$root"/tools/*) ;; *) add "script=${s#"$root"/}|$sh_"; found=1; [ -n "$first" ] || first=$s ;; esac
        for a in test lint fmt; do
            case " $subs " in *" $a "*) continue ;; esac
            has_arm "$s" "$a" && { add "script_sub=${s#"$root"/}|$sh_|$a"; subs="$subs $a"; }
        done
    done
    ports=""
    if [ -n "$first" ]; then
        # Every port the script names: one run script may start several servers.
        ports=$(grep -oE '\$\{[A-Z_]*PORT:-[0-9]+\}|[A-Z_]*PORT=[0-9]+|--port[= ][0-9]+' "$first" | grep -oE '[0-9]+')
        pv=$(sed -n 's/.*\${\([A-Z_]*PORT\):-[0-9][0-9]*}.*/\1/p' "$first" | head -n1)
        [ -n "$pv" ] && add "port_var=$pv"
        lg=$(sed -n 's/.*LOG:-\([^"'"'"' ]*\.log\).*/\1/p' "$first" | head -n1)
        [ -n "$lg" ] || lg=$(sed -n 's/.*>[[:space:]]*\(\/[^"'"'"' ]*\.log\).*/\1/p' "$first" | head -n1)
        [ -n "$lg" ] && add "log=$lg"
        # A dev server builds/serves for itself, so run must not depend on build.
        # ponytail: word-match heuristic (comments count); extend the list as needed.
        dv=$(grep -owE -e 'vite' -e 'run dev' -e 'next dev' -e 'webpack serve' -e '--reload' "$first" | head -n1)
        [ -n "$dv" ] && add "devserver=$dv"
        # Its own teardown subcommand: a `stop)` / `down)` case arm (stop first).
        for a in stop down; do has_arm "$first" "$a" && { add "script_stop=$a"; break; }; done
    fi
    # A vite dev server's fixed port (server.port), e.g. paired with strictPort.
    for d in $jsdirs; do
        ports="$ports
$(sed -n 's/^[[:space:]]*port:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$root/$d"/vite.config.* 2>/dev/null)"
    done
    for p in $(printf '%s\n' "$ports" | awk 'NF && !s[$0]++'); do add "port=$p"; done

    [ -f "$root/go.mod" ] && { add "go=yes"; found=1; }
    [ -f "$root/Cargo.toml" ] && { add "cargo=yes"; found=1; }
    for c in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
        [ -f "$root/$c" ] && { add "compose=$c"; found=1; break; }
    done

    # clear targets: allowlist names at the root and in each app dir,
    # kept only if a .gitignore covers them. pytest self-ignores its cache.
    for d in . $jsdirs $subdirs; do
        for a in $ALLOW; do
            rel=$a; [ "$d" = . ] || rel="$d/$a"
            case "$a" in __pycache__) [ "$d" = . ] || continue ;; esac
            if ignored "$root" "$rel"; then :
            elif [ "$a" = .pytest_cache ]; then
                case "$pyt" in *" $d "*) ;; *) continue ;; esac
            else continue; fi
            add "artifact=$rel"
        done
    done

    [ "$found" -eq 1 ] && st=ok || st=no-stack
    printf 'path=%s\nstatus=%s\nmakefile=%s\nlang=%s\n%s%s' "$root" "$st" "$mk" "$lang" "$out" "$WARNS"
    return 0
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0

    want() { # <label> <dir> <line>...  -- every <line> must appear verbatim
        _l=$1; _d=$2; shift 2
        _got=$(detect "$_d")
        for _w in "$@"; do
            if printf '%s\n' "$_got" | grep -qxF -- "$_w"; then :; else
                printf 'FAIL  %s: missing "%s"\n%s\n' "$_l" "$_w" "$_got"; fail=1; return
            fi
        done
        printf 'ok    %s\n' "$_l"
    }
    deny() { # <label> <dir> <regex>  -- no line may match
        if detect "$2" | grep -qE -- "$3"; then printf 'FAIL  %s\n' "$1"; fail=1
        else printf 'ok    %s\n' "$1"; fi
    }

    # brokerdesk-shaped: pip + pytest, bun sub-app, run script with port/log.
    b=$tmp/bd; mkdir -p "$b/frontend" "$b/web/data"
    printf '3.12\n' > "$b/.python-version"
    printf 'pytest>=7\n' > "$b/requirements-dev.txt"; : > "$b/requirements.txt"
    : > "$b/pytest.ini"; : > "$b/Makefile"; printf '# 한국어\n' > "$b/README.md"
    printf '.env\n.env.*\n__pycache__/\n.venv/\nweb/data/\nfrontend/node_modules/\nfrontend/dist/\n' > "$b/.gitignore"
    printf 'node_modules/\ndist/\n/test-results/\n/playwright-report/\n.env*.local\n' > "$b/frontend/.gitignore"
    : > "$b/frontend/bun.lock"
    cat > "$b/frontend/package.json" <<'EOF'
{
  "name": "frontend",
  "scripts": {
    "start": "expo start",
    "build:web": "expo export -p web",
    "gen:api": "node scripts/gen-api.mjs",
    "test": "jest",
    "test:e2e": "bun run build:web && playwright test"
  },
  "dependencies": { "expo": "1" }
}
EOF
    cat > "$b/run-web.sh" <<'EOF'
#!/usr/bin/env bash
PORT="${WEB_PORT:-8888}"
LOG="${WEB_LOG:-/tmp/web-${PORT}.log}"
EOF
    want "brokerdesk shape" "$b" status=ok makefile=present lang=ko py=pip py_version=3.12 \
        py_reqs=requirements-dev.txt py_test=pytest \
        'js=frontend|bun|start,build:web,gen:api,test,test:e2e' 'script=run-web.sh|bash' \
        port=8888 port_var=WEB_PORT 'log=/tmp/web-${PORT}.log' \
        artifact=__pycache__ artifact=.pytest_cache artifact=frontend/dist \
        artifact=frontend/test-results artifact=frontend/playwright-report
    deny "clear never sees .env/node_modules/.venv/data" "$b" '^artifact=.*(\.env|node_modules|\.venv|data)'

    m=$tmp/mise; mkdir -p "$m"
    printf '[tools]\npython = "3.12"\n\n[tasks.build]\nrun = "x"\n\n[tasks."test"]\nrun = "y"\n' > "$m/mise.toml"
    : > "$m/pyproject.toml"; : > "$m/uv.lock"
    want "mise tasks + uv" "$m" status=ok lang=en makefile=absent mise_task=build mise_task=test py=uv

    c=$tmp/conflict; mkdir -p "$c"; printf '{"scripts": {"build": "tsc", "lint": "eslint ."}}\n' > "$c/package.json"
    : > "$c/bun.lock"; : > "$c/package-lock.json"
    want "one-line scripts + lockfile conflict" "$c" 'js=.|bun|build,lint' \
        'warn=lockfile conflict in .: bun npm (using bun)'

    a=$tmp/mono; mkdir -p "$a/apps/x" "$a/apps/y"
    echo '{"scripts":{"build":"a"}}' > "$a/apps/x/package.json"; echo '{"scripts":{"build":"b"}}' > "$a/apps/y/package.json"
    : > "$a/apps/y/pnpm-lock.yaml"
    want "apps/* sub-apps" "$a" 'js=apps/x|npm|build' 'js=apps/y|pnpm|build'

    # stock-steward shape: JS frontend + uv/mise backend sub-app, dev script
    # with a `down)` arm that never names dist.
    k=$tmp/ss; mkdir -p "$k/frontend" "$k/backend" "$k/scripts" "$k/docs"
    printf '.pytest_cache/\nfrontend/dist/\n' > "$k/.gitignore"
    echo '{"scripts":{"dev":"vite","build":"vite build"}}' > "$k/frontend/package.json"
    printf '[project]\ndependencies = ["ruff>=0.6", "pytest"]\n' > "$k/backend/pyproject.toml"; : > "$k/backend/uv.lock"
    printf '[tasks.install]\nrun = "uv sync"\n[tasks.test]\nrun = "x"\n' > "$k/backend/mise.toml"
    printf '#!/usr/bin/env bash\ncase "$1" in\n  down) DOWN=1 ;;\nesac\nnpm run dev\n' > "$k/scripts/dev.sh"
    want "python/mise sub-app + script down arm" "$k" 'subapp=backend|uv|pytest,ruff|install,test' \
        script_stop=down artifact=frontend/dist artifact=backend/.pytest_cache
    want "dev-server script -> devserver" "$k" 'devserver=run dev'
    printf '#!/bin/sh\ncase "$1" in\n  start|stop) : ;;\n  down) : ;;\nesac\nexec python -m web\n' > "$k/scripts/dev.sh"
    want "stop arm preferred over down" "$k" script_stop=stop 'script=scripts/dev.sh|sh'
    deny "plain server script -> no devserver" "$k" '^devserver='
    printf 'uvicorn app:app --reload\n' > "$k/scripts/dev.sh"
    want "--reload is a dev-server signal" "$k" 'devserver=--reload'
    p=$tmp/pipsub; mkdir -p "$p/api"; printf 'ruff\n' > "$p/api/requirements.txt"
    want "pip sub-app with requirements" "$p" 'subapp=api|pip|ruff,req:requirements.txt|'
    : > "$p/pyproject.toml"
    deny "root Python owns the env -> no sub-apps" "$p" '^subapp='

    # quantfolio shape: root uv Python, nested JS app, two-server run script,
    # tools/dev.sh with test)/fmt| case arms.
    q=$tmp/qf; mkdir -p "$q/src/frontend" "$q/scripts" "$q/tools"
    : > "$q/pyproject.toml"; : > "$q/uv.lock"; printf 'pytest\nruff\n' > "$q/requirements.txt"
    printf '/build\n' > "$q/.gitignore"; printf 'node_modules\ndist\n' > "$q/src/frontend/.gitignore"
    echo '{"scripts":{"dev":"vite","build":"vite build","test":"vitest run","lint":"eslint ."}}' > "$q/src/frontend/package.json"
    : > "$q/src/frontend/package-lock.json"
    printf 'export default {\n  server: {\n    port: 9173,\n    strictPort: true,\n  },\n}\n' > "$q/src/frontend/vite.config.ts"
    printf '#!/usr/bin/env bash\nAPI_PORT=9100\nFRONT_PORT=9173   # vite strictPort\nnpm run dev\n' > "$q/scripts/dev.sh"
    printf '#!/usr/bin/env bash\ncase "$1" in\n  up) : ;;\n  test) : ;;\n  fmt|format) : ;;\nesac\n' > "$q/tools/dev.sh"
    want "nested JS app + every port + script subcommands" "$q" py=uv 'js=src/frontend|npm|dev,build,test,lint' \
        port=9100 port=9173 'script=scripts/dev.sh|bash' 'script_sub=tools/dev.sh|bash|test' \
        'script_sub=tools/dev.sh|bash|fmt' artifact=src/frontend/dist artifact=build
    [ "$(detect "$q" | grep -c '^port=')" = 2 ] && printf 'ok    ports deduplicated\n' \
        || { printf 'FAIL  ports not deduplicated\n'; fail=1; }
    deny "tools/dev.sh is not a run script; no lint) arm -> no lint sub" "$q" '^script=tools/|^script_sub=.*\|lint$'
    deny "root /build is anchored: never src/frontend/build" "$q" '^artifact=src/frontend/build$'

    g=$tmp/go; mkdir -p "$g"; : > "$g/go.mod"; : > "$g/Cargo.toml"; : > "$g/compose.yml"
    want "go / cargo / compose" "$g" go=yes cargo=yes compose=compose.yml

    mkdir -p "$tmp/empty"
    want "no stack" "$tmp/empty" status=no-stack makefile=absent
    detect "$tmp/nope" >/dev/null && { printf 'FAIL  missing path exits 0\n'; fail=1; } \
        || printf 'ok    missing path -> status=no-path exit 1\n'

    [ "$fail" -eq 0 ] && printf 'ok    detect.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
    "") usage >&2; exit 2 ;;
esac

detect "$1"
