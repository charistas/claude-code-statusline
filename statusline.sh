#!/bin/bash
#
# Claude Code Status Bar - Cost Tracking
#
# Calculates costs by parsing JSONL transcript files directly from:
#   ~/.claude/projects/*/*.jsonl
#
# Pricing (Claude 4.5, per MTok):
#   Opus:   $5 input, $25 output, $0.50 cache read, $6.25 cache write
#   Sonnet: $3 input, $15 output, $0.30 cache read, $3.75 cache write
#   Haiku:  $1 input, $5 output,  $0.10 cache read, $1.25 cache write
#
# Past days are cached in ~/.claude/statusline_data.json for performance.
#

# ===== CONFIGURATION =====
export TZ="Europe/Athens"  # Explicit timezone for consistent date boundaries

DATA_FILE="$HOME/.claude/statusline_data.json"
LOCK_FILE="${DATA_FILE}.lock"
CLAUDE_PROJECTS="$HOME/.claude/projects"

# ===== DEPENDENCY CHECKS =====
for cmd in jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed" >&2
        exit 1
    fi
done

# Check for flock (may not exist on all systems)
HAS_FLOCK=false
if command -v flock &>/dev/null; then
    HAS_FLOCK=true
fi

# ===== FILE LOCKING =====
# Acquire exclusive lock to prevent race conditions with parallel instances
if [ "$HAS_FLOCK" = true ]; then
    exec 200>"$LOCK_FILE"
    flock -x 200
    # Lock automatically released when script exits
fi

# ===== ATOMIC WRITE FUNCTION =====
write_json_file() {
    local file="$1"
    local content="$2"
    local temp_file
    temp_file=$(mktemp) || { echo "Error: Failed to create temp file" >&2; return 1; }
    if echo "$content" > "$temp_file"; then
        mv "$temp_file" "$file"
    else
        rm -f "$temp_file"
        echo "Error: Failed to write to temp file" >&2
        return 1
    fi
}

# ===== READ INPUT =====
input=$(cat)

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
TOTAL_INPUT=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUTPUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
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

# ===== CONTEXT TRACKING & RESET DETECTION =====
# Claude Code reports cumulative session tokens, not current context window tokens.
# We track a "baseline" to calculate effective context usage since last reset.
# Two reset conditions exist for different scenarios:
#   1. Token DECREASE: After auto-compact, tokens drop. The new count IS actual context.
#      → Reset baseline to 0 (trust the new token count)
#   2. IMPOSSIBLE STATE: Effective tokens > context size. This can't happen in reality.
#      → Reset baseline to CURRENT_TOKENS (assume fresh start, like /clear)

CTX_TRACK_FILE="$HOME/.claude/ctx_track.json"
if [ -f "$CTX_TRACK_FILE" ]; then
    CTX_DATA=$(cat "$CTX_TRACK_FILE" 2>/dev/null)
    if [ -z "$CTX_DATA" ] || ! echo "$CTX_DATA" | jq empty 2>/dev/null; then
        CTX_DATA='{}'
    fi
else
    CTX_DATA='{}'
fi

# Clean up sessions older than 7 days to prevent unbounded file growth
CUTOFF_DATE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "-7 days" +%Y-%m-%d 2>/dev/null)
if [ -n "$CUTOFF_DATE" ]; then
    CTX_DATA=$(echo "$CTX_DATA" | jq --arg cutoff "$CUTOFF_DATE" '
        with_entries(select(.value.updated == null or .value.updated >= $cutoff))
    ')
fi

# Get previous state for this session
PREV_TOKENS=$(echo "$CTX_DATA" | jq -r --arg sid "$SESSION_ID" '.[$sid].last_tokens // 0')
CTX_BASELINE=$(echo "$CTX_DATA" | jq -r --arg sid "$SESSION_ID" '.[$sid].baseline // 0')
CURRENT_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))

