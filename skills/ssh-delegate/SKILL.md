---
name: ssh-delegate
description: >-
  Manage AI SSH key delegation through a manifest instead of ad-hoc
  ssh-copy-id. Use for /devenv:ssh-delegate, /devenv-ssh-delegate, "이 호스트에
  키 위임 표준화", "ssh-copy-id 한 거 매니페스트로 관리", "어떤 서버에 접근
  가능한지", "delegate ssh access", "revoke ssh key from host".
allowed-tools: Bash, Read, Grep
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

- `add` runs `ssh-copy-id` interactively — the user enters the remote password
  **once**. Tell them to expect that single prompt; do not try to supply it. In
  a non-interactive shell (a Claude `!` session) `add` fails fast with the exact
  command to run in a real terminal — relay it verbatim (issue #1132).
- If the alias already has a hand-written `Host` block with a different
  `IdentityFile`, `add` adopts that key (via `ssh -G`) so the installed key is
  the one ssh actually offers — surface the adoption warning it prints.
- `add --dry-run` prints the planned actions (manifest upsert, `ssh-copy-id`
  command, config regen, verify) without touching the remote — use it first
  when the user is unsure.
- `add --key-only` installs the key without regenerating the ssh config drop-in
  — for a host that already has a working hand-written alias (issue #1132).
- Never bypass a fingerprint MISMATCH from `sync`. Surface the ALERT and stop;
  re-trust is a human decision (see `references/safety-model.md`).

## Step 3: Report

Relay the script's output. After `add`, confirm `ssh <alias>` now works
passwordless. After `revoke`, confirm the entry shows `state=revoked` and the
remote key was removed (or warn if the host was unreachable —
`references/revoke-runbook.md`).

## Idempotency & safety

- Re-running `add` for an existing alias is a no-op beyond refreshing
  `last_verified_at` — never a duplicate entry.
- The manifest and config drop-in are always written mode 0600.
- Every event is appended to the JSONL audit log (`flock`-serialized).

## References

- `references/help.md` — verbatim help / usage.
- `references/manifest-schema.md` — manifest fields + parser-engine note.
- `references/safety-model.md` — the 3-layer trust model.
- `references/revoke-runbook.md` — revoke + unreachable-host recovery.
