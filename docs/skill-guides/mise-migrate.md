# mise-migrate — 스킬 가이드

## 한 줄 요약

legacy Python venv/pip 프로젝트를 입력받아 **`mise.toml`(tools + env + tasks SSOT)
과 uv 가 소유하는 의존성 구조**를 산출한다. 기본은 `--dry-run` 이라 산출물은
"쓰여진 파일"이 아니라 **검토용 마이그레이션 플랜 4종**이다.

## 언제 쓰나

- pyenv / `python -m venv` + pip + setuptools 로 굴러온 Python 프로젝트를
  mise + uv 로 옮길 때.
- 옮기기 전에 무엇이 바뀌는지(빌드 백엔드, dev 의존성 위치, 삭제될 `.venv/`)
  먼저 확인하고 싶을 때.

## 언제 안 쓰나

- **Python 이 아닌 프로젝트** — node/go 등은 설계상 범위 밖이며 즉시 거부한다.
- **이미 `mise.toml` 이 있는 디렉터리** — 멱등 no-op 으로 빠진다.
- 설정 파일을 dotfiles 로 옮겨 심볼릭 링크하려는 경우는 `symlink-manager`,
  SSH 키 위임은 `ssh-delegate` 다. 이 스킬은 **한 프로젝트의 툴체인 구조**만 다룬다.

## 호출 형식

```
/devenv:mise-migrate [path] [flags]
```

| 인자/플래그 | 기본값 | 설명 |
|---|---|---|
| `[path]` | `.` | 대상 프로젝트 디렉터리 |
| `--dry-run` | **on** | 플랜만 출력, 아무것도 쓰지 않음 |
| `--apply` | off | `mise.toml` 작성 + `pyproject.toml` 재작성 + `uv sync` + 정리 |
| `--backend <name>` | `hatchling` | `hatchling` 또는 `uv_build` |
| `--keep-venv` | off | 기존 `.venv/`, `*.egg-info/` 를 지우지 않음 |
| `--update-docs` | off | `--apply` 와 함께일 때만, 레포 내 stale 문서를 uv 워크플로로 재작성 |
| `-h` / `--help` / `help` | — | 도움말 출력 후 종료 (탐지·변경 없음) |

## 동작 단계

1. **탐지** — `pyproject.toml` / `setup.py` / `requirements*.txt` 마커 확인.
   마커가 없고 직속 하위 디렉터리 하나에만 있으면 그쪽으로 재타게팅한다.
2. **추출**(읽기 전용) — Python 버전, 런타임/dev 의존성, `[project.scripts]`,
   테스트 러너와 `testpaths`, 빌드 백엔드, 설정된 linter(ruff/mypy).
3. **플랜 4종** — 생성될 `mise.toml`, `pyproject.toml` diff, 정리 목록,
   그리고 레포 내 legacy `venv`/`pip` 참조 스캔(`file:line`).
4. **`--apply` 일 때만** — 위 순서대로 쓰고 `uv sync` 실행 후 정리.

## 주의사항 / 제약

- **롤백이 없다.** `--apply` 는 첫 실패에서 멈추고 부분 상태를 보고한다.
  되돌리는 것은 사용자 몫이다.
- **PEP 735 silent regression** — dev 의존성이 `optional-dependencies` 에서
  `[dependency-groups]` 로 올라가면 `pip install -e ".[dev]"` 는 **exit 0 인 채로
  아무것도 설치하지 않는다.** 스킬이 이 경우 항상 `[WARN]` 을 띄우므로,
  해당 호출부를 `uv sync` 로 바꿔야 한다.
- **pin 은 floor 일 수 있다.** `.venv/pyvenv.cfg` 가 없으면 `requires-python`
  하한을 그대로 pin 하며, `uv sync` 는 그보다 최신 인터프리터를 고를 수 있다.
- 프로젝트에 없는 linter 용 task 는 만들지 않는다. 소스 코드는 건드리지 않는다.
- `--apply` 는 `uv` 가 `PATH` 에 있어야 한다.
