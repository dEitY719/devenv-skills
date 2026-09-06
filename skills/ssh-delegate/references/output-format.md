# Output format

`lib/ux.sh` owns the whole vocabulary. `[OK]` and `[..]` go to stdout; `[WARN]`,
`[FAIL]` and `[ALERT]` go to **stderr**.

| Marker | Meaning |
|---|---|
| `[OK]` | the step succeeded |
| `[..]` | progress, not a verdict |
| `[WARN]` | the command continued, but something needs a human eye |
| `[FAIL]` | this command did not do what was asked |
| `[ALERT]` | a safety invariant broke — terminal, see `safety-model.md` |

Close every run with one verdict line:

```
[OK]   devenv:ssh-delegate cmd=<sub> alias=<alias> state=<active|revoked> verified=<yes|no>
[FAIL] devenv:ssh-delegate cmd=<sub> alias=<alias> reason=<one-line>
```

An `[ALERT]` is never downgraded to `[FAIL]` so the run can continue.

## `list`

Five fixed-width columns. `LAST_VERIFIED` is `-` when the entry has never
verified; `STATE` is `active` or `revoked`.

```
== delegations (/home/you/.ssh/delegations.yml)
ALIAS                USER         HOST               LAST_VERIFIED        STATE
gpu1-bwyoon          bwyoon       10.0.0.1           2026-05-30T12:04:09Z active
gpu1-ssai            ssai         10.0.0.1           -                    revoked
```

## `list --json`

One object per entry — five keys, in this order. `revoked` is a JSON boolean,
every other value a string. The full manifest carries more fields than this
(`manifest-schema.md`); `list --json` deliberately projects only these.

```json
[{"alias":"gpu1-bwyoon","user":"bwyoon","host":"10.0.0.1","last_verified_at":"2026-05-30T12:04:09Z","revoked":false}]
```

## `test`

One line per alias checked, `--all` or single:

```
[OK] gpu1-bwyoon reachable
[FAIL] gpu1-ssai unreachable
```

## `add`

```
[..] upserting gpu1-bwyoon (bwyoon@10.0.0.1)
[..] installing key via ssh-copy-id -- expect ONE password prompt
[OK] key installed
[..] pinning host fingerprint SHA256:abcd...
[OK] devenv:ssh-delegate cmd=add alias=gpu1-bwyoon state=active verified=yes
```

`--dry-run` prints the same plan with nothing after `upserting`, and touches
neither the remote nor the manifest.

## `sync` — the fingerprint MISMATCH

The one output that must never be papered over. `sync` aborts; re-trust is a
human decision, and there is no flag that bypasses it.

```
[ALERT] gpu1-bwyoon: host fingerprint changed -- sync ABORTED (no auto re-trust)
```

Report it verbatim and stop. Do not re-run `sync`, do not `add` over it, and do
not remove the pin to make it pass.
