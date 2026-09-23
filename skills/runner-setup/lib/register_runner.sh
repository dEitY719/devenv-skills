#!/bin/sh
# register_runner.sh -- Steps 1-4 of devenv:runner-setup: register a
# Docker-container self-hosted GitHub Actions runner for one repo on a host
# reached over SSH, then prove it came online.
#
# Usage:
#   register_runner.sh [--env internal|public] [--repo owner/name]
#                      [--label name] [--host alias] [--plan]
#   register_runner.sh --self-test
#
# Steps (the duplicate check runs before the token is minted, so a refusal
# never leaves a live credential behind):
#   1  resolve repo (--repo, else `git remote get-url origin`), label, host
#   2  SSH: refuse when a container named <repo-name>-runner already exists
#   3  gh api: mint a registration token (GHES: GH_HOST=<ghes host>)
#   4  SSH: (public) build the minimal image if absent, start the container,
#      then poll the runners API until it is online with the label
#
# --plan prints the resolved key=value facts and stops: no SSH, no API call.
#
# The token never reaches a command line: the remote script travels on
# `ssh <host> sh -s` stdin, and the container reads it from its environment.
#
# Every site-specific value is an env override with a documented default
# (references/internal.md, references/public.md):
#   RUNNER_GHES_HOST       internal API/web host        (github.samsungds.net)
#   RUNNER_INTERNAL_HOST   internal default SSH alias   (ssai-ops)
#   RUNNER_INTERNAL_IMAGE  internal image               (skills_runner:26.09)
#   RUNNER_PROXY           internal http(s)_proxy       (http://12.26.204.100:8080)
#   RUNNER_NO_PROXY        internal no_proxy            (localhost,127.0.0.1,<ghes>,.<ghes parent domain>)
#   RUNNER_PUBLIC_IMAGE    public image tag             (runner-setup-public:22.04)
#   RUNNER_VERSION         actions/runner release       (2.328.0)
#   RUNNER_DIR             runner dir inside image      (/actions-runner)
#   RUNNER_VERIFY_TIMEOUT  seconds to wait for online   (90)
#
# exit 0  runner online with its label (or --plan printed)
# exit 1  a step failed (message names it)
# exit 2  usage error
# exit 3  container already exists -- refused, nothing changed
#
# Called explicitly, never sourced. POSIX sh only.

set -u

usage() {
    cat <<'EOF'
devenv:runner-setup -- self-hosted runner registration

Usage:
  register_runner.sh [--env internal|public] [--repo owner/name]
                     [--label name] [--host alias] [--plan]
  register_runner.sh --self-test
EOF
}

say() { printf '%s\n' "$@"; }
err() { printf '[FAIL] devenv:runner-setup %s\n' "$*" >&2; }

# q <value> -- single-quote for a POSIX shell.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# parse_remote <url> -- print "<host> <owner/name>" for scp-style, ssh:// and
# https:// remotes; nothing for anything else.
parse_remote() {
    printf '%s\n' "$1" | sed -n \
        -e 's#^[a-z+]*://\([^@/]*@\)\{0,1\}\([^/:]*\)\(:[0-9]*\)\{0,1\}/\([^/]*/[^/]*\)$#\2 \4#p' \
        -e 's#^\([^@/]*@\)\{0,1\}\([^/:]*\):\([^/]*/[^/]*\)$#\2 \3#p' |
        sed 's#\.git$##; s#/$##' | head -n 1
}

# resolve -- fill every fact from flags + env + git. Returns 2 on bad input.
resolve() {
    case "$ENV" in
        internal)
            API_HOST=${RUNNER_GHES_HOST:-github.samsungds.net}
            HOST=${HOST:-${RUNNER_INTERNAL_HOST:-ssai-ops}}
            IMAGE=${RUNNER_INTERNAL_IMAGE:-skills_runner:26.09}
            BUILD=0
            PROXY=${RUNNER_PROXY:-http://12.26.204.100:8080}
            NO_PROXY_V=${RUNNER_NO_PROXY:-localhost,127.0.0.1,$API_HOST,.${API_HOST#*.}}
            ;;
        public)
            API_HOST=github.com
            [ -n "$HOST" ] || { err "--host is required with --env public"; return 2; }
            IMAGE=${RUNNER_PUBLIC_IMAGE:-runner-setup-public:22.04}
            BUILD=1 PROXY='' NO_PROXY_V=''
            ;;
        *) err "--env must be internal or public (got '$ENV')"; return 2 ;;
    esac
    REMOTE_HOST=''
    if [ -z "$REPO" ]; then
        url=$(git remote get-url origin 2>/dev/null) || url=''
        parsed=$(parse_remote "$url")
        [ -n "$parsed" ] || { err "cannot detect repo from origin ('$url'); pass --repo owner/name"; return 2; }
        REMOTE_HOST=${parsed% *} REPO=${parsed#* }
    fi
    case "$REPO" in */*/*|/*|*/|*' '*|'') err "--repo must be owner/name (got '$REPO')"; return 2 ;; */*) ;; *) err "--repo must be owner/name (got '$REPO')"; return 2 ;; esac
    NAME=${REPO#*/}
    LABEL=${LABEL:-$NAME-build}
    CONTAINER=$NAME-runner
    URL=https://$API_HOST/$REPO
}

