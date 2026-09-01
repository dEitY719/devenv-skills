# Function Templates — management function code templates

> 본 템플릿은 CLAUDE.md "POSIX compatibility" + "All output must use ux_lib"
> 규칙을 따르도록 작성됨. `[[ ]]` 대신 POSIX `[ ]`, raw `echo` 대신
> `ux_info` / `ux_success` / `ux_warning` / `ux_error` 사용. 사용자는 그대로
> 복사해 사용.

## Symbolic Link Initialization Function

Add to `bash/app/<app>.bash`:

```bash
<app>_init() {
    local source="$HOME/dotfiles/bash/<category>/<filename>"
    local target="<target_file>"

    ux_info "Initializing <app> configuration..."

    # Create directory if needed
    if [ ! -d "$(dirname "$target")" ]; then
        ux_info "Creating $(dirname "$target") directory..."
        mkdir -p "$(dirname "$target")"
    fi

    # Handle symbolic link
    if [ -L "$target" ]; then
        ux_info "<filename> symbolic link already exists"
    elif [ -f "$target" ]; then
        ux_warning "<filename> exists as regular file"
        ux_info "Backing up to <filename>.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        ux_success "Created symbolic link for <filename>"
    else
        ln -s "$source" "$target"
        ux_success "Created symbolic link for <filename>"
    fi

    ux_success "<app> configuration initialization complete!"
    ux_info "Symbolic link:"
    ls -la "$target"
}
```

## Configuration Editing Function (optional)

```bash
<app>_edit_<config>() {
    local config_file="$HOME/dotfiles/bash/<category>/<filename>"

    if [ ! -f "$config_file" ]; then
        ux_error "Config file not found: $config_file"
        return 1
    fi

    ux_info "Editing <app> configuration..."
    ux_info "File: $config_file"

    ${EDITOR:-vim} "$config_file"

    ux_success "Configuration file edited"
    ux_info "Changes will take effect immediately (symlinked)"
}
```

## Help Documentation Block

Add to `<app>help` function:

```bash
ux_section "Configuration Management"
ux_bullet "<app>_init         : <app> 설정 파일 symbolic link 초기화"
ux_bullet_sub "(dotfiles/bash/<category>/<filename> ↔ <target_file>)"
ux_bullet "<app>_edit_<config> : <filename> 파일 편집"
```

## 의존성

- `ux_lib`은 인터랙티브 셸에서 자동 로드됨 (`shell-common/tools/ux_lib/ux_lib.sh`).
- `<app>_init` / `<app>_edit_*` 함수가 비인터랙티브 호출(예: 스크립트)에서도
  실행될 수 있다면 함수 진입부에 `command -v ux_info >/dev/null 2>&1 ||
  source "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/ux_lib/ux_lib.sh"` 가드를 권장.
