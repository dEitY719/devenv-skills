# devenv:runner-setup — Workflow migration

`lib/patch_workflows.sh` rewrites every `*.yml` / `*.yaml` directly in
`.github/workflows/`. Without `--apply` it prints a `diff -u` per file and
writes nothing; with `--apply` it rewrites in place. The rewrite is
idempotent — running it again over its own output changes nothing.

## Rules

| # | Env | From | To |
|---|-----|------|----|
| 1 | both | `runs-on: ubuntu-latest` (bare or quoted) | `runs-on: [self-hosted, Linux, X64]` |
| 2 | internal | a step `uses: jdx/mise-action@<any>` (+ its `with:` block) | a `run:` step that installs mise and runs `mise install` |
| 3 | internal | a job running on self-hosted without `UV_NATIVE_TLS` | job `env:` gains `UV_NATIVE_TLS: "true"` (an `env:` block is created after `runs-on` when absent) |

Rule 2's replacement step keeps the step's other keys (`name:`, `id:`, `if:`):

```yaml
      - name: Setup mise
        run: |
          curl -fsSL https://mise.run | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          echo "$HOME/.local/share/mise/shims" >> "$GITHUB_PATH"
          "$HOME/.local/bin/mise" install
```

`mise install` reads the repo's `mise.toml`, so uv comes from there. The
shims on `GITHUB_PATH` make the tools visible to every later step.

Rule 3 exists because the internal CA chain is in the system store, which uv
only consults with `UV_NATIVE_TLS=true`.

## Left untouched (review the diff)

The patcher is line-oriented, not a YAML parser. It does not change:

- `runs-on` values other than `ubuntu-latest` — `ubuntu-22.04`,
  `${{ matrix.os }}`, `windows-latest`, and so on.
- a flow-style job env (`env: {A: b}`) — rule 3 is skipped for that job.
- a `with:` key written *before* `uses: jdx/mise-action` in the same step.
- mise-action inputs such as `version:` or `install_args:`; the manual step
  installs the latest mise and all tools from `mise.toml`.

When the diff shows one of these, edit that line by hand after `--apply`.
