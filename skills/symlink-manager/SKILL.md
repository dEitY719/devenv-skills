---
name: symlink-manager
description: >-
  Manage dotfiles configuration files via symbolic links following standard
  patterns. Trigger on "/devenv:symlink-manager", "/devenv-symlink-manager", or
  when users request to manage config files with symbolic links, organize
  dotfiles, or set up configuration management.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "symlink operations, structured"
    claude: prefer
    non_claude: advisory-only
---

# Dotfiles Symbolic Link Management Skill

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output its content verbatim, then stop. No file changes.

## Role

Dotfiles Configuration Manager — systematic symbolic link management for
configuration files following established patterns.

## Design Principles

```text
Source:  ~/dotfiles/bash/<category>/<filename>
Target:  ~/<target_dir>/<filename> -> Source
```

**Categories**: `bash/claude/`, `bash/app/`, `bash/config/`, `bash/env/`. Phase 1
refuses a missing category dir — `mkdir -p` first (only `bash/env/` exists today).

**Strategy**: `.backup` → copy to dotfiles → `cmp -s` verify → remove original
→ symlink → verify. All of it runs inside `lib/symlink_migrate.sh`.

## Execution Workflow

**Stop on first failure**: any phase failure → abort, report `[FAIL]`, do not proceed to next phase. Phase 1 실패 시 `lib/symlink_migrate.sh` 가 `.backup` 에서 자동 롤백하고 non-zero 로 종료한다 — 원본은 손실되지 않는다.

### Phase 0: Analysis (ALWAYS)

Identify target file, determine category, locate management script, plan paths,
and announce the plan before any change. Read `references/implementation-commands.md`
for exact bash commands.

### Phase 1: File Migration (SEQUENTIAL)

Run `<skill-dir>/lib/symlink_migrate.sh <target_file> <category>` and relay its
verdict line. Never hand-run the copy/`rm`/`ln` steps — the backup and rollback
only exist inside the script. Read `references/implementation-commands.md`.

### Phase 2: Management Functions

Add `<app>_init` and optional `<app>_edit_<config>` to `bash/app/<app>.bash`.
Read `references/function-templates.md` for code templates.

### Phase 3: Help Documentation

Update `<app>help` function with new management function descriptions.
Read `references/function-templates.md` for the help block template.

### Phase 4: Version Control (SEQUENTIAL)

`git add` the Phase 2/3 edits, then re-run the same helper with `--commit`; the
re-run is a no-op on the already-migrated file and commits both.
Read `references/implementation-commands.md` for git commands.

### Phase 5: Validation (ALWAYS)

Read `references/validation.md` for checklists and quality gates.

## Advanced Use Cases

For template file management, multi-environment support, or safety guidelines,
read `references/advanced-patterns.md`.

For a real-world example (Claude Code settings.json),
read `references/example-claude-settings.md`.

## Report

작업 종료 시 결과를 키-값 verdict 로 보고한다 (files/links/functions/commit/validation 요약):

```
[OK]   devenv:symlink-manager target=<file> category=<dir> links=<n> commit=<sha>
[FAIL] devenv:symlink-manager phase=<n> reason=<one-line>
```

Next: source ~/.bashrc && <app>help  # 새 심볼릭 링크 검증, 또는 rollback 시 ./setup.sh
