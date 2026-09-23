# devenv:runner-setup — internal (GitHub Enterprise Server)

The default target. The runner container talks to a GHES instance from
inside the corporate network, so three things differ from GitHub.com:
proxy, certificate chain, and how `gh` finds the server.

## Defaults

| Item | Value | Override |
|------|-------|----------|
| API / web host | `github.samsungds.net` | `RUNNER_GHES_HOST` |
| SSH host alias | `ssai-ops` | `--host` or `RUNNER_INTERNAL_HOST` |
| Image | `skills_runner:26.09` | `RUNNER_INTERNAL_IMAGE` |
| Proxy | `http://12.26.204.100:8080` | `RUNNER_PROXY` |
| no_proxy | `localhost,127.0.0.1,github.samsungds.net,.samsungds.net` | `RUNNER_NO_PROXY` |

The image is reused, not built: it already carries the proxy settings, the CA
certificates (SECDS chain + McAfee) and `shellcheck`. The script still passes
the proxy variables explicitly, so a container is correct even if the image
defaults drift. The image is expected to hold the runner under `RUNNER_DIR`
(`/actions-runner`); the container runs `config.sh` there on first start only
and `run.sh` on every start. Because this script does not control that
image's user, the internal container is started with
`RUNNER_ALLOW_RUNASROOT=1`; the public image runs as a non-root user instead.

GitHub.com marketplace actions are not reachable from GHES, which is why the
workflow migration replaces `jdx/mise-action` with a manual install step
(`references/workflow-migration.md`).

## Pitfalls

1. **`no_proxy` is mandatory.** With only `http_proxy` / `https_proxy` set,
   requests to the GHES host also go through the proxy, and the
   registration-token API returns the proxy's HTML error page instead of JSON.
   Symptom: `config.sh` fails with a parse error, or `gh api` prints HTML. The
   default `no_proxy` covers the GHES host and its parent domain; extend it
   with `RUNNER_NO_PROXY` when the runner must reach other internal hosts.
2. **Full certificate chain.** The three certificates in the devops assets
   (McAfee, `SECDS_ROOT_CA`, `SECDS-T2IssuingCA`) are not enough:
   `SECDS-T2ROOTCA` ships in a separate file. `curl` passes without it, but the
   .NET-based runner listener validates the whole chain and fails. Symptom:
   `config.sh` or `run.sh` logs an SSL / `UntrustedRoot` error while `curl`
   to the same URL works. Fix it in the image, not per container.
3. **`gh` must be told it is talking to GHES.** Use `GH_ENTERPRISE_TOKEN` (not
   `GH_TOKEN`) together with `GH_HOST=<ghes host>`. `register_runner.sh` sets
   `GH_HOST` on every call; the token must already be in `gh auth` or the
   environment. Symptom: `HTTP 401` or a request sent to github.com.

## Checks when it fails

```
ssh <host> docker logs <repo-name>-runner           # config.sh / run.sh output
ssh <host> docker exec <repo-name>-runner env | grep -i proxy
GH_HOST=<ghes host> gh api repos/<owner>/<name>/actions/runners
```
