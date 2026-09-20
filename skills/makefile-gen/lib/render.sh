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
# The generated text ends with the custom sentinel; whatever <path>/Makefile
# already has below that line is copied over verbatim, never parsed.
# Mapping rules: references/target-catalog.md. POSIX sh only.

set -u
HERE=$(dirname "$0")
TAB=$(printf '\t')
NL='
'
# Everything below this line in a Makefile belongs to the user. It is copied
# across a regeneration as-is: never read, checked, merged or reordered.
SENTINEL='# --- custom (kept by makefile-gen) ---'

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

# gen_part / keep_region <makefile>: the two halves, split at the sentinel.
gen_part() { awk -v s="$SENTINEL" '$0 == s {exit} {print}' "$1"; }
keep_region() { awk -v s="$SENTINEL" 'f {print} $0 == s {f = 1}' "$1"; }

# ---------------------------------------------------------------- facts ------
load() { # <detect output> -> globals
    MISE=""; JS=""; SUBS=""; SCRIPTS=""; ARTS=""; DEVSERVER=""; SSTOP=""; SSETUP=""
    PY=""; PYV=""; PYREQS=""; PYTEST=""; PYLINT=""; PORT=""; PORTS=""; PORTVAR=""; LOG=""; SSUBS=""
    GO=""; CARGO=""; COMPOSE=""; DLANG=en; ST=""; WARNS=""
    _o=$IFS; IFS=$NL
    for _l in $1; do
        _k=${_l%%=*}; _v=${_l#*=}
        case "$_k" in
            status) ST=$_v ;; lang) DLANG=$_v ;;
            mise_task) MISE="$MISE $_v" ;;
            js) JS="$JS$_v$NL" ;;
            subapp) SUBS="$SUBS$_v$NL" ;;
            devserver) DEVSERVER=$_v ;; script_stop) SSTOP=$_v ;;
            script) SCRIPTS="$SCRIPTS$_v$NL" ;; script_sub) SSUBS="$SSUBS$_v$NL" ;;
            script_setup) SSETUP=$_v ;;
            artifact) ARTS="$ARTS $_v" ;;
            py) PY=$_v ;; py_version) PYV=$_v ;; py_reqs) PYREQS=$_v ;;
            py_test) PYTEST=$_v ;; py_lint) PYLINT=$_v ;;
            port) PORTS="$PORTS $_v"; [ -n "$PORT" ] || PORT=$_v ;; port_var) PORTVAR=$_v ;; log) LOG=$_v ;;
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

# sub_hits <target>: "cmd<TAB>source" per Python/mise sub-app, mise task first,
# then the tool directly (uv, or the sub-app's own .venv for pip).
sub_hits() {
    case "$1" in setup) _ns="install setup" ;; fmt) _ns="fmt format" ;; *) _ns=$1 ;; esac
    printf '%s' "$SUBS" | while IFS='|' read -r _d _p _f _m; do
        [ -n "$_d" ] || continue
        _c=""; _src=""
        for _n in $_ns; do
            case ",$_m," in *",$_n,"*) _c="mise run $_n"; _src="$_d/mise.toml [tasks.$_n]"; break ;; esac
        done
        [ "$_p" = uv ] && _x='uv run ' || _x='.venv/bin/python -m '
        if [ -z "$_c" ]; then case "$1:$_p:,$_f," in
            setup:uv:*) _c="uv sync"; _src="$_d/uv.lock" ;;
            setup:pip:*,req:*) _q=${_f#*req:}; _q=${_q%%,*}
                _c="{ test -x .venv/bin/python || python3 -m venv .venv; } && .venv/bin/pip install -q -r $_q"; _src="$_d/$_q" ;;
            setup:pip:*) _c="{ test -x .venv/bin/python || python3 -m venv .venv; } && .venv/bin/pip install -q -e ."; _src="$_d/pyproject.toml" ;;
            test:[up]*:*,pytest,*) _c="${_x}pytest"; _src="$_d pytest" ;;
            lint:[up]*:*,ruff,*) _c="${_x}ruff check ."; _src="$_d ruff" ;;
            fmt:[up]*:*,ruff,*) _c="${_x}ruff format ."; _src="$_d ruff" ;;
        esac; fi
        [ -n "$_c" ] && printf 'cd %s && %s\t%s\n' "$_d" "$_c" "$_src"
    done
}
r_sub() { r "${1%%"$TAB"*}"; }
# ssub <test|lint|fmt>: "<bash|sh> ./<script> <name>" for the first script arm.
ssub() { printf '%s' "$SSUBS" | while IFS='|' read -r _p _i _n; do
    [ "$_n" = "$1" ] && { printf '%s ./%s %s' "$_i" "$_p" "$1"; break; }; done; }
