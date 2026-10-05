# devenv:runner-setup — live verification record

**Status: NOT YET PERFORMED (stub self-tests only: `tests/run.sh`)**

Registration has only been proven by `register_runner.sh --self-test`, which
swaps ssh, gh and docker for stubs (duplicate refusal exit 3, token never on
argv, no `RUNNER_ALLOW_RUNASROOT` in the public container). No real runner
host has been touched. This file is the tracker for the live run (issue #31):
whoever has a runner host and repo admin fills in the results table below in
the same PR that flips the status line.

## Verification goal

- **internal**: `/devenv:runner-setup` (defaults) prints
  `[OK] devenv:runner-setup ... runner=<repo>-runner ... status=online`, and
  `GH_HOST=github.samsungds.net gh api repos/<o>/<n>/actions/runners` shows
  `status=online` with `<repo>-build` among the labels.
- **public**: `--env public --host <alias>` gives the same result, the host
  now has image `runner-setup-public:22.04`, and the container user is
  `runner` (not root).
- **workflows**: after `patch_workflows.sh --apply` and a push, CI runs on the
  self-hosted runner, and on GHES the mise install step
  (`${MISE_INSTALL_URL:-https://mise.run}`) succeeds.
- **restart**: after `docker restart <repo>-runner` the runner is `online`
  again (`config.sh` runs on first start only).

## Unverified assumptions

1. The internal image `skills_runner:26.09` keeps the runner in
   `/actions-runner` (`RUNNER_DIR`) and fits the entrypoint
   `cd $RUNNER_DIR && { [ -f .runner ] || ./config.sh ...; } && exec ./run.sh`.
2. The public image build (ubuntu:22.04 + ca-certificates/curl/git +
   actions/runner `2.328.0` + `bin/installdependencies.sh` + non-root
   `runner` user) succeeds and registers.
3. On GHES the default `no_proxy`
   (`localhost,127.0.0.1,github.samsungds.net,.samsungds.net`) lets
   registration get JSON back (pitfall 1 in `references/internal.md`).

## Resume procedure

Run from a target repo that has zero runners, with a session that holds repo
admin and a working `ssh -o BatchMode=yes <host>`.

```sh
cd <target repo with 0 runners>
S=<devenv-skills>/skills/runner-setup/lib
sh $S/register_runner.sh --plan                              # facts only, no side effects
sh $S/register_runner.sh                                     # internal: register
sh $S/patch_workflows.sh --env internal                      # review the diff
sh $S/patch_workflows.sh --env internal --apply              # then commit + push
ssh <host> docker restart <repo>-runner                      # restart check
# public
sh $S/register_runner.sh --env public --host <alias> --plan
sh $S/register_runner.sh --env public --host <alias>
ssh <alias> docker image ls runner-setup-public              # image exists
ssh <alias> docker exec <repo>-runner id -un                 # expect: runner
```

On failure: `ssh <host> docker logs <repo>-runner`. Undo steps: `references/help.md`.

## Pass / fail criteria

| Check | Pass | Fail |
|-------|------|------|
| register (internal) | exit 0, `status=online` line printed | exit 1 with `[FAIL]` |
| runners API (internal) | `status=online`, labels include `<repo>-build` | runner absent or `offline` |
| register (public) | exit 0, `status=online` line printed | exit 1 with `[FAIL]` |
| public image + user | `runner-setup-public:22.04` exists; `id -un` is `runner` | image missing or user `root` |
| workflow CI | pushed run picks the self-hosted runner and goes green, mise step included | job queued forever or mise step fails |
| restart | `online` again after `docker restart` without re-running `config.sh` | stays `offline` or re-registers |

Any fail: open a `fix` issue with the command, output excerpt and runners API
response, link it here, and leave the status line as is.

## Results

| Date | Env | Check | Command | Result | Evidence (output / API excerpt) |
|------|-----|-------|---------|--------|---------------------------------|
| - | internal | register | | not run | |
| - | internal | runners API | | not run | |
| - | internal | workflow CI | | not run | |
| - | internal | restart | | not run | |
| - | public | register | | not run | |
| - | public | image + user | | not run | |
| - | public | workflow CI | | not run | |
| - | public | restart | | not run | |
