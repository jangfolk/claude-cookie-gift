# cookie-gift Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent cookie reward ledger for Claude Code, with hybrid trigger (Claude proposes, user approves), session-start auto-injection of the recent 10 entries, and a global "1 working day = 1 hour AI" time-scaling rule.

**Architecture:** A single bash helper script (`log.sh`) is the only writer to the JSONL ledger; it validates input, locks for concurrent safety, appends one line, and regenerates `balance.md`. A `SessionStart` hook reads `balance.md` and injects a compact summary into context. A skill (`SKILL.md`) describes the trigger behavior. A line in CLAUDE.md applies the time-scaling rule globally.

**Tech Stack:** bash, `jq` (JSON construction/parsing), `flock` (file locking), Claude Code hooks (`SessionStart`), Claude Code skills.

**Note on environment:** `~/.claude/` is **not** a git repository, so this plan uses "verify state" steps instead of `git commit` steps. If the user later turns `~/.claude/` into a repo, commits can be added back.

---

## File Structure

**Created:**
- `~/.claude/cookie-gift/log.sh` — helper script (only writer to ledger)
- `~/.claude/cookie-gift/test.sh` — bash test suite for log.sh
- `~/.claude/cookie-gift/balance.md` — current balance + recent 10 (regenerated)
- `~/.claude/cookie-gift/history.jsonl` — append-only ledger (source of truth)
- `~/.claude/hooks/cookie-gift-session-start.sh` — SessionStart hook
- `~/.claude/skills/cookie-gift/SKILL.md` — skill definition

**Modified:**
- `~/.claude/settings.json` — register the SessionStart hook
- `~/.claude/CLAUDE.md` — add the time-scaling rule under "소통 방식"

---

## Task 1: Initialize directory structure and empty data files

**Files:**
- Create: `~/.claude/cookie-gift/` directory
- Create: `~/.claude/cookie-gift/history.jsonl` (empty file)
- Create: `~/.claude/cookie-gift/balance.md` (initial state, balance 0)

- [ ] **Step 1: Verify jq and flock are installed**

Run:
```bash
which jq && which flock
```

Expected: both paths printed. If `flock` is missing on macOS, install via `brew install flock`. If `jq` is missing, `brew install jq`.

- [ ] **Step 2: Create the directory and empty ledger**

Run:
```bash
mkdir -p ~/.claude/cookie-gift
touch ~/.claude/cookie-gift/history.jsonl
```

- [ ] **Step 3: Write the initial balance.md**

Write file `~/.claude/cookie-gift/balance.md` with content:

```markdown
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: `~/.claude/cookie-gift/history.jsonl`
```

- [ ] **Step 4: Verify state**

Run:
```bash
ls -la ~/.claude/cookie-gift/
```

Expected output: directory exists, `history.jsonl` (0 bytes), `balance.md` (with the initial content above).

---

## Task 2: Create test harness skeleton (test.sh)

**Files:**
- Create: `~/.claude/cookie-gift/test.sh`

- [ ] **Step 1: Write the test harness skeleton**

Write file `~/.claude/cookie-gift/test.sh` with content:

```bash
#!/usr/bin/env bash
# Test suite for ~/.claude/cookie-gift/log.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_SH="$SCRIPT_DIR/log.sh"

# Each test runs in an isolated temp dir; we rebind COOKIE_GIFT_DIR to point there.
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local fn="$2"
    local tmp
    tmp="$(mktemp -d)"
    export COOKIE_GIFT_DIR="$tmp"
    # Initialize blank ledger
    : > "$tmp/history.jsonl"
    if "$fn"; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name"
        FAIL=$((FAIL+1))
    fi
    rm -rf "$tmp"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "    expected: $expected"
        echo "    actual:   $actual"
        [[ -n "$msg" ]] && echo "    msg: $msg"
        return 1
    fi
    return 0
}

# ---- tests will be added below ----

echo "Running cookie-gift tests..."
echo "(no tests yet — fill in)"

echo ""
echo "Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x ~/.claude/cookie-gift/test.sh
```