# Reset condition 1: Token DECREASE detected (auto-compact or /compact)
# When Claude compacts context, the new token count represents actual usage.
# Setting baseline=0 means: trust the new token count as real context usage.
if [ "$PREV_TOKENS" -gt 0 ] && [ "$CURRENT_TOKENS" -lt "$PREV_TOKENS" ]; then
    CTX_BASELINE=0
fi

# Reset condition 2: IMPOSSIBLE STATE (effective > context size)
# This catches /clear scenarios where cumulative tokens stay high but context was cleared.
# Setting baseline=CURRENT_TOKENS means: start fresh, effective becomes 0.
EFFECTIVE_CHECK=$((CURRENT_TOKENS - CTX_BASELINE))
if [ "$CONTEXT_SIZE" -gt 0 ] && [ "$EFFECTIVE_CHECK" -gt "$CONTEXT_SIZE" ]; then
    CTX_BASELINE=$CURRENT_TOKENS
fi

# Calculate effective tokens (actual context usage since last reset)
EFFECTIVE_TOKENS=$((CURRENT_TOKENS - CTX_BASELINE))
[ "$EFFECTIVE_TOKENS" -lt 0 ] && EFFECTIVE_TOKENS=0

# Update tracking state with timestamp for cleanup (atomic write)
CTX_DATA=$(echo "$CTX_DATA" | jq --arg sid "$SESSION_ID" \
    --argjson tokens "$CURRENT_TOKENS" \
    --argjson baseline "$CTX_BASELINE" \
    --arg today "$TODAY" \
    '.[$sid] = {last_tokens: $tokens, baseline: $baseline, updated: $today}')
echo "$CTX_DATA" > "$CTX_TRACK_FILE.tmp" && mv "$CTX_TRACK_FILE.tmp" "$CTX_TRACK_FILE"

# Context calculation using effective tokens (adjusted for compaction)
if [ "$CONTEXT_SIZE" != "0" ]; then
    REMAINING=$((CONTEXT_SIZE - EFFECTIVE_TOKENS))
    PERCENT=$((REMAINING * 100 / CONTEXT_SIZE))
    # Clamp to valid range
    [ "$PERCENT" -lt 0 ] && PERCENT=0
    [ "$PERCENT" -gt 100 ] && PERCENT=100
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
# Initialize/load data file with JSON validation
if [ -f "$DATA_FILE" ]; then
    DATA=$(cat "$DATA_FILE")
    # Validate JSON - reinitialize if corrupt or empty
    if [ -z "$DATA" ] || ! echo "$DATA" | jq empty 2>/dev/null; then
        DATA='{"days":{},"history":{}}'
    fi
else
    DATA='{"days":{},"history":{}}'
fi

# Ensure history key exists (for upgrades from older versions)
DATA=$(echo "$DATA" | jq 'if .history == null then .history = {} else . end')

# Track if we need to save history updates
HISTORY_UPDATED=false

