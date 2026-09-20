# Stale legacy-reference scan (read-only) + `--update-docs`

After a migration the config files are correct, but README / docs /
bootstrap scripts still describe the **old** `venv + pip` workflow — worst
case the PEP 735 silent regression owned by `references/pyproject-rewrite.md`
"3. Dev deps → `[dependency-groups]`".

This scan surfaces those references. It is **always read-only** in the
plan; rewriting them is opt-in via `--update-docs`.

## Scan (always, both dry-run and `--apply`)

```
sh <skill-dir>/lib/stale_scan.sh <path>
```

The legacy-workflow ERE and the exclusion list are the script's, not this
file's — it is the SSOT for both, so neither is re-applied from memory.
Output is one `<file>:<line>:<match>` per live hit, then a final
`excluded=<n>`. One hit is always exactly one **physical line**, so the
stream is safe to read line by line: `<file>` is printed escaped — a
backslash as `\\`, a literal newline (POSIX permits one in a path) as `\n`
— and unescaping those two sequences gives the real path back. `<line>`
and `<match>` are grep's own and unescaped; a matched line never contains
a newline. `<file>` may still contain `:`, so recover it by stripping the
`<path>` you passed in rather than splitting at the first `:`.

Report the hits as `file:line` under a **Stale references** heading in the
plan, and turn the trailing count into
`[INFO] N stale-reference hits in history/archive paths (not shown)` so the
suppression is never silent. The `pip install -e ".[dev]"` and `.[dev]`
matches are the high-severity ones (silent regression) — flag them with
`[WARN]`.

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
