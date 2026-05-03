# cookie-gift Skill — Design Spec

**Date:** 2026-05-03
**Author:** jangfolk + Claude
**Status:** Approved (awaiting implementation plan)

---

## 1. Purpose

Reward system for tracking cookies (🍪) granted to or revoked from Claude based on work quality. The user gives cookies for good work and revokes them for bad work. This skill manages the ledger.

**Goals:**

- Persistent cookie balance across all Claude Code sessions
- Recent activity always visible to Claude (top 10 changes auto-injected at session start)
- Full history available on demand
- Hybrid trigger: Claude proposes a delta when it detects praise/criticism; user approves or adjusts

---

## 2. File Layout

```
~/.claude/cookie-gift/
├── balance.md          # Current balance + recent 10 changes (human + Claude readable)
├── history.jsonl       # Full append-only ledger (single source of truth)
└── log.sh              # Helper script: atomic append + balance.md regeneration

~/.claude/skills/cookie-gift/
└── SKILL.md            # Skill definition with trigger description and behavior rules

~/.claude/hooks/
└── cookie-gift-session-start.sh   # SessionStart hook: injects compact balance summary

~/.claude/settings.json
└── hooks.SessionStart entry registering the hook above
```

### 2.1 `balance.md` format

```markdown
# 🍪 Cookie Balance: **17**

> Updated: 2026-05-03 14:22

## Recent 10 changes
| Time | Δ | Balance | Reason |
|------|---|---------|--------|
| 05-03 14:22 | +3 | 17 | Brand design review well done |
| 05-03 13:50 | -1 | 14 | CSS overflow not verified |
| ... | | | |

For full history, load: `~/.claude/cookie-gift/history.jsonl`
```

### 2.2 `history.jsonl` format

One JSON object per line, append-only:

```json
{"ts":"2026-05-03T14:22:13+09:00","delta":3,"balance":17,"reason":"Brand design review well done"}
```

Required fields: `ts` (ISO 8601 with timezone), `delta` (signed integer, non-zero), `balance` (post-change integer, may be negative), `reason` (non-empty string).

---

## 3. Trigger Behavior (Hybrid)

### 3.1 Skill description (auto-activation keywords)

The SKILL.md `description` frontmatter triggers activation when:

- Praise/criticism tone detected ("good job", "nice", "why is this broken", "bad")
- Explicit invocation ("cookie", "🍪", "balance", "쿠키", "잔고")
- Work-duration evaluation context ("worked all day", "took 3 days")

### 3.2 Claude flow

1. Detect tone → propose weight (1–5)
2. **Time scaling**: if user uses human time units, convert AI-scale before weighting. Base rule is **1 working day (human) = 1 hour (AI)**, applied to working days only:
   - 1 day (human) = 1 hour (AI)
   - 1 week (human, 5 working days) = 5 hours (AI)
   - 1 month (human, ~20 working days) = 20 hours (AI)
3. **Propose**: `🍪 +3 받을게요? (이유: 브랜드 디자인 잘 잡음)` or `🍪 -1 자진납부할게요 (CSS 미검증)`
4. User approves / rejects / adjusts
5. On approval, run `~/.claude/cookie-gift/log.sh <delta> "<reason>"`
6. Reply with new balance: `🍪 잔고: 17 (+3)`

### 3.3 Weight guide

| Magnitude | Examples |
|-----------|----------|
| ±1 | Small fix, minor lapse |
| ±3 | Solid feature work, repeated mistake |
| ±5 | Shipped a major release / serious regression |

### 3.4 Time scaling rule (also added globally to CLAUDE.md)

When estimating durations or responding to "how long will this take", convert human-scale to AI-scale: **1 day (human) = 1 hour (AI)**. Do not parrot human timelines unchanged.

This rule lives in two places:

- `~/.claude/CLAUDE.md` "소통 방식" section (global, applies to all responses)
- This skill's SKILL.md (applies specifically to cookie weight calibration)

---

