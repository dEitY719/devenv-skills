---
name: makefile-gen
description: >-
  Detect a project's stack and generate a Makefile with help/build/run/clear.
  Use for /devenv:makefile-gen, /devenv-makefile-gen, "이 프로젝트에 Makefile
  만들어줘", "generate a Makefile for this project". Dry-run unless --apply.
allowed-tools: Bash, Read, Write
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "Deterministic detect + render scripts; the model only routes flags and reports"
    claude: prefer
    non_claude: advisory-only
---

# devenv:makefile-gen — detect the stack, generate a Makefile

Scans a project and writes a `Makefile` shaped for it. The required targets
`help` (the default goal), `build`, `run`, `clear` (+ `clean` alias) always
exist and mean the same thing in every project; `setup`, `serve`, `stop`,
`status`, `logs`, `test`, `test-e2e`, `test-all`, `lint`, `fmt`, `gen-*`
appear only when a tool for them is detected. Every recipe **delegates** to an
existing command SSOT — `mise run <task>` > `package.json` script > `run-*.sh`
/ `scripts/*.sh` > direct command — and never copies its logic. `--dry-run`
is the default and writes nothing. Full flag table: `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No detection, no file mutation.**

## Step 1: Parse Args + Detect

Positional `[path]` defaults to `.`. Flags: `--apply`, `--force`,
`--port N`, `--lang ko|en`. Reject any other flag with the usage line.

`sh <skill-dir>/lib/detect.sh <path>` prints `key=value` facts (read-only).
`status=no-path` (exit 1) → stop with `[FAIL] devenv:makefile-gen not a
directory: <path>`. `status=no-stack` is not an error: the required targets
become no-op placeholders. Key meanings and the signal matrix:
`references/detection.md`.

## Step 2: Map Facts to Targets

`sh <skill-dir>/lib/render.sh <path> [--port N] [--lang ko|en]` prints the
Makefile; the same call with `--report` prints one `target=<t> source=<file>`
line per generated target, one `skip=<t> reason=<why>` per omitted optional
target, and any `warn=` (e.g. lockfile conflict). The mapping rules — which
source wins per target, when `run` depends on `build`, when `serve` / `stop`
/ `status` / `logs` exist — are in `references/target-catalog.md`; the
skeleton conventions (GNU Make 3.81, `##` help, `.PHONY`) in
`references/template.md`. Do not hand-edit the rendered text; if a mapping
is wrong, say so in the report instead of patching it silently.

Help language: `--lang` wins, else `lang=` from detect (README Hangul → ko).

## Step 3: Dry-Run Report (default)

Print, in order, then stop without writing anything:

1. **Detection table** — signal | value | evidence file, from Step 1.
2. **Generated Makefile** — full text. If `makefile=present`, show
   `diff -u <path>/Makefile <(render)` instead, and say that `--apply`
   alone will refuse (`--apply --force` replaces it, keeping `Makefile.bak`).
3. **Target sources** — the `target=` lines as a table.
4. **Skipped targets** — the `skip=` lines with reasons, plus every `warn=`.
   For `status=no-stack`, state "no stack detected".

End with `Plan ready: <path> (targets=<n>, skipped=<m>)` and
`Next: review, then re-run with --apply`.

## Step 4: Apply (only if `--apply`)

Stop at the first failure with `[FAIL] devenv:makefile-gen <reason>` + exit 1:

1. `makefile=present` without `--force` → refuse; write nothing. The skill
   never merges (`references/constraints.md`): it copies the region below
   the custom sentinel over, and each `warn=` names a target that has none.
2. Render into a **temp file** — a redirect over `<path>/Makefile` truncates
   that region away — and `sh <skill-dir>/lib/render.sh --check <tmp>`; a
   failure means the renderer broke its own contract: report it, write nothing.
3. With `--force` and an existing Makefile, `cp Makefile Makefile.bak`.
4. Copy the temp file to `<path>/Makefile`.
5. Verify: `sh <skill-dir>/lib/render.sh --verify <path>` runs `make` (help must list every
   `.PHONY` target) and `make -n <t>` for each. It never runs `run`, `stop`,
   `build` for real. On failure, restore `Makefile.bak` (or delete the new
   Makefile if none existed) and report the failing targets.

## Step 5: Report

```
[OK] devenv:makefile-gen path=<path> targets=<n> skipped=<m> lang=<ko|en> [backup=Makefile.bak]
Next: make
```

Re-print every `warn=` line under it. Safety contract and out-of-scope
cases: `references/constraints.md`. A full worked example (brokerdesk,
PR #76): `references/example-brokerdesk.md`.
