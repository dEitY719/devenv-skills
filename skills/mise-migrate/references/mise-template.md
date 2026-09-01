# Generated `mise.toml` template

Render this from the Step 2 facts. Modeled on the dotfiles repo's own
`mise.toml` (the canonical target structure). Omit blocks that don't
apply — never emit a task that wraps a tool the project lacks.

## Skeleton

```toml
# mise.toml — Tool versions + task SSOT (migrated by devenv:mise-migrate)
#
# Daily use:
#   mise run lint   # ruff + mypy            (read-only)   [if linters detected]
#   mise run test   # pytest                               [if tests detected]
#   mise run fix    # ruff --fix + format    (mutating)    [if linters detected]
#   mise run run    # <entry-point>                        [if scripts exist]

[tools]
python = "{{ py_version }}"   # from pyvenv.cfg / requires-python
uv     = "{{ uv_pin }}"       # pin a current stable (match repo SSOT)
# ruff / mypy lines ONLY when those tools were detected

[env]
# Project-root convenience var, mirrors the repo pattern. Drop if unused.
# PROJECT_ROOT = "{{ config_root }}"

# ─── Lint gates (read-only) — emit only if a linter was detected ─────
[tasks.lint]
description = "전체 lint"
depends     = ["lint-py"]

[tasks.lint-py]
description = "Python lint (ruff check + format check[ + mypy])"
run = [
    "uv run ruff check .",          # only if ruff detected
    "uv run ruff format --check .", # only if ruff detected
    # "uv run mypy .",              # only if mypy detected
]
# mypy-only project (no ruff) → run = ["uv run mypy ."] and no fix-py.

# ─── Test gate ───────────────────────────────────────────────────────
[tasks.test]
description = "전체 테스트"
run = "uv run pytest"

# ─── Auto-fix (mutating) — emit only if a linter was detected ────────
[tasks.fix]
description = "전체 auto-fix"
depends     = ["fix-py"]

[tasks.fix-py]   # emit only if ruff detected (mypy has no auto-fix)
description = "Python auto-fix (ruff check --fix + format)"
run = [
    "uv run ruff check --fix .",
    "uv run ruff format .",
]

# ─── App entry point — emit only if [project.scripts] exists ─────────
[tasks.run]
description = "Run the project entry point"
run = "uv run {{ script_name }}"
```

## Rendering rules

- **`{{ py_version }}`** — concrete pin from `extraction.md`.
- **`{{ uv_pin }}`** — a current stable uv (e.g. the version already
  pinned in the dotfiles repo `mise.toml`); the user can bump later.
- **`[tools]` ruff/mypy** — add `ruff = "<ver>"` / `mypy = "<ver>"`
  lines only when those tools are detected. They are a `uv run`
  fallback, mirroring the repo comment "fallback for environments that
  need the binary outside `uv run`".
- **lint / fix tasks** — emit the `lint*`/`fix*` group only when *some*
  linter is detected, and build each `run` array per-tool — never emit a
  command for a tool that is absent (it would fail on `mise run`):
  - ruff detected → include the `ruff check` / `ruff format` lines
    (lint) and `ruff check --fix` / `ruff format` lines (fix).
  - mypy detected → append `uv run mypy .` to `lint-py` (mypy has no
    auto-fix, so it adds nothing to `fix-py`).
  - **mypy only (no ruff)** → `lint-py` runs *just* `uv run mypy .`;
    drop every ruff line and omit `fix`/`fix-py` entirely.
  - neither → omit `lint`/`fix` (logged per `extraction.md`).
  Adjust each `description` to match the lines actually emitted.
- **`[tasks.run]`** — only when `[project.scripts]` has at least one
  entry; `{{ script_name }}` is the first script name.
- **`test`** — always emitted; default `uv run pytest`.

Keep the comment header honest: list only the tasks actually generated.
