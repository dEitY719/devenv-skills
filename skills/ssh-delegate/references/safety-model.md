# Safety model (3-layer)

| Layer | Mechanism | Failure mode |
|-------|-----------|--------------|
| **L1 Identity** | Only the manifest's `identity_file` is ever offered (`IdentitiesOnly yes` in the generated config). | Key absent → `doctor` fails fast. |
| **L2 Host trust** | First install uses `StrictHostKeyChecking=accept-new` and pins the SHA256 fingerprint. Every later `sync` re-checks it; a mismatch is an audit ALERT and `sync` aborts. | Never auto-re-trusts a changed host key. |
| **L3 Allowlist + audit** | AI ssh always goes through a manifest alias (config drop-in). Every event (`add`, `install-ok/fail`, `verify-ok/fail`, `revoke`, `fingerprint-mismatch`, `sync`) is appended as JSONL to the audit log under an `flock`. | Access to a host not in the manifest has no alias and is not facilitated. |

## Why fingerprint pinning matters

`accept-new` trusts a host the *first* time only. Pinning the fingerprint in
the manifest lets `sync` detect a later key change (re-provisioned box, MITM,
IP reuse) and stop instead of silently trusting it — the difference between
TOFU (trust on first use) and blind trust on every use.

## Audit record shape

```json
{"ts":"2026-05-30T12:04:05Z","event":"add","alias":"gpu1-bwyoon","actor":"deity","detail":"bwyoon@12.81.221.129"}
```

One JSON object per line (JSONL), append-only. `flock` serializes concurrent
writers; the log is never rewritten in place, so it doubles as a tamper-
evident history.

## What this skill deliberately does NOT do (non-goals)

- Generate an AI-only sub-key automatically.
- Encrypt the manifest with sops/age (schema stays compatible for a later
  follow-up).
- Merge multiple manifests.
