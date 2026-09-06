# Output format

Two different things print here, and conflating them is the trap:

1. **The script's own output** — `lib/ux.sh` markers, shown per sub-command
   below.
2. **The skill's closing verdict line** — written by the *model* in Step 3
   after relaying that output. No sub-command prints it; it is the skill's
   report contract, not the script's.

## 1. The `lib/ux.sh` markers

`ux_header` frames a section as `== <text> ==`. `[OK]` and `[..]` go to
stdout; `[WARN]`, `[FAIL]` and `[ALERT]` go to **stderr**.

| Marker | Meaning |
|---|---|
| `[OK]` | the step succeeded |
| `[..]` | progress, not a verdict |
| `[WARN]` | the command continued, but something needs a human eye |
| `[FAIL]` | this command did not do what was asked |
| `[ALERT]` | a safety invariant broke — see `safety-model.md` |

## 2. The closing verdict line

One line, after the relayed output:

```
[OK]   devenv:ssh-delegate cmd=<sub-command> <field>=<value> ...
[FAIL] devenv:ssh-delegate cmd=<sub-command> reason=<one-line>
```

The fields differ per sub-command, because most of them have no single alias
and no verification state:

| `cmd=` | Fields on `[OK]` |
|---|---|
| `sync` | `verified=<n>/<n>` |
| `add` | `alias=<alias> state=active verified=yes` (dry-run: `state=dry-run`, no `verified` field) |
| `list` | `entries=<n> revoked=<n>` |
| `test` | `checked=<n> failed=<n>` |
| `revoke` | `alias=<alias> state=revoked remote_key=<removed\|unreachable>` |
| `doctor` | `checks=<n> warn=<n>` |

`add`'s verification is the whole point of the sub-command — a passwordless
`ssh <alias>` check that failed is a `[FAIL]`, never an `[OK]` with
`verified=no`: `[FAIL] devenv:ssh-delegate cmd=add alias=<alias>
reason=verify-failed`. `--dry-run` runs no verification at all, so it never
carries a `verified` field either way — see the `add` section below.

**`list --json` never gets a closing verdict line** (`SKILL.md` Step 3): its
stdout is a machine-readable contract, and appending text after the JSON
array would break a caller parsing it.

**`[ALERT]` is terminal.** When `sync` reports a fingerprint MISMATCH, report
that ALERT and stop. Do not write a closing verdict line for it, do not
restate it as `[FAIL]`, and do not continue the run — re-trust is a human
decision (`safety-model.md`).

## `list`

`LAST_VERIFIED` is `-` when the entry has never verified; `STATE` is `active`
or `revoked`.

```
== delegations (/home/you/.ssh/delegations.yml) ==
ALIAS                USER         HOST               LAST_VERIFIED        STATE
gpu1-bwyoon          bwyoon       10.0.0.1           2026-05-30T12:04:09Z active
gpu1-ssai            ssai         10.0.0.1           -                    revoked
```

## `list --json`

Five keys per entry, in this order; `revoked` is a JSON boolean, the rest are
strings. The column headers above are the display names of these fields:
`LAST_VERIFIED` is `last_verified_at`, `STATE` is `revoked` rendered as
`active` / `revoked`. The manifest itself carries more fields
(`manifest-schema.md`); `list --json` deliberately projects only these five.

```json
[{"alias":"gpu1-bwyoon","user":"bwyoon","host":"10.0.0.1","last_verified_at":"2026-05-30T12:04:09Z","revoked":false}]
```

## `add`

```
== add: gpu1-bwyoon -> bwyoon@10.0.0.1 ==
[..] installing key on bwyoon@10.0.0.1:22 (password prompt once)
[OK] ssh gpu1-bwyoon now works passwordless
```
```
[OK] devenv:ssh-delegate cmd=add alias=gpu1-bwyoon state=active verified=yes
```

The key install can succeed while the passwordless check still fails (a
stale `authorized_keys` permission, a second `IdentityFile` taking priority);
that is a `[FAIL]`, not an `[OK]` with `verified=no`:

```
[FAIL] devenv:ssh-delegate cmd=add alias=gpu1-bwyoon reason=verify-failed
```

`--dry-run` touches neither the remote nor the manifest:

```
== add (dry-run): gpu1-bwyoon -> bwyoon@10.0.0.1 ==
[..] manifest upsert: alias=gpu1-bwyoon user=bwyoon host=10.0.0.1 identity_file=/home/you/.ssh/id_ed25519
[..] would run: ssh-copy-id -i "/home/you/.ssh/id_ed25519.pub" -p 22 bwyoon@10.0.0.1
[..] would regenerate /home/you/.ssh/config.d/devx-delegations and verify 'gpu1-bwyoon'
```
```
[OK] devenv:ssh-delegate cmd=add alias=gpu1-bwyoon state=dry-run
```

With no TTY, `add` refuses and prints the command to run instead — relay those
`[..]` lines verbatim rather than summarising them.

## `test`

One line per alias, single or `--all`:

```
[OK] gpu1-bwyoon reachable
[FAIL] gpu1-ssai unreachable
```

## `revoke`

```
[..] removing key from remote authorized_keys for 'gpu1-bwyoon'
[OK] revoked 'gpu1-bwyoon' (remote key removed, manifest revoked:true)
```

If the host is unreachable, the script says so instead of claiming removal
(`revoke-runbook.md` § "If the remote is unreachable"):

```
[..] removing key from remote authorized_keys for 'gpu1-bwyoon'
[WARN] could not reach remote — marking revoked locally anyway
[OK] revoked 'gpu1-bwyoon' (manifest revoked:true, remote_key=unreachable)
```

## `sync`

```
== sync (/home/you/.ssh/delegations.yml) ==
[..] gpu1-bwyoon: pinned fingerprint
[OK] gpu1-bwyoon verified
[OK] ssh config drop-in regenerated
```

The one output that must never be papered over:

```
[ALERT] gpu1-bwyoon: host fingerprint changed — sync ABORTED (no auto re-trust)
```

This is the general `[ALERT]` rule above, applied here: do not re-run `sync`,
do not `add` over it, and do not remove the pin to make it pass.

## `doctor`

```
== doctor ==
[OK] manifest perms OK (/home/you/.ssh/delegations.yml)
[OK] default identity present (/home/you/.ssh/id_ed25519)
[OK] ssh present
[..] yq absent — using built-in awk parser (OK)
[OK] audit log writable (/home/you/.local/state/devx/ssh-delegations.log)
```