sub_srcs() { printf '%s\n' "$1" | awk -F'\t' -v s="$2" 'NF {o = o (n++ ? s : "") $2} END {printf "%s", o}'; }

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
    elif [ -n "$SSETUP" ]; then
        # The repo already owns its bootstrap; delegate, never copy its logic.
        _ss=${SSETUP%%|*}
        target setup "" "$(L '최초 1회: 의존성 설치' 'First-time setup: install dependencies')" "$_ss"
        r "${SSETUP##*|} ./$_ss"
    elif _sh=$(sub_hits setup); [ -n "$PY$JS$_sh" ]; then
        _v=$(printf '%s' "$PYV" | cut -d. -f1,2)
        _pd=""; _s=""
        # Name the file that drives the recipe: uv sync reads uv.lock, not requirements.
        [ "$PY" = uv ] && _pf=uv.lock || _pf=${PYREQS:-pyproject.toml}
        [ -n "$PY" ] && { _pd=" .venv${_v:+ (Python $_v)} +"; _s="$_pf${_v:+ + .python-version}"; }
        _jp=$(printf '%s' "$JS" | awk -F'|' 'NF {printf "%s%s", (n++ ? " + " : ""), ($1 == "." ? "" : $1 "/") "package.json"}')
        [ -n "$JS" ] && _s="${_s:+$_s + }$_jp"
        [ -n "$_sh" ] && _s="${_s:+$_s + }$(sub_srcs "$_sh" ' + ')"
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
        each "$_sh" r_sub
    else skip setup "no dependency manifest (pyproject/requirements/package.json/mise)"; fi

    # build
    BUILD_REAL=1; BHITS=$(js_hits build build:web)
    if mise_t build; then
        target build "" "$(L '빌드' 'Build')" "mise.toml [tasks.build]"; r "mise run build"; BHITS=""
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
    # Build output = an allowlisted output artifact inside a JS app that builds.
    # Unknown (mise/go/cargo build, or none in the app dir) -> no guard, no guess.
    GUARD=""; _bd="$NL$(printf '%s\n' "$BHITS" | cut -f1)$NL"
    for _a in $ARTS; do
        case "$_a" in */dist|dist|*/build|build|*/out|out|*/.next|.next) ;; *) continue ;; esac
        _ad=${_a%/*}; [ "$_ad" = "$_a" ] && _ad=.
        case "$_bd" in *"$NL$_ad$NL"*) GUARD=$_a; break ;; esac
    done
    case "$RKIND" in
        mise) target run "" "$(L '실행' 'Run')" "mise.toml [tasks.run]"; r "mise run run" ;;
        js) target run "" "$(L '실행' 'Run')" "$(js_src "$RHIT")"; r_js "$RHIT" ;;
        go) target run "" "$(L '실행' 'Run')" "go.mod"; r "go run ." ;;
        cargo) target run "" "$(L '실행' 'Run')" "Cargo.toml"; r "cargo run" ;;
        script)
            if [ "$BUILD_REAL" = 1 ] && [ -z "$DEVSERVER" ]; then
                target run "build serve" "$(L '빌드 후 서버 (재)기동 -- 코드를 바꿨으면 이것' 'Build, then (re)start the server')" "build + serve"
                target serve "" "$(L '빌드 없이 서버 (재)기동 -- 산출물이 없으면 멈춘다' '(Re)start the server without building; stops if the build output is missing')" "$_sp"
                if [ -n "$GUARD" ]; then r "@test -e $GUARD || { echo \"$(L "$GUARD 없음 -- 먼저 make build" "$GUARD missing -- run make build first")\"; exit 1; }"
                else skip serve-guard "no allowlisted build output dir detected"; fi
                r "$SCMD"
                # The path under it is app knowledge, but the origin is not.
                case "${PORTS# }" in
                    *" "*) r "@for p in \$(PORTS); do echo \"  -> http://localhost:\$\$p/\"; done" ;;
                    ?*) r "@echo \"  -> http://localhost:\$(PORT)/\"" ;;
                esac
            else
                target run "" "$(L '서버 (재)기동' '(Re)start the server')" "$_sp"; r "$SCMD"
            fi ;;
        none)
            target run "" "$(L '실행 명령 없음(no-op) -- 직접 채운다' 'No run command detected (no-op) -- fill it in')" "none detected"
            r "@echo \"$(L '실행 명령 없음 -- Makefile 의 run 을 채운다' 'no run command detected -- edit the run target')\"" ;;
    esac
    if has_t serve; then :
    elif [ "$RKIND" = script ] && [ -n "$DEVSERVER" ]; then skip serve "run script starts a dev server ($DEVSERVER); it builds/serves for itself"
    else skip serve "run does not depend on build (or runs no server script)"; fi

    # stop / status / logs -- only for a server whose port / log is known
    case "$RKIND" in script|js|mise) SERVER=1 ;; *) SERVER="" ;; esac
    # One run script may start several servers: loop over $(PORTS) then.
    case "${PORTS# }" in *" "*) _pl="for p in \$(PORTS); do "; _pe="; done"; _pv='$$p'; _ps="ports${PORTS}" ;;
        *) _pl=""; _pe=""; _pv='$(PORT)'; _ps="port $PORT" ;; esac
    if [ "$RKIND" = script ] && [ -n "$SSTOP" ]; then
        target stop "" "$(L '종료 -- 실행 스크립트의 정리 명령에 맡긴다' 'Stop via the run script teardown subcommand')" "$_sp $SSTOP"
        r "${SCRIPT##*|} ./$_sp $SSTOP"
    elif [ -n "$PORT" ] && [ -n "$SERVER" ]; then
        target stop "" "$(L '서버 종료(포트 기준 -- 같은 이름의 다른 프로세스는 건드리지 않는다)' 'Stop the server by port (never by process name)')" "$_ps"
        r "@${_pl}if fuser $_pv/tcp >/dev/null 2>&1; then fuser -k -TERM $_pv/tcp >/dev/null 2>&1; echo \"$(L '종료 요청' 'stop requested'): $_pv\"; else echo \"$(L '떠 있는 서버 없음' 'nothing listening on'): $_pv\"; fi$_pe"
    else skip stop "no long-running server with a known port (pass --port N)"; fi
    if [ -n "$PORT" ] && [ -n "$SERVER" ]; then
        target status "" "$(L '서버·빌드 상태' 'Server and build status')" "$_ps${GUARD:+ + $GUARD}"
        r "@${_pl}if fuser $_pv/tcp >/dev/null 2>&1; then echo \"$(L '실행 중' 'running'): $_pv\"; else echo \"$(L '정지' 'stopped'): $_pv\"; fi$_pe"
        [ -n "$GUARD" ] && r "@test -e $GUARD && echo \"$(L "$GUARD 있음" "$GUARD present")\" || echo \"$(L "$GUARD 없음 -- make build" "$GUARD missing -- make build")\""
    else skip status "no long-running server with a known port (pass --port N)"; fi
    if [ -n "$LOG" ]; then
        target logs "" "$(L '서버 로그 따라 보기(Ctrl+C 로 종료)' 'Follow the server log (Ctrl+C to quit)')" "${_sp:-script} log redirect"
        r 'tail -f $(LOG)'
    else skip logs "no log path found in a run script"; fi

    # test
    if mise_t test; then target test "" "$(L '단위 테스트' 'Unit tests')" "mise.toml [tasks.test]"; r "mise run test"
    else
        _h=$(js_hits test); _sh=$(sub_hits test); _s=""; _pt=$PYTEST; _go=$GO; _ca=$CARGO
        _x=$(ssub test); [ -n "$_x" ] && { [ -n "$_pt$_go$_ca" ] || [ -z "$_h$_sh" ]; } || _x=""
        [ -n "$_x" ] && { _s=${_x#* ./}; _pt=""; _go=""; _ca=""; }
        [ -n "$_pt" ] && _s="pytest"
        [ -n "$_h" ] && _s="${_s:+$_s, }$(srcs "$_h")"
        [ -n "$_sh" ] && _s="${_s:+$_s, }$(sub_srcs "$_sh" ', ')"
        [ -n "$_go" ] && _s="${_s:+$_s, }go.mod"; [ -n "$_ca" ] && _s="${_s:+$_s, }Cargo.toml"
        if [ -n "$_s" ]; then
            target test "" "$(L '단위 테스트' 'Unit tests')" "$_s"
            [ -n "$_x" ] && r "$_x"
            [ -n "$_pt" ] && r "$(pyrun pytest)"
            each "$_h" r_js; each "$_sh" r_sub
            [ -n "$_go" ] && r "go test ./..."; [ -n "$_ca" ] && r "cargo test"
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
        if [ "$_t" = lint ]; then _d=$(L '린트' 'Lint')
        elif has_t lint; then _d=$(L '포맷 -- make lint 가 빨갛게 나올 때' 'Format -- run it when make lint is red')
        else _d=$(L '포맷' 'Format'); fi
        if mise_t "$_t"; then
            # A fmt-check task next to lint is what CI runs, so `make lint`
            # runs the pair -- a lint that passes on code CI rejects is the
            # failure this target exists to prevent. fmt-check is then not
            # emitted again by the catch-all "any other mise task" rule.
            _fc=""
            if [ "$_t" = lint ]; then
                for _n in fmt-check format-check lint:fmt; do
                    mise_t "$_n" && { _fc=$_n; break; }
                done
                [ -n "$_fc" ] && _d=$(L '린트 + 포맷 검사 -- CI 와 같은 검사' 'Lint + format check -- the pair CI runs')
            fi
            target "$_t" "" "$_d" "mise.toml [tasks.$_t]${_fc:+ + [tasks.$_fc]}"
            r "mise run $_t"; [ -n "$_fc" ] && r "mise run $_fc"
            continue
        fi
        [ "$_t" = lint ] && _h=$(js_hits lint) || _h=$(js_hits format fmt)
        _sh=$(sub_hits "$_t"); _rl=$PYLINT
        # A run/dev script's own `lint)`/`fmt)` arm replaces the direct ruff call.
        _x=$(ssub "$_t"); [ -n "$_x" ] && { [ -n "$_rl" ] || [ -z "$_h$_sh" ]; } || _x=""
        [ -n "$_x" ] && _rl=""
        _s=$(srcs "$_h"); [ -n "$_x" ] && _s="${_x#* ./}${_s:+, $_s}"; [ -n "$_rl" ] && _s="${_s:+$_s, }ruff"
        [ -n "$_sh" ] && _s="${_s:+$_s, }$(sub_srcs "$_sh" ', ')"
        if [ -n "$_s" ]; then
            target "$_t" "" "$_d" "$_s"; [ -n "$_x" ] && r "$_x"; each "$_h" r_js
            [ -n "$_rl" ] && { [ "$_t" = lint ] && r "$(pyrun 'ruff check .')" || r "$(pyrun 'ruff format .')"; }
            each "$_sh" r_sub
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
    case "${PORTS# }" in
        *" "*) VARS="${VARS}PORTS ?=$PORTS$NL"; [ -n "$PORTVAR$LOG" ] && VARS="${VARS}PORT ?= $PORT$NL" ;;
        ?*) VARS="${VARS}PORT ?= $PORT$NL" ;;
    esac
    [ "$PY" = pip ] && VARS="${VARS}PY   := \$(if \$(wildcard .venv/bin/python),.venv/bin/python,python3)$NL"
    [ -n "$LOG" ] && has_t logs && VARS="${VARS}LOG  := $(printf '%s' "$LOG" | sed 's/\${PORT}/$(PORT)/g; s/\$PORT/$(PORT)/g')$NL"
    dir_vars
}

# dir_vars: an app dir named three or more times across the recipes becomes a
# variable, so renaming the app stays a one-line edit. Recipes only -- the
# help awk prints `##` text raw, so a $(VAR) in a description would show up
# literally. Longest path first, so `src/frontend` claims the name before
# plain `frontend` could rewrite half of it.
dir_vars() {
    for _d in $(printf '%s%s' "$JS" "$SUBS" | cut -d'|' -f1 | grep -v '^\.$' \
        | awk 'NF {print length, $0}' | sort -rn -k1,1 | cut -d' ' -f2- | awk '!s[$0]++'); do
        _v=$(printf '%s' "${_d##*/}" | tr 'a-z-' 'A-Z_' | tr -c 'A-Z0-9_\n' '_')
        case " PORT PORTS PY LOG $(printf '%s' "$VARS" | cut -d' ' -f1 | tr '\n' ' ')" in
            *" $_v "*) continue ;;
        esac
        _b=$(printf '%s' "$BODY" | awk -v t="$TAB" -v d="$_d" -v v="\$($_v)" '
            function subst(l,   o, i, p, nx, pc) {
                o = ""; p = 1
                while ((i = index(substr(l, p), d)) > 0) {
                    i = p + i - 1
                    pc = (i > 1) ? substr(l, i - 1, 1) : ""
                    nx = substr(l, i + length(d), 1)
                    if (pc !~ "[A-Za-z0-9_./-]" && nx !~ "[A-Za-z0-9_.-]") {
                        o = o substr(l, p, i - p) v; n++
                    } else { o = o substr(l, p, i - p + length(d)) }
                    p = i + length(d)
                }
                return o substr(l, p)
            }
            { L[NR] = (substr($0, 1, 1) == t) ? subst($0) : $0 }
            END { if (n < 3) exit 1; for (k = 1; k <= NR; k++) print L[k] }') \
            && { BODY="$_b$NL"; VARS="${VARS}$_v := $_d$NL"; }
    done
}

