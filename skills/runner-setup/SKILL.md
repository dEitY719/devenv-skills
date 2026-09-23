---
name: runner-setup
description: >-
  Register a Docker-container self-hosted GitHub Actions runner for a repo
  (GHES or GitHub.com) and move its workflows onto it. Use for
  /devenv:runner-setup, /devenv-runner-setup, "셀프호스티드 러너 등록", "CI 가
  runner 없어서 실패", "set up a self-hosted runner". Workflow edits dry-run
  unless --apply.
allowed-tools: Bash, Read
license: MIT
compatibility:
  # ssh to the runner host, gh api to GHES/GitHub.com, docker pull/build there.
  network: required
metadata:
  model_recommendation:
    tier: sonnet
    reason: "Two deterministic scripts do the work; the model routes flags, relays output and judges warn= lines"
    claude: prefer
    non_claude: advisory-only
---

# devenv:runner-setup — self-hosted runner in a container

A repo whose CI fails at once with `runner_id=null` has no runner. This skill
starts one as a Docker container on a host reached over SSH, registers it to
the repo, proves it is online, then (with `--apply`) rewrites the repo's
workflows to run on it. Two targets: `internal` (GHES, the default) and
`public` (GitHub.com). All real work lives in `lib/register_runner.sh`
(Steps 1-4) and `lib/patch_workflows.sh` (Step 5).

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No SSH, no API call, no file mutation.

## Step 1: Parse Args + Plan

Flags: `--env internal|public`, `--repo owner/name`, `--label name`,
`--host alias`, `--dry-run` (default) / `--apply`. Anything else → usage line
from `references/help.md` + stop. Run from the target repo's root.

```bash
sh <skill-dir>/lib/register_runner.sh --env <e> [--repo R] [--label L] [--host H] --plan
```

It prints `key=value` facts (repo, api_host, host, label, container, image,
proxy) and touches nothing. Exit 2 → relay the message and stop (public
without `--host`, undetectable repo). Show the facts as a table. A
`warn=origin host ... differs` line usually means the wrong `--env`: stop and
ask before going on.

Before running Step 2 for `--env internal`, read `references/internal.md`; for
`--env public`, read `references/public.md`.

## Step 2: Register the Runner (always)

Same command without `--plan`. In order: duplicate-container check over SSH,
registration token via `gh api`, `docker run` on the host (public: builds the
minimal image first if absent), then polls the runners API until the runner
is `online` with its label (`RUNNER_VERIFY_TIMEOUT`, default 90 s).

- Exit 3 — a `<repo-name>-runner` container already exists. Nothing was
  changed. Relay the printed `docker rm -f` hint; never remove it yourself.
- Exit 1 — relay the `[FAIL]` line and any `hint:` verbatim. A token failure
  on GHES is almost always one of the three pitfalls in
  `references/internal.md`; name the matching one.
- Never pass the registration token on a command line or echo it; the script
  keeps it on stdin and in the container environment only.

## Step 3: Workflow Migration (dry-run unless `--apply`)

```bash
sh <skill-dir>/lib/patch_workflows.sh --env <e> [--apply] [.github/workflows]
```

Rules per env: `references/workflow-migration.md`. Without `--apply` it prints
a `diff -u` per file and writes nothing; with `--apply` it rewrites in place.
Both end with `mode=<m> changed=<n> files=<k>`. `status=no-workflows` (exit
1) is not a failure of the runner — report it and finish. Review the diff for
the known blind spots (flow-style `env:`, matrix `runs-on`) listed there.

## Step 4: Report

```
[OK] devenv:runner-setup repo=<r> env=<e> runner=<container> host=<h> label=<l> status=online
workflows: mode=<dry-run|apply> changed=<n> files=<k>
Next: re-run with --apply | commit .github/workflows and push to trigger CI
```

On any failure: `[FAIL] devenv:runner-setup <step> <reason>` and stop.
Registration is not rolled back when Step 3 fails — the runner stays useful.
