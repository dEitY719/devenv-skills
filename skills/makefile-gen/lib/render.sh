#!/bin/sh
# render.sh -- Steps 2-4 for devenv:makefile-gen: map detect.sh facts to a
# Makefile, and check / verify a Makefile against the skill's contract.
#
# Usage:
#   render.sh <path> [--port N] [--lang ko|en]   print the Makefile to stdout
#   render.sh <path> ... --report                 print target sources + skips
#   render.sh --check <Makefile>                  static contract check
#   render.sh --verify <dir>                      `make` + `make -n <t>` for all
#   render.sh --self-test
#
# Rendering and --check never write; --verify runs make in dry-run (-n) mode
# only, apart from `make` itself, which runs the side-effect-free help target.
# Mapping rules: references/target-catalog.md. POSIX sh only.

set -u
HERE=$(dirname "$0")
TAB=$(printf '\t')
NL='
'

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- facts ------
load() { # <detect output> -> globals
    MISE=""; JS=""; SCRIPTS=""; ARTS=""
    PY=""; PYV=""; PYREQS=""; PYTEST=""; PYLINT=""; PORT=""; PORTVAR=""; LOG=""
    GO=""; CARGO=""; COMPOSE=""; DLANG=en; ST=""; WARNS=""
    _o=$IFS; IFS=$NL
    for _l in $1; do
        _k=${_l%%=*}; _v=${_l#*=}
        case "$_k" in
            status) ST=$_v ;; lang) DLANG=$_v ;;
            mise_task) MISE="$MISE $_v" ;;
            js) JS="$JS$_v$NL" ;;
            script) SCRIPTS="$SCRIPTS$_v$NL" ;;
            artifact) ARTS="$ARTS $_v" ;;
            py) PY=$_v ;; py_version) PYV=$_v ;; py_reqs) PYREQS=$_v ;;
            py_test) PYTEST=$_v ;; py_lint) PYLINT=$_v ;;
            port) PORT=$_v ;; port_var) PORTVAR=$_v ;; log) LOG=$_v ;;
            go) GO=1 ;; cargo) CARGO=1 ;; compose) COMPOSE=$_v ;;
            warn) WARNS="${WARNS}warn=$_v$NL" ;;
        esac
    done
    IFS=$_o
}

L() { [ "$LANG_" = ko ] && printf '%s' "$1" || printf '%s' "$2"; }

# js_hits <name>...: "dir<TAB>runner<TAB>script" per app, first matching name.
js_hits() {
    printf '%s' "$JS" | while IFS='|' read -r _d _r _s; do
        [ -n "$_d" ] || continue
        for _n in "$@"; do
            case ",$_s," in *",$_n,"*) printf '%s\t%s\t%s\n' "$_d" "$_r" "$_n"; break ;; esac
        done
    done
}
js_cmd() { # <hit line> -> shell command
    _d=${1%%"$TAB"*}; _rest=${1#*"$TAB"}; _r=${_rest%%"$TAB"*}; _s=${_rest#*"$TAB"}
    [ "$_d" = . ] && printf '%s run %s' "$_r" "$_s" || printf 'cd %s && %s run %s' "$_d" "$_r" "$_s"
}
js_src() { printf '%s/package.json scripts.%s' "${1%%"$TAB"*}" "${1##*"$TAB"}"; }

# ---------------------------------------------------------------- emit -------
target() { # <name> <deps> <desc> <source>
    NAMES="$NAMES $1"
    BODY="$BODY$NL$1:${2:+ $2} ## $3$NL"
    REPORT="${REPORT}target=$1${TAB}source=$4$NL"
}
r() { BODY="$BODY$TAB$1$NL"; }
skip() { REPORT="${REPORT}skip=$1${TAB}reason=$2$NL"; }
mise_t() { case " $MISE " in *" $1 "*) USED="$USED $1"; return 0 ;; esac; return 1; }
has_t() { case " $NAMES " in *" $1 "*) return 0 ;; esac; return 1; }
each() { # <hits> <fn>: call fn per hit line, in this shell (no pipe subshell)
    _o=$IFS; IFS=$NL; set -f
    for _h in $1; do IFS=$_o; "$2" "$_h"; done
    IFS=$_o; set +f
}
r_js() { r "$(js_cmd "$1")"; }
srcs() { # <hits> -> "a, b"
    printf '%s\n' "$1" | while IFS= read -r _h; do [ -n "$_h" ] && js_src "$_h" && printf ', '; done | sed 's/, $//'
}

