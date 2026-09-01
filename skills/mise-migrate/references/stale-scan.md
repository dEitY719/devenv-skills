# Stale legacy-reference scan (read-only) + `--update-docs`

After a migration the config files are correct, but README / docs /
bootstrap scripts still describe the **old** `venv + pip` workflow.
Worst case is a *silent regression*: a script that calls
`pip install -e ".[dev]"` keeps running with **exit 0** but now skips the
dev deps, because the `dev` extra was lifted to PEP 735
`[dependency-groups]` (see `references/pyproject-rewrite.md` "3. Dev deps
→ `[dependency-groups]`"). CI passes with pytest never installed.

This scan surfaces those references. It is **always read-only** in the
plan; rewriting them is opt-in via `--update-docs`.

## Scan (always, both dry-run and `--apply`)

`Grep` the target `<path>` (recursively) for the legacy-workflow ERE:

```
python -m venv|python3 -m venv|pip install|\.venv/bin/activate|\.\[dev\]|setuptools|requirements\.txt
```

The `requirements\.txt` alternative catches bare doc references (e.g.
"see `requirements.txt`") that `pip install` alone would miss — uv folds
those deps into `pyproject.toml`, so the file reference is also stale.

Report each hit as `file:line` under a **Stale references** heading in
the plan. The `pip install -e ".[dev]"` and `.[dev]` hits are the
high-severity ones (silent regression) — flag them with `[WARN]`.

### Exclusions (history, not live instructions)

Skip paths that document the *past* rather than instruct the *present* —
they are expected to mention the old flow:

- `**/archive/**`, `**/_archive/**`
- design/spec/plan docs: `**/*plan*.md`, `**/*spec*.md`, `**/*design*.md`,
  `CHANGELOG*`, `docs/**/decisions/**`
- the generated `mise.toml` / `uv.lock` / `.venv/**` themselves

List how many hits were excluded so the suppression is never silent:
`[INFO] N stale-reference hits in history/archive paths (not shown)`.

## `--update-docs` (opt-in, only with `--apply`)

Off by default. When set, after the config rewrite + `uv sync` succeed,
rewrite the **non-excluded** hits with the canonical replacements below,
then re-print the touched files. Never edit excluded/history paths.

| Legacy | Replacement |
|---|---|
| `python -m venv .venv` / `python3 -m venv .venv` | `uv sync` (creates the venv) |
| `source .venv/bin/activate` | (drop; prefix commands with `uv run`) |
| `pip install -e ".[dev]"` / `pip install -e .` | `uv sync` |
| `pip install -r requirements.txt` / `pip install -r requirements-dev.txt` | `uv sync` (deps now in `pyproject.toml`) |
| `pip install <pkg>` | `uv add <pkg>` |

Code blocks that show a *full* sequence (`venv` → `activate` →
`pip install`) collapse to a single `uv sync`. The remaining ERE
alternatives have **no mechanical rewrite** — a bare `setuptools` mention
or a prose `requirements.txt` reference depends on surrounding context
(build-backend prose, a stale install doc, a historical note). Report
these as manual-review hits and leave them untouched. When any line's
intent is ambiguous, do the same rather than guess — this skill never
improvises source/doc edits (`constraints.md`).

`--update-docs` without `--apply` is a no-op with a note:
`[INFO] --update-docs requires --apply; scan is read-only in dry-run`.