- [ ] **Step 3: Run it (sanity check)**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected output:
```
Running cookie-gift tests...
(no tests yet — fill in)

Pass: 0  Fail: 0
```

---

## Task 3: log.sh — argument validation (TDD)

**Files:**
- Modify: `~/.claude/cookie-gift/test.sh`
- Create: `~/.claude/cookie-gift/log.sh`

- [ ] **Step 1: Add failing tests for argument validation**

Replace the `# ---- tests will be added below ----` section in `~/.claude/cookie-gift/test.sh` with:

```bash
test_rejects_missing_args() {
    local out
    out="$("$LOG_SH" 2>&1)" && return 1  # should fail (non-zero)
    [[ "$out" == *"Usage:"* ]] || { echo "    no usage msg"; return 1; }
    return 0
}

test_rejects_zero_delta() {
    local out
    out="$("$LOG_SH" 0 "reason" 2>&1)" && return 1
    [[ "$out" == *"non-zero"* ]] || return 1
    return 0
}

test_rejects_non_integer_delta() {
    local out
    out="$("$LOG_SH" abc "reason" 2>&1)" && return 1
    [[ "$out" == *"integer"* ]] || return 1
    return 0
}

test_rejects_empty_reason() {
    local out
    out="$("$LOG_SH" 1 "" 2>&1)" && return 1
    [[ "$out" == *"reason"* ]] || return 1
    return 0
}

run_test "rejects missing args"        test_rejects_missing_args
run_test "rejects zero delta"          test_rejects_zero_delta
run_test "rejects non-integer delta"   test_rejects_non_integer_delta
run_test "rejects empty reason"        test_rejects_empty_reason
```

Replace `echo "(no tests yet — fill in)"` with `# tests run via run_test calls above`.

