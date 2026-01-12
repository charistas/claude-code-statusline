# Claude Code Statusline

A beautiful, feature-rich statusline for Claude Code CLI with real-time context tracking, cost monitoring, and git integration.

![Bash](https://img.shields.io/badge/Bash-4.0+-green)
![License](https://img.shields.io/badge/License-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-2.0+-purple)

## Preview

```
🤖 Opus [████████░░] 78% 📁 my-project 🌿 feature/auth 💰 s $1.50 · d $45 · w $312 · m $1.2k · y $8.5k 🕐 14:32
```

## Features

- **🤖 Model Display** - Shows current Claude model (Opus, Sonnet, Haiku)
- **📊 Context Progress Bar** - Visual 10-segment bar showing remaining context
- **🚦 Traffic Light Colors** - Green (>50%), Yellow (25-50%), Red (<25%), Blinking (<10%)
- **📁 Project Name** - Current project directory
- **🌿 Git Branch** - Active git branch (when in a repo)
- **💰 Cost Tracking** - Session, daily, weekly, monthly, and yearly cost tracking with persistent history
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
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Or use the Claude Code command:
```
/config set statusLine.command ~/.claude/statusline.sh
```

## Dependencies

- `jq` - JSON processor (required)
- `bc` - Calculator for cost math (required)
- `git` - For branch display (optional)

### Install Dependencies

**macOS:**
```bash
brew install jq bc
```

**Ubuntu/Debian:**
```bash
sudo apt install jq bc
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

| Label | Meaning | Source |
|-------|---------|--------|
| **s** | Session | Current session cost from Claude Code |
| **d** | Day | Today's total (sum of all sessions) |
| **w** | Week | Last 7 days |
| **m** | Month | Last 30 days |
| **y** | Year | Last 365 days |

#### How It Works

- **Today's cost** is tracked per-session in `~/.claude/statusline_data.json`
- **Historical costs** (for w/m/y) are calculated from Claude Code's built-in `~/.claude/stats-cache.json` which tracks daily token usage per model
- **Persistent history** is archived to our data file, so yearly totals remain accurate even after stats-cache rolls off older data (~30 days)

#### Pricing Used

Costs are estimated from output token usage:
- Opus: $75 per million tokens
- Sonnet: $15 per million tokens
- Haiku: $4 per million tokens

> **Note:** These are API-equivalent estimates. If you're on a Pro/Max subscription, these don't reflect actual charges.

## Customization

### Modify Colors

Edit the color variables at the top of `statusline.sh`:

```bash
CYAN="\033[36m"     # Model name
GREEN="\033[32m"    # Git branch, healthy context
YELLOW="\033[33m"   # Warning context, session cost
RED="\033[31m"      # Critical context
MAGENTA="\033[35m"  # Daily/weekly/monthly costs
BLUE="\033[34m"     # Project name
DIM="\033[90m"      # Labels
```

### Modify Layout

The output is built in the `BUILD OUTPUT` section. Reorder or remove sections as needed:

```bash
# Example: Remove time display
# Comment out or delete these lines:
# OUTPUT+=" ${DIM}🕐 ${CURRENT_TIME}${RESET}"
```

## Data Storage

| File | Purpose | Owned By |
|------|---------|----------|
| `~/.claude/statusline_data.json` | Session costs, daily totals, persistent history | This script |
| `~/.claude/stats-cache.json` | Token usage per day per model | Claude Code |

### Data Structure

```json
{
  "days": {
    "2026-01-11": {
      "sessions": { "session-id": 5.50 },
      "total": 5.50
    }
  },
  "history": {
    "2026-01-10": 31.50,
    "2026-01-09": 28.75
  }
}
```

- **days** - Today's session tracking (resets each day)
- **history** - Archived daily costs (persists forever for yearly tracking)

### Reset Cost Data

To reset your cost tracking:

```bash
rm ~/.claude/statusline_data.json
```

> **Note:** This only resets the statusline's data. Claude Code's stats-cache.json is unaffected.

## Troubleshooting

### Statusline not appearing

1. Check the script is executable: `ls -la ~/.claude/statusline.sh`
2. Verify settings.json has the correct path
3. Restart Claude Code

### Costs showing $0

The cost data comes from Claude Code's JSON input. Ensure you're using a recent version of Claude Code (2.0+).

### Git branch not showing

- Verify you're in a git repository
- Check git is installed: `which git`

### Characters not displaying correctly

Ensure your terminal supports:
- Unicode (for emojis and progress bar)
- ANSI colors (for colored output)

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [powerline](https://github.com/powerline/powerline) and the Claude Code community
- Built for use with [Claude Code](https://claude.ai/code) by Anthropic

---

**Found this useful?** Give it a ⭐ on GitHub!
