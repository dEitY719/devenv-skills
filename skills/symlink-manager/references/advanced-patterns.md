# Advanced Patterns — templates, multi-env, safety

## Template File Management

For sensitive information:

```bash
# Create template file
cp config.json config.json.template
git add config.json.template

# Add actual file to .gitignore
echo "bash/<category>/config.json" >> .gitignore

# Add template copy logic to init function
if [ ! -f "$source" ] && [ -f "$source.template" ]; then
    cp "$source.template" "$source"
fi
```

## Multi-Environment Support

```bash
# Environment-specific files
config.local.json    # .gitignore
config.dev.json      # git managed
config.prod.json     # git managed

# Environment selection in init
<app>_init() {
    local env="${1:-local}"
    local source="$HOME/dotfiles/bash/<category>/config.$env.json"
    # ...
}
```

## Safety Guidelines

### File Permissions
- Add sensitive files to .gitignore
- Consider git-crypt for secrets
- Verify file permissions after linking

### Category Selection
- Application-specific management: `bash/app/<app>/`
- Simple config files: `bash/config/`
- Environment variables: `bash/env/`

### Multi-File Management
- Handle multiple config files in single `<app>_init` function
- Example: claude_init manages both settings.json and statusline-command.sh

### Function Naming Convention
- Initialization: `<app>_init`
- Editing: `<app>_edit_<config>`
- Help: `<app>help`
