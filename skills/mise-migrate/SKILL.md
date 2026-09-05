---
name: mise-migrate
description: >-
  Convert a legacy Python venv/pip project into the canonical mise + uv
  structure. Use for /devenv:mise-migrate, /devenv-mise-migrate, "예전 파이썬
  venv 프로젝트를 mise+uv 로 전환", "migrate this venv project to mise".
  Python-venv projects only.
allowed-tools: Bash, Read, Edit, Write, Grep
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "Config transformation + dependency/backend mapping; structured, low-ambiguity reasoning"
    claude: prefer
    non_claude: advisory-only
---

# devenv:mise-migrate — legacy Python venv → mise + uv

Turns a pyenv / `python -m venv` + pip + setuptools project into the canonical
structure: a `mise.toml` carrying `[tools]` + `[env]` + `[tasks.*]` as the
command SSOT, with **uv** owning the venv and dependencies and **hatchling**
(default `--backend`) as the build backend. **Python-venv projects only** —
non-Python or already-migrated (`mise.toml` present) directories are refused,
never improvised around. `--dry-run` is the default and mutates nothing; only
an explicit `--apply` writes. Full flag table: `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No detection, no file mutation.**

## Step 1: Parse Args + Detect a Legacy Python Project

Positional `[path]` defaults to `.`. Flags: `--dry-run` (default),
`--apply`, `--backend hatchling|uv_build` (default `hatchling`),
`--keep-venv`, `--update-docs`. Full table in `references/help.md`.

Detect a legacy Python project (pyproject / setup.py / `requirements*.txt`),
applying the nested-fallback retarget, the already-migrated short-circuit,
and the refusal exit codes in `references/detection.md`.

## Step 2: Extract Migration Facts (read-only)

Gather, via `Read` + `Grep`, the inputs in `references/extraction.md`:
Python version, runtime + dev deps, `[project.scripts]` entry points,
test runner + `testpaths`, build backend, and which linters (ruff /
mypy) are configured — lint/fix tasks are generated only for tools
actually present (Step 3).

## Step 3: Build the Migration Plan

Assemble four artifacts per `references/mise-template.md` and
`references/pyproject-rewrite.md` (`references/example-karakeep.md` is a
full before→after walkthrough):

1. **`mise.toml`** — `[tools]` (python + uv, + ruff/mypy if detected),
   `[env]`, `[tasks.lint|test|fix|run]` wrapping `uv run`. Mapping +
   linter-conditional rules: `references/mise-template.md`.
2. **`pyproject.toml` diff** — backend → `--backend`, explicit-packages
   carried over, `optional-dependencies.dev` → `[dependency-groups].dev`.
3. **Cleanup list** — stale `.venv/` + `*.egg-info/` (skipped by
   `--keep-venv`).
4. **Stale references** — read-only grep of `<path>` for the legacy
   `venv`/`pip`/`.[dev]` workflow, reported as `file:line` (history /
   archive excluded). Full ERE + opt-in `--update-docs` rewrite:
   `references/stale-scan.md`.

Surface the PEP 735 silent-regression `[WARN]` whenever a `dev` extra is
lifted into `[dependency-groups]` — `pip install -e ".[dev]"` then installs
nothing and still exits 0 (`references/pyproject-rewrite.md`) — and the
floor-vs-resolved `[INFO]` when the pin came from `requires-python`
(`references/extraction.md`).

In `--dry-run` (default), print all four and stop using the plan block in
`references/output-format.md`.

## Step 4: Apply (only if `--apply`)

In order, stopping on first failure with `[FAIL] devenv:mise-migrate
<reason>` + exit 1 (no automatic rollback — report partial state):

1. Write `mise.toml`.
2. Rewrite `pyproject.toml` in place (backend, packages, dep-groups).
3. Run `uv sync` to materialize the uv-managed venv + lockfile.
4. Cleanup — remove `.venv/` + `*.egg-info/` unless `--keep-venv`;
   never delete outside `<path>`. Guardrails: `references/constraints.md`.
5. Stale docs — **only if `--update-docs`**, rewrite the non-excluded
   stale hits and re-print touched files (`references/stale-scan.md`).
   The PEP 735 `[WARN]` still fires (external CI is out of reach).

## Step 5: Report

Emit the success line, the `--apply` append fields, the dry-run `Next:`
hint, and the carried-over `[WARN]`/`[INFO]` notes per
`references/output-format.md`.
