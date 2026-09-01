# Symlink Manager Skill

A Claude Code skill for managing dotfiles configuration files via symbolic links following standard patterns.

## Purpose

This skill automates the process of managing configuration files as symbolic links in the dotfiles repository, ensuring consistency, proper version control, and maintainability.

## When to Use

Invoke this skill when you need to:

- Manage a config file with symbolic links
- Organize configuration files in dotfiles
- Set up automated configuration management
- Create management functions for config files

## Trigger Examples

```bash
# Korean
"xxx.yyy 파일을 symbolic link로 관리해"
"dotfiles로 zzz 설정 파일 관리하고 싶어"

# English
"Manage settings.json with dotfiles"
"Set up symbolic link for .bashrc"
```

## What This Skill Does

1. **Analyzes** the target configuration file
2. **Determines** appropriate category (claude/app/config/env)
3. **Migrates** file to dotfiles repository
4. **Creates** symbolic link from original location
5. **Implements** management functions (`<app>_init`, `<app>_edit_<config>`)
6. **Updates** help documentation
7. **Commits** changes to git

## File Structure

```text
~/dotfiles/bash/<category>/<filename>  (source file)
        ↓ symbolic link
~/<target_dir>/<filename>              (linked file)
```

## Categories

- `bash/claude/`: Claude Code related configuration
- `bash/app/`: Application-specific configs
- `bash/config/`: General configuration files
- `bash/env/`: Environment variable configs

## Management Functions

Generated functions for each managed config:

```bash
<app>_init              # Initialize symbolic links
<app>_edit_<config>     # Edit configuration file
<app>help               # Show help (updated)
```

## Example: Claude Code Settings

```bash
# File migration
~/.claude/settings.json -> ~/dotfiles/bash/claude/settings.json

# Generated functions
claude_init              # Set up symbolic links
claude_edit_settings     # Edit settings.json
claude-help             # Show all commands
```

## Safety Features

- Auto-backup of existing files (.backup extension)
- .gitignore integration for sensitive files
- Verification of symbolic links
- Template file support for secrets
- Multi-environment configuration support

## Workflow Phases

1. **Phase 0: Analysis** - Examine file and plan migration
2. **Phase 1: Migration** - Move file and create link
3. **Phase 2: Functions** - Generate management functions
4. **Phase 3: Documentation** - Update help
5. **Phase 4: Version Control** - Commit changes
6. **Phase 5: Validation** - Verify everything works

## Quality Gates

Before completion, ensures:

- Symbolic link verified and functional
- Management functions tested
- Help documentation updated
- Changes committed to git
- No sensitive data exposed
- Backup created

## Advanced Features

### Template Files

```bash
config.json.template  # Versioned template
config.json          # Local, .gitignored
```

### Multi-Environment

```bash
config.local.json    # Development
config.dev.json      # Staging
config.prod.json     # Production
```

## Related Files

- Source: `dEitY719/dotfiles` `claude/skills/devx-symlink-manager/` (pre-split origin)
- Skill: `skills/symlink-manager/SKILL.md` (this skill)

## Author

Generated from dotfiles symbolic link management guidelines.

## Version

1.0.0 - Initial skill conversion
