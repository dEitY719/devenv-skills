# devenv:makefile-gen — Help

## Usage

```
/devenv:makefile-gen [path] [flags]
/devenv-makefile-gen                                  # dry-run for the cwd
/devenv-makefile-gen ~/para/project/brokerdesk --apply
/devenv:makefile-gen -h        # show this help
/devenv:makefile-gen --help    # show this help
/devenv:makefile-gen help      # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `[path]` | no | Target project directory. Defaults to `.` (cwd). |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | **on** | Default. Prints the detection table, the Makefile (or a diff against the existing one), target sources and skipped targets; writes nothing. |
| `--apply` | off | Writes `<path>/Makefile`, then verifies it with `make` + `make -n <target>`. Refuses when a Makefile already exists. |
| `--force` | off | With `--apply`, replace an existing Makefile after copying it to `Makefile.bak`. |
| `--port N` | detected | Server port for `PORT ?=`. Overrides the port found in a run script; also enables `stop`/`status` for a server whose port is not in any script. |
| `--lang ko\|en` | README | Language of the `##` help descriptions. Without it: `ko` when the README contains Hangul, else `en`. |
| `-h` / `--help` / `help` | — | Print this help and stop. No detection, no file mutation. |

## Examples

```
# 1. See what would be generated for the current dir (no writes):
/devenv-makefile-gen

# 2. Write it:
/devenv-makefile-gen . --apply

# 3. Replace a hand-written Makefile (old one kept as Makefile.bak):
/devenv-makefile-gen . --apply --force

# 4. English help text, server on :9000:
/devenv-makefile-gen ~/work/api --apply --lang en --port 9000
```

## Targets

Always: `help` (default goal), `build`, `run`, `clear`, `clean` (alias of
`clear`). Only when detected: `setup`, `serve`, `stop`, `status`, `logs`,
`test`, `test-e2e`, `test-all`, `lint`, `fmt`, `gen-*`, `up`/`down` (docker
compose), `build-<app>` (several sub-apps), and one target per remaining
`mise.toml` task. Meanings and conditions: `references/target-catalog.md`.

## What the skill will NOT do

- Merge into an existing Makefile — it replaces (with `--force` + `.bak`)
  or refuses.
- Copy command logic out of `mise.toml`, `package.json` or run scripts —
  recipes call them.
- Let `clear` touch `.env*`, credentials, `node_modules`, `.venv`, `.git`
  or runtime data directories.
- Stop a server by process name (`pkill`) — `stop` is the run script's own
  `stop`/`down` subcommand, else port-based.
- Run `run`, `serve`, `stop` or `build` during verification — only `make`
  (help) and `make -n`.
- Generate CI workflows, Dockerfiles, or a new build system.

## Prerequisites

- GNU Make 3.81+ (macOS default is fine) and POSIX `sh`.
- `fuser` (psmisc) for the generated `stop` / `status` targets.
- Write access to `<path>` for `--apply`.

## Pairs with

- `/devenv:mise-migrate` — produces the `mise.toml [tasks.*]` this skill
  delegates to. Run it first on a legacy Python project.
