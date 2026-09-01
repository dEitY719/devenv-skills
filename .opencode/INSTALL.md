# Installing devenv for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["devenv-skills@git+https://github.com/dEitY719/devenv-skills.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all three skills.

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install this plugin separately for each one.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load mise-migrate
```

## Tool mapping

The authoritative OpenCode tool mapping for every `dEitY719/*-skills` repo lives
in [`dEitY719/harness-skills`](https://github.com/dEitY719/harness-skills) at
[`references/opencode-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/opencode-tools.md).
This repo carries no copy — read the mapping there when a skill names a tool you
do not recognise. Short version:

- "Read a file" -> `read`
- "Create a file" / "edit a file" -> `apply_patch`
- "Run a shell command" -> `bash`
- "Search file contents" / "find files by name" -> `grep`, `glob`
- "Create a todo" -> `todowrite`
- "Dispatch a subagent" -> `task` with `subagent_type: "general"` (or
  `"explore"` for read-only repo exploration)
- "Invoke a skill" -> OpenCode's native `skill` tool

All three devenv skills write, so their safety contracts matter here:

- `mise-migrate` is dry-run by default. Without an explicit `--apply` it prints
  the plan and must not reach `apply_patch` or a mutating `bash`.
- `symlink-manager` moves a config file out of its original location and
  commits. It backs the original up to `.backup` first, verifies the link, and
  rolls back from that backup if the move fails.
- `ssh-delegate` runs `skills/ssh-delegate/lib/ssh_delegate.sh` through `bash`.
  `add` needs a real TTY for its one `ssh-copy-id` password prompt — in a
  non-interactive session it fails fast and prints the command to run by hand.
  A host-fingerprint MISMATCH from `sync` is a hard stop; never bypass it.

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i devenv`
2. Verify the plugin line in your `opencode.json`
3. Make sure you are running a recent version of OpenCode

### Skills not found

1. Use the `skill` tool to list what was discovered
2. Check that the plugin is loading (see above)

## Getting Help

Report issues: https://github.com/dEitY719/devenv-skills/issues
