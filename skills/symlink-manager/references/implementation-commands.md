# Implementation Commands — bash commands for each phase

## Phase 0: Analysis

```bash
# Verify file exists and check content
cat <target_file>
ls -la <target_file>
```

- Analyze file purpose and content
- Select appropriate category (claude/app/config/env)
- Check category directory structure

```bash
# Find or identify bash script location
cat ~/dotfiles/shell-common/tools/external/<app>.sh
```

Plan file paths:
- Source: `~/dotfiles/bash/<category>/<filename>`
- Target: Original file location
- Backup: `<target_file>.backup` (created by the Phase 1 helper, not here)

Output: File analysis, category decision, path planning

## Phase 1: File Migration (SEQUENTIAL)

Phase 1 is **not** a command list any more. It is one script, because a promise
in `SKILL.md` and a command list here are two documents and nothing kept them
in agreement — the old list copied the file, `cat`-ed the destination, and then
ran `rm <target_file>` unconditionally, with no backup to restore from.

```bash
<skill-dir>/lib/symlink_migrate.sh <target_file> <category>
```

`<category>` is one of `claude` / `app` / `config` / `env`. The dotfiles root is
`$DOTFILES_ROOT` (default `~/dotfiles`). What it does, in order:

1. `cp -p <target_file> <target_file>.backup` — **before** anything touches the
   original — and confirms the backup is byte-identical.
2. `cp` into `$DOTFILES_ROOT/bash/<category>/<filename>`, then `cmp -s` against
   the source. A `cat` prints; only `cmp` compares.
3. Only then `rm <target_file>`, then `ln -s` back.
4. Verifies the link exists, resolves, and reads back byte-identical.

Any failure in 1-4 removes the partial copy, restores the original from
`.backup`, and exits non-zero with
`[FAIL] devenv:symlink-manager phase=1 reason=<one-line>`. On success it prints
the `[OK]` verdict line and leaves `.backup` in place as the safety net.

It refuses rather than guesses: unknown category, missing target, a target that
is not a regular file, a missing or unwritable category directory, or a
pre-existing `.backup` it would have to clobber.

Re-running on an already-migrated file is a no-op (that is how Phase 4 invokes
it), and `--self-test` runs the backup + rollback assertions on scratch files.

## Phase 4: Version Control (SEQUENTIAL)

```bash
# Check .gitignore if needed
grep "<filename>" .gitignore

# Stage the Phase 2/3 edits first — they ride along in the same commit
git -C ~/dotfiles add bash/app/<app>.bash
git -C ~/dotfiles add .gitignore  # if modified

# Stage the migrated file and commit
<skill-dir>/lib/symlink_migrate.sh <target_file> <category> --commit
```

A Phase 4 failure is **not** rolled back: the symbolic link is already verified
at that point and `.backup` is still on disk, so undoing a good migration
because `git` failed would be the destructive choice.