emit_makefile() {
    printf '# Generated by devenv:makefile-gen -- `make` prints the targets.\n'
    printf '# Regenerate: /devenv:makefile-gen --apply --force (keeps Makefile.bak).\n\n'
    [ -n "$VARS" ] && printf '%s\n' "$VARS"
    printf '.DEFAULT_GOAL := help\n.PHONY:%s\n%s' "$NAMES" "$BODY"
    printf '\n%s\n' "$SENTINEL"
    [ -n "$KEEP" ] && printf '%s\n' "$KEEP"
    return 0
}

# ---------------------------------------------------------------- check ------
recipe() { awk -v t="$1" 'index($0, t ":") == 1 {on=1; next} on && /^\t/ {print; next} on {exit}' "$2"; }

check() {
    f=$1; bad=0
    no() { printf 'FAIL  %s: %s\n' "$f" "$1"; bad=1; }
    [ -f "$f" ] || { no "not a file"; return 1; }
    # Only the generated region is the skill's to judge. What a user keeps
    # below the sentinel may use any tooling, and .PHONY never covers it.
    _g=$(gen_part "$f"); G() { printf '%s\n' "$_g"; }
    G | grep -q '^\.DEFAULT_GOAL := help' || no ".DEFAULT_GOAL := help missing"
    G | grep -qF '/^[a-zA-Z0-9_-]+:.*## /' || no "help awk regex must be ^[a-zA-Z0-9_-]+:.*## "
    grep -qxF "$SENTINEL" "$f" || no "custom sentinel missing (a regeneration would drop hand-written targets)"
    G | grep -qE '^\.ONESHELL|\$\(file ' && no "GNU Make 4.x-only construct (.ONESHELL / \$(file))"
    G | grep -qE '^[a-zA-Z0-9_-]+:.*## .*\$\(' && no "\$(VAR) inside a ## description (awk prints it raw)"
    G | grep -qE 'pkill|killall' && no "name-based kill (pkill/killall); stop must be port-based"
    if G | grep -q '^stop:'; then G | recipe stop - | grep -qE -e 'fuser \$\(PORT\)/tcp' -e 'for p in \$\(PORTS\); do if fuser \$\$p/tcp' -e '^	(bash|sh) \./[^ ]+ (stop|down)$' \
        || no "stop is neither fuser \$(PORT)/tcp (or a \$(PORTS) loop) nor the run script's stop/down"; fi
    G | recipe clear - | sed -e "s/-name [^ ]* -prune//g" -e "s/-path [^ ]* -prune//g" \
        | grep -qE '\.env|node_modules|\.venv|\.git|(^|[/[:space:]])data(/|[[:space:]]|$)' \
        && no "clear touches .env*/node_modules/.venv/.git/data"
    _ph=$(G | sed -n 's/^\.PHONY:[[:space:]]*//p' | tr ' ' '\n' | grep . | sort)
    _dc=$(G | grep -E '^[a-zA-Z0-9_-]+:.*## ' | cut -d: -f1 | sort)
    [ -n "$_ph" ] && [ "$_ph" = "$_dc" ] || no ".PHONY and ## -documented targets differ"
    return "$bad"
}

