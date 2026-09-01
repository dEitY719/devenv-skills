# Worked example — karakeep/sync (before → after)

A real legacy project: `~/para/project/karakeep/sync`. Has a PEP 621
`pyproject.toml` but a pyenv-built `.venv` (pip-installed), setuptools
backend, `*.egg-info/`, and the `.venv/bin/activate` workflow.

## Extracted facts

| Fact | Value | Source |
|---|---|---|
| Python | `3.13` | `.venv/pyvenv.cfg` → `version = 3.13.5` |
| Runtime deps | click, httpx, pyyaml | `[project] dependencies` |
| Dev deps | pytest, pytest-httpx | `[project.optional-dependencies] dev` |
| Entry point | `karakeep-sync = karakeep_sync.cli:cli` | `[project.scripts]` |
| Test runner | pytest, `testpaths = ["tests"]` | `[tool.pytest.ini_options]` |
| Backend | `setuptools.build_meta`, `packages = ["karakeep_sync"]` | `[build-system]`, `[tool.setuptools]` |
| Linters | none detected | no `[tool.ruff]`/`[tool.mypy]`, none in dev-deps |

## Generated `mise.toml`

No linter detected → **no `lint`/`fix` tasks** (logged). `test` + `run`
emitted.

```toml
# mise.toml — Tool versions + task SSOT (migrated by devenv:mise-migrate)
#
# Daily use:
#   mise run test   # pytest
#   mise run run    # karakeep-sync

[tools]
python = "3.13"
uv     = "0.10.12"

[tasks.test]
description = "전체 테스트"
run = "uv run pytest"

[tasks.run]
description = "Run the project entry point"
run = "uv run karakeep-sync"
```

Plan note: `[INFO] no linter detected — lint/fix tasks omitted (add ruff
to [dependency-groups].dev to enable)`.

## `pyproject.toml` diff

```diff
 [build-system]
-requires = ["setuptools>=68"]
-build-backend = "setuptools.build_meta"
+requires = ["hatchling"]
+build-backend = "hatchling.build"

-[tool.setuptools]
-packages = ["karakeep_sync"]
+[tool.hatch.build.targets.wheel]
+packages = ["karakeep_sync"]

-[project.optional-dependencies]
+[dependency-groups]
 dev = [
     "pytest>=8.0",
     "pytest-httpx>=0.30",
 ]
```

`[project]` metadata, runtime `dependencies`, `[project.scripts]`, and
`[tool.pytest.ini_options]` are untouched.

## Cleanup list (`--apply`, no `--keep-venv`)

```
remove: .venv/
remove: karakeep_sync.egg-info/
```

## Stale references (read-only scan)

The migration is correct, but the repo still documents the old flow:

```
[WARN] scripts/bootstrap.sh:12   pip install -e ".[dev]"   (silent regression — now skips dev deps)
[WARN] README.md:40              source .venv/bin/activate
       README.md:38              python -m venv .venv
       docs/todo.md:21           pip install -e ".[dev]"
       docs/pc-environment.md:9  python -m venv .venv
[INFO] 2 stale-reference hits in docs/archive/ (history — not shown)
```

`--update-docs` would rewrite the five live hits to `uv sync` / `uv run`
and leave the archived ones alone. `scripts/bootstrap.sh` is the real
victim of the PEP 735 move — without the rewrite it keeps exiting 0 while
pytest never installs.

## Verdict

```
[WARN] dev deps moved to PEP 735 [dependency-groups] — any
       `pip install -e ".[dev]"` in scripts/CI will now silently skip
       dev deps. Use `uv sync` instead.
[OK] devenv:mise-migrate path=~/para/project/karakeep/sync backend=hatchling py=3.13 tasks=2
     synced=yes cleaned=.venv,egg-info docs=rewrote-5
Next: mise run test
```
