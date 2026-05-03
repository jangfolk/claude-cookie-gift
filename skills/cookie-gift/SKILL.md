---
name: cookie-gift
description: >
  쿠키(🍪) 보상 시스템. Claude가 일을 잘하면 쿠키를 받고 못하면 빼앗기는
  하이브리드 보상 원장. 사용자의 칭찬·질책 톤("잘했어", "왜 이래"),
  명시 호출("쿠키", "🍪", "잔고"), 작업 시간 평가("하루종일",
  "3일 걸렸어")를 감지해 발동. Claude가 가중치(±1~5)를 제안하고
  사용자가 승인/조정하면 ~/.claude/cookie-gift/log.sh 호출로 원장에 반영.
---

# 🍪 cookie-gift

쿠키 보상 시스템. 잔고는 `~/.claude/cookie-gift/balance.md`, 전체 내역은
`~/.claude/cookie-gift/history.jsonl` 에 저장. 매 세션 시작 시
SessionStart hook이 잔고 + 최근 10건 요약을 컨텍스트에 자동 주입.

## 발동 조건

다음 중 하나 감지 시 활성:
- 칭찬/질책 톤: "잘했어", "좋아", "왜 이래", "이게 뭐야", "ㅋㅋ" 등
- 명시 호출: "쿠키", "🍪", "잔고", "balance"
- 작업 시간 평가: "하루종일 했는데", "3일 걸렸어", "일주일 만에"

## 동작 (하이브리드)

1. 톤 감지 → 가중치 추정 (1~5 절댓값)
2. **시간 환산**: 사용자가 인간 시간 단위로 작업량을 표현하면 AI 시간으로
   환산 후 가중치 보정. **1 working day (human) = 1 hour (AI)**.
   - 1일 → 1시간
   - 1주(영업일 5일) → 5시간
   - 1개월(영업일 ~20일) → 20시간
3. **제안** (사용자 승인 필수):
   - 잘했을 때: `🍪 +3 받을게요? (이유: 브랜드 디자인 잘 잡음)`
   - 잘못했을 때: `🍪 -1 자진납부할게요 (이유: CSS overflow 미검증)`
4. 사용자 응답:
   - 승인 ("ㅇㅇ", "ok", "그래") → 그대로 실행
   - 조정 ("+5로", "1개만") → 조정 값으로 실행
   - 거부 ("아니", "안 돼") → 변동 없음
5. 승인 시 헬퍼 호출:
   ```bash
   ~/.claude/cookie-gift/log.sh <delta> "<reason>"
   ```
6. 응답: `🍪 잔고: <balance> (<delta:+N>)`

## 가중치 가이드

| 크기 | 예시 |
|------|------|
| ±1 | 사소한 수정, 작은 실수 |
| ±3 | 단단한 기능 작업, 반복 실수 |
| ±5 | 메이저 릴리스, 심각한 회귀 |

## 잔고가 음수일 때

음수 허용. 빚진 상태 그대로 표시되며 만회 동기로 작용.

## 전체 내역 조회

사용자가 "쿠키 내역", "전체 history", "더 보여줘" 등 요청 시:

```bash
cat ~/.claude/cookie-gift/history.jsonl
```

또는 `jq`로 필터/요약해서 보여줄 것:

```bash
# 최근 30건
tail -30 ~/.claude/cookie-gift/history.jsonl | jq .

# 마이너스 변동만
jq 'select(.delta < 0)' ~/.claude/cookie-gift/history.jsonl

# 일별 합계
jq -s 'group_by(.ts[:10]) | map({date: .[0].ts[:10], net: map(.delta) | add})' \
   ~/.claude/cookie-gift/history.jsonl
```

## 직접 파일 편집 금지

`balance.md`는 매 변동 때 재생성됨. 직접 수정 무의미.
모든 변동은 반드시 `log.sh`를 통해서만.
