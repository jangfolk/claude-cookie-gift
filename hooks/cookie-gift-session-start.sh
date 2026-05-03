#!/usr/bin/env bash
# SessionStart hook: emit cookie balance summary to stdout
# Runs when Claude Code starts a session

set -u

COOKIE_GIFT_DIR="${COOKIE_GIFT_DIR:-$HOME/.claude/cookie-gift}"
HISTORY="$COOKIE_GIFT_DIR/history.jsonl"
BALANCE="$COOKIE_GIFT_DIR/balance.md"

# Init if missing
if [[ ! -d "$COOKIE_GIFT_DIR" ]]; then
    mkdir -p "$COOKIE_GIFT_DIR"
    : > "$HISTORY"
    cat > "$BALANCE" <<'EOF'
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: `~/.claude/cookie-gift/history.jsonl`
EOF
fi

# Ensure files exist
[[ -f "$HISTORY" ]] || : > "$HISTORY"
[[ -f "$BALANCE" ]] || cat > "$BALANCE" <<'EOF'
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: `~/.claude/cookie-gift/history.jsonl`
EOF

# Compute current balance from last valid line
compute_balance() {
    local file="$1"
    local bal=0

    if [[ ! -s "$file" ]]; then
        echo "$bal"
        return 0
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "$bal"
        return 0
    fi

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

# Build recent summary: up to 10 entries, newest first
# Format: {sign}{delta} {reason-truncated-to-20-chars}
build_recent_summary() {
    local file="$1"

    if [[ ! -s "$file" ]]; then
        return 0
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        return 0
    fi

    local recent_lines
    recent_lines="$(tail -10 "$file" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}')"

    local summary_parts=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local delta reason
        delta="$(echo "$line" | jq -r '.delta' 2>/dev/null || true)"
        reason="$(echo "$line" | jq -r '.reason' 2>/dev/null || true)"

        if [[ -z "$delta" ]] || [[ -z "$reason" ]]; then
            continue
        fi

        # Format delta with sign
        local delta_str
        if [[ "$delta" -ge 0 ]]; then
            delta_str="+$delta"
        else
            delta_str="$delta"
        fi

        # Truncate reason to 20 chars
        local reason_truncated
        reason_truncated="${reason:0:20}"

        summary_parts+=("$delta_str $reason_truncated")
    done <<< "$recent_lines"

    if [[ ${#summary_parts[@]} -gt 0 ]]; then
        local joined=""
        local part
        for part in "${summary_parts[@]}"; do
            if [[ -z "$joined" ]]; then
                joined="$part"
            else
                joined="$joined, $part"
            fi
        done
        echo "$joined"
    fi
}

# Main output
balance=$(compute_balance "$HISTORY")
echo "🍪 Cookie Balance: $balance"

recent=$(build_recent_summary "$HISTORY")
if [[ -n "$recent" ]]; then
    echo "Recent: $recent"
fi

echo "For full history, read: ~/.claude/cookie-gift/history.jsonl"

exit 0