- [ ] **Step 2: Run tests — expect failures (log.sh doesn't exist yet)**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: 4 ❌ failures (script not found / not executable).

- [ ] **Step 3: Implement log.sh argument validation**

Write file `~/.claude/cookie-gift/log.sh`:

```bash
#!/usr/bin/env bash
# log.sh — append a cookie change to the ledger and regenerate balance.md
# Usage: log.sh <delta> <reason>
set -u

COOKIE_GIFT_DIR="${COOKIE_GIFT_DIR:-$HOME/.claude/cookie-gift}"
HISTORY="$COOKIE_GIFT_DIR/history.jsonl"
BALANCE="$COOKIE_GIFT_DIR/balance.md"

usage() {
    echo "Usage: log.sh <delta> <reason>" >&2
    echo "  <delta>   Signed non-zero integer (e.g., +3, -1)" >&2
    echo "  <reason>  Non-empty string" >&2
    exit 2
}

# Validate args
[[ $# -ge 2 ]] || usage

DELTA="$1"
REASON="$2"

# delta must be a signed integer (e.g. 3, +3, -1)
if ! [[ "$DELTA" =~ ^[+-]?[0-9]+$ ]]; then
    echo "Error: delta must be an integer" >&2
    exit 2
fi

# Strip leading '+' if any (so arithmetic works)
DELTA="${DELTA#+}"

if [[ "$DELTA" -eq 0 ]]; then
    echo "Error: delta must be non-zero" >&2
    exit 2
fi

if [[ -z "$REASON" ]]; then
    echo "Error: reason must be non-empty" >&2
    exit 2
fi

# (rest of implementation added in later tasks)
echo "🍪 (validation only — append not implemented yet)" >&2
exit 0
```

- [ ] **Step 4: Make it executable**

Run:
```bash
chmod +x ~/.claude/cookie-gift/log.sh
```

- [ ] **Step 5: Run tests — expect 4 passes**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 4  Fail: 0`.

---

## Task 4: log.sh — balance accumulation + JSONL append (TDD)

**Files:**
- Modify: `~/.claude/cookie-gift/test.sh`
- Modify: `~/.claude/cookie-gift/log.sh`

- [ ] **Step 1: Add failing tests for balance accumulation**

Append before the `echo ""` "Pass:" footer in `~/.claude/cookie-gift/test.sh`:

```bash
test_first_entry_balance_is_delta() {
    "$LOG_SH" 3 "first" >/dev/null || return 1
    local lines
    lines="$(wc -l < "$COOKIE_GIFT_DIR/history.jsonl" | tr -d ' ')"
    assert_eq "1" "$lines" "history line count" || return 1
    local bal
    bal="$(jq -r '.balance' < "$COOKIE_GIFT_DIR/history.jsonl" | tail -1)"
    assert_eq "3" "$bal" "first balance" || return 1
}

test_accumulates_deltas() {
    "$LOG_SH" 5 "a" >/dev/null || return 1
    "$LOG_SH" -2 "b" >/dev/null || return 1
    "$LOG_SH" 1 "c" >/dev/null || return 1
    local last_bal
    last_bal="$(jq -r '.balance' < "$COOKIE_GIFT_DIR/history.jsonl" | tail -1)"
    assert_eq "4" "$last_bal" "accumulated balance" || return 1
}

test_allows_negative_balance() {
    "$LOG_SH" -3 "owe" >/dev/null || return 1
    local bal
    bal="$(jq -r '.balance' < "$COOKIE_GIFT_DIR/history.jsonl" | tail -1)"
    assert_eq "-3" "$bal" "negative balance" || return 1
}

test_jsonl_has_required_fields() {
    "$LOG_SH" 2 "hello" >/dev/null || return 1
    local line
    line="$(tail -1 "$COOKIE_GIFT_DIR/history.jsonl")"
    [[ -n "$(echo "$line" | jq -r '.ts')"     ]] || return 1
    [[ "$(echo "$line" | jq -r '.delta')"   == "2"     ]] || return 1
    [[ "$(echo "$line" | jq -r '.balance')" == "2"     ]] || return 1
    [[ "$(echo "$line" | jq -r '.reason')"  == "hello" ]] || return 1
}

run_test "first entry balance is delta"     test_first_entry_balance_is_delta
run_test "accumulates deltas"               test_accumulates_deltas
run_test "allows negative balance"          test_allows_negative_balance
run_test "jsonl has required fields"        test_jsonl_has_required_fields
```

- [ ] **Step 2: Run tests — expect 4 new failures**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: previous 4 pass, 4 new fail.

- [ ] **Step 3: Implement balance read + jsonl append**

Replace the "rest of implementation added in later tasks" comment block in `~/.claude/cookie-gift/log.sh` with:

```bash
mkdir -p "$COOKIE_GIFT_DIR"
[[ -f "$HISTORY" ]] || : > "$HISTORY"

# Robust last-valid-balance read (works on macOS without tac).
# Skips lines whose .balance doesn't parse as integer (corrupt-line resilience).
read_last_balance() {
    local file="$1"
    local bal=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local parsed
            parsed="$(echo "$line" | jq -r '.balance' 2>/dev/null || true)"
            if [[ "$parsed" =~ ^-?[0-9]+$ ]]; then
                bal="$parsed"
            fi
        fi
    done < "$file"
    echo "$bal"
}

prev_balance="$(read_last_balance "$HISTORY")"
new_balance=$((prev_balance + DELTA))

ts="$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")"

# Compose JSON line safely with jq
new_line="$(jq -nc \
    --arg ts "$ts" \
    --argjson delta "$DELTA" \
    --argjson balance "$new_balance" \
    --arg reason "$REASON" \
    '{ts:$ts,delta:$delta,balance:$balance,reason:$reason}')"

# Append (no lock yet — added in Task 6)
echo "$new_line" >> "$HISTORY"

