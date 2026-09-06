# devenv:mise-migrate — Help

## Usage

```
/devenv:mise-migrate [path] [flags]
/devenv-mise-migrate ~/para/project/karakeep/sync          # dry-run plan
/devenv-mise-migrate ~/para/project/karakeep/sync --apply  # write + uv sync
/devenv:mise-migrate -h        # show this help
/devenv:mise-migrate --help    # show this help
/devenv:mise-migrate help      # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `[path]` | no | Target project directory. Defaults to `.` (cwd). |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | **on** | Default. Prints the migration plan; writes nothing. |
| `--apply` | off | Writes `mise.toml`, rewrites `pyproject.toml`, runs `uv sync`, then cleans up. |
| `--backend <name>` | `hatchling` | Build backend to modernize toward: `hatchling` or `uv_build`. |
| `--keep-venv` | off | Skip the cleanup step — leave the old `.venv/` and `*.egg-info/` in place. |
| `--update-docs` | off | With `--apply`, rewrite in-repo stale `venv`/`pip` references (README, docs, bootstrap scripts) to the `uv` workflow. Off → the scan is report-only. |
| `-h` / `--help` / `help` | — | Print this help and stop. No detection, no file mutation. |

## Examples

```
# 1. Inspect the plan for the current dir (no writes):
/devenv-mise-migrate

# 2. Plan a specific project:
/devenv-mise-migrate ~/para/project/karakeep/sync

# 3. Apply — write mise.toml, rewrite pyproject, uv sync, clean up:
/devenv-mise-migrate ~/para/project/karakeep/sync --apply

# 4. Apply but keep the old venv/egg-info, and use uv's own backend:
/devenv-mise-migrate . --apply --backend uv_build --keep-venv
```

## What the skill does

The workflow is Steps 1-5 of `SKILL.md`; the per-step detail lives in
`references/detection.md`, `extraction.md`, `mise-template.md`,
`pyproject-rewrite.md`, and `stale-scan.md` (PEP 735 silent-regression
`[WARN]` included).

## What the skill will NOT do

- Touch non-Python projects, or migrate node/go/etc. — Python-venv scope
  only by design.
- Re-migrate a project that already has a `mise.toml` (idempotent no-op).
- Rewrite stale doc/script references unless `--update-docs` is set, and
  never touch history/archive/design-spec paths even then.
- Generate lint/fix tasks for tools the project does not use — a missing
  linter is logged, not silently added.
- Rewrite source code or change import paths — only `mise.toml` and the
  build/dependency stanzas of `pyproject.toml`.
- Delete anything outside the target `<path>`, or delete the old venv
  when `--keep-venv` is set.
- Roll back a partial `--apply` failure — it reports partial state and
  stops; the user owns cleanup.

## Prerequisites

- `uv` and `mise` available on `PATH` (the generated `[tools]` pins both,
  but `--apply` calls `uv sync` directly).
- Write access to `<path>` for `--apply`.

## Pairs with

- `mise run lint|test|fix` — the workflow this skill bootstraps. After a
  successful apply, start with `mise run test`.
