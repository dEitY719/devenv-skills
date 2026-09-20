# Operational constraints

## Safety

- **Dry-run is the default.** Nothing is written without an explicit
  `--apply`. `detect.sh` and `render.sh` (render, `--report`, `--check`)
  never write.
- **One file.** `--apply` writes only `<path>/Makefile`, plus
  `<path>/Makefile.bak` under `--force`. No source, config or script is
  edited.
- **No merge.** An existing Makefile is replaced (`--apply --force`, after
  `cp Makefile Makefile.bak`) or left alone (`--apply` alone refuses).
  Merging hand-written rules the skill does not understand breaks them
  silently.
- **The sentinel region is copied, never merged.** The generated text ends
  with `# --- custom (kept by makefile-gen) ---`; whatever an existing
  Makefile has below that line is carried over byte for byte. The skill
  never reads, validates or rewrites it, and `--check` / `--verify` stop at
  the sentinel. A Makefile with no sentinel gets no preservation, and the
  report names every target `--force` would drop. Render into a temp file
  and move it in: `render.sh <path> > <path>/Makefile` truncates the file
  before the region can be read out of it.
- **Secrets and data are out of reach.** `clear` deletes only allowlisted
  names that a `.gitignore` also covers (`references/detection.md`). The
  allowlist has no entry that could match `.env*`, credential files,
  `node_modules` (possibly a symlink to a shared store), `.venv`, `.git`
  or runtime data such as `web/data`. The `__pycache__` sweep prunes every
  dot-directory and `node_modules` before it looks.
- **Port, not name.** `stop` kills whatever holds `:$(PORT)` (each of `$(PORTS)`
  when the run script starts several servers) and nothing else. A name or env match also hits sibling processes; brokerdesk's
  scheduler inherits `WEB_PORT` from the web server, so a name-based stop
  killed running strategies.
- **Verification has no side effects.** `--verify` runs `make` (help only)
  and `make -n <target>` over the generated `.PHONY` set. It never really
  runs `run`, `serve`, `stop`, `build` or `clear`, and it never `make -n`s a
  preserved target — that recipe is the user's and may call tooling the
  skill knows nothing about.

## Failure handling

- Render fails `--check` → nothing is written; report the rule that failed.
- `--verify` fails after the write → restore `Makefile.bak` (or delete the
  new Makefile when there was none before) and report the failing targets.
  This is the only rollback, and it covers the only file the skill wrote.
- `<path>` missing or not a directory → one-line `[FAIL]`, exit 1.

## Idempotency

- Re-running dry-run on an unchanged project gives the same Makefile.
- Re-running `--apply` after a successful apply refuses (a Makefile now
  exists); `--apply --force` rewrites it and refreshes `Makefile.bak`.

## Portability

- GNU Make 3.81+ and POSIX `sh` recipes (`references/template.md`).
- `stop` / `status` use `fuser` (Linux psmisc). On macOS without it, they
  print the "not running" branch; the report should say so, and point the
  user at `lsof -ti tcp:<port> | xargs kill` as the manual equivalent.
- Windows `nmake` / `cmd` are not targets.

## Out of scope (refuse / skip, don't improvise)

- Introducing or changing a build system — that is `mise-migrate` or the
  user's job.
- CI workflows, Dockerfiles, compose files.
- Guessing commands with no evidence file. An undetected optional target is
  skipped and listed with its reason, not invented.
