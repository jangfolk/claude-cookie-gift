# 🍪 cookie-gift

A cookie-based reward ledger for [Claude Code](https://docs.claude.com/en/docs/claude-code).
Give Claude cookies when it does good work, take them away when it screws up.
Balance is persistent across sessions and auto-injected at session start.

```
🍪 Claim +3? (reason: shipped the brand redesign)
```

```
🍪 Self-deduct -1? (reason: didn't verify CSS overflow)
```

## How it works

- Claude detects praise/criticism tone (`nice`, `good job`, `why is this broken`, `worked all day`...) and **proposes** a delta.
- You approve, adjust, or reject.
- On approval, a flock-protected bash helper appends an entry to a JSONL ledger and regenerates a markdown summary.
- A `SessionStart` hook injects the current balance + recent 10 changes into every new Claude Code session, so context is always available.

Hybrid trigger means Claude proposes (so you don't have to type exact commands) but the user has the final say.

## Bonus: AI-time scaling rule

This skill ships with a global rule for `~/.claude/CLAUDE.md`:

> **1 working day (human) = 1 hour (AI).**

So when you say "this took me 3 days", Claude weights cookies on the AI scale (~3 hours of work) instead of pretending human timelines apply to AI work.

## Install

```bash
git clone https://github.com/jangfolk/claude-cookie-gift.git
cd claude-cookie-gift
./install.sh
```

The installer:
- Copies `log.sh` and `test.sh` to `~/.claude/cookie-gift/`
- Copies the SessionStart hook to `~/.claude/hooks/`
- Copies `SKILL.md` to `~/.claude/skills/cookie-gift/`
- Registers the hook in `~/.claude/settings.json` (idempotent — won't duplicate)
- Initializes empty ledger if missing
- Optionally appends the time-scaling rule to `~/.claude/CLAUDE.md` (asks first)

Then start a new Claude Code session — you should see `🍪 Cookie Balance: 0` injected at start.

## Requirements

- macOS or Linux
- bash 4+
- [`jq`](https://stedolan.github.io/jq/) (`brew install jq`)
- [`flock`](https://man7.org/linux/man-pages/man1/flock.1.html) (`brew install util-linux` on macOS)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) with hook + skill support

## Manual usage

You normally never call `log.sh` yourself — Claude does. But you can:

```bash
~/.claude/cookie-gift/log.sh +3 "shipped a feature"
~/.claude/cookie-gift/log.sh -1 "broke the build"

# View the latest summary
cat ~/.claude/cookie-gift/balance.md

# Full history
cat ~/.claude/cookie-gift/history.jsonl | jq .

# Net change today
jq -s --arg today "$(date +%Y-%m-%d)" \
   '[.[] | select(.ts | startswith($today))] | map(.delta) | add // 0' \
   ~/.claude/cookie-gift/history.jsonl
```

## Layout

```
~/.claude/
├── cookie-gift/
│   ├── log.sh                         # only writer (flock-protected)
│   ├── test.sh                        # 12 bash tests
│   ├── history.jsonl                  # append-only ledger (source of truth)
│   ├── balance.md                     # derived summary (regenerated)
│   └── .lock                          # flock file
├── hooks/
│   └── cookie-gift-session-start.sh   # injects balance summary on session start
└── skills/cookie-gift/
    └── SKILL.md                       # skill description for Claude
```

## Test

```bash
~/.claude/cookie-gift/test.sh
# → Pass: 12  Fail: 0
```

Tests cover argument validation, balance accumulation, balance.md regen, concurrent writes (10 parallel), and corrupt-line resilience.

## Design

See [`docs/design-spec.md`](./docs/design-spec.md) for the design and [`docs/implementation-plan.md`](./docs/implementation-plan.md) for the TDD-style task breakdown that built this.

## License

MIT — see [LICENSE](./LICENSE).
