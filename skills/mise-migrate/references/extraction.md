# Extraction — what to read from the legacy project

All read-only. Gather these facts before building the plan (Step 3).

## Python version

Priority order:

1. `.venv/pyvenv.cfg` → `version = X.Y.Z` (the version the project was
   actually built against — most authoritative).
2. `pyproject.toml` → `[project] requires-python` (e.g. `>=3.11` → pin
   the lowest satisfying stable, or echo the floor and let the user
   bump). Prefer the concrete `pyvenv.cfg` value when both exist.
3. `.python-version` (pyenv) if present.

Emit a single concrete pin for `[tools] python` (e.g. `"3.13"`). When
only a `>=` floor is known (no `pyvenv.cfg`), pin the floor and note in
the plan that the pin is the **floor**, not what `uv` will actually
resolve — `uv sync` picks the newest interpreter on the box that
satisfies it (e.g. floor `3.11` but uv grabs the system `3.13.5`):

```
[INFO] python pin = requires-python floor (3.11); no pyvenv.cfg found.
       `uv sync` may resolve a newer interpreter (e.g. 3.13). Pin
       [tools] python to an exact version if you need it reproducible.
```

## Dependencies

- **Runtime** — `pyproject.toml` `[project] dependencies`, else
  `requirements.txt`. Carried over verbatim.
- **Dev** — `[project.optional-dependencies] dev`, else
  `requirements-dev.txt` / `dev-requirements.txt`. These become
  `[dependency-groups] dev` (see `pyproject-rewrite.md`).

## Entry points

`[project.scripts]` — each `name = "module:fn"` line. The first entry
becomes the `[tasks.run]` target (`uv run <name>`). If there are none,
omit the `run` task and note it.

## Test runner

- `[tool.pytest.ini_options] testpaths` → pytest is the runner; the
  `test` task becomes `uv run pytest` (append the testpath only if it is
  non-default and not already discovered).
- No pytest config but a `tests/` dir exists → still default to
  `uv run pytest`.
- No test signal → emit `test` as `uv run pytest` with a plan note that
  no tests were detected.

## Linters (conditional task generation)

Detect ruff / mypy via `[tool.ruff]` / `[tool.mypy]` stanzas OR their
presence in dev-deps. Generate `lint`/`fix` tasks **only** for tools
found:

- ruff found → `lint-py` includes `uv run ruff check .` +
  `ruff format --check .`; `fix-py` includes `ruff check --fix .` +
  `ruff format .`.
- mypy found → append `uv run mypy .` to `lint-py`.
- Neither found → omit `lint`/`fix` and log:
  `[INFO] no linter detected — lint/fix tasks omitted (add ruff to
  [dependency-groups].dev to enable)`.

## Build backend

`pyproject.toml` `[build-system] build-backend` (e.g.
`setuptools.build_meta`) and any `[tool.setuptools] packages = [...]`.
Both feed the rewrite in `pyproject-rewrite.md`.