render() { # <path> -> sets BODY, NAMES, REPORT, VARS
    NAMES=""; BODY=""; REPORT=""; USED=""
    pyrun() { [ "$PY" = uv ] && printf 'uv run %s' "$1" || printf '$(PY) -m %s' "$1"; }

    # help
    target help "" "$(L '이 도움말' 'Show this help')" "skill template"
    r "@awk 'BEGIN {FS = \":.*## \"} /^[a-zA-Z0-9_-]+:.*## / {printf \"  make %-10s %s\\n\", \$\$1, \$\$2}' \$(MAKEFILE_LIST)"

    # setup
    if mise_t setup; then
        target setup "" "$(L '최초 1회: 의존성 설치' 'First-time setup: install dependencies')" "mise.toml [tasks.setup]"
        r "mise run setup"
    elif [ -n "$PY$JS" ]; then
        _v=$(printf '%s' "$PYV" | cut -d. -f1,2)
        _pd=""; _s=""
        [ -n "$PY" ] && { _pd=" .venv${_v:+ (Python $_v)} +"; _s="${PYREQS:-pyproject.toml}${_v:+ + .python-version}"; }
        [ -n "$JS" ] && _s="${_s:+$_s + }package.json"
        target setup "" "$(L "최초 1회:$_pd 의존성 설치" "First-time setup:$_pd install dependencies")" "$_s"
        if [ "$PY" = uv ]; then r "uv sync"
        elif [ -n "$PY" ]; then
            if [ -n "$_v" ]; then
                r "@test -x .venv/bin/python || { PYV=\$\$(command -v python$_v || command -v python3); \"\$\$PYV\" -m venv .venv; }"
            else r "@test -x .venv/bin/python || python3 -m venv .venv"; fi
            [ -n "$PYREQS" ] && r ".venv/bin/pip install -q -r $PYREQS" || r ".venv/bin/pip install -q -e ."
        fi
        _inst() { _d=${1%%|*}; _r=${1#*|}; _r=${_r%%|*}
            [ "$_d" = . ] && r "$_r install" || r "cd $_d && $_r install"; }
        each "$JS" _inst
    else skip setup "no dependency manifest (pyproject/requirements/package.json/mise)"; fi

    # build
    BUILD_REAL=1; BHITS=$(js_hits build build:web)
    if mise_t build; then
        target build "" "$(L '빌드' 'Build')" "mise.toml [tasks.build]"; r "mise run build"
    elif [ -n "$BHITS" ] && [ "$(printf '%s\n' "$BHITS" | wc -l)" -gt 1 ]; then
        _deps=""
        for _d in $(printf '%s\n' "$BHITS" | cut -f1); do _deps="$_deps build-${_d##*/}"; done
        target build "${_deps# }" "$(L '모든 앱 빌드' 'Build every app')" "per-app build-* targets"
        _one() { _d=${1%%"$TAB"*}; target "build-${_d##*/}" "" "$(L "$_d 빌드" "Build $_d")" "$(js_src "$1")"; r_js "$1"; }
        each "$BHITS" _one
    elif [ -n "$BHITS" ]; then
        target build "" "$(L '빌드' 'Build')" "$(srcs "$BHITS")"; r_js "$BHITS"
    elif [ -n "$GO" ]; then target build "" "$(L '빌드' 'Build')" "go.mod"; r "go build ./..."
    elif [ -n "$CARGO" ]; then target build "" "$(L '빌드' 'Build')" "Cargo.toml"; r "cargo build"
    else
        BUILD_REAL=0
        target build "" "$(L '빌드 단계 없음(no-op)' 'No build step (no-op)')" "none detected"
        r "@echo \"$(L '빌드 단계 없음' 'no build step')\""
    fi

    # run (priority: mise > root package.json > run script > sub-app > go/cargo)
    RKIND=none; RHIT=$(js_hits start dev | head -n1)
    SCRIPT=$(printf '%s' "$SCRIPTS" | head -n1)
    if mise_t run; then RKIND=mise
    elif [ "${RHIT%%"$TAB"*}" = . ] && [ -n "$RHIT" ]; then RKIND=js
    elif [ -n "$SCRIPT" ]; then RKIND=script
    elif [ -n "$RHIT" ]; then RKIND=js
    elif [ -n "$GO" ]; then RKIND=go
    elif [ -n "$CARGO" ]; then RKIND=cargo; fi
    if [ "$RKIND" = script ]; then
        _sp=${SCRIPT%%|*}
        SCMD="${PORTVAR:+$PORTVAR=\$(PORT) }${SCRIPT##*|} ./$_sp"
    fi
    GUARD=""
    for _a in $ARTS; do case "$_a" in */dist|dist|*/build|build|*/out|out|*/.next|.next) GUARD=$_a; break ;; esac; done
    case "$RKIND" in
        mise) target run "" "$(L '실행' 'Run')" "mise.toml [tasks.run]"; r "mise run run" ;;
        js) target run "" "$(L '실행' 'Run')" "$(js_src "$RHIT")"; r_js "$RHIT" ;;
        go) target run "" "$(L '실행' 'Run')" "go.mod"; r "go run ." ;;
        cargo) target run "" "$(L '실행' 'Run')" "Cargo.toml"; r "cargo run" ;;
        script)
            if [ "$BUILD_REAL" = 1 ]; then
                target run "build serve" "$(L '빌드 후 서버 (재)기동 -- 코드를 바꿨으면 이것' 'Build, then (re)start the server')" "build + serve"
                target serve "" "$(L '빌드 없이 서버 (재)기동 -- 산출물이 없으면 멈춘다' '(Re)start the server without building; stops if the build output is missing')" "$_sp"
                if [ -n "$GUARD" ]; then r "@test -e $GUARD || { echo \"$(L "$GUARD 없음 -- 먼저 make build" "$GUARD missing -- run make build first")\"; exit 1; }"
                else skip serve-guard "no allowlisted build output dir detected"; fi
                r "$SCMD"
            else
                target run "" "$(L '서버 (재)기동' '(Re)start the server')" "$_sp"; r "$SCMD"
            fi ;;
        none)
            target run "" "$(L '실행 명령 없음(no-op) -- 직접 채운다' 'No run command detected (no-op) -- fill it in')" "none detected"
            r "@echo \"$(L '실행 명령 없음 -- Makefile 의 run 을 채운다' 'no run command detected -- edit the run target')\"" ;;
    esac
    has_t serve || skip serve "run does not depend on build (or runs no server script)"

    # stop / status / logs -- only for a server whose port / log is known
    case "$RKIND" in script|js|mise) SERVER=1 ;; *) SERVER="" ;; esac
    if [ -n "$PORT" ] && [ -n "$SERVER" ]; then
        target stop "" "$(L '서버 종료(포트 기준 -- 같은 이름의 다른 프로세스는 건드리지 않는다)' 'Stop the server by port (never by process name)')" "port $PORT"
        r "@if fuser \$(PORT)/tcp >/dev/null 2>&1; then fuser -k -TERM \$(PORT)/tcp >/dev/null 2>&1; echo \"$(L '종료 요청' 'stop requested'): \$(PORT)\"; else echo \"$(L '떠 있는 서버 없음' 'nothing listening on'): \$(PORT)\"; fi"
        target status "" "$(L '서버·빌드 상태' 'Server and build status')" "port $PORT${GUARD:+ + $GUARD}"
        r "@if fuser \$(PORT)/tcp >/dev/null 2>&1; then echo \"$(L '실행 중' 'running'): \$(PORT)\"; else echo \"$(L '정지' 'stopped'): \$(PORT)\"; fi"
        [ -n "$GUARD" ] && r "@test -e $GUARD && echo \"$(L "$GUARD 있음" "$GUARD present")\" || echo \"$(L "$GUARD 없음 -- make build" "$GUARD missing -- make build")\""
    else
        skip stop "no long-running server with a known port (pass --port N)"
        skip status "no long-running server with a known port (pass --port N)"
    fi
    if [ -n "$LOG" ]; then
        target logs "" "$(L '서버 로그 따라 보기(Ctrl+C 로 종료)' 'Follow the server log (Ctrl+C to quit)')" "${_sp:-script} log redirect"
        r 'tail -f $(LOG)'
    else skip logs "no log path found in a run script"; fi

    # test
    if mise_t test; then target test "" "$(L '단위 테스트' 'Unit tests')" "mise.toml [tasks.test]"; r "mise run test"
    else
        _h=$(js_hits test); _s=""
        [ -n "$PYTEST" ] && _s="pytest"
        [ -n "$_h" ] && _s="${_s:+$_s, }$(srcs "$_h")"
        [ -n "$GO" ] && _s="${_s:+$_s, }go.mod"; [ -n "$CARGO" ] && _s="${_s:+$_s, }Cargo.toml"
        if [ -n "$_s" ]; then
            target test "" "$(L '단위 테스트' 'Unit tests')" "$_s"
            [ -n "$PYTEST" ] && r "$(pyrun pytest)"
            each "$_h" r_js
            [ -n "$GO" ] && r "go test ./..."; [ -n "$CARGO" ] && r "cargo test"
        else skip test "no test runner detected"; fi
    fi
    if mise_t test-e2e; then target test-e2e "" "$(L 'E2E 테스트' 'End-to-end tests')" "mise.toml [tasks.test-e2e]"; r "mise run test-e2e"
    else
        _h=$(js_hits test:e2e e2e)
        if [ -n "$_h" ]; then target test-e2e "" "$(L 'E2E 테스트' 'End-to-end tests')" "$(srcs "$_h")"; each "$_h" r_js
        else skip test-e2e "no test:e2e / e2e script"; fi
    fi
    if has_t test && has_t test-e2e; then target test-all "test test-e2e" "test + test-e2e" "test + test-e2e"
    else skip test-all "needs both test and test-e2e"; fi

    # lint / fmt
    for _t in lint fmt; do
        [ "$_t" = lint ] && _d=$(L '린트' 'Lint') || _d=$(L '포맷' 'Format')
        if mise_t "$_t"; then target "$_t" "" "$_d" "mise.toml [tasks.$_t]"; r "mise run $_t"; continue; fi
        [ "$_t" = lint ] && _h=$(js_hits lint) || _h=$(js_hits format fmt)
        _s=$(srcs "$_h"); [ -n "$PYLINT" ] && _s="${_s:+$_s, }ruff"
        if [ -n "$_s" ]; then
            target "$_t" "" "$_d" "$_s"; each "$_h" r_js
            [ -n "$PYLINT" ] && { [ "$_t" = lint ] && r "$(pyrun 'ruff check .')" || r "$(pyrun 'ruff format .')"; }
        else skip "$_t" "no $_t tool detected"; fi
    done

    # gen-* from gen:X / gen-X package.json scripts
    _g=$(printf '%s' "$JS" | while IFS='|' read -r _d _r _s; do
        for _n in $(printf '%s' "$_s" | tr ',' ' '); do
            case "$_n" in gen:*|gen-*) printf '%s\t%s\t%s\n' "$_d" "$_r" "$_n" ;; esac
        done
    done)
    _gen() { _n=${1##*"$TAB"}; _tn="gen-$(printf '%s' "${_n#gen?}" | tr -c 'a-zA-Z0-9_\n-' '-')"
        has_t "$_tn" && return
        target "$_tn" "" "$(L "$_n 스크립트로 생성물 재생성" "Regenerate via the $_n script")" "$(js_src "$1")"; r_js "$1"; }
    each "$_g" _gen

    # docker compose
    if [ -n "$COMPOSE" ]; then
        target up "" "$(L 'docker compose 기동' 'docker compose up')" "$COMPOSE"; r "docker compose -f $COMPOSE up -d"
        target down "" "$(L 'docker compose 종료' 'docker compose down')" "$COMPOSE"; r "docker compose -f $COMPOSE down"
    fi

    # remaining mise tasks -> same-name targets
    for _m in $MISE; do
        case " $USED " in *" $_m "*) continue ;; esac
        _tn=$(printf '%s' "$_m" | tr -c 'a-zA-Z0-9_\n-' '-')
        case "$_tn" in help|clear|clean) skip "$_tn" "reserved name (mise task $_m not mapped)"; continue ;; esac
        has_t "$_tn" && continue
        target "$_tn" "" "$(L "mise 태스크 $_m" "mise task $_m")" "mise.toml [tasks.$_m]"; r "mise run $_m"
    done

    # clear -- allowlisted artifacts only (detect.sh ALLOW, gitignored)
    target clear "" "$(L '빌드·테스트 산출물 정리(의존성·비밀·데이터는 남긴다)' 'Remove build/test artifacts (keeps dependencies, secrets, data)')" "allowlist x .gitignore"
    _rm=""; _pyc=""
    for _a in $ARTS; do [ "$_a" = __pycache__ ] && _pyc=1 || _rm="$_rm $_a"; done
    [ -n "$_rm" ] && r "rm -rf ${_rm# }"
    [ -n "$_pyc" ] && r "find . -path '*/.*' -prune -o -name node_modules -prune -o -type d -name __pycache__ -prune -exec rm -rf {} +"
    [ -n "$_rm$_pyc" ] || r "@echo \"$(L '정리할 산출물 없음' 'nothing to clear')\""
    target clean clear "$(L 'clear 와 같다' 'Same as clear')" "alias of clear"

    VARS=""
    [ -n "$PORT" ] && VARS="${VARS}PORT ?= $PORT$NL"
    [ "$PY" = pip ] && VARS="${VARS}PY   := \$(if \$(wildcard .venv/bin/python),.venv/bin/python,python3)$NL"
    [ -n "$LOG" ] && has_t logs && VARS="${VARS}LOG  := $(printf '%s' "$LOG" | sed 's/\${PORT}/$(PORT)/g; s/\$PORT/$(PORT)/g')$NL"
}

