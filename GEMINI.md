# devenv — skill index

Three skills for one-time machine and toolchain setup. Each lives in this
extension's `skills/` directory. They are task-triggered: load the one that
matches the job by reading its `SKILL.md`, then follow it. Do not load all three.

| Skill | Read | Use when |
|-------|------|----------|
| `mise-migrate` | `@./skills/mise-migrate/SKILL.md` | Converting a legacy Python venv / pip / setuptools project into the canonical `mise.toml` + uv layout. Python-venv projects only; refuses anything else. |
| `symlink-manager` | `@./skills/symlink-manager/SKILL.md` | Moving a config file into the dotfiles repo and linking it back from its original path, with management functions and a commit. |
| `ssh-delegate` | `@./skills/ssh-delegate/SKILL.md` | Standardising SSH key delegation through `~/.ssh/delegations.yml` instead of ad-hoc `ssh-copy-id` — add, list, test, sync, revoke, doctor. |

Each skill's `references/` directory holds the detail it loads on demand;
`SKILL.md` says which file to read and when. Do not read `references/` files up
front.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command`
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
[`dEitY719/harness-skills`](https://github.com/dEitY719/harness-skills) at
[`references/gemini-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md)
— this repo carries no copy. Read it there when a skill names a tool you do not
recognise. On Antigravity read
[`references/antigravity-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/antigravity-tools.md)
instead — `agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- `ssh-delegate` is a thin router over `skills/ssh-delegate/lib/ssh_delegate.sh`
  (POSIX sh). It needs `run_shell_command` and, for `add`, a real interactive
  terminal: `ssh-copy-id` prompts once for the remote password and the prompt
  cannot be answered from a non-interactive session. When there is no TTY the
  script fails fast and prints the exact command to run by hand — relay it
  verbatim rather than trying to supply the password.
- `mise-migrate` shells out to `uv sync` on `--apply`. Without `uv` on `PATH`
  the apply step stops at that point and reports the partial state; there is no
  automatic rollback.
- `symlink-manager` assumes a dotfiles repo laid out as
  `bash/{claude,app,config,env}/` and commits with `git`. Outside that layout,
  read `references/advanced-patterns.md` before adapting the paths.

## Safety rules

- `mise-migrate` is dry-run by default. It prints the plan and writes nothing
  unless the user passed `--apply`. Never infer `--apply` from context.
- `symlink-manager` moves the original file, so it must back it up to
  `.backup`, create the link, and verify it. Any phase failure aborts the run
  and reports `[FAIL]`; a Phase 1 failure restores from the backup. Announce the
  plan before the first change.
- `ssh-delegate` is the most destructive of the three: it installs and removes
  public keys on remote hosts. Three rules are absolute — the manifest and ssh
  config drop-in are written mode 0600, a host-fingerprint MISMATCH reported by
  `sync` is an ALERT that stops the run (re-trusting a changed host key is a
  human decision), and every event is appended to the `flock`-serialized JSONL
  audit log. Use `add --dry-run` first when the user is unsure. `revoke` marks
  the manifest entry `revoked: true` and keeps the row for audit history; it
  never deletes it.
