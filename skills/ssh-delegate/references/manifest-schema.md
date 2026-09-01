# Manifest schema — `~/.ssh/delegations.yml`

Mode **0600**. `alias` is the unique primary key, so the same host can carry
multiple user delegations (e.g. `bwyoon@host` + `ssai@host`).

```yaml
version: 1
defaults:
  identity_file: ~/.ssh/id_ed25519
  port: 22
  strict_host_key_checking: yes
entries:
  - alias: gpu1-bwyoon
    user: bwyoon
    host: 12.81.221.129
    note: "Internal GPU box — bwyoon account"
    expires: 2026-08-30
    installed_at: 2026-05-30T12:04:05Z
    last_verified_at: 2026-05-30T12:04:09Z
    fingerprint_sha256: SHA256:abcd...
    revoked: false
```

## Fields

| Field | Scope | Meaning |
|---|---|---|
| `identity_file` | default / per-entry | Private key; its `.pub` is what gets installed. |
| `port` | default / per-entry | SSH port. |
| `strict_host_key_checking` | default | Written into the config drop-in. |
| `alias` | entry (PK) | ssh Host alias the AI must use. |
| `user`, `host` | entry | Remote account + address. |
| `note` | entry | Free-text description. |
| `expires` | entry | `YYYY-MM-DD`; `doctor` flags past entries. |
| `installed_at` | entry | Set by `add` on a successful `ssh-copy-id`. |
| `last_verified_at` | entry | Refreshed by every successful BatchMode verify. |
| `fingerprint_sha256` | entry | Host key pinned at first install (L2). |
| `revoked` | entry | `true` hides the entry from config + verify. |

## Parser engine (deviation from the issue, documented)

The issue named **`yq`** as the manifest parser. This implementation instead
uses a **dependency-free `awk` engine** (`lib/manifest.sh`) as the
authoritative read/write path, because:

1. Standalone operation on a bare machine is an explicit acceptance
   requirement, and `yq` is frequently absent (it is not installed in this
   repo's CI image).
2. All writes are funneled through `manifest_save_tsv`, which re-emits the
   canonical YAML above — a lossless round-trip for the documented schema.

`yq`, when present, is used by `doctor` only, as an optional extra validator.
Hand-edits are safe as long as they keep the canonical 2-space indentation
shown above.
