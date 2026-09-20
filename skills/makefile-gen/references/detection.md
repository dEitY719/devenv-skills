# Detection — what is this project built with? (Step 1)

```
sh <skill-dir>/lib/detect.sh <path>
```

Read-only and offline: it stats and greps files under `<path>` and prints one
`key=value` fact per line. The script is the SSOT for the rules below — this
page explains them; if the two disagree, the script wins and this page is the
bug. `detect.sh --help` prints the key list.

## Signal matrix (priority order)

| Signal | Key(s) | Maps to |
|---|---|---|
| `mise.toml` / `.mise.toml` `[tasks.X]` | `mise_task=X` | Same-name target → `mise run X`. Highest priority: shared SSOT with `mise-migrate`. |
| `package.json` scripts — root, else every immediate subdir, `apps/*` and `src/*` (e.g. `src/frontend`) | `js=<dir>\|<runner>\|<scripts>` | `build`←`build`/`build:web`, `run`←`start`/`dev`, `test`←`test`, `test-e2e`←`test:e2e`/`e2e`, `lint`←`lint`, `fmt`←`format`/`fmt`, `gen-X`←`gen:X`, `setup`←`<runner> install` |
| Runner lockfile in the app dir | (in `js=`) | `bun.lock`/`bun.lockb` > `pnpm-lock.yaml` > `yarn.lock` > `package-lock.json`; none → `npm`. More than one → `warn=lockfile conflict ...` |
| `pyproject.toml` / `setup.py` / `requirements*.txt` (root) | `py=uv\|pip` | `uv.lock` → `uv run ...` / `uv sync`; else `$(PY)` (`.venv/bin/python` via `$(wildcard)`, fallback `python3`) |
| `.python-version` | `py_version=` | `setup` creates `.venv` with `python<major.minor>` |
| `requirements-dev.txt` > `requirements.txt` | `py_reqs=` | `setup` installs it; without one, `pip install -e .` |
| `pytest.ini` / `conftest.py` / `pytest` in deps | `py_test=pytest` | `test` runs pytest |
| `ruff.toml` / `ruff` in deps or pyproject | `py_lint=ruff` | `lint` (`ruff check .`), `fmt` (`ruff format .`) |
| Subdir with `pyproject.toml` / `setup.py` / `requirements*.txt` / `uv.lock` and/or `mise.toml` `[tasks.X]` — every immediate subdir, `apps/*` and `src/*` (same globs as the JS scan), only when the root has no Python, and never a JS app dir. The name is the root-relative path (`apps/server`), so every `cd` resolves from the repo root | `subapp=<rel>\|<uv\|pip\|->\|<pytest,ruff,req:F>\|<mise tasks>` | Per target, `cd <rel> && ...`, appended after the JS lines: `setup`←`mise run install`/`setup` > `uv sync` (uv) > `.venv` + `pip install -r F`/`-e .` (pip); `test`←`mise run test` > `uv run pytest` (pip: `.venv/bin/python -m pytest`) when pytest is present; `lint`/`fmt`←`mise run lint`/`fmt`(`format`) > `ruff check .`/`ruff format .` when ruff is present. Other sub-app mise tasks are not mapped. |
| `run-*.sh`, `scripts/{dev,start,run}.sh` | `script=<rel>\|<bash\|sh>` | `run`/`serve` call the first one (with its shebang interpreter), never re-implement its restart logic |
| A `test)` / `lint)` / `fmt)` case arm (also `fmt\|format)`) in one of those scripts or `tools/dev.sh`; first script per name wins | `script_sub=<rel>\|<bash\|sh>\|<name>` | `test`/`lint`/`fmt` → `<bash\|sh> ./<rel> <name>` in place of the root direct command (pytest/ruff/go/cargo). Only arms that exist are used. `tools/dev.sh` is a dispatcher, never the run script |
| `scripts/setup.sh`, else `setup.sh` | `script_setup=<rel>\|<bash\|sh>` | `setup` becomes the one line `<bash\|sh> ./<rel>`, above the manifest-derived recipe and below `[tasks.setup]` — the repo owns its bootstrap, so the target delegates instead of copying it |
| Every `${X_PORT:-N}`, `--port N`, `X_PORT=N` in that script, then `server.port: N` in a JS app's `vite.config.*`; deduplicated, in that order | `port=N` (repeat), `port_var=X_PORT` (first `${X_PORT:-N}`) | One port: `PORT ?= N`. Several (one script starting backend + frontend): `PORTS ?= N M`, and `stop`/`status` loop over them. `serve` passes `X_PORT=$(PORT)` |
| `LOG:-<path>.log` or `> /abs/path.log` in that script | `log=` | `LOG :=` (with `${PORT}` → `$(PORT)`) and `logs` |
| A `stop)` / `down)` case arm in that script (also `a\|stop)`), `stop` preferred | `script_stop=` | `stop` → `<bash\|sh> ./<script> stop\|down`, before the port rule |
| Dev-server signal in that script (word match: `vite`, `run dev`, `next dev`, `webpack serve`, `--reload`) | `devserver=<signal>` | `run` calls the script directly, no `serve` (it builds/serves for itself) |
| `go.mod` | `go=yes` | `go build ./...`, `go run .`, `go test ./...` |
| `Cargo.toml` | `cargo=yes` | `cargo build` / `run` / `test` |
| `compose.yml` / `docker-compose.yml` (and `.yaml`) | `compose=` | `up` / `down` |
| Allowlisted name covered by a `.gitignore` | `artifact=<rel>` | `clear` deletes it; `serve` and `status` check the first `dist`/`build`/`out`/`.next` inside the JS app that `build` runs (none there, or a non-JS build → no check) |
| `Makefile` exists | `makefile=present` | dry-run shows a diff; `--apply` refuses without `--force` |
| README contains Hangul | `lang=ko` | help language when `--lang` is absent |

## Artifacts: allowlist x .gitignore

`clear` may only ever delete the names in `ALLOW` at the top of
`lib/detect.sh`, at the root or inside a JS or Python/mise sub-app dir. A name is emitted only when the root
`.gitignore` or the app dir's own `.gitignore` lists it (leading `**/`
and trailing `/` are ignored when matching; a leading `/` anchors the line to
that `.gitignore`'s dir, so a root `/build` never covers `src/frontend/build`). `.pytest_cache` is also emitted
whenever pytest is detected, because pytest writes its own `.gitignore` into
it. `.gitignore` is never used on its own: it also lists `.env` and data
directories, which is exactly what `clear` must not touch.

## Status and exit codes

| `status=` | exit | Meaning |
|---|---|---|
| `ok` | 0 | At least one stack signal found. |
| `no-stack` | 0 | Nothing found; required targets become no-op placeholders and the report says "no stack detected". |
| `no-path` | 1 | `<path>` missing or not a directory — stop with a one-line `[FAIL]`. |

## Monorepos

A root `package.json` owns the workspace, so JS sub-apps are only scanned when
the root has none. Likewise a root Python project owns the env, so
Python/mise sub-apps (`subapp=`) are only scanned when the root has no
Python; the scan covers the same three levels as the JS one (immediate
subdir, `apps/*`, `src/*`) and they are aggregated into
`setup`/`test`/`lint`/`fmt` after the JS lines (a root `[tasks.X]` still wins
for the whole target; a `script_setup=` script wins `setup` outright). With two or more sub-apps that have a build script, each
gets `build-<dir>` and `build` depends on all of them in order.
