#!/usr/bin/env bash
# Test suite for ~/.claude/cookie-gift/log.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_SH="$SCRIPT_DIR/log.sh"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local fn="$2"
    local tmp
    tmp="$(mktemp -d)"
    export COOKIE_GIFT_DIR="$tmp"
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

# --- argument validation ---

test_rejects_missing_args() {
    local out
    out="$("$LOG_SH" 2>&1)" && return 1
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

# --- balance accumulation ---

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

# --- balance.md regeneration ---

test_balance_md_shows_current_balance() {
    "$LOG_SH" 7 "for md" >/dev/null || return 1
    grep -q "Cookie Balance: \*\*7\*\*" "$COOKIE_GIFT_DIR/balance.md" || return 1
}

test_balance_md_shows_recent_10_max() {
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        "$LOG_SH" 1 "entry $i" >/dev/null || return 1
    done
    # Count data rows (start with "| " followed by a digit, time column)
    local rows
    rows="$(grep -cE '^\| [0-9]' "$COOKIE_GIFT_DIR/balance.md" || true)"
    [[ "$rows" -eq 10 ]] || { echo "    expected 10 rows, got $rows"; return 1; }
    grep -q "entry 12" "$COOKIE_GIFT_DIR/balance.md" || return 1
    ! grep -q "entry 1\b"  "$COOKIE_GIFT_DIR/balance.md" || return 1
}

# --- concurrency ---

test_concurrent_writes_no_loss() {
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

# --- corrupt-line resilience ---

test_skips_corrupt_lines() {
    cat > "$COOKIE_GIFT_DIR/history.jsonl" <<EOF
{"ts":"2026-05-03T00:00:00+00:00","delta":5,"balance":5,"reason":"a"}
this is not json
{"ts":"2026-05-03T00:01:00+00:00","delta":-2,"balance":3,"reason":"b"}
EOF

    "$LOG_SH" 1 "after corrupt" >/dev/null || return 1
    # log.sh should compute prev_balance=3 (skipping corrupt line), new=4.
    # Check balance.md (the user-visible source of truth) shows 4.
    grep -q "Cookie Balance: \*\*4\*\*" "$COOKIE_GIFT_DIR/balance.md" \
        || { echo "    balance.md does not show **4**"; return 1; }
}

echo "Running cookie-gift tests..."

run_test "rejects missing args"                       test_rejects_missing_args
run_test "rejects zero delta"                         test_rejects_zero_delta
run_test "rejects non-integer delta"                  test_rejects_non_integer_delta
run_test "rejects empty reason"                       test_rejects_empty_reason
run_test "first entry balance is delta"               test_first_entry_balance_is_delta
run_test "accumulates deltas"                         test_accumulates_deltas
run_test "allows negative balance"                    test_allows_negative_balance
run_test "jsonl has required fields"                  test_jsonl_has_required_fields
run_test "balance.md shows current balance"           test_balance_md_shows_current_balance
run_test "balance.md keeps recent 10 max"             test_balance_md_shows_recent_10_max
run_test "concurrent writes have no loss"             test_concurrent_writes_no_loss
run_test "skips corrupt lines when computing balance" test_skips_corrupt_lines

echo ""
echo "Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
