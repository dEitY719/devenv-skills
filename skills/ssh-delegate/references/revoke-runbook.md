# Revoke runbook

`revoke <alias>` tears down a single delegation. It is idempotent and safe to
re-run.

## What `revoke` does

1. Reads the alias's `identity_file` and derives the `.pub` key text
   (`type base64`, comment ignored).
2. SSHes to the alias (BatchMode) and removes any matching line from the
   remote `~/.ssh/authorized_keys` via a temp-file rewrite.
3. Sets `revoked: true` on the manifest entry (the row is kept for audit
   history — it is never deleted).
4. Regenerates the config drop-in, which drops the now-revoked `Host` block
   so the alias stops resolving.
5. Appends a `revoke` event to the audit log.

## If the remote is unreachable

The remote-key removal is best-effort. If the host is down or the key already
gone, `revoke` prints a warning and **still** marks the entry revoked locally
so the alias is removed from your config. Re-run `revoke` once the host is
reachable to complete the remote cleanup, or remove the line by hand:

```
ssh <alias-or-host> "vi ~/.ssh/authorized_keys"   # delete the matching line
```

## Verifying a revoke

```
/devenv:ssh-delegate list           # entry shows state=revoked
/devenv:ssh-delegate test <alias>   # should now fail (no Host block)
grep -c <alias> ~/.ssh/config.d/devx-delegations   # 0
```

## Re-enabling later

There is no `unrevoke`. Re-add the delegation fresh:

```
/devenv:ssh-delegate add <user>@<host> <alias>
```

This installs a new key and resets `revoked: false`, `installed_at`, and the
pinned fingerprint.
