# devenv-skills

Three skills for the one-time work of setting a machine and its toolchain up —
migrate a legacy Python venv project onto mise + uv, move a config file into
dotfiles and link it back, replace ad-hoc `ssh-copy-id` with an audited key
manifest. Packaged as a single plugin named `devenv`, installable on six
coding-agent harnesses.

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `mise-migrate` | `/devenv:mise-migrate [path] [--apply]` | Converts a pyenv / `python -m venv` + pip + setuptools project into `mise.toml` (tools, env, tasks) with uv owning the venv and dependencies. Python-venv projects only; dry-run unless `--apply`. |
| `symlink-manager` | `/devenv:symlink-manager <file>` | Moves a config file into the dotfiles repo, links it back from its original path with a `.backup` of the original, generates `<app>_init` / `<app>_edit_*` helpers, updates help, and commits. |
| `ssh-delegate` | `/devenv:ssh-delegate <sync\|add\|list\|test\|revoke\|doctor>` | Manages SSH key delegation through `~/.ssh/delegations.yml` (mode 0600) instead of one-shot `ssh-copy-id` — identity pinning, host-fingerprint pinning, and a `flock`-serialized JSONL audit log. |

All three write. None of them is a read-only auditor — see
[Harness support](#harness-support) and [`CLAUDE.md`](CLAUDE.md) for each
skill's safety contract.

### Visual guides and worked examples (GitHub Pages)

- `mise-migrate` — [visual guide](https://deity719.github.io/devenv-skills/skill-guides/mise-migrate.html) · [usage example](https://deity719.github.io/devenv-skills/skill-output/mise-migrate-usage.html) (legacy venv project to mise + uv migration plan)
- `symlink-manager` — [visual guide](https://deity719.github.io/devenv-skills/skill-guides/symlink-manager.html) · [usage example](https://deity719.github.io/devenv-skills/skill-output/symlink-manager-usage.html) (config file to dotfiles symlink and commit)
- `ssh-delegate` — [visual guide](https://deity719.github.io/devenv-skills/skill-guides/ssh-delegate.html) · [usage example](https://deity719.github.io/devenv-skills/skill-output/ssh-delegate-usage.html) (ad-hoc ssh-copy-id to audited manifest)

Each page is generated from a Markdown source under
[`docs/skill-guides/`](docs/skill-guides) and [`docs/skill-output/`](docs/skill-output).

## Install

### Claude Code

```
/plugin marketplace add dEitY719/devenv-skills
/plugin install devenv@devenv-skills
```

### Codex

```
codex plugin install dEitY719/devenv-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/devenv-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/devenv-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/devenv-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

These skills are written in Claude Code's vocabulary, but none of them depends
on a Claude-Code-only tool: `mise-migrate` and `symlink-manager` need only
read/write/shell, and `ssh-delegate` is a thin router over a POSIX-sh script in
`skills/ssh-delegate/lib/`. What varies between harnesses is not the tool
vocabulary but the *environment* each one runs in. Per-harness tool names are
mapped in [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `mise-migrate` | full | full | full | full | full | full |
| `symlink-manager` | full | full | full | full | full | full |
| `ssh-delegate` | full | needs a TTY for `add` | needs a TTY for `add` | needs a TTY for `add` | needs a TTY for `add` | needs a TTY for `add` |

*needs a TTY for `add`* — `ssh-copy-id` prompts once for the remote password and
that prompt cannot be answered from a non-interactive session. `ssh_delegate.sh`
detects this and fails fast with the exact command to run in a real terminal;
every other sub-command (`sync`, `list`, `test`, `revoke`, `doctor`) works
unattended. This applies to Claude Code's non-interactive `!` sessions too.

Two environment dependencies apply everywhere: `mise-migrate --apply` runs
`uv sync`, so `uv` must be on `PATH`; `symlink-manager` assumes a dotfiles repo
laid out as `bash/{claude,app,config,env}/` and commits with `git`.

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{mise-migrate,symlink-manager,ssh-delegate}/
│   ├── SKILL.md
│   ├── references/
│   └── lib/                                   ssh-delegate only
├── .claude-plugin/{marketplace,plugin}.json   Claude Code
├── .codex-plugin/plugin.json                  Codex
├── .kimi-plugin/plugin.json                   Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
├── .opencode/plugins/devenv.js + INSTALL.md   OpenCode
├── .agents/plugins/marketplace.json           Antigravity
├── gemini-extension.json + GEMINI.md          Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout. The other
five harnesses resolve manifests at the repo root and a skills tree at
`./skills/`, so this repo keeps everything flat. See [`CLAUDE.md`](CLAUDE.md) for
the full rationale and contribution rules.

There is deliberately **no `references/` directory at this repo's root**. The
shared per-harness tool mappings are owned solely by
[`dEitY719/harness-skills`](https://github.com/dEitY719/harness-skills) (#1410
F-5 / NF-2); this repo links to them rather than carrying copies, so one tool
rename stays one edit.

The `.kimi-plugin/` manifest is pre-provisioned: Kimi CLI is not installed on the
maintainer's machines yet, and shipping the manifest now costs nothing and saves
a migration later.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) is a thin
caller. The checks themselves — manifests, skill frontmatter, progressive
disclosure, the Codex description budget, version agreement, shell scripts,
emoji — live once in
[`dEitY719/harness-skills`](https://github.com/dEitY719/harness-skills)'
reusable `skill-check.yml` workflow, which every split-out skill repo calls:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: devenv
```

To change what is checked, edit that workflow, not this repo.

## Provenance

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/devx-{mise-migrate,symlink-manager,ssh-delegate}`) as a content
snapshot — no history rewriting. The source commit SHA is recorded in this
repo's first commit message. The `devx-` prefix is dropped here because the
plugin namespace (`devenv:`) now supplies it.

One thing the rename deliberately did not touch: `ssh-delegate` still writes
`~/.ssh/config.d/devx-delegations` and `~/.local/state/devx/ssh-delegations.log`
and reads `DEVX_SSH_*` environment variables. Those are live on-disk state;
renaming them is a separate change with a migration attached.

This is Phase 1 of the dotfiles #1410 migration; `packaging-skills` was Phase 0.

## License

MIT. See [LICENSE](LICENSE).
