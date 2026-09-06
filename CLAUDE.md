# devenv-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `devenv` and it bundles
three skills for one-time machine and toolchain setup — the things you do once
on a new box and then want reproducible:

| Skill | Role |
|-------|------|
| `mise-migrate` | Convert a legacy Python venv/pip project into the canonical `mise.toml` + uv structure. Dry-run unless `--apply`. |
| `symlink-manager` | Move a config file into the dotfiles repo, link it back, generate management functions, commit. |
| `ssh-delegate` | Manage SSH key delegation through `~/.ssh/delegations.yml` instead of ad-hoc `ssh-copy-id`, with fingerprint pinning and an audit log. |

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/devx-{mise-migrate,symlink-manager,ssh-delegate}`) as a snapshot
— see the first commit for the source SHA. The dotfiles copies are gone: that
tree was deleted in dotfiles Phase 4-1 (`ad0d33d5`), so this repo is now the
only home for these three skills.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/devenv.js                OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live in `harness-skills` — link, never copy

The per-harness tool mappings (`references/{codex,kimi,gemini,antigravity,
hermes,opencode}-tools.md`, dotfiles #1410 F-5) are owned solely by
[`dEitY719/harness-skills`](https://github.com/dEitY719/harness-skills). **This
repo does not own them and must not carry copies** — `GEMINI.md`,
`.opencode/INSTALL.md`, and the `.kimi-plugin` `skillInstructions` field each
link out to that repo and keep only a short inline summary. One tool rename
must stay one edit, not fifteen (NF-2). If you are about to paste one of those
files in here, stop and add a link instead. There is no `references/` directory
at this repo's root, and adding one for tool mappings is a bug.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`ssh-delegate`), never namespaced (`devenv:ssh-delegate`). CI
  rejects a `:` in the name outright. The harness supplies the `devenv:` prefix
  at invocation time.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/devenv:ssh-delegate` (or `/devenv-ssh-delegate`).
- **Progressive disclosure.** `SKILL.md` stays under 100 lines (CI enforces it)
  and names which `references/` file to read and when. All three are currently
  at 95-99 lines — there is almost no headroom, so an addition means an
  extraction. Detail lives in `references/`. Do not inline a reference file
  back into `SKILL.md`.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget. Keep new descriptions tight.
- **Honour each skill's safety contract.** All three write; none of them is a
  read-only auditor.
  - `mise-migrate` — `--dry-run` is the default and mutates nothing; only an
    explicit `--apply` writes. It rewrites `pyproject.toml` in place and runs
    `uv sync`, stops at the first failure, and does **not** roll back — it
    reports the partial state. It refuses non-Python and already-migrated
    directories rather than improvising.
  - `symlink-manager` — moves the original file out of its location, so it
    backs it up to `.backup` first and verifies the link; a Phase 1 failure
    restores from that backup. It also `git commit`s. Announce the plan before
    the first change, and confirm before replacing a file that already exists.
  - `ssh-delegate` — the most destructive: it installs and removes public keys
    on remote hosts. The three-layer contract in
    `skills/ssh-delegate/references/safety-model.md` is not optional. L1: only
    the manifest's `identity_file` is ever offered (`IdentitiesOnly yes`). L2:
    the host fingerprint is pinned at first install and re-checked on every
    `sync`; a mismatch is an audit ALERT that aborts, and re-trust is a human
    decision — never bypass it. L3: every event is appended to a
    `flock`-serialized JSONL audit log, and a host absent from the manifest has
    no alias and is not facilitated. The manifest and config drop-in are always
    mode 0600. `revoke` sets `revoked: true` and keeps the row for audit
    history; it never deletes it, and there is no `unrevoke`.
- **Harness gaps are documented, not worked around silently.** These skills are
  written in Claude Code's vocabulary. When you add a step that depends on a
  Claude-Code-only capability, record the fallback in `GEMINI.md` and
  `.opencode/INSTALL.md` here, and open a PR against `harness-skills` for the
  `references/*-tools.md` files in the same change.
- **Runtime artifact names are frozen.** `ssh-delegate` still writes
  `~/.ssh/config.d/devx-delegations`, `~/.local/state/devx/ssh-delegations.log`,
  and reads `DEVX_SSH_*` environment variables. Those are existing on-disk state
  on the maintainer's machines; the `devx` -> `devenv` rename covered invocation
  strings only. Renaming them is a separate, migration-bearing change.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo
(dEitY719/dotfiles#1410 D-9); this repo does not move in lockstep with its
siblings.

## CI

`.github/workflows/validate.yml` is a thin caller into `harness-skills`'
reusable `skill-check.yml` (dEitY719/dotfiles#1410 D-10). To change what is
checked, edit that workflow in `harness-skills` — do not re-inline the checks
here.

That workflow also runs every `tests/*.sh` in this repo. `tests/run.sh` is the
single entry point: it calls each `lib/*.sh` that ships a `--self-test`. A new
`lib/` script with a self-test gets one line there; the assertions stay in the
script, next to the code they cover.

## No emojis

Anywhere in this repo. Token efficiency.
