#!/usr/bin/env bash
# install.sh — install cookie-gift into ~/.claude/
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "🍪 cookie-gift installer"
echo "  source: $REPO_DIR"
echo "  target: $CLAUDE_DIR"
echo ""

# --- prereqs ---
missing=()
command -v jq    >/dev/null 2>&1 || missing+=("jq")
command -v flock >/dev/null 2>&1 || missing+=("flock")
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "❌ Missing required tools: ${missing[*]}"
    echo "   On macOS: brew install ${missing[*]}"
    echo "   (flock comes from util-linux: brew install util-linux)"
    exit 1
fi

if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "❌ $CLAUDE_DIR does not exist. Is Claude Code installed?"
    exit 1
fi

# --- copy files ---
mkdir -p "$CLAUDE_DIR/cookie-gift"
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/skills/cookie-gift"

cp "$REPO_DIR/cookie-gift/log.sh"  "$CLAUDE_DIR/cookie-gift/log.sh"
cp "$REPO_DIR/cookie-gift/test.sh" "$CLAUDE_DIR/cookie-gift/test.sh"
chmod +x "$CLAUDE_DIR/cookie-gift/log.sh" "$CLAUDE_DIR/cookie-gift/test.sh"

cp "$REPO_DIR/hooks/cookie-gift-session-start.sh" \
   "$CLAUDE_DIR/hooks/cookie-gift-session-start.sh"
chmod +x "$CLAUDE_DIR/hooks/cookie-gift-session-start.sh"

cp "$REPO_DIR/skills/cookie-gift/SKILL.md" \
   "$CLAUDE_DIR/skills/cookie-gift/SKILL.md"

echo "✅ scripts and skill installed"

# --- initialize ledger if missing ---
HISTORY="$CLAUDE_DIR/cookie-gift/history.jsonl"
BALANCE="$CLAUDE_DIR/cookie-gift/balance.md"

if [[ ! -f "$HISTORY" ]]; then
    : > "$HISTORY"
    echo "✅ initialized empty history.jsonl"
fi
if [[ ! -f "$BALANCE" ]]; then
    cat > "$BALANCE" <<'EOF'
# 🍪 Cookie Balance: **0**

> Updated: (none yet)

## Recent 10 changes
_No changes yet._

For full history, load: `~/.claude/cookie-gift/history.jsonl`
EOF
    echo "✅ initialized balance.md (balance 0)"
fi

# --- register SessionStart hook in settings.json ---
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD='~/.claude/hooks/cookie-gift-session-start.sh'

if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
    echo "✅ created empty settings.json"
fi

if jq -e --arg cmd "$HOOK_CMD" '
    [.. | objects | select(.command == $cmd)] | length > 0
' "$SETTINGS" > /dev/null 2>&1; then
    echo "ℹ️  hook already registered in settings.json — skipping"
else
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
    jq --arg cmd "$HOOK_CMD" '
        .hooks = (.hooks // {})
        | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{
            "matcher": "*",
            "hooks": [{"type": "command", "command": $cmd}]
        }])
    ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "✅ hook registered in settings.json (backup saved)"
fi

# --- offer time-scaling rule for CLAUDE.md ---
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
RULE='- **Time scaling**: when estimating or reporting durations, convert to AI scale. **1 working day (human) = 1 hour (AI)**. Do not parrot human timelines unchanged (e.g. 1 human week → 5 AI hours, 1 human month → 20 AI hours — working days only).'

if [[ -f "$CLAUDE_MD" ]] && grep -qF "1 working day (human) = 1 hour (AI)" "$CLAUDE_MD"; then
    echo "ℹ️  time-scaling rule already present in CLAUDE.md — skipping"
else
    echo ""
    echo "Optional: append the AI-time-scaling rule to ~/.claude/CLAUDE.md?"
    echo "  Rule: 1 working day (human) = 1 hour (AI)"
    read -r -p "  [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        if [[ ! -f "$CLAUDE_MD" ]]; then
            cat > "$CLAUDE_MD" <<EOF
# Personal Claude Code preferences

## Communication
$RULE
EOF
        else
            printf '\n%s\n' "$RULE" >> "$CLAUDE_MD"
        fi
        echo "✅ rule appended to CLAUDE.md"
    else
        echo "ℹ️  skipped CLAUDE.md modification"
    fi
fi

# --- run tests ---
echo ""
echo "Running tests…"
if "$CLAUDE_DIR/cookie-gift/test.sh"; then
    echo ""
    echo "🍪 Install complete. Start a new Claude Code session — you should see"
    echo "   🍪 Cookie Balance: <N> at session start."
else
    echo "❌ Tests failed. See output above."
    exit 1
fi