## 4. SessionStart Hook

### 4.1 Behavior

On every Claude Code session start, the hook:

1. Ensures `~/.claude/cookie-gift/` exists. If missing, initializes with balance 0 and empty history.
2. Reads `balance.md` and emits a compact one-line summary to stdout:

   ```
   🍪 Cookie Balance: 17 (Recent: +3 brand-design, -1 css-not-verified, +2 design-clear, ...)
   For full history: read ~/.claude/cookie-gift/history.jsonl
   ```

3. Token budget: target ~100–200 tokens. Truncate reasons to ~20 chars each.

### 4.2 settings.json registration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "command": "~/.claude/hooks/cookie-gift-session-start.sh",
        "description": "Inject cookie balance + recent 10 into context"
      }
    ]
  }
}
```

---

## 5. Helper Script (`log.sh`)

### 5.1 Contract

```
Usage: log.sh <delta> <reason>

  <delta>   Signed integer (non-zero). e.g., +3, -1
  <reason>  Non-empty string explaining the change
```

### 5.2 Steps

1. Validate args: delta is non-zero integer; reason is non-empty.
2. Acquire `flock` on `history.jsonl` (avoid races between parallel sessions).
3. Read current balance from the last valid line of `history.jsonl`. If file empty, balance = 0.
4. Compute `new_balance = balance + delta`.
5. Append a new JSON line to `history.jsonl` (use `jq -c` to construct safely).
6. Regenerate `balance.md` from the last 10 lines of `history.jsonl`.
7. Release lock; print confirmation: `🍪 Balance: <new_balance> (<delta:+N>)`.

### 5.3 Negative balance

Allowed. Negative balances persist and display normally. No floor.

---

## 6. Edge Cases

| Case | Handling |
|------|----------|
| First run (no files) | Hook auto-creates dir + empty `history.jsonl` + balance.md with balance 0 |
| Corrupt JSON line in history | Skip invalid lines; recompute balance from valid ones; show ⚠️ banner in balance.md |
| `delta = 0` or non-integer | `log.sh` rejects with error message |
| Empty reason | `log.sh` rejects |
| Concurrent sessions | `flock` on `history.jsonl` serializes writes |
| User edits `balance.md` directly | Ignored — `history.jsonl` is source of truth, balance.md is regenerated on next change |
| User asks for full history | Claude reads `~/.claude/cookie-gift/history.jsonl` and summarizes/filters as requested |

---

## 7. Testing

Single bash test script `~/.claude/cookie-gift/test.sh` covering:

- Fresh init produces balance 0
- `+3` then `-1` results in balance 2 with two history lines
- Negative final balance permitted
- Invalid delta (`0`, `abc`) rejected
- Empty reason rejected
- Corrupt history line skipped, balance recomputed correctly
- Concurrent runs (`log.sh` × N in parallel) all logged without loss

No external test framework required — assert-based bash.

---

## 8. Out of Scope (YAGNI)

- Multi-user / multi-profile cookie ledgers
- Cloud sync of history
- Web UI / dashboard
- Analytics beyond the simple ledger
- Cookie redemption / shop mechanics
- Per-project balances (single global balance for now)

---

## 9. Open Questions

None — all resolved during brainstorming.

---

## 10. Implementation Outline (for the next step — writing-plans)

1. Create `~/.claude/cookie-gift/` directory structure
2. Implement `log.sh` (validation, flock, append, regenerate balance.md)
3. Implement `cookie-gift-session-start.sh` hook (init-if-missing, parse balance.md, emit compact summary)
4. Register hook in `~/.claude/settings.json`
5. Write `~/.claude/skills/cookie-gift/SKILL.md` with description + behavior rules
6. Add time-scaling rule to `~/.claude/CLAUDE.md` "소통 방식" section
7. Write `~/.claude/cookie-gift/test.sh` with the 7 cases above
8. Manual smoke test: open a fresh session, verify hook injects balance, run a simulated cookie change, verify balance.md and history.jsonl