facts() {
    say "env=$ENV" "repo=$REPO" "api_host=$API_HOST" "host=$HOST" "label=$LABEL" \
        "container=$CONTAINER" "image=$IMAGE" "build_image=$BUILD" "runner_url=$URL"
    [ -n "$PROXY" ] && say "proxy=$PROXY" "no_proxy=$NO_PROXY_V"
    if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_HOST" != "$API_HOST" ]; then
        say "warn=origin host $REMOTE_HOST differs from api_host $API_HOST (wrong --env?)"
    fi
    return 0
}

# remote_script <token> -- the script `ssh <host> sh -s` runs.
remote_script() {
    printf 'IMAGE=%s CONTAINER=%s BUILD=%s RUNNER_VERSION=%s\n' \
        "$(q "$IMAGE")" "$(q "$CONTAINER")" "$BUILD" "$(q "${RUNNER_VERSION:-2.328.0}")"
    printf 'RUNNER_URL=%s RUNNER_NAME=%s RUNNER_LABELS=%s RUNNER_DIR=%s RUNNER_TOKEN=%s\n' \
        "$(q "$URL")" "$(q "$CONTAINER")" "$(q "$LABEL")" "$(q "${RUNNER_DIR:-/actions-runner}")" "$(q "$1")"
    printf 'PROXY=%s NO_PROXY_V=%s\n' "$(q "$PROXY")" "$(q "$NO_PROXY_V")"
    cat <<'REMOTE'
set -eu
export RUNNER_URL RUNNER_NAME RUNNER_LABELS RUNNER_DIR RUNNER_TOKEN
if [ "$BUILD" = 1 ] && ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build -q -t "$IMAGE" --build-arg RUNNER_VERSION="$RUNNER_VERSION" - <<'DOCKERFILE'
FROM ubuntu:22.04
ARG RUNNER_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git \
 && mkdir /actions-runner && cd /actions-runner \
 && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | tar xz \
 && ./bin/installdependencies.sh \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi
set -- -e RUNNER_URL -e RUNNER_NAME -e RUNNER_LABELS -e RUNNER_DIR -e RUNNER_TOKEN -e RUNNER_ALLOW_RUNASROOT=1
if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
    export no_proxy="$NO_PROXY_V" NO_PROXY="$NO_PROXY_V"
    set -- "$@" -e http_proxy -e https_proxy -e HTTP_PROXY -e HTTPS_PROXY -e no_proxy -e NO_PROXY
fi
# config.sh only on first start: a restart reuses .runner, the token has expired.
docker run -d --name "$CONTAINER" --restart unless-stopped "$@" \
    --entrypoint /bin/sh "$IMAGE" -c 'cd "$RUNNER_DIR" && { [ -f .runner ] || ./config.sh --unattended --replace --url "$RUNNER_URL" --token "$RUNNER_TOKEN" --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work _work; } && exec ./run.sh'
REMOTE
}

register() {
    ENV=internal REPO='' LABEL='' HOST='' PLAN=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --env|--repo|--label|--host)
                [ $# -ge 2 ] || { usage >&2; return 2; }
                case "$1" in --env) ENV=$2 ;; --repo) REPO=$2 ;; --label) LABEL=$2 ;; --host) HOST=$2 ;; esac
                shift ;;
            --plan) PLAN=1 ;;
            *) usage >&2; return 2 ;;
        esac
        shift
    done
    resolve || return $?
    facts
    [ "$PLAN" -eq 1 ] && return 0

    say "[..] step 2: duplicate check on $HOST"
    names=$(ssh -o BatchMode=yes "$HOST" "docker ps -a --format '{{.Names}}'") ||
        { err "ssh $HOST docker ps failed (host alias / docker access?)"; return 1; }
    if printf '%s\n' "$names" | grep -qx "$CONTAINER"; then
        err "container $CONTAINER already exists on $HOST -- remove it first: ssh $HOST docker rm -f $CONTAINER"
        return 3
    fi

    say "[..] step 3: registration token from $API_HOST"
    if ! token=$(GH_HOST=$API_HOST gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token 2>&1) ||
        [ -z "$token" ]; then
        err "registration token: $token"
        [ "$ENV" = internal ] && say "hint: GHES needs GH_ENTERPRISE_TOKEN + GH_HOST=$API_HOST, and no_proxy must cover $API_HOST (references/internal.md)" >&2
        return 1
    fi

    say "[..] step 4: start $CONTAINER from $IMAGE"
    remote_script "$token" | ssh -o BatchMode=yes "$HOST" sh -s ||
        { err "docker run on $HOST failed"; return 1; }

    left=${RUNNER_VERIFY_TIMEOUT:-90}
    while :; do
        got=$(GH_HOST=$API_HOST gh api "repos/$REPO/actions/runners" \
            --jq ".runners[] | select(.name == \"$CONTAINER\") | .status + \" \" + ([.labels[].name] | join(\",\"))" 2>/dev/null) || got=''
        status=${got%% *} labels=${got#* }
        if [ "$status" = online ] && printf ',%s,' "$labels" | grep -q ",$LABEL,"; then
            say "status=online" "labels=$labels"
            say "[OK] devenv:runner-setup runner $CONTAINER online on $HOST for $REPO (label=$LABEL)"
            return 0
        fi
        [ "$left" -le 0 ] && break
        sleep 5; left=$((left - 5))
    done
    err "runner $CONTAINER not online with label $LABEL (last: '${got:-absent}') -- ssh $HOST docker logs $CONTAINER"
    return 1
}