emit_makefile() {
    printf '# Generated by devenv:makefile-gen -- `make` prints the targets.\n'
    printf '# Regenerate: /devenv:makefile-gen --apply --force (keeps Makefile.bak).\n\n'
    [ -n "$VARS" ] && printf '%s\n' "$VARS"
    printf '.DEFAULT_GOAL := help\n.PHONY:%s\n%s' "$NAMES" "$BODY"
}

# ---------------------------------------------------------------- check ------
recipe() { awk -v t="$1" 'index($0, t ":") == 1 {on=1; next} on && /^\t/ {print; next} on {exit}' "$2"; }

check() {
    f=$1; bad=0
    no() { printf 'FAIL  %s: %s\n' "$f" "$1"; bad=1; }
    [ -f "$f" ] || { no "not a file"; return 1; }
    grep -q '^\.DEFAULT_GOAL := help' "$f" || no ".DEFAULT_GOAL := help missing"
    grep -qF '/^[a-zA-Z0-9_-]+:.*## /' "$f" || no "help awk regex must be ^[a-zA-Z0-9_-]+:.*## "
    grep -qE '^\.ONESHELL|\$\(file ' "$f" && no "GNU Make 4.x-only construct (.ONESHELL / \$(file))"
    grep -qE '^[a-zA-Z0-9_-]+:.*## .*\$\(' "$f" && no "\$(VAR) inside a ## description (awk prints it raw)"
    grep -qE 'pkill|killall' "$f" && no "name-based kill (pkill/killall); stop must be port-based"
    if grep -q '^stop:' "$f"; then recipe stop "$f" | grep -qF 'fuser $(PORT)/tcp' || no "stop is not fuser \$(PORT)/tcp"; fi
    recipe clear "$f" | sed -e "s/-name [^ ]* -prune//g" -e "s/-path [^ ]* -prune//g" \
        | grep -qE '\.env|node_modules|\.venv|\.git|(^|[/[:space:]])data(/|[[:space:]]|$)' \
        && no "clear touches .env*/node_modules/.venv/.git/data"
    _ph=$(sed -n 's/^\.PHONY:[[:space:]]*//p' "$f" | tr ' ' '\n' | grep . | sort)
    _dc=$(grep -E '^[a-zA-Z0-9_-]+:.*## ' "$f" | cut -d: -f1 | sort)
    [ -n "$_ph" ] && [ "$_ph" = "$_dc" ] || no ".PHONY and ## -documented targets differ"
    return "$bad"
}

