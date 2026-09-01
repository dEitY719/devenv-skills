# `pyproject.toml` rewrite rules

Three in-place edits. Touch only these stanzas — never reorder or
reformat unrelated keys, and never change `dependencies` versions.

## 1. Build backend → `--backend`

### hatchling (default)

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

### uv_build

```toml
[build-system]
requires = ["uv_build>=0.10"]
build-backend = "uv_build"
```

## 2. Explicit packages mapping

setuptools' explicit-packages stanza must move to the chosen backend so
flat-layout auto-discovery doesn't pull in non-package dirs (the exact
breakage the karakeep `[tool.setuptools]` comment guards against).

| Source (setuptools) | hatchling | uv_build |
|---|---|---|
| `[tool.setuptools]`<br>`packages = ["pkg"]` | `[tool.hatch.build.targets.wheel]`<br>`packages = ["pkg"]` | `[tool.uv.build-backend]`<br>`module-name = "pkg"` |

If the source had no explicit `packages` (auto-discovery worked), only
emit a target-packages stanza when the project root contains non-package
dirs that would otherwise be picked up; otherwise leave discovery to the
backend.

## 3. Dev deps → `[dependency-groups]`

uv-native dependency groups (PEP 735) replace the
`optional-dependencies.dev` extra. This matches the dotfiles repo, whose
`mise.toml` notes ruff "is pinned in pyproject.toml's dev group".

Before:

```toml
[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-httpx>=0.30",
]
```

After:

```toml
[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-httpx>=0.30",
]
```

Remove the now-empty `[project.optional-dependencies]` table if `dev`
was its only key. If other extras exist, keep the table and only lift
the `dev` key out.

### Silent regression — warn loudly

Moving `dev` out of `optional-dependencies` is a **breaking change for
any pip-based install path**. `pip install -e ".[dev]"` no longer finds a
`dev` extra and *skips the dev deps with exit 0* — no error. Bootstrap /
CI scripts that called it keep passing while pytest, ruff, etc. are never
installed.

So whenever a `dev` extra is lifted, the plan **and** the `--apply`
report must carry this warning verbatim:

```
[WARN] dev deps moved to PEP 735 [dependency-groups] — any
       `pip install -e ".[dev]"` in scripts/CI will now silently skip
       dev deps. Use `uv sync` instead.
```

The `--update-docs` flag (see `stale-scan.md`) rewrites the in-repo
callers; external CI still needs a manual look, so the warning fires even
when `--update-docs` is set.

## Left untouched

`[project]` name/version/description/`requires-python`, runtime
`dependencies`, `[project.scripts]`, `[tool.pytest.ini_options]`, and any
tool config (`[tool.ruff]`, `[tool.mypy]`) pass through verbatim.