echo "🍪 Balance: $new_balance ($([[ $DELTA -ge 0 ]] && echo +$DELTA || echo $DELTA))"
exit 0
```

Note: remove the earlier placeholder echo `(validation only — append not implemented yet)`.

- [ ] **Step 4: Run tests — expect all 8 pass**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 8  Fail: 0`.

---

## Task 5: log.sh — regenerate balance.md (TDD)

**Files:**
- Modify: `~/.claude/cookie-gift/test.sh`
- Modify: `~/.claude/cookie-gift/log.sh`

- [ ] **Step 1: Add failing tests for balance.md regeneration**

Append before the `echo ""` "Pass:" footer in `~/.claude/cookie-gift/test.sh`:

```bash
test_balance_md_shows_current_balance() {
    "$LOG_SH" 7 "for md" >/dev/null || return 1
    grep -q "Cookie Balance: \*\*7\*\*" "$COOKIE_GIFT_DIR/balance.md" || return 1
}

test_balance_md_shows_recent_10_max() {
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        "$LOG_SH" 1 "entry $i" >/dev/null || return 1
    done
    # balance.md table should contain at most 10 entry rows
    local rows
    rows="$(grep -c '^| 20' "$COOKIE_GIFT_DIR/balance.md" || true)"
    [[ "$rows" -le 10 ]] || { echo "    rows=$rows"; return 1; }
    [[ "$rows" -eq 10 ]] || { echo "    expected 10 rows, got $rows"; return 1; }
    # Most recent reason should appear; oldest entry "entry 1" should NOT
    grep -q "entry 12" "$COOKIE_GIFT_DIR/balance.md" || return 1
    ! grep -q "entry 1\b"  "$COOKIE_GIFT_DIR/balance.md" || return 1
}

run_test "balance.md shows current balance"  test_balance_md_shows_current_balance
run_test "balance.md keeps recent 10 max"    test_balance_md_shows_recent_10_max
```

- [ ] **Step 2: Run tests — expect 2 new failures**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: previous 8 pass, 2 new fail.

- [ ] **Step 3: Implement balance.md regeneration**

In `~/.claude/cookie-gift/log.sh`, replace the final lines:

```bash
echo "🍪 Balance: $new_balance ($([[ $DELTA -ge 0 ]] && echo +$DELTA || echo $DELTA))"
exit 0
```

with:

```bash
regenerate_balance_md() {
    local recent
    # Last 10 valid JSON lines
    recent="$(
        grep -E '^\{.*\}$' "$HISTORY" 2>/dev/null \
        | tail -10
    )"

    {
        echo "# 🍪 Cookie Balance: **$new_balance**"
        echo ""
        echo "> Updated: $ts"
        echo ""
        echo "## Recent 10 changes"
        if [[ -z "$recent" ]]; then
            echo "_No changes yet._"
        else
            echo "| Time | Δ | Balance | Reason |"
            echo "|------|---|---------|--------|"
            # Newest first
            echo "$recent" | tac 2>/dev/null || echo "$recent" | tail -r
        fi | while IFS= read -r line; do
            if [[ "$line" == \{* ]]; then
                local t d b r short_t
                t="$(echo "$line" | jq -r '.ts')"
                d="$(echo "$line" | jq -r '.delta')"
                b="$(echo "$line" | jq -r '.balance')"
                r="$(echo "$line" | jq -r '.reason')"
                short_t="${t:5:11}"  # MM-DDTHH:MM
                short_t="${short_t/T/ }"
                # show sign on positive deltas
                [[ "$d" -gt 0 ]] && d="+$d"
                printf '| %s | %s | %s | %s |\n' "$short_t" "$d" "$b" "$r"
            else
                echo "$line"
            fi
        done
        echo ""
        echo "For full history, load: \`~/.claude/cookie-gift/history.jsonl\`"
    } > "$BALANCE"
}

regenerate_balance_md

echo "🍪 Balance: $new_balance ($([[ $DELTA -ge 0 ]] && echo +$DELTA || echo $DELTA))"
exit 0
```

