---
name: symlink-manager
description: >-
  Manage dotfiles configuration files via symbolic links following standard
  patterns. Trigger on "/devenv:symlink-manager" or when users request to manage
  config files with symbolic links, organize dotfiles, or set up configuration
  management.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
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

**Categories**: `bash/claude/` (Claude Code), `bash/app/` (app-specific),
`bash/config/` (general config), `bash/env/` (environment vars)

**Strategy**: Move original → auto-backup (.backup) → create symlink → verify

## Execution Workflow

**Stop on first failure**: any phase failure → abort, report `[FAIL]`, do not proceed to next phase. Phase 1 파일 이동 실패는 자동 롤백 (.backup 복원).

### Phase 0: Analysis (ALWAYS)

Identify target file, determine category, locate management script, plan paths.
Read `references/implementation-commands.md` for exact bash commands.

### Phase 1: File Migration (SEQUENTIAL)

Copy file to dotfiles, remove original, create symbolic link, verify.
Read `references/implementation-commands.md` for exact bash commands.

### Phase 2: Management Functions

Add `<app>_init` and optional `<app>_edit_<config>` to `bash/app/<app>.bash`.
Read `references/function-templates.md` for code templates.

### Phase 3: Help Documentation

Update `<app>help` function with new management function descriptions.
Read `references/function-templates.md` for the help block template.

### Phase 4: Version Control (SEQUENTIAL)

Stage and commit all changes.
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

## Command

When invoked, IMMEDIATELY analyze the target file, determine the category, and
EXECUTE the workflow. Start with Phase 0 and announce the plan before any change.
