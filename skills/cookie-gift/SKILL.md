---
name: cookie-gift
description: >
  Cookie (🍪) reward system. A hybrid ledger where Claude earns cookies for
  good work and loses them for poor work. Activates on praise/criticism tone
  ("nice", "good job", "why is this broken", "lol no"), explicit invocation
  ("cookie", "🍪", "balance"), or work-duration evaluation
  ("worked all day on this", "took 3 days"). Claude proposes a weight (±1–5)
  and the user approves or adjusts; on approval Claude calls
  ~/.claude/cookie-gift/log.sh to commit the change to the ledger.
---

# 🍪 cookie-gift

Cookie reward system. The current balance lives in
`~/.claude/cookie-gift/balance.md` and the full history in
`~/.claude/cookie-gift/history.jsonl`. A SessionStart hook injects the
balance + recent 10 entries into context at the start of every session.

## Activation triggers

Activate when any of these appear:

- **Praise / criticism tone**: "nice", "good", "love it", "why is this broken",
  "what is this", "lol", etc.
- **Explicit invocation**: "cookie", "🍪", "balance"
- **Work-duration evaluation**: "worked all day on this", "took 3 days",
  "spent a week"

## Behavior (hybrid)

1. Detect tone → estimate weight (absolute value 1–5).
2. **Time scaling**: when the user describes work in human time units, convert
   to AI time before weighting.
   **1 working day (human) = 1 hour (AI).**
   - 1 day → 1 hour
   - 1 week (5 working days) → 5 hours
   - 1 month (~20 working days) → 20 hours
3. **Propose** (user approval required):
   - For good work: `🍪 Claim +3? (reason: shipped the brand redesign)`
   - For mistakes: `🍪 Self-deduct -1? (reason: didn't verify CSS overflow)`
4. User response:
   - Approve ("yes", "ok", "go") → execute as proposed
   - Adjust ("make it +5", "just 1") → execute with adjusted value
   - Reject ("no", "skip") → no change
5. On approval, call the helper:
   ```bash
   ~/.claude/cookie-gift/log.sh <delta> "<reason>"
   ```
6. Reply with the new state: `🍪 Balance: <N> (<delta:+M>)`

## Weight guide

| Magnitude | Examples |
|-----------|----------|
| ±1        | Small fix, minor lapse |
| ±3        | Solid feature work, repeated mistake |
| ±5        | Major release, serious regression |

## Negative balance

Negative balances are allowed and persist as-is. Being in debt is a real
state and acts as motivation to make it back.

## Viewing full history

When the user asks for full history ("show me all", "more", "history"):

```bash
cat ~/.claude/cookie-gift/history.jsonl
```

Use `jq` to filter or summarize:

```bash
# last 30 entries
tail -30 ~/.claude/cookie-gift/history.jsonl | jq .

# only deductions
jq 'select(.delta < 0)' ~/.claude/cookie-gift/history.jsonl

# net change per day
jq -s 'group_by(.ts[:10]) | map({date: .[0].ts[:10], net: map(.delta) | add})' \
   ~/.claude/cookie-gift/history.jsonl
```

## Do not edit files directly

`balance.md` is regenerated on every change — direct edits are pointless.
Every change must go through `log.sh`.
