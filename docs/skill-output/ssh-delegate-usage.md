# ssh-delegate 사용 결과

> **한 줄 요약** — 서브커맨드와 매니페스트를 받아 위임 상태 진단과 실행 계획을
> 생성합니다.

```
서브커맨드 + 매니페스트  ──▶  /devenv:ssh-delegate  ──▶  진단 / 계획 출력
```

## 1. 실행한 명령

```
/devenv:ssh-delegate <sync|add|list|test|revoke|doctor>     # 범용 형식

/devenv:ssh-delegate doctor                                 # 이번 실행 1
/devenv:ssh-delegate add deploy@example.invalid demo --dry-run   # 이번 실행 2
/devenv:ssh-delegate list                                   # 이번 실행 3
```

원격에 키를 설치·삭제하지 않는 읽기 전용 경로만 실행했고, `DEVX_SSH_MANIFEST` /
`DEVX_SSH_AUDIT_LOG` / `DEVX_SSH_CONFIG_DROPIN` 로 샌드박스를 가리켰다.

## 2. 입력

매니페스트가 아직 없는 빈 샌드박스. 기본 identity 는 실제 환경의
`~/.ssh/id_ed25519`.

## 3. 결과

`doctor` (exit 0):

```
== doctor ==
[..] no manifest yet (...delegations.yml) — run `add` to create one
[OK] default identity present (/home/bwyoon/.ssh/id_ed25519)
[OK] ssh present
[..] yq absent — using built-in awk parser (OK)
[OK] audit log writable (...ssh-delegations.log)
```

`add --dry-run` (exit 0) 은 매니페스트 upsert, `ssh-copy-id -i
"~/.ssh/id_ed25519.pub" -p 22 deploy@example.invalid`, config 재생성 + verify
를 "would" 로만 출력했다. `list` 는 헤더만 있는 빈 표를 냈다.

실행 후 샌드박스에는 `state/` 만 남고 `delegations.yml` 은 생성되지 않았다 —
`--dry-run` 이 원격은 물론 로컬 매니페스트도 건드리지 않음이 확인됐다.
