# Target catalog (Step 2)

`lib/render.sh` implements this table; `--report` prints which row fired for
each target and why each optional target was skipped. Source priority for
every delegating target is **mise task > package.json script > run script >
direct command** — the Makefile calls the SSOT, never copies it.

## Required (always generated)

| Target | Meaning | Source, in priority order | No source detected |
|---|---|---|---|
| `help` | Default goal. Lists every `## ` documented target. | skill template (awk over `$(MAKEFILE_LIST)`) | — |
| `build` | Produce the build output. | `mise run build` > JS `build`/`build:web` (several apps → `build-<app>` each, `build` depends on all) > `go build ./...` > `cargo build` | `@echo "no build step"`, exit 0 |
| `run` | Start the project. | `mise run run` > root JS `start`/`dev` > first run script > sub-app JS `start`/`dev` > `go run .` > `cargo run` | `@echo` hint to fill it in, exit 0 |
| `clear` | Delete build/test artifacts only. | `rm -rf` of the `artifact=` paths; `__pycache__` via a `find` that prunes dot-dirs and `node_modules` | `@echo "nothing to clear"` |
| `clean` | Alias: `clean: clear`. | — | — |

## When `run` depends on `build`

Only when `run` resolves to a **run script**, `build` is a real step, **and**
the script does not look like a dev server: the script serves what `build`
produced. Then `run: build serve` has no recipe of its own and `serve`
carries the script call. A script with a dev-server signal (`devserver=`:
`vite`, `run dev`, `next dev`, `webpack serve`, `--reload`) builds and serves
for itself, so `run` calls it directly and the report says
`skip=serve reason=run script starts a dev server (<signal>)`. `mise run`,
JS `start`/`dev`, `go run` and `cargo run` likewise build for themselves.
Known limit: the signal is a word match over the whole script, comments
included; a production script that merely mentions `vite` loses `serve`.
Known limit: a Node `start` that serves a prebuilt `dist/` also
needs `build` first; mark it in the report and let the user re-order.

## Optional (only when detected)

| Target | Generated when | Recipe |
|---|---|---|
| `setup` | Python, JS or a sub-app detected, or `[tasks.setup]` | `mise run setup`; else `uv sync`, or `.venv` creation (`python<ver>` from `.python-version`, fallback `python3`) + `pip install -r <reqs>` / `-e .`; then `<runner> install` per JS app; then per Python/mise sub-app `cd <dir> && mise run install`/`setup` > `uv sync` > `.venv` + pip |
| `serve` | `run` depends on `build` (above) | guard `test -e <first dist/build/out/.next artifact> \|\| { echo ...; exit 1; }`, then `[<PORT_VAR>=$(PORT)] <bash\|sh> ./<script>` |
| `stop` | `run` via a script with a `stop)`/`down)` case arm; else a server (`run` via script, JS or mise) **and** a port (detected or `--port`) | `<bash\|sh> ./<script> stop` (else `down`), no port needed; else `fuser $(PORT)/tcp` then `fuser -k -TERM $(PORT)/tcp`. Never `pkill`/`killall`: a name match also hits sibling processes (brokerdesk's scheduler inherits the web server's env and name) |
| `status` | a server and a port (the port rule of `stop`) | port listening or not; build output present or not |
| `logs` | a log path found in the run script | `tail -f $(LOG)` |
| `test` | `[tasks.test]`, or any of pytest / JS `test` / sub-app / go / cargo | `mise run test`; else every detected runner in turn: `$(PY) -m pytest` (or `uv run pytest`), JS `test` per app, per sub-app `cd <dir> && mise run test` > `uv run pytest`, `go test ./...`, `cargo test` |
| `test-e2e` | `[tasks.test-e2e]` or JS `test:e2e`/`e2e` | the script, per app |
| `test-all` | both `test` and `test-e2e` exist | `test-all: test test-e2e` (dependency only) |
| `lint` | `[tasks.lint]`, JS `lint`, ruff, or a sub-app lint | `mise run lint`; else JS `lint` + `ruff check .` + per sub-app `mise run lint` > `ruff check .` |
| `fmt` | `[tasks.fmt]`, JS `format`/`fmt`, ruff, or a sub-app fmt | `mise run fmt`; else JS script + `ruff format .` + per sub-app `mise run fmt`/`format` > `ruff format .` |
| `gen-X` | JS script `gen:X` or `gen-X` | the script |
| `up` / `down` | a compose file | `docker compose -f <file> up -d` / `down` |
| `<task>` | any other `mise.toml` task (`:` → `-`) | `mise run <task>`; `help`/`clear`/`clean` are reserved and reported as skipped |

## Descriptions

One line after `## `, in `--lang` (or the detected language). They never
contain `$(VAR)` — awk prints the raw text, so `PORT=$(PORT)` would show
literally. Mention the variable by name instead ("change with PORT=...").