- [ ] **Step 4: Run tests — expect all 10 pass**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 10  Fail: 0`.

If `tail -r` and `tac` both fail on the runner, replace the reverse-pipe line with: `echo "$recent" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}'`.

---

## Task 6: log.sh — flock for concurrent safety (TDD)

**Files:**
- Modify: `~/.claude/cookie-gift/test.sh`
- Modify: `~/.claude/cookie-gift/log.sh`

- [ ] **Step 1: Add failing test for concurrent writes**

Append before the `echo ""` "Pass:" footer in `~/.claude/cookie-gift/test.sh`:

```bash
test_concurrent_writes_no_loss() {
    # Spawn 10 parallel +1 writes; expect 10 history lines and balance == 10
    local pids=()
    for i in 1 2 3 4 5 6 7 8 9 10; do
        ( "$LOG_SH" 1 "concurrent-$i" >/dev/null ) &
        pids+=($!)
    done
    for p in "${pids[@]}"; do wait "$p"; done

    local lines
    lines="$(wc -l < "$COOKIE_GIFT_DIR/history.jsonl" | tr -d ' ')"
    assert_eq "10" "$lines" "concurrent line count" || return 1
    local final_bal
    final_bal="$(jq -r '.balance' < "$COOKIE_GIFT_DIR/history.jsonl" | tail -1)"
    assert_eq "10" "$final_bal" "final balance after concurrent writes" || return 1
}

run_test "concurrent writes have no loss" test_concurrent_writes_no_loss
```

- [ ] **Step 2: Run tests — expect intermittent failure**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: previous 10 pass, the new concurrent test likely fails (race on read-modify-write of balance).

- [ ] **Step 3: Wrap the read-modify-write in flock**

In `~/.claude/cookie-gift/log.sh`, find the section beginning at:

```bash
prev_balance="$(read_last_balance "$HISTORY")"
```

Wrap from that line through the `regenerate_balance_md` call inside a `flock` block. The final structure of the script should be:

```bash
mkdir -p "$COOKIE_GIFT_DIR"
[[ -f "$HISTORY" ]] || : > "$HISTORY"

read_last_balance() {
    local file="$1"
    local bal=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local parsed
            parsed="$(echo "$line" | jq -r '.balance' 2>/dev/null || true)"
            if [[ "$parsed" =~ ^-?[0-9]+$ ]]; then
                bal="$parsed"
            fi
        fi
    done < "$file"
    echo "$bal"
}

LOCK="$COOKIE_GIFT_DIR/.lock"
exec 9>"$LOCK"
flock 9

prev_balance="$(read_last_balance "$HISTORY")"
new_balance=$((prev_balance + DELTA))

ts="$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")"

new_line="$(jq -nc \
    --arg ts "$ts" \
    --argjson delta "$DELTA" \
    --argjson balance "$new_balance" \
    --arg reason "$REASON" \
    '{ts:$ts,delta:$delta,balance:$balance,reason:$reason}')"

echo "$new_line" >> "$HISTORY"

regenerate_balance_md

flock -u 9
exec 9>&-

echo "🍪 Balance: $new_balance ($([[ $DELTA -ge 0 ]] && echo +$DELTA || echo $DELTA))"
exit 0
```

(Keep the `regenerate_balance_md()` function definition where it already is — only the read-modify-write critical section is moved inside the flock.)

