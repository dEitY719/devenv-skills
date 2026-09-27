# devenv:runner-setup — public (GitHub.com)

For a repo on GitHub.com. No proxy, no private CA, and every marketplace
action is reachable, so only `runs-on` changes in the workflows — unless the
runner host sits behind a TLS-intercepting proxy (see below).

## Requirements

- `--host` is required: there is no default runner host for public repos.
  The alias must work with `ssh -o BatchMode=yes` and its user must be able
  to run `docker`.
- `gh` authenticated to github.com with admin rights on the repo (the
  registration-token endpoint needs them).

## Image

The script builds a minimal image on the host the first time, tagged
`runner-setup-public:22.04` (`RUNNER_PUBLIC_IMAGE`), and reuses it afterwards:

- base `ubuntu:22.04`
- `ca-certificates`, `curl`, `git`
- `actions/runner` `RUNNER_VERSION` (default `2.328.0`) unpacked in
  `/actions-runner`, plus its `bin/installdependencies.sh`
- a non-root `runner` user that owns `/actions-runner` and runs the
  container; no Docker socket is mounted

The runner updates itself after registration, so an old `RUNNER_VERSION`
only costs one self-update. Anything a job needs beyond that (mise, uv,
compilers) is installed by the workflow, as on a hosted runner.

## Security

A self-hosted runner executes whatever a workflow tells it to. On a public
repo, a fork's pull request can run a workflow on it. Before using this on a
public repo, set Settings > Actions > "Require approval for all outside
collaborators" (or keep `pull_request` workflows off the self-hosted label).

## Behind a TLS-intercepting proxy

A host behind a firewall that re-signs TLS (the host trusts a corporate CA,
e.g. via `/usr/local/share/ca-certificates/`) fails the first image build:
the build container does not know that CA, `curl` refuses the runner tarball,
and the log ends in `gzip: stdin: unexpected end of file` / `tar ... exit
code: 2` (#39). Point `RUNNER_EXTRA_CA` at the CA file **on the runner host**:

```
RUNNER_EXTRA_CA=/usr/local/share/ca-certificates/<proxy-ca>.crt \
    register_runner.sh --env public --host <alias>
```

The CA is copied into the build context and trusted with
`update-ca-certificates`, so the runner and every job in it trust it too. The
file is checked before the registration token is minted. The image is built
only when its tag is absent, so an image built before setting the CA must be
removed first: `ssh <host> docker rmi runner-setup-public:22.04`.

## Checks when it fails

```
ssh <host> docker logs <repo-name>-runner
gh api repos/<owner>/<name>/actions/runners
```

Right after `docker restart <repo-name>-runner`, the log repeats `A session
for this runner already exists` for a minute or two until the old session
expires, and the API can report `online` from that old session meanwhile.
Wait for `Listening for Jobs` in the log; a run queued during that window
may stay queued — cancel it and re-run.
