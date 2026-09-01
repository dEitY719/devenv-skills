# symlink-manager 사용 결과

> **한 줄 요약** — 설정 파일 하나를 받아 dotfiles 정본 + 원위치 심볼릭 링크 +
> 관리 함수 + 커밋을 생성합니다.

```
설정 파일  ──▶  /devenv:symlink-manager  ──▶  dotfiles 정본 + 심볼릭 링크 + 커밋
```

## 1. 실행한 명령

```
/devenv:symlink-manager <file>                        # 범용 형식
/devenv:symlink-manager $SANDBOX/home/.config/ripgrep/ripgreprc   # 이번 실행
```

`SANDBOX=/tmp/claude-1000/.../scratchpad/symlink-sandbox`. 이 스킬은 원본을
이동시키고 `git commit` 까지 하므로, 실제 `~/dotfiles` 가 아니라
`bash/{claude,app,config,env}/` 로 배치한 샌드박스 dotfiles 레포에서 실행했다.

## 2. 입력

`$SANDBOX/home/.config/ripgrep/ripgreprc` — 4줄짜리 ripgrep 설정 파일
(`--smart-case`, `--hidden`, `--glob=!.git/*`, `--max-columns=200`).
일반 설정이므로 카테고리는 `bash/config/` 로 결정됐다.

## 3. 결과

```
[OK] devenv:symlink-manager target=ripgreprc category=config links=1 commit=9c12954
```

- Phase 1 — `ripgreprc.backup` 생성 후 원본을 `bash/config/ripgreprc` 로 옮기고
  원위치에 심볼릭 링크 생성. 링크를 통해 읽은 내용이 백업과 `diff` 상 동일함을
  확인했다.
- Phase 2/3 — `bash/app/ripgrep.bash` 에 `ripgrep_init`,
  `ripgrep_edit_config` 를 추가하고 `ripgrephelp` 에 설명을 넣었다
  (`bash -n` 문법 검사 통과).
- Phase 4 — 커밋 `9c12954 feat: manage ripgreprc via dotfiles with symbolic link`,
  2 files changed / 18 insertions.
- Phase 5 — link / source / backup 존재 확인, 관리 함수 2개 검출.
