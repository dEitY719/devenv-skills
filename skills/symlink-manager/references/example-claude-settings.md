# Example — Claude Code settings.json

## Implementation Result

```text
Source (dotfiles): ~/dotfiles/claude/settings.json
Symbolic link:     ~/.claude/settings.json -> ~/dotfiles/claude/settings.json
Management script: ~/dotfiles/shell-common/tools/integrations/claude.sh
```

This one predates the `bash/<category>/` convention and sits at the dotfiles
root, so it is the layout as it actually is, not what Phase 1 would produce for
a new file today.

## Added Functions

- `claude_init`: Initialize Claude Code config symbolic links
  - Manages settings.json and statusline-command.sh
  - Auto-backup functionality
- `claude_edit_settings`: Edit settings.json

## Usage

```bash
# Initial setup or reset
claude_init

# Edit configuration
claude_edit_settings

# Show help
claude-help
```