- [ ] **Step 4: Run tests — expect all 11 pass**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 11  Fail: 0`.

If the concurrent test still flakes, add `for _ in 1 2 3; do ~/.claude/cookie-gift/test.sh || true; done` to confirm behavior across runs.

---

## Task 7: log.sh — corrupt-line resilience (TDD)

**Files:**
- Modify: `~/.claude/cookie-gift/test.sh`

- [ ] **Step 1: Add failing test for corrupted history**

Append before the `echo ""` "Pass:" footer in `~/.claude/cookie-gift/test.sh`:

```bash
test_skips_corrupt_lines() {
    # Pre-seed history with: valid +5, garbage, valid -2 → expected last balance 3
    cat > "$COOKIE_GIFT_DIR/history.jsonl" <<EOF
{"ts":"2026-05-03T00:00:00+00:00","delta":5,"balance":5,"reason":"a"}
this is not json
{"ts":"2026-05-03T00:01:00+00:00","delta":-2,"balance":3,"reason":"b"}
EOF

    "$LOG_SH" 1 "after corrupt" >/dev/null || return 1
    local last_bal
    last_bal="$(jq -r '.balance' < "$COOKIE_GIFT_DIR/history.jsonl" 2>/dev/null | tail -1)"
    assert_eq "4" "$last_bal" "balance after corrupt-line skip" || return 1
}

run_test "skips corrupt lines when computing balance" test_skips_corrupt_lines
```

- [ ] **Step 2: Run tests — expect 1 new failure (or pass)**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Already-implemented `read_last_balance()` skips lines whose `.balance` doesn't parse, so this test may already pass. If it does, mark this task complete after verification. If it fails, hop to Step 3.

- [ ] **Step 3: Harden read_last_balance (only if failing)**

If Step 2 failed, ensure `read_last_balance()` in `~/.claude/cookie-gift/log.sh` looks exactly like:

```bash
read_last_balance() {
    local file="$1"
    local bal=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local parsed
        parsed="$(echo "$line" | jq -r '.balance' 2>/dev/null || true)"
        if [[ "$parsed" =~ ^-?[0-9]+$ ]]; then
            bal="$parsed"
        fi
    done < "$file"
    echo "$bal"
}
```

- [ ] **Step 4: Run tests — expect all 12 pass**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 12  Fail: 0`.

---

## Task 8: SessionStart hook script

**Files:**
- Create: `~/.claude/hooks/cookie-gift-session-start.sh`

- [ ] **Step 1: Verify hooks directory exists**

Run:
```bash
mkdir -p ~/.claude/hooks
```

- [ ] **Step 2: Write the hook script**

Write file `~/.claude/hooks/cookie-gift-session-start.sh`:

```bash
#!/usr/bin/env bash
# SessionStart hook — emits a compact cookie-balance summary to stdout
# so it gets injected into the session context.
set -u

DIR="$HOME/.claude/cookie-gift"
HISTORY="$DIR/history.jsonl"
BALANCE_MD="$DIR/balance.md"

# First-run init: create empty ledger if missing.
if [[ ! -d "$DIR" ]]; then
    mkdir -p "$DIR"
    : > "$HISTORY"
    cat > "$BALANCE_MD" <<EOF
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: \`~/.claude/cookie-gift/history.jsonl\`
EOF
fi

# Compute current balance from last valid line.
balance=0
if [[ -s "$HISTORY" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        parsed="$(echo "$line" | jq -r '.balance' 2>/dev/null || true)"
        [[ "$parsed" =~ ^-?[0-9]+$ ]] && balance="$parsed"
    done < "$HISTORY"
fi

# Build a one-line "Recent" summary: up to 10 short tokens.
recent_summary=""
if [[ -s "$HISTORY" ]] && command -v jq >/dev/null 2>&1; then
    # Iterate last 10 lines newest first
    last10="$(tail -10 "$HISTORY")"
    reversed="$(
        echo "$last10" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}'
    )"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        d="$(echo "$line" | jq -r '.delta' 2>/dev/null || echo '?')"
        r="$(echo "$line" | jq -r '.reason' 2>/dev/null || echo '?')"
        # truncate reason to 20 chars
        rshort="${r:0:20}"
        sign=""
        [[ "$d" =~ ^[0-9]+$ ]] && sign="+"
        recent_summary+="${sign}${d} ${rshort}, "
    done <<< "$reversed"
    recent_summary="${recent_summary%, }"
fi

echo "🍪 Cookie Balance: $balance"
[[ -n "$recent_summary" ]] && echo "Recent: $recent_summary"
echo "For full history, read: ~/.claude/cookie-gift/history.jsonl"
```

