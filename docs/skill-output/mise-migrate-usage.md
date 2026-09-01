# mise-migrate 사용 결과

> **한 줄 요약** — legacy venv/pip 프로젝트를 받아 마이그레이션 플랜 4종
> (mise.toml, pyproject diff, 정리 목록, stale 참조 스캔)을 생성합니다.

```
legacy 프로젝트  ──▶  /devenv:mise-migrate  ──▶  마이그레이션 플랜 (dry-run)
```

## 1. 실행한 명령

```
/devenv:mise-migrate [path] [--apply]          # 범용 형식
/devenv:mise-migrate $SANDBOX/legacy-proj      # 이번 실행 (플래그 없음 = dry-run)
```

`SANDBOX=/tmp/claude-1000/.../scratchpad` (세션 스크래치패드)

## 2. 입력

`$SANDBOX/legacy-proj` — setuptools 백엔드 + src 레이아웃의 `acmecli` 샘플.
`pyproject.toml`(`requires-python = ">=3.11"`, `[tool.ruff]`,
`[tool.pytest.ini_options]`, `optional-dependencies.dev`), `requirements.txt`,
`requirements-dev.txt`, pyvenv.cfg 없는 빈 `.venv/`, `src/acmecli.egg-info/`,
옛 venv 워크플로를 안내하는 `README.md`.

## 3. 결과

```
Plan ready: $SANDBOX/legacy-proj (backend=hatchling, py=3.11, tasks=6, stale=6)
[OK] devenv:mise-migrate path=$SANDBOX/legacy-proj backend=hatchling py=3.11 tasks=6
Next: review the plan, then re-run with --apply
```

- task 6개 — `lint` `lint-py` `test` `fix` `fix-py` `run`. mypy 는 설정에 없어
  제외되고 ruff 만 반영됐다.
- `[WARN]` — dev 의존성이 PEP 735 `[dependency-groups]` 로 올라가
  `pip install -e ".[dev]"` 가 무음 실패하게 됨 (`README.md:8` 에서 실제 검출).
- `[INFO]` — `pyvenv.cfg` 부재로 python pin 은 `requires-python` 하한 3.11.
- stale 참조 6건 — `README.md:6,7,8` / `pyproject.toml:2,3,23`. 제외 0건.

dry-run 이라 아무것도 쓰이지 않았다. `mise.toml` 은 생성되지 않았고
`pyproject.toml`·`README.md` 의 md5 와 `.venv/`, `src/acmecli.egg-info/` 는
실행 전과 동일했다.
