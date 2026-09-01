# ssh-delegate — 스킬 가이드

## 한 줄 요약

일회성 `ssh-copy-id` 를 **`~/.ssh/delegations.yml` 매니페스트(mode 0600) + ssh
config 드롭인 + JSONL 감사 로그**로 산출한다. "어떤 키가 어느 호스트에 어떤
계정으로 설치되어 있는가"의 단일 진실 공급원을 만드는 것이 목적이다.

## 언제 쓰나

- AI/에이전트에게 SSH 접근을 위임하되, 그 위임 내역이 기록·감사되어야 할 때.
- 과거에 손으로 `ssh-copy-id` 한 호스트들을 매니페스트로 흡수해 관리할 때.
- 어떤 서버에 접근 가능한지 목록·검증(`list`, `test`, `doctor`)이 필요할 때.
- 위임을 회수할 때(`revoke` — 원격 `authorized_keys` 에서 키 제거).

## 언제 안 쓰나

- 로컬 설정 파일 관리는 `symlink-manager`, Python 툴체인 이전은 `mise-migrate`.
  이 스킬은 **원격 호스트 접근 권한**만 다룬다.
- 범용 SSH 클라이언트가 아니다. 매니페스트에 없는 호스트에는 alias 를 만들어
  주지 않으며, 접속을 대신 주선하지도 않는다.

## 호출 형식

```
/devenv:ssh-delegate <sub-command> [args]
```

| 서브커맨드 | 인자 | 효과 |
|---|---|---|
| `sync` | — | 매니페스트 ↔ 실제 상태 조정. config 재생성, 지문 pin/검증 |
| `add` | `<user>@<host> [alias] [--dry-run] [--key-only]` | 항목 추가 + 키 설치 + 검증 |
| `list` | `[--json]` | 위임 테이블 / JSON 출력 |
| `test` | `[<alias>\|--all]` | BatchMode 도달성 검사 |
| `revoke` | `<alias>` | 원격 키 제거 + `revoked: true` 표시 |
| `doctor` | — | 환경 + 매니페스트 health check |

인자가 없으면 usage 를 출력하고, 모르는 서브커맨드는 usage + exit 2 다.

## 3단 안전 모델

- **L1 Identity** — 매니페스트의 `identity_file` 만 제시한다(`IdentitiesOnly yes`).
- **L2 Host trust** — 최초 설치 시 SHA256 호스트 지문을 pin 하고 `sync` 마다
  재확인한다. **불일치는 ALERT 이며 즉시 중단**한다. 재신뢰는 사람의 결정이다.
- **L3 Allowlist + audit** — 모든 이벤트를 `flock` 직렬화된 JSONL 로 남긴다.

## 동작 단계

1. 첫 위치 인자로 서브커맨드를 고른다.
2. 번들된 `lib/ssh_delegate.sh` 에 인자를 넘겨 실행한다. 실제 로직은 전부
   `lib/*.sh` 에 있고 SKILL.md 는 라우터일 뿐이다.
3. 스크립트 출력을 그대로 전달하고, `add` 후 passwordless 접속을,
   `revoke` 후 `state=revoked` 를 확인해 보고한다.

## 주의사항 / 제약

- **`add` 는 TTY 가 필요하다.** `ssh-copy-id` 가 원격 비밀번호를 한 번 묻는다.
  비대화형 셸에서는 실행할 명령을 알려주며 fail-fast 한다.
- **`revoke` 는 행을 지우지 않는다.** `revoked: true` 로 표시해 감사 이력을
  남기며, `unrevoke` 는 존재하지 않는다.
- 지문 MISMATCH 를 우회하지 말 것. 매니페스트와 config 드롭인은 항상 0600.
- 런타임 산출물 이름은 고정이다 — `~/.ssh/config.d/devx-delegations`,
  `~/.local/state/devx/ssh-delegations.log`, `DEVX_SSH_*` 환경변수.
- `yq` 는 선택이며 `doctor` 만 사용한다. 없으면 내장 awk 파서로 동작한다.
