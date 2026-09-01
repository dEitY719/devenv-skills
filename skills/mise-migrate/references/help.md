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

1. **Detects** a legacy Python project (pyproject / setup.py /
   requirements + a pyenv-style `.venv`) and refuses non-Python or
   already-migrated (`mise.toml` present) directories. If the given path
   has no project file but exactly one direct subdir does, it retargets
   to that nested project.
2. **Extracts** the Python version, runtime + dev deps, `[project.scripts]`
   entry points, test runner/`testpaths`, and current build backend.
3. **Plans** four artifacts: the generated `mise.toml`, a
   `pyproject.toml` diff, the cleanup list, and a read-only **stale
   reference** scan (in-repo docs/scripts still describing the old
   `venv`/`pip` flow). In dry-run this is the single review surface —
   nothing is written.
4. **`--apply` only** — writes `mise.toml`, rewrites `pyproject.toml`
   (backend → hatchling, `optional-dependencies.dev` →
   `[dependency-groups].dev`), runs `uv sync`, and removes the stale
   `.venv/` + `*.egg-info/`. With `--update-docs`, also rewrites the
   stale in-repo references found in step 3.

> **PEP 735 silent regression** — lifting `dev` out of
> `optional-dependencies` means `pip install -e ".[dev]"` silently stops
> installing dev deps (exit 0, no error). The skill warns whenever this
> happens; switch such callers to `uv sync`.

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
