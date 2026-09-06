# devenv:ssh-delegate — Help

Standardize one-shot `ssh-copy-id` key delegation into a manifest-based,
idempotent skill. The manifest (`~/.ssh/delegations.yml`, mode 0600) is the
single source of truth for *which key is installed on which host as which
account*, when it was last verified, and the host fingerprint pinned at first
install.

## Usage

```
/devenv:ssh-delegate sync                       # manifest ↔ reality 일치
/devenv:ssh-delegate add <user>@<host> [alias]  # 1 항목 추가 + install + verify
/devenv:ssh-delegate list [--json]              # 검증 상태 표 출력
/devenv:ssh-delegate test [<alias>|--all]       # BatchMode ssh 검증
/devenv:ssh-delegate revoke <alias>             # 원격 authorized_keys 에서 키 제거
/devenv:ssh-delegate doctor                     # 환경 + manifest health check
-h | --help | help                            # 이 도움말
```

The underlying script is `lib/ssh_delegate.sh` — callable directly:

```
lib/ssh_delegate.sh add bwyoon@10.0.0.1 gpu1-bwyoon
ssh gpu1-bwyoon            # passwordless after one password prompt
```

`add` notes:

- **Interactive only.** `ssh-copy-id` prompts for the remote password once, so
  `add` needs a real TTY. In a non-interactive shell (a Claude `!` session, CI)
  it fails fast with the exact command to run in a terminal instead of dying as
  a misleading `Permission denied`. To supply the password without a TTY, set
  `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force`.
- **Adopts an existing IdentityFile.** If a hand-written `Host <alias>` block
  already pins a different key, `add` detects it via `ssh -G` and installs
  *that* key (with a warning) so the installed key matches the one ssh offers.

## Flags

| Flag | Applies to | Default | Description |
|---|---|---|---|
| `--dry-run` | `add` | off | Print the planned actions (manifest upsert, `ssh-copy-id` command, config regen, verify) without touching the remote. |
| `--key-only` | `add` | off | Install the key but skip ssh-config regeneration — for a host with a working hand-written alias you don't want rewritten. |
| `--json` | `list` | off | Emit JSON instead of the table (`references/output-format.md`). |
| `--all` | `test` | off | Verify every active alias instead of one. |

## Sub-commands

| Command | What it does |
|---|---|
| `sync` | Regenerates the ssh config drop-in, pins first-seen fingerprints, verifies every active alias. Aborts on a fingerprint MISMATCH. |
| `add <user>@<host> [alias]` | Upserts a manifest entry, runs `ssh-copy-id`, pins the fingerprint, regenerates config, verifies. Flags: see the table above. |
| `list [--json]` | Prints the entry table (alias / user / host / last-verified / state) or JSON — shapes in `references/output-format.md`. |
| `test [<alias>\|--all]` | `ssh -o BatchMode=yes <alias> true` — no password fallback. |
| `revoke <alias>` | Removes the key line from the remote `authorized_keys`, sets `revoked: true`, regenerates config. |
| `doctor` | Checks identity file, manifest perms, ssh/yq presence, audit-log writability, expired entries. |

## Safety model

`references/safety-model.md` is the SSOT for the 3-layer model (identity
pinning, host-fingerprint pinning, allowlist + audit); `references/revoke-runbook.md`
covers teardown. The audit log it refers to is
`~/.local/state/devx/ssh-delegations.log` — JSONL, append-only, flock-serialized.

## Environment overrides

| Var | Default |
|---|---|
| `DEVX_SSH_MANIFEST` | `~/.ssh/delegations.yml` |
| `DEVX_SSH_AUDIT_LOG` | `${XDG_STATE_HOME:-~/.local/state}/devx/ssh-delegations.log` |
| `DEVX_SSH_CONFIG` | `~/.ssh/config` |
| `DEVX_SSH_CONFIG_DROPIN` | `~/.ssh/config.d/devx-delegations` |
| `DEVX_SSH_BIN` / `DEVX_SSH_COPY_ID_BIN` / `DEVX_SSH_KEYSCAN_BIN` / `DEVX_SSH_KEYGEN_BIN` | `ssh` / `ssh-copy-id` / `ssh-keyscan` / `ssh-keygen` |
| `DEVX_SSH_CONNECT_TIMEOUT` | `5` |