# ===== JSONL TRANSCRIPT PARSING =====
# jq cost calculation logic (extracted to avoid duplication)
# Groups by requestId and takes MAX of each token type (streaming responses have cumulative counts)
# Deduplicates by uuid since same entries can appear in multiple JSONL files
JQ_COST_CALC='
    # Claude 4.5 pricing per million tokens
    def opus_cost: { input: 5, output: 25, cache_read: 0.5, cache_write: 6.25 };
    def sonnet_cost: { input: 3, output: 15, cache_read: 0.3, cache_write: 3.75 };
    def haiku_cost: { input: 1, output: 5, cache_read: 0.1, cache_write: 1.25 };

    def get_pricing($model):
        if ($model | test("opus"; "i")) then opus_cost
        elif ($model | test("sonnet"; "i")) then sonnet_cost
        elif ($model | test("haiku"; "i")) then haiku_cost
        else sonnet_cost
        end;

    # Filter valid entries with usage, deduplicate by uuid
    [.[] | select(
        .message.usage and
        (.isSidechain | not) and
        (.isApiErrorMessage | not)
    )] | unique_by(.uuid) |

    # Group by requestId (streaming responses have cumulative token counts)
    # Take MAX of each token type per request, then calculate cost
    group_by(.requestId // .uuid) |
    map(
        # Get model from first entry in group
        (.[0].message.model // "claude-sonnet-4-5-20250929") as $model |
        get_pricing($model) as $price |
        # Take max of each token type across all entries in this request
        {
            input: ([.[].message.usage.input_tokens // 0] | max),
            output: ([.[].message.usage.output_tokens // 0] | max),
            cache_read: ([.[].message.usage.cache_read_input_tokens // 0] | max),
            cache_write: ([.[].message.usage.cache_creation_input_tokens // 0] | max)
        } as $tokens |
        (
            ($tokens.input * $price.input) +
            ($tokens.output * $price.output) +
            ($tokens.cache_read * $price.cache_read) +
            ($tokens.cache_write * $price.cache_write)
        ) / 1000000
    ) | add // 0
'

# Calculate accurate daily cost from JSONL transcripts
# Returns cost in USD for the given date
calc_daily_cost_from_jsonl() {
    local target_date="$1"

    if [ ! -d "$CLAUDE_PROJECTS" ]; then
        echo "0"
        return
    fi

    # Pre-filter with grep for target date (much faster than jq filtering all data)
    # Use jq -R to read as raw strings, then parse with try/catch to skip malformed lines
    local result
    local jq_filter='[inputs | try fromjson catch empty]'
    if [ "$target_date" = "$TODAY" ]; then
        # For today: only scan recently modified files, grep for date, then jq
        result=$(find "$CLAUDE_PROJECTS" -name "*.jsonl" -type f -mtime 0 2>/dev/null \
            -exec grep -h "\"timestamp\":\"${target_date}T" {} + 2>/dev/null | \
            jq -Rn "$jq_filter" 2>/dev/null | jq "$JQ_COST_CALC" 2>/dev/null)
    else
        # For past days: scan all files (but results are cached so only runs once)
        result=$(find "$CLAUDE_PROJECTS" -name "*.jsonl" -type f 2>/dev/null \
            -exec grep -h "\"timestamp\":\"${target_date}T" {} + 2>/dev/null | \
            jq -Rn "$jq_filter" 2>/dev/null | jq "$JQ_COST_CALC" 2>/dev/null)
    fi

    echo "${result:-0}"
}

# Get cached cost for a date from history
get_cached_cost() {
    local target_date="$1"
    echo "$DATA" | jq -r --arg d "$target_date" '.history[$d] // "0"'
}

# Pre-cache costs for a range of past days (call before loops)
precache_costs() {
    local days_back="$1"

    for ((i=1; i<=days_back; i++)); do
        local date
        date=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
        [ -z "$date" ] && continue

        # Check if already cached
        local cached
        cached=$(echo "$DATA" | jq -r --arg d "$date" '.history[$d] // "null"')

        if [ "$cached" = "null" ]; then
            # Not cached - calculate and cache it (including zero-cost days to avoid re-scanning)
            local cost
            cost=$(calc_daily_cost_from_jsonl "$date")

            # Validate cost is a valid number before storing
            if [[ "$cost" =~ ^[0-9]*\.?[0-9]+$ ]]; then
                DATA=$(echo "$DATA" | jq --arg d "$date" --argjson c "${cost}" '.history[$d] = $c')
                HISTORY_UPDATED=true
            fi
        fi
    done
}

# ===== SESSION BASELINE TRACKING =====
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

# Save session data using atomic write
write_json_file "$DATA_FILE" "$DATA"

# ===== CALCULATE COSTS =====
# Daily cost (today) - calculate fresh from JSONL for accuracy
DAILY_COST=$(calc_daily_cost_from_jsonl "$TODAY")

# Weekly: Calendar week (Monday-Sunday)
DAY_OF_WEEK=$(date +%u)  # 1=Mon, 7=Sun
DAYS_SINCE_MONDAY=$((DAY_OF_WEEK - 1))

# Monthly: Calendar month (1st to today)
DAY_OF_MONTH=$(date +%d | sed 's/^0//')  # Remove leading zero
DAYS_SINCE_FIRST=$((DAY_OF_MONTH - 1))

# Pre-cache all needed past days (max of week or month lookback)
MAX_LOOKBACK=$DAYS_SINCE_FIRST
[ "$DAYS_SINCE_MONDAY" -gt "$MAX_LOOKBACK" ] && MAX_LOOKBACK=$DAYS_SINCE_MONDAY
precache_costs "$MAX_LOOKBACK"

# Calculate weekly cost
WEEKLY_COST=$DAILY_COST
for ((i=1; i<=DAYS_SINCE_MONDAY; i++)); do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    [ -z "$DATE" ] && continue
    DAY_COST=$(get_cached_cost "$DATE")
    WEEKLY_COST=$(echo "$WEEKLY_COST + $DAY_COST" | bc)
done

# Calculate monthly cost
MONTHLY_COST=$DAILY_COST
for ((i=1; i<=DAYS_SINCE_FIRST; i++)); do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-${i} days" +%Y-%m-%d 2>/dev/null)
    [ -z "$DATE" ] && continue
    DAY_COST=$(get_cached_cost "$DATE")
    MONTHLY_COST=$(echo "$MONTHLY_COST + $DAY_COST" | bc)
done

# Yearly: Sum from history (excluding today) + today's cost
YEAR_START="${TODAY%%-*}-01-01"
YEARLY_HISTORY=$(echo "$DATA" | jq --arg cutoff "$YEAR_START" --arg today "$TODAY" '
    [.history | to_entries[] | select(.key >= $cutoff and .key != $today) | .value] | add // 0
')
YEARLY_COST=$(echo "$DAILY_COST + $YEARLY_HISTORY" | bc)

# Save if history was updated with newly calculated past days
if [ "$HISTORY_UPDATED" = true ]; then
    write_json_file "$DATA_FILE" "$DATA"
fi

# Format costs
SESSION_FMT=$(printf "%.2f" "$SESSION_COST")
DAILY_FMT=$(printf "%.0f" "$DAILY_COST")
YEARLY_FMT=$(printf "%.0f" "$YEARLY_COST")
WEEKLY_FMT=$(printf "%.0f" "$WEEKLY_COST")
MONTHLY_FMT=$(printf "%.0f" "$MONTHLY_COST")

# ===== BUILD OUTPUT =====
OUTPUT=""

# Model
OUTPUT+="${CYAN}🤖 ${MODEL}${RESET}"

# Progress bar + percentage (context)
OUTPUT+=" ${DIM}[${RESET}${CTX_STYLE}${CTX_COLOR}${BAR}${RESET}${DIM}]${RESET} ${CTX_STYLE}${CTX_COLOR}${PERCENT}%${RESET}"

# Project name (if available)
if [ -n "$PROJECT_NAME" ]; then
    OUTPUT+=" ${BLUE}📁 ${PROJECT_NAME}${RESET}"
fi

# Git branch (if available)
if [ -n "$GIT_BRANCH" ]; then
    OUTPUT+=" ${GREEN}🌿 ${GIT_BRANCH}${RESET}"
fi

# Costs: s=session, d=day, w=week, m=month, y=year
OUTPUT+=" ${DIM}💰 s${RESET} ${YELLOW}\$${SESSION_FMT}${RESET} ${DIM}· d${RESET} ${MAGENTA}\$${DAILY_FMT}${RESET} ${DIM}· w${RESET} ${MAGENTA}\$${WEEKLY_FMT}${RESET} ${DIM}· m${RESET} ${MAGENTA}\$${MONTHLY_FMT}${RESET} ${DIM}· y${RESET} ${MAGENTA}\$${YEARLY_FMT}${RESET}"

# Time
OUTPUT+=" ${DIM}🕐 ${CURRENT_TIME}${RESET}"

echo -e "$OUTPUT"