verify() { # <dir>: help lists every .PHONY target; make -n passes for each
    d=$1; bad=0
    command -v make >/dev/null 2>&1 || { echo "FAIL  make not on PATH"; return 1; }
    h=$(make --no-print-directory -C "$d" 2>&1) || { printf 'FAIL  make (help):\n%s\n' "$h"; return 1; }
    for t in $(gen_part "$d/Makefile" | sed -n 's/^\.PHONY:[[:space:]]*//p'); do
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
    [ -n "$OPORT" ] && { PORT=$OPORT; PORTS=" $OPORT"; }
    [ -n "$LANG_" ] || LANG_=$DLANG
    render
    # An existing Makefile's custom region survives a regeneration; one with
    # no sentinel cannot, so name what --force would drop instead of taking
    # it away quietly. The user moves those targets below the sentinel once.
    KEEP=""
    if [ -f "$p/Makefile" ]; then
        if grep -qxF "$SENTINEL" "$p/Makefile"; then KEEP=$(keep_region "$p/Makefile")
        else
            for _t in $(grep -E '^[a-zA-Z0-9_-]+:' "$p/Makefile" | cut -d: -f1 | sort -u); do
                has_t "$_t" && continue
                WARNS="${WARNS}warn=custom target $_t not preserved (no sentinel; move it below the sentinel to keep it)$NL"
            done
        fi
    fi
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
    # Render to a temp file, then move it in -- exactly Step 4 of SKILL.md.
    # `main ... > <path>/Makefile` would truncate the file before main could
    # read the custom region out of it.
    gen() { main "$@" > "$1/.mk.tmp" && mv "$1/.mk.tmp" "$1/Makefile" && check "$1/Makefile" >/dev/null; }
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
        && recipe serve "$b/Makefile" | grep -qF '@test -e $(FRONTEND)/dist ||' \
        && grep -qF 'WEB_PORT=$(PORT) bash ./run-web.sh' "$b/Makefile" && grep -qF 'LOG  := /tmp/web-$(PORT).log' "$b/Makefile" \
        && recipe stop "$b/Makefile" | grep -qF 'fuser $(PORT)/tcp' \
        && ok "plain script -> run: build serve + guard, stop by port" || ko "brokerdesk run/serve/log mapping"
    # frontend is named in five recipes, so it is a variable everywhere in
    # them -- and nowhere in a ## description, which awk prints raw.
    grep -qx 'FRONTEND := frontend' "$b/Makefile" \
        && [ "$(recipe build "$b/Makefile")" = "${TAB}cd \$(FRONTEND) && bun run build:web" ] \
        && ! grep -qE '^[a-z-]+:.*## .*frontend' "$b/Makefile" \
        && ok "a repeated app dir becomes a variable, recipes only" || ko "FRONTEND var: $(cat "$b/Makefile")"
    recipe serve "$b/Makefile" | grep -qxF "${TAB}@echo \"  -> http://localhost:\$(PORT)/\"" \
        && ok "serve prints the URL it just started" || ko "serve URL: $(recipe serve "$b/Makefile")"

    # stock-steward shape: JS frontend + uv/mise backend, dev script with down)
    k=$tmp/ss; mkdir -p "$k/frontend" "$k/backend" "$k/scripts"
    printf 'frontend/dist/\n.pytest_cache/\n' > "$k/.gitignore"
    echo '{"scripts":{"dev":"vite","build":"b","test":"t","lint":"l","fmt":"f"}}' > "$k/frontend/package.json"
    printf '[project]\ndependencies = ["ruff", "pytest"]\n' > "$k/backend/pyproject.toml"; : > "$k/backend/uv.lock"
    printf '[tasks.install]\nrun="uv sync"\n[tasks.test]\nrun="x"\n[tasks.lint]\nrun="x"\n' > "$k/backend/mise.toml"
    printf '#!/usr/bin/env bash\ncase "$1" in\n  down) exit 0 ;;\nesac\nnpm run dev\n' > "$k/scripts/dev.sh"
    gen "$k" && ok "stock-steward shape passes --check" || ko "stock-steward --check"
    [ "$(recipe setup "$k/Makefile")" = "${TAB}cd \$(FRONTEND) && npm install${NL}${TAB}cd \$(BACKEND) && mise run install" ] \
        && [ "$(recipe test "$k/Makefile")" = "${TAB}cd \$(FRONTEND) && npm run test${NL}${TAB}cd \$(BACKEND) && mise run test" ] \
        && [ "$(recipe lint "$k/Makefile")" = "${TAB}cd \$(FRONTEND) && npm run lint${NL}${TAB}cd \$(BACKEND) && mise run lint" ] \
        && [ "$(recipe fmt "$k/Makefile")" = "${TAB}cd \$(FRONTEND) && npm run fmt${NL}${TAB}cd \$(BACKEND) && uv run ruff format ." ] \
        && ok "sub-app: mise task > uv tool, aggregated with JS" || ko "sub-app mapping: $(cat "$k/Makefile")"
    grep -q '^run: ## ' "$k/Makefile" && ! grep -q '^serve:' "$k/Makefile" \
        && recipe run "$k/Makefile" | grep -qx "${TAB}bash ./scripts/dev.sh" \
        && recipe stop "$k/Makefile" | grep -qx "${TAB}bash ./scripts/dev.sh down" \
        && main "$k" --report | grep -qxF "target=stop${TAB}source=scripts/dev.sh down" \
        && main "$k" --report | grep -qF "skip=serve${TAB}reason=run script starts a dev server (run dev)" \
        && recipe clear "$k/Makefile" | grep -qF '$(BACKEND)/.pytest_cache' \
        && ok "dev-server script: run direct, stop -> script down" || ko "dev-script run/stop: $(cat "$k/Makefile")"
    rm "$k/backend/mise.toml"; gen "$k" && recipe setup "$k/Makefile" | grep -qx "${TAB}cd \$(BACKEND) && uv sync" \
        && recipe test "$k/Makefile" | grep -qx "${TAB}cd \$(BACKEND) && uv run pytest" \
        && ok "sub-app without mise -> uv sync / uv run pytest" || ko "sub-app uv fallback"

    # agent-toolbox shape: root bun workspace, uv app under apps/, scripts/setup.sh
    t=$tmp/at; mkdir -p "$t/apps/server" "$t/scripts"
    printf 'dist/\n' > "$t/.gitignore"
    printf '{"scripts":{"dev":"x","build":"y","lint":"z","format":"w"}}\n' > "$t/package.json"
    : > "$t/bun.lock"
    printf '[project]\ndependencies = ["pytest", "ruff"]\n' > "$t/apps/server/pyproject.toml"
    : > "$t/apps/server/uv.lock"
    printf '#!/usr/bin/env bash\nbun install\n' > "$t/scripts/setup.sh"
    gen "$t" && ok "agent-toolbox shape passes --check" || ko "agent-toolbox --check"
    [ "$(recipe setup "$t/Makefile")" = "${TAB}bash ./scripts/setup.sh" ] \
        && main "$t" --report | grep -qxF "target=setup${TAB}source=scripts/setup.sh" \
        && ok "setup delegates to scripts/setup.sh" || ko "setup delegation: $(recipe setup "$t/Makefile")"
    [ "$(recipe test "$t/Makefile")" = "${TAB}cd \$(SERVER) && uv run pytest" ] \
        && [ "$(recipe lint "$t/Makefile")" = "${TAB}bun run lint${NL}${TAB}cd \$(SERVER) && uv run ruff check ." ] \
        && [ "$(recipe fmt "$t/Makefile")" = "${TAB}bun run format${NL}${TAB}cd \$(SERVER) && uv run ruff format ." ] \
        && grep -qx 'SERVER := apps/server' "$t/Makefile" \
        && ok "sub-app under apps/ joins test/lint/fmt" || ko "nested sub-app: $(cat "$t/Makefile")"
    [ "$(recipe clear "$t/Makefile")" = "${TAB}rm -rf dist \$(SERVER)/dist \$(SERVER)/.pytest_cache" ] \
        && ok "clear lists each artifact once" || ko "clear: $(recipe clear "$t/Makefile")"

    # quantfolio shape: uv root + nested vite app, two-server script, tools/dev.sh
    q=$tmp/qf; mkdir -p "$q/src/frontend" "$q/scripts" "$q/tools"
    : > "$q/pyproject.toml"; : > "$q/uv.lock"; printf 'pytest\nruff\n' > "$q/requirements.txt"
    printf '/build\n' > "$q/.gitignore"; printf 'dist\n' > "$q/src/frontend/.gitignore"
    echo '{"scripts":{"dev":"vite","build":"vite build","test":"t","lint":"l"}}' > "$q/src/frontend/package.json"
    printf '#!/usr/bin/env bash\nAPI_PORT=9100\nFRONT_PORT=9173\nnpm run dev\n' > "$q/scripts/dev.sh"
    printf '#!/usr/bin/env bash\ncase "$1" in\n  test) : ;;\n  fmt|format) : ;;\nesac\n' > "$q/tools/dev.sh"
    gen "$q" && ok "quantfolio shape passes --check" || ko "quantfolio --check"
    grep -qx 'PORTS ?= 9100 9173' "$q/Makefile" && ! grep -q '^PORT ' "$q/Makefile" \
        && recipe stop "$q/Makefile" | grep -qF 'for p in $(PORTS); do if fuser $$p/tcp' \
        && recipe status "$q/Makefile" | grep -qF 'for p in $(PORTS); do' \
        && ok "multi-server script -> stop/status over every port" || ko "multi-port: $(cat "$q/Makefile")"
    [ "$(recipe build "$q/Makefile")" = "${TAB}cd \$(FRONTEND) && npm run build" ] \
        && grep -qx 'FRONTEND := src/frontend' "$q/Makefile" \
        && recipe status "$q/Makefile" | grep -qF '@test -e $(FRONTEND)/dist &&' \
        && ! recipe status "$q/Makefile" | grep -qF 'test -e build ' \
        && ok "nested JS build delegated, status checks its output" || ko "nested build: $(cat "$q/Makefile")"
    main "$q" --report | grep -qxF "target=setup${TAB}source=uv.lock + src/frontend/package.json" \
        && [ "$(recipe setup "$q/Makefile")" = "${TAB}uv sync${NL}${TAB}cd \$(FRONTEND) && npm install" ] \
        && ok "setup source names uv.lock" || ko "setup source: $(main "$q" --report | grep setup)"
    [ "$(recipe test "$q/Makefile")" = "${TAB}bash ./tools/dev.sh test${NL}${TAB}cd \$(FRONTEND) && npm run test" ] \
        && [ "$(recipe fmt "$q/Makefile")" = "${TAB}bash ./tools/dev.sh fmt" ] \
        && [ "$(recipe lint "$q/Makefile")" = "${TAB}cd \$(FRONTEND) && npm run lint${NL}${TAB}uv run ruff check ." ] \
        && main "$q" --report | grep -qxF "target=test${TAB}source=tools/dev.sh test, src/frontend/package.json scripts.test" \
        && ok "script test)/fmt) arm replaces the direct command" || ko "script subcommands: $(cat "$q/Makefile")"
    gen "$q" --port 9000 && grep -qx 'PORT ?= 9000' "$q/Makefile" && ! grep -q '^PORTS' "$q/Makefile" \
        && ok "--port N forces a single port" || ko "--port override: $(head -6 "$q/Makefile")"

    # mise tasks delegate, never duplicate
    m=$tmp/mise; mkdir -p "$m"; printf '[tasks.build]\nrun="x"\n[tasks.test]\nrun="y"\n[tasks.fix]\nrun="z"\n' > "$m/mise.toml"
    gen "$m" && recipe build "$m/Makefile" | grep -qx "${TAB}mise run build" && recipe test "$m/Makefile" | grep -qx "${TAB}mise run test" \
        && recipe fix "$m/Makefile" | grep -qx "${TAB}mise run fix" && ok "mise tasks -> mise run" || ko "mise delegation"

    # brokerdesk's mise.toml: lint + fmt-check is the pair CI runs, so `make
    # lint` must run both -- a lint that is green on code CI rejects is the
    # bug -- and fmt-check must not also land as a target of its own.
    l=$tmp/lint; mkdir -p "$l"
    printf '[tasks.lint]\nrun="ruff check ."\n[tasks.fmt-check]\nrun="ruff format --check ."\n[tasks.fmt]\nrun="ruff format ."\n' > "$l/mise.toml"
    gen "$l" && [ "$(recipe lint "$l/Makefile")" = "${TAB}mise run lint${NL}${TAB}mise run fmt-check" ] \
        && ! grep -q '^fmt-check:' "$l/Makefile" \
        && main "$l" --report | grep -qxF "target=lint${TAB}source=mise.toml [tasks.lint] + [tasks.fmt-check]" \
        && ok "lint keeps CI parity with fmt-check" || ko "lint/fmt-check: $(cat "$l/Makefile")"

    # The custom region: copied verbatim across a regeneration, never parsed.
    # Without the sentinel nothing can be kept, so --force must name what it
    # would drop rather than taking it away quietly.
    c=$tmp/keep; mkdir -p "$c"; printf '[tasks.build]\nrun="x"\n' > "$c/mise.toml"
    gen "$c" && cp "$c/Makefile" "$c/Makefile.gen"
    printf '%s\n%s\n' "backup-db: ## back up the db" "${TAB}pg_dump mine > out.sql" >> "$c/Makefile"
    gen "$c" && recipe backup-db "$c/Makefile" | grep -qx "${TAB}pg_dump mine > out.sql" \
        && grep -qx 'backup-db: ## back up the db' "$c/Makefile" \
        && ! main "$c" --report | grep -q '^warn=custom target' \
        && ok "the region below the sentinel survives a regeneration" || ko "sentinel keep: $(cat "$c/Makefile")"
    check "$c/Makefile" >/dev/null \
        && ok "--check ignores the custom region (not in .PHONY, not its rules)" || ko "check over a kept region"
    cp "$c/Makefile" "$c/Makefile.1"; gen "$c" \
        && diff -q "$c/Makefile.1" "$c/Makefile" >/dev/null \
        && [ "$(grep -c '^# --- custom' "$c/Makefile")" = 1 ] \
        && ok "regenerating over a kept region is idempotent" || ko "sentinel idempotency: $(cat "$c/Makefile")"
    printf 'backups: ## list backups\n%sls -1 b/\n' "$TAB" > "$c/Makefile"
    main "$c" --report | grep -qxF 'warn=custom target backups not preserved (no sentinel; move it below the sentinel to keep it)' \
        && ok "a sentinel-less Makefile reports each target --force would drop" || ko "no-sentinel warn: $(main "$c" --report)"
    main "$c" --report | grep -q '^warn=custom target build ' && ko "warn names a regenerated target" \
        || ok "only targets absent from the new Makefile are warned about"
    check "$c/Makefile.gen" >/dev/null || ko "check rejects a generated Makefile"
    sed '/^# --- custom/d' "$c/Makefile.gen" > "$c/Makefile.nosent"
    check "$c/Makefile.nosent" >/dev/null && ko "check accepts a Makefile with no sentinel" \
        || ok "check rejects a Makefile that lost its sentinel"

    # no stack: required four exist, build is an exit-0 no-op
    e=$tmp/empty; mkdir -p "$e"
    gen "$e" --lang en && [ "$(targets "$e")" = "help build run clear clean" ] && ok "no stack -> help build run clear clean" || ko "no-stack targets: $(targets "$e")"

    # multi-app build fan-out
    a=$tmp/mono; mkdir -p "$a/apps/x" "$a/apps/y"
    echo '{"scripts":{"build":"a"}}' > "$a/apps/x/package.json"; echo '{"scripts":{"build":"b"}}' > "$a/apps/y/package.json"
    gen "$a" && grep -q '^build: build-x build-y ## ' "$a/Makefile" && ok "apps/* -> build-x build-y" || ko "multi-app build"

    # --check must reject contract violations
    bad() { printf '%s\n%s\n' "$2" "$SENTINEL" > "$tmp/bad.mk"; check "$tmp/bad.mk" >/dev/null && ko "check accepts: $1" || ok "check rejects: $1"; }
    H=".DEFAULT_GOAL := help${NL}.PHONY: help clear stop${NL}help: ## h${NL}${TAB}@awk '/^[a-zA-Z0-9_-]+:.*## /' x${NL}stop: ## s${NL}${TAB}fuser \$(PORT)/tcp"
    bad "clear deletes .env" "$H${NL}clear: ## c${NL}${TAB}rm -rf dist .env"
    bad "clear deletes web/data" "$H${NL}clear: ## c${NL}${TAB}rm -rf web/data"
    bad "clear deletes node_modules" "$H${NL}clear: ## c${NL}${TAB}rm -rf frontend/node_modules"
    bad "pkill stop" "$(printf '%s' "$H" | sed 's/fuser.*/pkill -f web/')${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad ".ONESHELL" ".ONESHELL:${NL}$H${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad "help regex without digits" "$(printf '%s' "$H" | sed 's/a-zA-Z0-9_-/a-zA-Z_-/')${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad "\$(VAR) in description" "$H${NL}clear: ## port \$(PORT)${NL}${TAB}rm -rf dist"
    bad "stop runs an arbitrary script arg" "$(printf '%s' "$H" | sed 's|fuser.*|bash ./dev.sh restart|')${NL}clear: ## c${NL}${TAB}rm -rf dist"
    bad "target missing from .PHONY" "$H${NL}clear: ## c${NL}${TAB}rm -rf dist${NL}lint: ## l${NL}${TAB}true"

    if [ "$hasmake" -eq 1 ]; then
        gen "$q"
        for d in "$b" "$m" "$e" "$a" "$k" "$q" "$t"; do verify "$d" >/dev/null && ok "verify $(basename "$d")" || ko "verify $d: $(verify "$d")"; done
        # A preserved target may call tooling the skill knows nothing about,
        # so --verify covers the generated .PHONY set and stops there.
        gen "$c"; printf '%s\n%s\n' "deploy: ## ship it" "${TAB}definitely-not-a-command" >> "$c/Makefile"
        verify "$c" >/dev/null && ok "--verify skips make -n on preserved targets" || ko "verify over a kept region: $(verify "$c")"
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
