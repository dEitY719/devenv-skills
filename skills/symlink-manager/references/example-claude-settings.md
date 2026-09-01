# Example — Claude Code settings.json

## Implementation Result

```text
Original location: ~/dotfiles/bash/claude/settings.json
Symbolic link:     ~/.claude/settings.json -> ~/dotfiles/bash/claude/settings.json
Management script: ~/dotfiles/shell-common/tools/external/claude.sh
```

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
