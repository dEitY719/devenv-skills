# Operational constraints

## Safety

- **Dry-run is the default.** Nothing is written, rewritten, deleted, or
  `uv sync`-ed without an explicit `--apply`.
- **Path-scoped.** All writes and deletes stay within the target
  `<path>`. Never `rm` above it; never follow a `.venv` symlink outside
  the tree.
- **Cleanup is guarded.** `.venv/` and `*.egg-info/` are removed only on
  `--apply` and only after `mise.toml` + `pyproject.toml` are written and
  `uv sync` succeeds. `--keep-venv` skips `.venv/` entirely. uv's project
  env is `<path>/.venv` too, so the old and new env share one path: a
  `.venv` whose `pyvenv.cfg` has a `uv = ` key is the one `uv sync` just
  built, and it is kept (`kept: <path>/.venv (uv-managed)`), never
  deleted. A legacy venv that `uv sync` reused in place carries no such
  key and is still removed; the next `uv sync` / `uv run` recreates it.
  `*.egg-info/` is always removed, and any target resolving outside
  `<path>` is refused. The exact paths to be removed are listed in the
  dry-run plan first.
- **No source edits.** Only `mise.toml` (new) and the build/dependency
  stanzas of `pyproject.toml` change. Application code and imports are
  never touched.

## Idempotency

- A target that already has a `mise.toml` is a no-op (`[INFO] already
  migrated`). Safe to re-run.
- Re-running dry-run on the same project yields the same plan.

## Failure handling

- Mid-`--apply` failure stops at the first error with `[FAIL]
  devenv:mise-migrate <reason>` + exit 1 and reports what was written so
  far. **No automatic rollback** — the user owns cleanup. Ordering
  (write configs → `uv sync` → delete venv last) means a failure never
  destroys the old venv before the new one is proven.

## Out of scope (refuse / skip, don't improvise)

- Non-Python projects, and node/go/multi-language repos — Python-venv
  scope only.
- Monorepos with multiple `pyproject.toml` files — operate on the single
  `<path>` given; do not recurse.
- Publishing, lockfile pinning beyond what `uv sync` produces, or CI
  config — those are follow-up work, not this skill's job.
