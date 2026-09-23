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
          curl -fsSL "${MISE_INSTALL_URL:-https://mise.run}" | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          echo "$HOME/.local/share/mise/shims" >> "$GITHUB_PATH"
          "$HOME/.local/bin/mise" install
```

`mise install` reads the repo's `mise.toml`, so uv comes from there. On GHES
the step reaches `mise.run` and the tool downloads through the container's
proxy and CA chain (`references/internal.md`) — the same egress
`jdx/mise-action` itself needs; what GHES lacks is the marketplace *action*,
not outbound HTTPS. A site without that egress sets `MISE_INSTALL_URL` (runner env, or a
workflow/job `env:`) to an internal mirror of the install script; the
tool downloads then follow mise's own mirror settings in `mise.toml`. The
shims on `GITHUB_PATH` make the tools visible to every later step.

Rule 3 exists because the internal CA chain is in the system store, which uv
only consults with `UV_NATIVE_TLS=true`.

## Refused or left untouched

The patcher is line-oriented, not a YAML parser. A shape it will not rewrite is
left as is and reported as `warn=<file>:<line> <reason>` before the summary
line, and the run exits 3 (the other changes are still made, or with `--apply`
written):

- a Linux-looking `runs-on` other than `ubuntu-latest` — `ubuntu-22.04`,
  `${{ matrix.os }}`, a list (`[ubuntu-latest]`) or block list. Plain other
  OS labels (`windows-latest`, `macos-14`) are skipped silently.
- a `with:` key written *before* `uses: jdx/mise-action` in the same step —
  the whole step keeps the action.
- a job `env:` that is neither a block nor a one-line flow mapping (for
  example `env: ${{ fromJSON(...) }}`) — rule 3 is skipped for that job.

Handled rather than refused: a one-line flow env (`env: {A: b}`) becomes
`env: {A: b, UV_NATIVE_TLS: "true"}`, and an existing `env:` block gains the
key at its own child indent, whatever the file's indent width.

Not changed and not reported: mise-action inputs such as `version:` or
`install_args:` (the manual step installs the latest mise and all tools from
`mise.toml`), and anything stranger than the above (multi-line flow mappings,
anchors). When a warn line or the diff shows one of these, edit it by hand.
