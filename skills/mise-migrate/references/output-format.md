# Output & report formats — dry-run plan + final report

Used by Step 3 (dry-run plan) and Step 5 (final report). Print these
verbatim, substituting the `<...>` fields.

## Dry-run plan block (Step 3, `--dry-run` default)

After printing all four artifacts, end with this block and stop — mutate
nothing:

```
Plan ready: <path> (backend=<backend>, py=<ver>, tasks=<n>, stale=<s>)
Run with --apply to write mise.toml, rewrite pyproject, and uv sync.
```

## Final report (Step 5)

Emit a **single** structured success line. The `--apply` fields append to
that same line (one key=value verdict line — never a second line); the
`Next:` hint then prints on its own separate line.

Base success line (always):

```
[OK] devenv:mise-migrate path=<path> backend=<backend> py=<ver> tasks=<n>
```

On `--apply`, append the apply fields to that **same** line:

```
[OK] devenv:mise-migrate path=<path> backend=<backend> py=<ver> tasks=<n> synced=yes cleaned=<.venv,egg-info|kept> docs=<rewrote-N|scan-only>
```

Then print the next-step hint on its **own** line:

- `--dry-run` → `Next: review the plan, then re-run with --apply`
- successful `--apply` → `Next: mise run test`

## Carried-over notes (both modes)

Always re-print any `[WARN]` / `[INFO]` notes so they survive into the
final surface:

- PEP 735 silent-regression `[WARN]` (dev extra lifted to
  `[dependency-groups]`) — `references/pyproject-rewrite.md`.
- Stale legacy references found by the scan — `references/stale-scan.md`.
- Pin-is-floor `[INFO]` (Python pin came from `requires-python`, no
  `pyvenv.cfg`) — `references/extraction.md`.
