# Detection — is this a legacy Python project? (Step 1)

Run after parsing args. Decide whether `<path>` is a migratable legacy
Python project, retarget if needed, or refuse early. All read-only.

```
bash <skill-dir>/lib/detect_project.sh <path>
```

The script implements the rules below and is their SSOT — Step 1 reads its
two output lines (`path=`, `status=`, plus `candidate=` lines when
ambiguous) instead of walking the tree by hand. The rest of this file is the
contract it satisfies and the wording of the notes to surface.

## Signals

A pyenv `.venv/` / `pyvenv.cfg` is the signal worth migrating, but its
absence is **not** fatal — a pip/`requirements*.txt` project still
qualifies. The project markers are `pyproject.toml`, `setup.py`, or
`requirements*.txt` at `<path>`.

## Decision rules (in order)

1. **No marker at `<path>` → nested fallback.** If `<path>` itself has no
   marker but exactly **one** direct child dir (depth 1) does, retarget to
   it and note:

   ```
   [INFO] retargeting to nested project: <child>
   ```

   - **≥2 candidate child dirs** → list them and fail (exit 1).
   - **Still none** anywhere →

     ```
     [FAIL] devenv:mise-migrate: not a Python project: <path>
     ```

     (exit 1).

2. **Already migrated.** A `mise.toml` already exists at the (possibly
   retargeted) path → idempotent no-op:

   ```
   [INFO] devenv:mise-migrate: already migrated
   ```

   (exit 0).

3. Otherwise proceed to Step 2 (Extract Migration Facts).
