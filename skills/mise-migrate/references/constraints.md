# Operational constraints

## Safety

- **Dry-run is the default.** Nothing is written, rewritten, deleted, or
  `uv sync`-ed without an explicit `--apply`.
- **Path-scoped.** All writes and deletes stay within the target
  `<path>`. Never `rm` above it; never follow a `.venv` symlink outside
  the tree.
- **Cleanup is guarded.** `.venv/` and `*.egg-info/` are removed only on
  `--apply` and only after `mise.toml` + `pyproject.toml` are written and
  `uv sync` succeeds. `--keep-venv` skips this entirely. The exact paths
  to be removed are listed in the dry-run plan first.
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
