# Detection — is this a legacy Python project? (Step 1)

Run after parsing args, before anything else. All read-only.

```
bash <skill-dir>/lib/detect_project.sh <path>
```

The script owns the rules — the marker set, the nested-fallback threshold, the
already-migrated short-circuit, and the exit codes. Do not restate them here:
a second copy is what lets the two drift. `detect_project.sh --help` prints
them, and the script itself is the SSOT.

## Reading its output

| `status=` | exit | What Step 1 does |
|---|---|---|
| `ok` | 0 | Proceed to Step 2 with `path=`. |
| `nested` | 0 | Proceed with the retargeted `path=`, after noting `[INFO] retargeting to nested project: <path>`. |
| `already-migrated` | 0 | Stop. `[INFO] devenv:mise-migrate: already migrated` — an idempotent no-op, not a failure. |
| `no-marker` | 1 | Stop. `[FAIL] devenv:mise-migrate: not a Python project: <path>` |
| `ambiguous` | 1 | Stop. List the `candidate=` lines it printed, so the user can re-run against one of them. |

## Why the `.venv/` is not required

A pyenv `.venv/` or `pyvenv.cfg` is the signal most worth migrating, but its
absence is not fatal — a pip / `requirements*.txt` project qualifies just as
much, and after a failed earlier attempt the venv may already be gone.