- [ ] **Step 3: Make it executable**

Run:
```bash
chmod +x ~/.claude/hooks/cookie-gift-session-start.sh
```

- [ ] **Step 4: Run it manually and verify output**

Run:
```bash
~/.claude/hooks/cookie-gift-session-start.sh
```

Expected output (with empty ledger):
```
🍪 Cookie Balance: 0
For full history, read: ~/.claude/cookie-gift/history.jsonl
```

If the ledger is non-empty (after running tests), expect a `Recent: …` line as well.

---

## Task 9: Register the hook in settings.json

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Inspect current settings.json**

Run:
```bash
jq '.hooks // {}' ~/.claude/settings.json
```

Note any existing `SessionStart` array. We will append (not replace).

- [ ] **Step 2: Back up settings.json**

Run:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d-%H%M%S)
```

- [ ] **Step 3: Add the SessionStart hook entry**

If `~/.claude/settings.json` already has a `hooks.SessionStart` array, add this object to it:

```json
{
  "command": "~/.claude/hooks/cookie-gift-session-start.sh",
  "description": "Inject 🍪 cookie balance + recent 10 entries into context"
}
```

If `hooks.SessionStart` does not exist, create it. Use `jq` for safe JSON manipulation:

```bash
jq '.hooks = (.hooks // {}) | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{"command":"~/.claude/hooks/cookie-gift-session-start.sh","description":"Inject 🍪 cookie balance + recent 10 entries into context"}])' \
    ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

- [ ] **Step 4: Validate JSON**

Run:
```bash
jq '.hooks.SessionStart' ~/.claude/settings.json
```

Expected: an array containing (at least) the new hook entry.

If invalid, restore from the backup created in Step 2.

---

## Task 10: Write the cookie-gift skill (SKILL.md)

**Files:**
- Create: `~/.claude/skills/cookie-gift/` directory
- Create: `~/.claude/skills/cookie-gift/SKILL.md`

- [ ] **Step 1: Create the skill directory**

Run:
```bash
mkdir -p ~/.claude/skills/cookie-gift
```

- [ ] **Step 2: Write SKILL.md**

Write file `~/.claude/skills/cookie-gift/SKILL.md`:

```markdown
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

쿠키 보상 시스템. 잔고는 ~/.claude/cookie-gift/balance.md, 전체 내역은
~/.claude/cookie-gift/history.jsonl 에 저장. 매 세션 시작 시
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
   - 1일 → 1시간, 1주(영업일 5일) → 5시간, 1개월(영업일 ~20일) → 20시간
3. **제안** (사용자 승인 필수):
   - 잘했을 때: `🍪 +3 받을게요? (이유: 브랜드 디자인 잘 잡음)`
   - 잘못했을 때: `🍪 -1 자진납부할게요 (이유: CSS overflow 미검증)`
4. 사용자 응답:
   - 승인 ("ㅇㅇ", "ok") → 그대로 실행
   - 조정 ("+5로", "1개만") → 조정 값으로 실행
   - 거부 ("아니") → 변동 없음
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
| ±5 | 메이저 릴리스 / 심각한 회귀 |

## 잔고가 음수일 때

음수 허용. 빚진 상태 그대로 표시되며 만회 동기로 작용.

## 전체 내역 조회

사용자가 "쿠키 내역", "전체 history", "더 보여줘" 등 요청 시:
```bash
cat ~/.claude/cookie-gift/history.jsonl
```
또는 jq로 필터/요약해서 보여줄 것.

## 직접 파일 편집 금지

`balance.md` 는 매 변동 때 재생성됨. 직접 수정 무의미.
모든 변동은 반드시 `log.sh` 통해서만.
```

- [ ] **Step 3: Verify**

