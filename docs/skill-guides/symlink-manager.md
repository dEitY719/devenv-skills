# symlink-manager — 스킬 가이드

## 한 줄 요약

원래 위치에 있던 설정 파일 하나를 입력받아 **dotfiles 레포 안의 정본 +
원위치의 심볼릭 링크 + `<app>_init` / `<app>_edit_*` 관리 함수 + 커밋**을
산출한다.

## 언제 쓰나

- 설정 파일을 dotfiles 로 버전 관리하면서 원래 경로에서도 그대로 읽히게 할 때.
- 여러 머신에 같은 설정을 재현 가능하게 깔고 싶을 때.
- 앱별 관리 함수와 help 항목까지 같이 만들어 두고 싶을 때.

## 언제 안 쓰나

- Python 프로젝트 툴체인 이전은 `mise-migrate`, 원격 호스트 SSH 키 위임은
  `ssh-delegate`. 이 스킬은 **로컬 설정 파일의 위치와 링크**만 다룬다.
- dotfiles 레포가 `bash/{claude,app,config,env}/` 로 배치되어 있지 않으면
  전제가 성립하지 않는다.

## 호출 형식

```
/devenv:symlink-manager <file>
/devenv:symlink-manager -h | --help | help
```

카테고리는 파일 성격에 따라 결정된다:

| 카테고리 | 용도 |
|---|---|
| `bash/claude/` | Claude Code 관련 설정 |
| `bash/app/` | 앱 전용 설정 및 관리 함수 |
| `bash/config/` | 일반 설정 파일 |
| `bash/env/` | 환경 변수 |

이 중 `dEitY719/dotfiles` 에 실제로 존재하는 디렉터리는 `bash/env/` 뿐이다.
Phase 1 헬퍼는 없는 카테고리 디렉터리를 만들지 않고 거부하므로, 먼저
`mkdir -p ~/dotfiles/bash/<category>` 를 해야 한다.

경로 규약은 `Source: ~/dotfiles/bash/<category>/<filename>` →
`Target: ~/<target_dir>/<filename>` 이다.

## 동작 단계

| Phase | 내용 |
|---|---|
| 0 | 분석 — 대상 파일 확인, 카테고리 결정, 경로 계획. 변경 전 계획을 announce |
| 1 | 이전 — `.backup` 생성 → dotfiles 로 복사 → 원본 제거 → 심볼릭 링크 → 검증 |
| 2 | 관리 함수 — `bash/app/<app>.bash` 에 `<app>_init`, `<app>_edit_<config>` 추가 |
| 3 | help — `<app>help` 함수에 새 함수 설명 추가 |
| 4 | 버전 관리 — stage 후 commit |
| 5 | 검증 — 링크/정본/백업/함수/커밋 확인 후 키-값 verdict 보고 |

각 Phase 는 **첫 실패에서 중단**한다. Phase 1 의 파일 이동 실패는 `.backup`
에서 자동 롤백된다.

## 주의사항 / 제약

- **원본을 이동시킨다.** 그래서 먼저 `.backup` 을 만들고 링크를 검증한다.
  이미 존재하는 파일을 덮어쓰기 전에는 반드시 확인을 받는다.
- **`git commit` 까지 수행한다.** 읽기 전용 감사 스킬이 아니다.
- Phase 2 이후의 실패는 자동 롤백되지 않는다 — Phase 1 만 백업 복원 대상이다.
- 완료 후 `source ~/.bashrc && <app>help` 로 새 링크와 함수를 검증한다.
- 보고 형식은 `[OK] devenv:symlink-manager target=<file> category=<dir>
  links=<n> commit=<sha>` 또는 `[FAIL] ... phase=<n> reason=<one-line>` 이다.
