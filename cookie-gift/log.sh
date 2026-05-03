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

[[ $# -ge 2 ]] || usage

DELTA="$1"
REASON="$2"

if ! [[ "$DELTA" =~ ^[+-]?[0-9]+$ ]]; then
    echo "Error: delta must be an integer" >&2
    exit 2
fi

DELTA="${DELTA#+}"

if [[ "$DELTA" -eq 0 ]]; then
    echo "Error: delta must be non-zero" >&2
    exit 2
fi

if [[ -z "$REASON" ]]; then
    echo "Error: reason must be non-empty" >&2
    exit 2
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "Error: 'flock' not found. Install util-linux (e.g., brew install util-linux)." >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' not found. Install jq (e.g., brew install jq)." >&2
    exit 2
fi

mkdir -p "$COOKIE_GIFT_DIR"
[[ -f "$HISTORY" ]] || : > "$HISTORY"

# Robust last-valid-balance read. Skips lines whose .balance doesn't parse
# as integer (corrupt-line resilience).
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

regenerate_balance_md() {
    local file="$1"
    local cur_bal="$2"
    local cur_ts="$3"

    local reversed
    reversed="$(tail -10 "$file" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}')"

    {
        echo "# 🍪 Cookie Balance: **$cur_bal**"
        echo ""
        echo "> Updated: $cur_ts"
        echo ""
        echo "## Recent 10 changes"
        if [[ -z "$reversed" ]]; then
            echo "_No changes yet._"
        else
            echo "| Time | Δ | Balance | Reason |"
            echo "|------|---|---------|--------|"
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local t d b r short_t md_d
                t="$(echo "$line" | jq -r '.ts' 2>/dev/null || echo '')"
                d="$(echo "$line" | jq -r '.delta' 2>/dev/null || echo '')"
                b="$(echo "$line" | jq -r '.balance' 2>/dev/null || echo '')"
                r="$(echo "$line" | jq -r '.reason' 2>/dev/null || echo '')"
                if [[ -z "$t" || -z "$d" || -z "$b" ]]; then
                    continue
                fi
                # Extract MM-DD HH:MM from ISO ts like 2026-05-03T14:22:13+00:00
                short_t="$(echo "$t" | sed -E 's/^[0-9]{4}-([0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}).*$/\1 \2/')"
                if [[ "$d" -gt 0 ]]; then
                    md_d="+$d"
                else
                    md_d="$d"
                fi
                printf '| %s | %s | %s | %s |\n' "$short_t" "$md_d" "$b" "$r"
            done <<< "$reversed"
        fi
        echo ""
        echo "For full history, load: \`~/.claude/cookie-gift/history.jsonl\`"
    } > "$BALANCE"
}

# --- Critical section: read previous balance, append, regenerate ---
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
    '{ts:$ts,delta:$delta,balance:$balance,reason:$reason}')" || {
    echo "Error: failed to construct JSON entry" >&2
    flock -u 9
    exec 9>&-
    exit 2
}

if [[ -z "$new_line" ]]; then
    echo "Error: jq produced empty output" >&2
    flock -u 9
    exec 9>&-
    exit 2
fi

echo "$new_line" >> "$HISTORY"

regenerate_balance_md "$HISTORY" "$new_balance" "$ts"

flock -u 9
exec 9>&-

if [[ "$DELTA" -ge 0 ]]; then
    echo "🍪 Balance: $new_balance (+$DELTA)"
else
    echo "🍪 Balance: $new_balance ($DELTA)"
fi
exit 0
