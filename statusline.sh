#!/bin/bash
input=$(cat)

DATA_FILE="$HOME/.claude/statusline_data.json"
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
    echo '{"days":{}}' > "$DATA_FILE"
fi

DATA=$(cat "$DATA_FILE")

# Update today's session cost
DATA=$(echo "$DATA" | jq --arg date "$TODAY" --arg sid "$SESSION_ID" --argjson cost "$SESSION_COST" '
    .days[$date].sessions[$sid] = $cost |
    .days[$date].total = ([.days[$date].sessions[]] | add // 0)
')

# Save data
echo "$DATA" > "$DATA_FILE"

# Calculate daily, weekly, monthly costs
DAILY_COST=$(echo "$DATA" | jq --arg date "$TODAY" '.days[$date].total // 0')

# Weekly: sum last 7 days
WEEKLY_COST=0
for i in {0..6}; do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    DAY_COST=$(echo "$DATA" | jq -r --arg d "$DATE" '.days[$d].total // 0')
    WEEKLY_COST=$(echo "$WEEKLY_COST + $DAY_COST" | bc)
done

# Monthly: sum last 30 days
MONTHLY_COST=0
for i in {0..29}; do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    DAY_COST=$(echo "$DATA" | jq -r --arg d "$DATE" '.days[$d].total // 0')
    MONTHLY_COST=$(echo "$MONTHLY_COST + $DAY_COST" | bc)
done

# Format costs
SESSION_FMT=$(printf "%.2f" "$SESSION_COST")
DAILY_FMT=$(printf "%.0f" "$DAILY_COST")
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

# 💰 Costs: cur / 24h / 7d / 30d
OUTPUT+=" ${DIM}💰 cur${RESET} ${YELLOW}\$${SESSION_FMT}${RESET} ${DIM}· 24h${RESET} ${MAGENTA}\$${DAILY_FMT}${RESET} ${DIM}· 7d${RESET} ${MAGENTA}\$${WEEKLY_FMT}${RESET} ${DIM}· 30d${RESET} ${MAGENTA}\$${MONTHLY_FMT}${RESET}"

# 🕐 Time
OUTPUT+=" ${DIM}🕐 ${CURRENT_TIME}${RESET}"

echo -e "$OUTPUT"
