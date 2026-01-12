#!/bin/bash
input=$(cat)

DATA_FILE="$HOME/.claude/statusline_data.json"
STATS_CACHE="$HOME/.claude/stats-cache.json"
TODAY=$(date +%Y-%m-%d)
CURRENT_TIME=$(date +%H:%M)

# Colors
RESET="\033[0m"
BOLD="\033[1m"
BLINK="\033[5m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"
BLUE="\033[34m"
DIM="\033[90m"

# Parse input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
SESSION_COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
USAGE=$(echo "$input" | jq '.context_window.current_usage // null')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // ""')

# Get project name from path
if [ -n "$PROJECT_DIR" ]; then
    PROJECT_NAME=$(basename "$PROJECT_DIR")
else
    PROJECT_NAME=""
fi

# Get git branch
GIT_BRANCH=""
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/.git" ]; then
    GIT_BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null)
elif [ -d ".git" ]; then
    GIT_BRANCH=$(git branch --show-current 2>/dev/null)
fi

# Context calculation
if [ "$USAGE" != "null" ] && [ "$CONTEXT_SIZE" != "0" ]; then
    CURRENT=$(echo "$USAGE" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
    REMAINING=$((CONTEXT_SIZE - CURRENT))
    PERCENT=$((REMAINING * 100 / CONTEXT_SIZE))
else
    PERCENT=100
fi

# Progress bar (10 chars)
FILLED=$((PERCENT / 10))
EMPTY=$((10 - FILLED))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# Traffic light color + critical effects
if [ "$PERCENT" -gt 50 ]; then
    CTX_COLOR="$GREEN"
    CTX_STYLE=""
elif [ "$PERCENT" -gt 25 ]; then
    CTX_COLOR="$YELLOW"
    CTX_STYLE=""
elif [ "$PERCENT" -gt 10 ]; then
    CTX_COLOR="$RED"
    CTX_STYLE="$BOLD"
else
    # Critical: bold + blink
    CTX_COLOR="$RED"
    CTX_STYLE="${BOLD}${BLINK}"
fi

# ===== COST TRACKING =====
# Initialize/load data file
if [ ! -f "$DATA_FILE" ]; then
    echo '{"days":{},"history":{}}' > "$DATA_FILE"
fi

DATA=$(cat "$DATA_FILE")

# Ensure history key exists (for upgrades from older versions)
DATA=$(echo "$DATA" | jq 'if .history == null then .history = {} else . end')

# Check if we've seen this session today - if not, record baseline
# Baseline = session cost when first seen today (accounts for sessions spanning midnight)
BASELINE=$(echo "$DATA" | jq -r --arg date "$TODAY" --arg sid "$SESSION_ID" '.days[$date].baselines[$sid] // "null"')

if [ "$BASELINE" = "null" ]; then
    # First time seeing this session today - current cost becomes baseline
    DATA=$(echo "$DATA" | jq --arg date "$TODAY" --arg sid "$SESSION_ID" --argjson cost "$SESSION_COST" '
        .days[$date].baselines[$sid] = $cost
    ')
    BASELINE=$SESSION_COST
fi

# Today's contribution from this session = current cost - baseline
SESSION_TODAY=$(echo "$SESSION_COST - $BASELINE" | bc)

# Update session's contribution for today and recalculate total
DATA=$(echo "$DATA" | jq --arg date "$TODAY" --arg sid "$SESSION_ID" --argjson contrib "$SESSION_TODAY" '
    .days[$date].sessions[$sid] = $contrib |
    .days[$date].total = ([.days[$date].sessions[]] | add // 0)
')

# Save data
echo "$DATA" > "$DATA_FILE"

# Calculate daily cost from session tracking
DAILY_COST=$(echo "$DATA" | jq --arg date "$TODAY" '.days[$date].total // 0')

# ===== HISTORICAL COSTS FROM STATS-CACHE =====
# Calculate cost from token usage in stats-cache.json
# Pricing per 1M tokens (output): Opus=$75, Sonnet=$15, Haiku=$4
calc_cost_from_stats() {
    local target_date="$1"
    if [ ! -f "$STATS_CACHE" ]; then
        echo "0"
        return
    fi

    # Get tokens for this date from dailyModelTokens array
    local day_data=$(jq -r --arg d "$target_date" '
        .dailyModelTokens[] | select(.date == $d) | .tokensByModel // {}
    ' "$STATS_CACHE" 2>/dev/null)

    if [ -z "$day_data" ] || [ "$day_data" = "{}" ]; then
        echo "0"
        return
    fi

    # Calculate cost based on model (tokens are output tokens, price per 1M)
    local cost=$(echo "$day_data" | jq '
        ((.["claude-opus-4-5-20251101"] // 0) * 75 / 1000000) +
        ((.["claude-sonnet-4-5-20250929"] // 0) * 15 / 1000000) +
        ((.["claude-haiku-4-5-20251001"] // 0) * 4 / 1000000)
    ')
    echo "$cost"
}

# Archive recent days from stats-cache to our persistent history
# This runs on each invocation but only writes if there's new data
HISTORY_UPDATED=false
for i in {1..35}; do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    # Check if this date is already in our history
    EXISTING=$(echo "$DATA" | jq -r --arg d "$DATE" '.history[$d] // "null"')
    if [ "$EXISTING" = "null" ]; then
        # Not in history - try to get from stats-cache
        COST=$(calc_cost_from_stats "$DATE")
        if [ "$COST" != "0" ] && [ -n "$COST" ]; then
            DATA=$(echo "$DATA" | jq --arg d "$DATE" --argjson c "$COST" '.history[$d] = $c')
            HISTORY_UPDATED=true
        fi
    fi
done

# Save if history was updated
if [ "$HISTORY_UPDATED" = true ]; then
    echo "$DATA" > "$DATA_FILE"
fi

# Get historical cost - first check our history, then fall back to stats-cache
get_historical_cost() {
    local target_date="$1"
    # First check our persistent history
    local cost=$(echo "$DATA" | jq -r --arg d "$target_date" '.history[$d] // "null"')
    if [ "$cost" != "null" ]; then
        echo "$cost"
        return
    fi
    # Fall back to stats-cache for recent days not yet archived
    calc_cost_from_stats "$target_date"
}

# Weekly: Calendar week (Monday-Sunday)
# Find days since last Monday (0=Mon, 1=Tue, ..., 6=Sun)
DAY_OF_WEEK=$(date +%u)  # 1=Mon, 7=Sun
DAYS_SINCE_MONDAY=$((DAY_OF_WEEK - 1))

WEEKLY_COST=$DAILY_COST
for ((i=1; i<=DAYS_SINCE_MONDAY; i++)); do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    DAY_COST=$(get_historical_cost "$DATE")
    WEEKLY_COST=$(echo "$WEEKLY_COST + $DAY_COST" | bc)
done

# Monthly: Calendar month (1st to today)
DAY_OF_MONTH=$(date +%d | sed 's/^0//')  # Remove leading zero
DAYS_SINCE_FIRST=$((DAY_OF_MONTH - 1))

MONTHLY_COST=$DAILY_COST
for ((i=1; i<=DAYS_SINCE_FIRST; i++)); do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    DAY_COST=$(get_historical_cost "$DATE")
    MONTHLY_COST=$(echo "$MONTHLY_COST + $DAY_COST" | bc)
done

# Yearly: Calendar year (Jan 1 to today)
YEAR_START=$(date +%Y)-01-01
YEARLY_HISTORY=$(echo "$DATA" | jq --arg cutoff "$YEAR_START" '
    [.history | to_entries[] | select(.key >= $cutoff) | .value] | add // 0
')
YEARLY_COST=$(echo "$DAILY_COST + $YEARLY_HISTORY" | bc)

# Format costs
SESSION_FMT=$(printf "%.2f" "$SESSION_COST")
DAILY_FMT=$(printf "%.0f" "$DAILY_COST")
YEARLY_FMT=$(printf "%.0f" "$YEARLY_COST")
WEEKLY_FMT=$(printf "%.0f" "$WEEKLY_COST")
MONTHLY_FMT=$(printf "%.0f" "$MONTHLY_COST")

# ===== BUILD OUTPUT =====
OUTPUT=""

# 🤖 Model
OUTPUT+="${CYAN}🤖 ${MODEL}${RESET}"

# Progress bar + percentage (context)
OUTPUT+=" ${DIM}[${RESET}${CTX_STYLE}${CTX_COLOR}${BAR}${RESET}${DIM}]${RESET} ${CTX_STYLE}${CTX_COLOR}${PERCENT}%${RESET}"

# 📁 Project name (if available)
if [ -n "$PROJECT_NAME" ]; then
    OUTPUT+=" ${BLUE}📁 ${PROJECT_NAME}${RESET}"
fi

# 🌿 Git branch (if available)
if [ -n "$GIT_BRANCH" ]; then
    OUTPUT+=" ${GREEN}🌿 ${GIT_BRANCH}${RESET}"
fi

# 💰 Costs: s=session, d=day, w=week, m=month, y=year
OUTPUT+=" ${DIM}💰 s${RESET} ${YELLOW}\$${SESSION_FMT}${RESET} ${DIM}· d${RESET} ${MAGENTA}\$${DAILY_FMT}${RESET} ${DIM}· w${RESET} ${MAGENTA}\$${WEEKLY_FMT}${RESET} ${DIM}· m${RESET} ${MAGENTA}\$${MONTHLY_FMT}${RESET} ${DIM}· y${RESET} ${MAGENTA}\$${YEARLY_FMT}${RESET}"

# 🕐 Time
OUTPUT+=" ${DIM}🕐 ${CURRENT_TIME}${RESET}"

echo -e "$OUTPUT"
