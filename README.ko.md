# 🍪 cookie-gift

[Claude Code](https://docs.claude.com/en/docs/claude-code)용 쿠키 기반 보상 원장.
일을 잘하면 쿠키를 주고, 못하면 빼앗아요. 잔고는 세션 간 유지되며 매 세션 시작 시 자동 주입됩니다.

> 🌐 **언어:** 한국어 | [English](README.md)

```
🍪 +3 받을게요? (이유: 브랜드 디자인 잘 잡음)
```

```
🍪 -1 자진납부할게요 (이유: CSS overflow 미검증)
```

## 동작 방식

- Claude가 칭찬/질책 톤(`잘했어`, `왜 이래`, `하루종일 했는데`...)을 감지해 **변동 값을 제안**합니다.
- 사용자는 승인, 조정, 거부할 수 있어요.
- 승인하면 flock 잠금이 걸린 bash 헬퍼가 JSONL 원장에 한 줄 append하고 markdown 요약을 재생성합니다.
- `SessionStart` hook이 매 새 세션 시작 시 잔고 + 최근 10건 변동을 컨텍스트에 주입하므로, 항상 잔고 인지 상태로 작동.

하이브리드 트리거 — Claude가 제안하므로 정확한 명령을 외울 필요 없고, 최종 결정권은 사용자에게.

## 보너스: AI 시간 환산 룰

이 스킬은 `~/.claude/CLAUDE.md`에 들어갈 글로벌 룰을 함께 제공:

> **인간 영업일 1일 = AI 1시간**

"이거 3일 걸렸어"라고 말하면 Claude는 인간 시간 그대로 적용 안 하고 AI 스케일(약 3시간)로 환산해서 쿠키 가중치를 책정합니다.

## 설치

```bash
git clone https://github.com/jangfolk/claude-cookie-gift.git
cd claude-cookie-gift
./install.sh
```

설치 스크립트가 하는 일:
- `log.sh`, `test.sh` → `~/.claude/cookie-gift/`
- SessionStart hook → `~/.claude/hooks/`
- `SKILL.md` → `~/.claude/skills/cookie-gift/`
- `~/.claude/settings.json`에 hook 등록 (idempotent — 중복 등록 방지)
- 원장 파일 없으면 빈 상태로 초기화
- `~/.claude/CLAUDE.md`에 시간 환산 룰 추가 여부 묻기 (선택)

설치 후 새 Claude Code 세션을 열면 시작 시점에 `🍪 Cookie Balance: 0`이 보여야 합니다.

## 요구 사항

- macOS 또는 Linux
- bash 4+
- [`jq`](https://stedolan.github.io/jq/) (`brew install jq`)
- [`flock`](https://man7.org/linux/man-pages/man1/flock.1.html) (macOS는 `brew install util-linux`)
- hook + skill 지원되는 [Claude Code](https://docs.claude.com/en/docs/claude-code)

## 수동 사용

원래는 직접 호출할 일이 없습니다 (Claude가 호출). 하지만 직접 쓸 수도:

```bash
~/.claude/cookie-gift/log.sh +3 "기능 출시"
~/.claude/cookie-gift/log.sh -1 "빌드 깸"

# 최신 요약 보기
cat ~/.claude/cookie-gift/balance.md

# 전체 내역
cat ~/.claude/cookie-gift/history.jsonl | jq .

# 오늘 순변동
jq -s --arg today "$(date +%Y-%m-%d)" \
   '[.[] | select(.ts | startswith($today))] | map(.delta) | add // 0' \
   ~/.claude/cookie-gift/history.jsonl
```

## 파일 구조

```
~/.claude/
├── cookie-gift/
│   ├── log.sh                         # 유일한 writer (flock 잠금)
│   ├── test.sh                        # 12개 bash 테스트
│   ├── history.jsonl                  # append-only 원장 (단일 진실의 출처)
│   ├── balance.md                     # 파생 요약 (재생성)
│   └── .lock                          # flock 파일
├── hooks/
│   └── cookie-gift-session-start.sh   # 세션 시작 시 잔고 요약 주입
└── skills/cookie-gift/
    └── SKILL.md                       # Claude용 스킬 정의
```

## 테스트

```bash
~/.claude/cookie-gift/test.sh
# → Pass: 12  Fail: 0
```

테스트는 인자 검증, 잔고 누적, balance.md 재생성, 동시 쓰기(10개 병렬), 손상 라인 복구를 커버합니다.

## 디자인

설계 문서는 [`docs/design-spec.md`](./docs/design-spec.md), TDD 방식 작업 분해는 [`docs/implementation-plan.md`](./docs/implementation-plan.md) 참고.

## 라이선스

MIT — [LICENSE](./LICENSE) 참고.
