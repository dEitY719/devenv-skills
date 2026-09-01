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
- Backup: `<target_file>.backup`

Output: File analysis, category decision, path planning

## Phase 1: File Migration (SEQUENTIAL)

### 1. Copy to dotfiles location

```bash
cp <target_file> ~/dotfiles/bash/<category>/<filename>

# Verify copy
cat ~/dotfiles/bash/<category>/<filename>
```

### 2. Create symbolic link

```bash
# Remove original file
rm <target_file>

# Create symbolic link
ln -s ~/dotfiles/bash/<category>/<filename> <target_file>
```

### 3. Verify link

```bash
# Check symbolic link
ls -la <target_file>

# Verify content accessibility
cat <target_file>
```

## Phase 4: Version Control (SEQUENTIAL)

```bash
# Check .gitignore if needed
grep "<filename>" .gitignore

# Stage changes
git add bash/<category>/<filename>
git add bash/app/<app>.bash
git add .gitignore  # if modified

# Commit with descriptive message
git commit -m "feat: manage <filename> via dotfiles with symbolic link"
```