verify() { # <dir>: help lists every .PHONY target; make -n passes for each
    d=$1; bad=0
    command -v make >/dev/null 2>&1 || { echo "FAIL  make not on PATH"; return 1; }
    h=$(make --no-print-directory -C "$d" 2>&1) || { printf 'FAIL  make (help):\n%s\n' "$h"; return 1; }
    for t in $(sed -n 's/^\.PHONY:[[:space:]]*//p' "$d/Makefile"); do
        printf '%s\n' "$h" | grep -qE "make +$t( |\$)" || { echo "FAIL  help does not list $t"; bad=1; }
        make --no-print-directory -C "$d" -n "$t" >/dev/null 2>&1 || { echo "FAIL  make -n $t"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "ok    $d: help lists all targets, make -n passes for each"
    return "$bad"
}

# ---------------------------------------------------------------- main -------
main() {
    p=""; LANG_=""; OPORT=""; mode="make"
    while [ $# -gt 0 ]; do
        case "$1" in
            --port) OPORT=${2:-}; shift ;;
            --lang) LANG_=${2:-}; shift ;;
            --report) mode=report ;;
            *) p=$1 ;;
        esac
        shift
    done
    case "$OPORT" in ''|*[!0-9]*) [ -z "$OPORT" ] || { echo "render.sh: --port needs a number" >&2; return 2; } ;; esac
    case "$LANG_" in ''|ko|en) ;; *) echo "render.sh: --lang must be ko or en" >&2; return 2 ;; esac
    facts=$(sh "$HERE/detect.sh" "$p") || { echo "render.sh: not a directory: $p" >&2; return 1; }
    load "$facts"
    [ -n "$OPORT" ] && PORT=$OPORT
    [ -n "$LANG_" ] || LANG_=$DLANG
    render
    if [ "$mode" = report ]; then
        [ "$ST" = no-stack ] && printf 'note=no stack detected; required targets are no-op placeholders\n'
        printf '%s%s' "$WARNS" "$REPORT"
    else emit_makefile; fi
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0
    ok() { printf 'ok    %s\n' "$1"; }
    ko() { printf 'FAIL  %s\n' "$1"; fail=1; }
    gen() { main "$@" > "$1/Makefile" && check "$1/Makefile" >/dev/null; }
    targets() { sed -n 's/^\.PHONY: //p' "$1/Makefile"; }
    hasmake=0; command -v make >/dev/null 2>&1 && hasmake=1

    # brokerdesk shape -> PR #76 target set
    b=$tmp/bd; mkdir -p "$b/frontend"
    printf '3.12\n' > "$b/.python-version"; printf 'pytest\n' > "$b/requirements-dev.txt"
    printf '__pycache__/\nweb/data/\n.env\n' > "$b/.gitignore"; printf 'dist/\n/test-results/\n/playwright-report/\n' > "$b/frontend/.gitignore"
    : > "$b/frontend/bun.lock"
    printf '{"scripts": {"start": "x", "build:web": "x", "gen:api": "x", "test": "x", "test:e2e": "x"}}\n' > "$b/frontend/package.json"
    printf '#!/usr/bin/env bash\nPORT="${WEB_PORT:-8888}"\nLOG="${WEB_LOG:-/tmp/web-${PORT}.log}"\n' > "$b/run-web.sh"
    gen "$b" && ok "brokerdesk shape renders and passes --check" || ko "brokerdesk shape --check"
    [ "$(targets "$b")" = "help setup build run serve stop status logs test test-e2e test-all gen-api clear clean" ] \
        && ok "brokerdesk target set = PR #76" || ko "brokerdesk targets: $(targets "$b")"
    grep -q '^serve: ## ' "$b/Makefile" && grep -q '^run: build serve ## ' "$b/Makefile" \
        && grep -qF 'WEB_PORT=$(PORT) bash ./run-web.sh' "$b/Makefile" && grep -qF 'LOG  := /tmp/web-$(PORT).log' "$b/Makefile" \
        && ok "run -> build serve, serve delegates to run-web.sh" || ko "brokerdesk run/serve/log mapping"

    # mise tasks delegate, never duplicate
    m=$tmp/mise; mkdir -p "$m"; printf '[tasks.build]\nrun="x"\n[tasks.test]\nrun="y"\n[tasks.fix]\nrun="z"\n' > "$m/mise.toml"
    gen "$m" && recipe build "$m/Makefile" | grep -qx "${TAB}mise run build" && recipe test "$m/Makefile" | grep -qx "${TAB}mise run test" \
        && recipe fix "$m/Makefile" | grep -qx "${TAB}mise run fix" && ok "mise tasks -> mise run" || ko "mise delegation"

    # no stack: required four exist, build is an exit-0 no-op
    e=$tmp/empty; mkdir -p "$e"
    gen "$e" --lang en && [ "$(targets "$e")" = "help build run clear clean" ] && ok "no stack -> help build run clear clean" || ko "no-stack targets: $(targets "$e")"

    # multi-app build fan-out
    a=$tmp/mono; mkdir -p "$a/apps/x" "$a/apps/y"
    echo '{"scripts":{"build":"a"}}' > "$a/apps/x/package.json"; echo '{"scripts":{"build":"b"}}' > "$a/apps/y/package.json"
    gen "$a" && grep -q '^build: build-x build-y ## ' "$a/Makefile" && ok "apps/* -> build-x build-y" || ko "multi-app build"

    # --check must reject contract violations
    bad() { printf '%s\n' "$2" > "$tmp/bad.mk"; check "$tmp/bad.mk" >/dev/null && ko "check accepts: $1" || ok "check rejects: $1"; }
    H=".DEFAULT_GOAL := help${NL}.PHONY: help clear stop${NL}help: ## h${NL}${TAB}@awk '/^[a-zA-Z0-9_-]+:.*## /' x${NL}stop: ## s${NL}${TAB}fuser \$(PORT)/tcp"
    bad "clear deletes .env" "$H${NL}clear: ## c${NL}${TAB}rm -rf dist .env"
    bad "clear deletes web/data" "$H${NL}clear: ## c${NL}${TAB}rm -rf web/data"
    bad "clear deletes node_modules" "$H${NL}clear: ## c${NL}${TAB}rm -rf frontend/node_modules"
    bad "pkill stop" "$(printf '%s' "$H" | sed 's/fuser.*/pkill -f web/')${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad ".ONESHELL" ".ONESHELL:${NL}$H${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad "help regex without digits" "$(printf '%s' "$H" | sed 's/a-zA-Z0-9_-/a-zA-Z_-/')${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad "\$(VAR) in description" "$H${NL}clear: ## port \$(PORT)${NL}${TAB}rm -rf dist"
    bad "target missing from .PHONY" "$H${NL}clear: ## c${NL}${TAB}rm -rf dist${NL}lint: ## l${NL}${TAB}true"

    if [ "$hasmake" -eq 1 ]; then
        for d in "$b" "$m" "$e" "$a"; do verify "$d" >/dev/null && ok "verify $(basename "$d")" || ko "verify $d: $(verify "$d")"; done
        o=$(make --no-print-directory -C "$e" build 2>&1) && [ "$o" = "no build step" ] && ok "no-stack make build -> exit 0" || ko "no-stack build: $o"
    else printf 'skip  make not on PATH -- verify cases not run\n'; fi

    [ "$fail" -eq 0 ] && printf 'ok    render.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
    --check) check "${2:-}"; exit $? ;;
    --verify) verify "${2:-.}"; exit $? ;;
    "") usage >&2; exit 2 ;;
esac
main "$@"
