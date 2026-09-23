# devenv:runner-setup — Help

## Usage

```
/devenv:runner-setup [--env internal|public] [--repo owner/name] [--label name] [--host alias] [--dry-run|--apply]
/devenv-runner-setup                                   # GHES runner for this repo, workflow diff only
/devenv-runner-setup --apply                           # ... and rewrite .github/workflows
/devenv-runner-setup --env public --host buildbox      # GitHub.com repo, runner on host alias buildbox
/devenv:runner-setup -h | --help | help                # show this help
```

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--env` | `internal` | `internal` (GitHub Enterprise Server) or `public` (GitHub.com). Picks the API host, image, proxy and workflow rules. |
| `--repo` | from `git remote get-url origin` | Target repo, `owner/name`. |
| `--label` | `<repo-name>-build` | Custom runner label, added on top of `self-hosted,Linux,X64`. |
| `--host` | internal: `ssai-ops` · public: **required** | SSH host alias that runs Docker. Must work with `ssh -o BatchMode=yes` (see `/devenv:ssh-delegate`). |
| `--dry-run` | **on** | Default. Runner registration still runs; workflow changes are printed as a diff only. |
| `--apply` | off | Also rewrite `.github/workflows/*.yml` in place. |
| `-h` / `--help` / `help` | — | Print this help and stop. |

## What always runs vs. what `--apply` gates

| Step | Runs | Effect |
|------|------|--------|
| 1 plan | always | Resolves repo/label/host/image; prints `key=value` facts. No side effects. |
| 2 register | always | Duplicate check, registration token, `docker run` on `--host`, online + label verification. |
| 3 workflows | always, writes only with `--apply` | `runs-on` / mise / `UV_NATIVE_TLS` rewrite (`references/workflow-migration.md`). |

## Names it creates

- Container and runner name: `<repo-name>-runner` (restart policy `unless-stopped`).
- Runner labels: `self-hosted`, `Linux`, `X64`, `<label>`.

## Exit codes (`lib/register_runner.sh`)

| Code | Meaning |
|------|---------|
| 0 | Runner online with its label (or `--plan` printed). |
| 1 | A step failed; the `[FAIL]` line names it. |
| 2 | Usage error — bad flag, public without `--host`, repo not detectable. |
| 3 | `<repo-name>-runner` container already exists on the host. Nothing changed. |

## Environment overrides

Every site-specific value is an env var with a default, so no site value has
to be edited into the scripts:

| Variable | Default | Used by |
|----------|---------|---------|
| `RUNNER_GHES_HOST` | `github.samsungds.net` | internal: API host and runner URL |
| `RUNNER_INTERNAL_HOST` | `ssai-ops` | internal: default `--host` |
| `RUNNER_INTERNAL_IMAGE` | `skills_runner:26.09` | internal: image to run |
| `RUNNER_PROXY` | `http://12.26.204.100:8080` | internal: `http(s)_proxy` in the container |
| `RUNNER_NO_PROXY` | `localhost,127.0.0.1,<ghes host>,.<ghes parent domain>` | internal: `no_proxy` in the container |
| `RUNNER_PUBLIC_IMAGE` | `runner-setup-public:22.04` | public: image tag built on the host |
| `RUNNER_VERSION` | `2.328.0` | public image build (and any image without a runner) |
| `RUNNER_DIR` | `/actions-runner` | runner install dir inside the image |
| `RUNNER_VERIFY_TIMEOUT` | `90` | seconds to wait for `online` |

## Undo

```
ssh <host> docker rm -f <repo-name>-runner
gh api -X DELETE repos/<owner>/<name>/actions/runners/<id>   # GH_HOST=<ghes host> on internal
git checkout -- .github/workflows                            # before committing an --apply
```