Run:
```bash
ls ~/.claude/skills/cookie-gift/
head -5 ~/.claude/skills/cookie-gift/SKILL.md
```

Expected: SKILL.md present, frontmatter starts with `---` and `name: cookie-gift`.

---

## Task 11: Add time-scaling rule to global CLAUDE.md

**Files:**
- Modify: `~/.claude/CLAUDE.md`

- [ ] **Step 1: Back up CLAUDE.md**

Run:
```bash
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)
```

- [ ] **Step 2: Locate the "소통 방식" section**

Run:
```bash
grep -n "소통 방식" ~/.claude/CLAUDE.md
```

Expected: returns one line. The section is followed by 3-4 bullet items currently.

- [ ] **Step 3: Add the time-scaling bullet**

In `~/.claude/CLAUDE.md`, find:

```markdown
## 소통 방식
- 한국어로 대화, 코드 주석은 영어
- 간결하게. 설명보다 코드 우선
- 모르면 모른다고 말하기
```

Replace with:

```markdown
## 소통 방식
- 한국어로 대화, 코드 주석은 영어
- 간결하게. 설명보다 코드 우선
- 모르면 모른다고 말하기
- **시간 환산**: 시간 추정·응답 시 AI 기준으로 환산. **1 working day (human) = 1 hour (AI)**. 인간 시간 단위 그대로 쓰지 말 것. (예: 인간 1주 → AI 5시간, 인간 1개월 → AI 20시간 — 영업일 기준)
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -A 5 "소통 방식" ~/.claude/CLAUDE.md
```

Expected: the new bullet present.

---

## Task 12: End-to-end smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite one more time**

Run:
```bash
~/.claude/cookie-gift/test.sh
```

Expected: `Pass: 12  Fail: 0`.

- [ ] **Step 2: Reset the live ledger to empty**

Run:
```bash
: > ~/.claude/cookie-gift/history.jsonl
~/.claude/cookie-gift/log.sh 1 "smoke-test bootstrap" >/dev/null
~/.claude/cookie-gift/log.sh 2 "smoke-test add"
```

Expected: second command prints `🍪 Balance: 3 (+2)`.

- [ ] **Step 3: Verify balance.md regenerated**

Run:
```bash
cat ~/.claude/cookie-gift/balance.md
```

Expected: shows `Cookie Balance: **3**`, table with 2 rows (newest first), reasons "smoke-test add" and "smoke-test bootstrap".

- [ ] **Step 4: Run the SessionStart hook manually**

Run:
```bash
~/.claude/hooks/cookie-gift-session-start.sh
```

Expected:
```
🍪 Cookie Balance: 3
Recent: +2 smoke-test add, +1 smoke-test bootstrap
For full history, read: ~/.claude/cookie-gift/history.jsonl
```

- [ ] **Step 5: Reset ledger to clean state**

Run:
```bash
: > ~/.claude/cookie-gift/history.jsonl
cat > ~/.claude/cookie-gift/balance.md <<'EOF'
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: `~/.claude/cookie-gift/history.jsonl`
EOF
```

- [ ] **Step 6: Open a fresh Claude Code session and verify hook injection**

Manually start a new Claude Code session in a separate terminal and confirm that the system reminder contains `🍪 Cookie Balance: 0`. (This step requires a real session; document the result here for the user.)

- [ ] **Step 7: Verify settings.json is valid JSON**

Run:
```bash
jq . ~/.claude/settings.json > /dev/null && echo "OK"
```

Expected: `OK`.

---

## Done Criteria

- All 12 bash tests pass
- `log.sh` validates input, locks, appends, regenerates balance.md
- `balance.md` shows current balance + last 10 changes table
- `history.jsonl` is append-only single source of truth
- SessionStart hook prints compact summary
- Hook is registered in `~/.claude/settings.json`
- `cookie-gift` skill discoverable with proper description
- Global time-scaling rule added to `~/.claude/CLAUDE.md`
- Live smoke test (Task 12) confirms balance flows end-to-end
