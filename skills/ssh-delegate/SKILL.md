---
name: ssh-delegate
description: >-
  Manage AI SSH key delegation through a manifest instead of ad-hoc
  ssh-copy-id. Use for /devenv:ssh-delegate, /devenv-ssh-delegate, "이 호스트에
  키 위임 표준화", "ssh-copy-id 한 거 매니페스트로 관리", "어떤 서버에 접근
  가능한지", "delegate ssh access", "revoke ssh key from host".
allowed-tools: Bash, Read, Grep
license: MIT
compatibility:
  # ssh, ssh-copy-id, ssh-keyscan, ssh-keygen all reach the remote host.
  network: required
metadata:
  model_recommendation:
    tier: haiku
    reason: "deterministic manifest CRUD + ssh wrapper; bounded output, low reasoning, all logic in lib/"
    claude: prefer
    non_claude: advisory-only
---

# devenv:ssh-delegate — Manifest-based SSH key delegation + audit

Standardizes one-shot `ssh-copy-id` delegation into an idempotent, audited
skill. All real work lives in `lib/ssh_delegate.sh` (+ sibling `lib/*.sh`);
this file routes the user's sub-command to it.

The manifest **`~/.ssh/delegations.yml`** (mode **0600**) is the single source
of truth for which key is installed on which host as which account, when it was
last verified, and the host fingerprint pinned at first install. 3-layer safety:
identity pinning, host-fingerprint pinning (no auto re-trust), and a
`flock`-serialized JSONL audit log (`references/safety-model.md`). POSIX shell
with a plain-printf parser so it runs standalone; `yq` is optional and used by
`doctor` only (`references/manifest-schema.md`).

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No side effects.

## Step 1: Parse the sub-command

First positional arg selects the action:

| Sub-command | Args | Effect |
|---|---|---|
| `sync` | — | Reconcile manifest ↔ reality (regen config, pin/verify). |
| `add` | `<user>@<host> [alias] [--dry-run] [--key-only]` | Add + install + verify one entry. |
| `list` | `[--json]` | Print the delegation table / JSON. |
| `test` | `[<alias>\|--all]` | BatchMode reachability check. |
| `revoke` | `<alias>` | Remove remote key + mark `revoked: true`. |
| `doctor` | — | Environment + manifest health check. |

Default (no sub-command) → print usage. Unknown sub-command → usage + exit 2.

## Step 2: Run the script

Invoke the bundled script with the parsed args (resolve `<skill-dir>` to this
skill's directory):

```bash
<skill-dir>/lib/ssh_delegate.sh <sub-command> [args...]
```

- `add` needs a TTY for its one `ssh-copy-id` password prompt. Without one it
  fails fast printing the exact command to run in a real terminal — relay that
  verbatim; never try to supply the password (dEitY719/dotfiles#1132).
- If the alias already pins a different `IdentityFile`, `add` adopts that key
  via `ssh -G` — surface the adoption warning it prints.
- Never bypass a fingerprint MISMATCH from `sync`. Surface the ALERT and stop;
  re-trust is a human decision (`references/safety-model.md`).
- Flags (`--dry-run`, `--key-only`, `--json`, `--all`): `references/help.md`.

## Step 3: Report

Relay the script's output — `lib/ux.sh` prints `[OK]` `[..]` `[WARN]` `[FAIL]`
`[ALERT]` — then add one closing verdict line of your own. The script does not
print this line; its per-sub-command fields are tabled in
`references/output-format.md`.

```
[OK]   devenv:ssh-delegate cmd=<sub-command> <field>=<value> ...
[FAIL] devenv:ssh-delegate cmd=<sub-command> reason=<one-line>
```

A fingerprint MISMATCH `[ALERT]` from `sync` is terminal: report the ALERT and
stop the run. Write no verdict line for it, and never restate it as `[FAIL]`.
After `add` confirm `ssh <alias>` works passwordless; after `revoke` that the
entry reads `state=revoked` (or warn on an unreachable host —
`references/revoke-runbook.md`).

## References

- `references/help.md` — verbatim help / usage, flags, env overrides.
- `references/output-format.md` — output + verdict examples per sub-command.
- `references/manifest-schema.md` — manifest fields + parser-engine note.
- `references/safety-model.md` — the 3-layer trust model.
- `references/revoke-runbook.md` — revoke + unreachable-host recovery.
