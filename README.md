# Claude Code Statusline

A beautiful, feature-rich statusline for Claude Code CLI with real-time context tracking, cost monitoring, and git integration.

![Bash](https://img.shields.io/badge/Bash-4.0+-green)
![License](https://img.shields.io/badge/License-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-2.0+-purple)

## Preview

```
🤖 Opus 4.5 [████████░░] 78% 📁 my-project 🌿 feature/auth 💰 s $1.50 · d $45 · w $120 · m $340 · y $1.2k 🕐 14:32
```

## Features

- **🤖 Model Display** - Shows current Claude model (Opus, Sonnet, Haiku)
- **📊 Context Progress Bar** - Visual 10-segment bar showing remaining context
- **🚦 Traffic Light Colors** - Green (>50%), Yellow (25-50%), Red (<25%), Blinking (<10%)
- **📁 Project Name** - Current project directory
- **🌿 Git Branch** - Active git branch (when in a repo)
- **💰 Cost Tracking** - Session, daily, weekly, monthly, and yearly costs
- **🕐 Current Time** - Live clock display

## Installation

### Quick Install (curl)

```bash
# Download the script
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/charistas/claude-code-statusline/main/statusline.sh

# Make it executable
chmod +x ~/.claude/statusline.sh
```

### Manual Install

1. Copy `statusline.sh` to `~/.claude/statusline.sh`
2. Make it executable: `chmod +x ~/.claude/statusline.sh`

### Configure Claude Code

Add to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "StatusLine": [
      {
        "type": "command",
        "command": "~/.claude/statusline.sh"
      }
    ]
  }
}
```

## Dependencies

- `jq` - JSON processor (required)
- `bc` - Calculator for cost math (required)
- `flock` - File locking for parallel instances (optional, recommended)
- `git` - For branch display (optional)

### Install Dependencies

**macOS:**
```bash
brew install jq bc flock
```

**Ubuntu/Debian:**
```bash
sudo apt install jq bc
# flock is usually pre-installed
```

## How It Works

### Context Tracking

The statusline reads Claude Code's JSON input which includes context window information:

| Context Remaining | Color | Style |
|-------------------|-------|-------|
| > 50% | 🟢 Green | Normal |
| 25-50% | 🟡 Yellow | Normal |
| 10-25% | 🔴 Red | Bold |
| < 10% | 🔴 Red | Bold + Blinking |

### Cost Tracking

Costs are displayed with compact labels:

| Label | Meaning | Period |
|-------|---------|--------|
| **s** | Session | Current session (real-time from Claude Code) |
| **d** | Day | Calendar day (today) |
| **w** | Week | Calendar week (Monday-Sunday) |
| **m** | Month | Calendar month (1st to today) |
| **y** | Year | Calendar year (Jan 1 to today) |

#### How It Works

- **Session cost**: Comes directly from Claude Code's `total_cost_usd` (100% accurate)
- **Daily aggregates**: Calculated from JSONL transcript files in `~/.claude/projects/` (~90% accurate)
- **Historical costs**: Cached in `~/.claude/statusline_data.json` for fast access

#### JSONL Parsing

The script parses Claude Code's transcript files directly:

1. **Filters**: Excludes sidechain and API error entries
2. **Deduplication**: Groups by `requestId`, takes MAX of each token type (correctly handles streaming responses where token counts are cumulative)
3. **Pricing**: Applies Claude 4.5 rates per million tokens

#### Pricing (Claude 4.5)

| Model | Input | Output | Cache Read | Cache Write |
|-------|-------|--------|------------|-------------|
| Opus | $5 | $25 | $0.50 | $6.25 |
| Sonnet | $3 | $15 | $0.30 | $3.75 |
| Haiku | $1 | $5 | $0.10 | $1.25 |

#### Accuracy

| Metric | Accuracy | Notes |
|--------|----------|-------|
| Session cost | 100% | Direct from Claude Code |
| Daily/Weekly/Monthly/Yearly | ~90% | JSONL parsing excludes sidechains |

The ~10% variance is due to sidechain operations being excluded to avoid potential double-counting.

### Concurrency Safety

- **File locking**: Uses `flock` (if available) to prevent race conditions when multiple Claude Code instances run simultaneously
- **Atomic writes**: Uses temp file + mv pattern to prevent data corruption

### Performance

- Historical costs are calculated once and cached forever
- Today's cost is always calculated fresh from JSONL
- Typical execution time: ~0.4 seconds

## Customization

### Timezone

Edit the timezone at the top of `statusline.sh`:

```bash
export TZ="Europe/Athens"  # Change to your timezone
```

### Modify Colors

Edit the color variables:

```bash
CYAN="\033[36m"     # Model name
GREEN="\033[32m"    # Git branch, healthy context
YELLOW="\033[33m"   # Warning context, session cost
RED="\033[31m"      # Critical context
MAGENTA="\033[35m"  # Daily/weekly/monthly costs
BLUE="\033[34m"     # Project name
DIM="\033[90m"      # Labels
```

## Data Storage

| File | Purpose |
|------|---------|
| `~/.claude/statusline_data.json` | Cached daily costs and session baselines |
| `~/.claude/projects/*/*.jsonl` | Claude Code transcript files (read-only) |

### Data Structure

```json
{
  "days": {
    "2026-01-12": {
      "baselines": { "session-id": 10.50 },
      "sessions": { "session-id": 5.50 },
      "total": 5.50
    }
  },
  "history": {
    "2026-01-11": 31.50,
    "2026-01-10": 28.75
  }
}
```

- **days**: Today's session tracking with baselines (for sessions spanning midnight)
- **history**: Archived daily costs (calculated from JSONL, cached permanently)

### Reset Cost Data

```bash
rm ~/.claude/statusline_data.json
```

## Troubleshooting

### Statusline not appearing

1. Check the script is executable: `ls -la ~/.claude/statusline.sh`
2. Verify settings.json has the correct path
3. Restart Claude Code

### Costs showing $0

- Ensure JSONL files exist in `~/.claude/projects/`
- Check `jq` is installed: `which jq`
- Try running manually: `echo '{}' | ~/.claude/statusline.sh`

### Git branch not showing

- Verify you're in a git repository
- Check git is installed: `which git`

### Parse errors in output

- May occur with malformed JSONL entries
- The script handles these gracefully but may show stderr
- Consider redirecting: `~/.claude/statusline.sh 2>/dev/null`

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built for use with [Claude Code](https://claude.ai/code) by Anthropic
- Validated against [ccusage](https://github.com/ryoppippi/ccusage) for accuracy

---

**Found this useful?** Give it a star on GitHub!
