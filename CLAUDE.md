# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash script that provides a real-time statusline for Claude Code CLI. It displays model info, context window usage (with traffic-light colors), project/git info, cost tracking (session/daily/weekly/monthly/yearly), and current time.

## Architecture

**Single-file project**: `statusline.sh` is a self-contained Bash script (~365 lines).

### Key Components

1. **Input Parsing** (lines 78-100): Reads JSON from stdin provided by Claude Code's StatusLine hook
2. **Context Calculation** (lines 102-132): Computes remaining context % and applies traffic-light coloring
3. **Cost Tracking** (lines 134-331):
   - Session cost: Direct from Claude Code's `total_cost_usd`
   - Daily aggregates: Parsed from JSONL transcript files in `~/.claude/projects/`
   - Historical costs: Cached in `~/.claude/statusline_data.json`
4. **JSONL Parsing** (lines 152-226): jq logic that groups by `requestId`, deduplicates by `uuid`, and applies Claude pricing
5. **Output Rendering** (lines 340-365): Builds the formatted statusline with ANSI colors

### Data Flow

```
Claude Code → JSON stdin → statusline.sh → parse input → calculate costs → render output
                                              ↓
                                        ~/.claude/statusline_data.json (cache)
                                              ↓
                                        ~/.claude/projects/*/*.jsonl (read-only)
```

### Concurrency

- Uses `flock` for file locking when multiple Claude Code instances run
- Atomic writes via temp file + mv pattern

## Development

### Testing Locally

```bash
# Run with sample input
echo '{"model":{"display_name":"Opus 4.5"},"session_id":"test","cost":{"total_cost_usd":1.5},"context_window":{"context_window_size":200000,"total_input_tokens":50000,"total_output_tokens":10000}}' | ./statusline.sh
```

### Dependencies

- `jq` - JSON processor (required)
- `bc` - Calculator for cost math (required)
- `flock` - File locking (optional, for concurrency safety)

### Configuration

Timezone is set at line 17:
```bash
export TZ="Europe/Athens"
```

### Pricing Constants

Claude 4.5 pricing (per million tokens) is defined in the jq filter at lines 158-167:
- Opus: $5 input, $25 output, $0.50 cache read, $6.25 cache write
- Sonnet: $3 input, $15 output, $0.30 cache read, $3.75 cache write
- Haiku: $1 input, $5 output, $0.10 cache read, $1.25 cache write

### Reset Cost Data

```bash
rm ~/.claude/statusline_data.json
```