self_test() {
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fail=0
    # ck <label> -- judge the exit status of the command right before it.
    ck() { if [ $? -eq 0 ]; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fail=1; fi; }

    [ "$(parse_remote git@github.com:o/r.git)" = "github.com o/r" ]; ck "remote: scp style"
    [ "$(parse_remote https://ghe.example.com/o/r)" = "ghe.example.com o/r" ]; ck "remote: https"
    [ "$(parse_remote ssh://git@ghe.example.com:2222/o/r.git)" = "ghe.example.com o/r" ]; ck "remote: ssh:// with port"
    [ -z "$(parse_remote /local/path)" ]; ck "remote: local path rejected"
    [ "$(eval "printf %s $(q "a'b \$c")")" = "a'b \$c" ]; ck "q round-trips quotes and dollars"

    out=$(register --plan --repo o/myrepo 2>&1)
    printf '%s\n' "$out" | grep -qx 'label=myrepo-build' &&
        printf '%s\n' "$out" | grep -qx 'container=myrepo-runner' &&
        printf '%s\n' "$out" | grep -qx 'host=ssai-ops' &&
        printf '%s\n' "$out" | grep -qx 'no_proxy=localhost,127.0.0.1,github.samsungds.net,.samsungds.net'
    ck "plan: internal defaults"
    register --plan --env public --repo o/r > /dev/null 2>&1; [ $? -eq 2 ]; ck "public without --host exits 2"
    register --plan --env bogus --repo o/r > /dev/null 2>&1; [ $? -eq 2 ]; ck "bad --env exits 2"
    register --plan --repo nope > /dev/null 2>&1; [ $? -eq 2 ]; ck "bad --repo exits 2"
    out=$(register --plan --env public --host box --repo o/r --label x 2>&1)
    printf '%s\n' "$out" | grep -qx 'label=x' && ! printf '%s\n' "$out" | grep -q '^proxy='; ck "plan: public, no proxy"

    # End to end against stub ssh/gh on PATH.
    mkdir "$tmp/bin"
    cat > "$tmp/bin/ssh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB/ssh.argv"
case "$*" in
    *"docker ps"*) cat "$STUB/names" 2>/dev/null || true ;;
    *"sh -s") cat > "$STUB/remote.sh" ;;
esac
EOF
    cat > "$tmp/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
    *registration-token*) echo SECRET-TKN ;;
    *runners*) echo "online self-hosted,Linux,X64,r-build" ;;
esac
EOF
    chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
    out=$(STUB=$tmp PATH="$tmp/bin:$PATH" register --env public --host box --repo o/r 2>&1); rc=$?
    [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^\[OK\]'; ck "e2e: registers and verifies online"
    ! grep -q SECRET-TKN "$tmp/ssh.argv"; ck "e2e: token never on an ssh command line"
    grep -q "RUNNER_TOKEN='SECRET-TKN'" "$tmp/remote.sh" && sh -n "$tmp/remote.sh"; ck "e2e: remote script carries token and parses"
    printf 'other\nr-runner\n' > "$tmp/names"
    STUB=$tmp PATH="$tmp/bin:$PATH" register --env public --host box --repo o/r > /dev/null 2>&1; [ $? -eq 3 ]
    ck "e2e: existing container refused with exit 3"

    [ "$fail" -eq 0 ] && printf 'ok    register_runner.sh self-test passed\n'
    return "$fail"
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --self-test) self_test; exit $? ;;
esac

register "$@"
