# 🔍 openclaw-skill-subagent-monitor

An [OpenClaw](https://openclaw.io) skill to monitor active subagents in real-time.

## Features

- **Table, JSON, and compact** output formats
- **Model detection** — Opus, Sonnet, Codex, Haiku, etc.
- **Progress estimation** — heuristic-based percentage
- **Watch mode** — auto-refresh dashboard
- **Long-running alerts** — flag subagents exceeding a time threshold
- **Filtering & sorting** — by model, label, or runtime

## ⚡ Performance

Recent optimizations (2026-02-18):

- 🚀 **~70% faster** — Replaced ~15 separate `jq` calls with 1 unified pipeline using inline emoji maps
- 📉 **Reduced process spawns** — From ~15 `jq` invocations to a single pipeline for all subagent data extraction
- 🎯 **Emoji maps in jq** — Model names, status icons, progress bars, and runtime indicators all resolved inside one `jq` expression

These optimizations are especially noticeable in watch mode with frequent refreshes and many active subagents.

## Quick Start

```bash
# Clone
git clone https://github.com/manthis/openclaw-skill-subagent-monitor.git
cd openclaw-skill-subagent-monitor

# Run
./scripts/subagent-monitor.sh
```

### Requirements

- `openclaw` CLI installed and configured
- `jq` (JSON processor)

## Usage

```bash
# Table output (default)
./scripts/subagent-monitor.sh

# JSON output
./scripts/subagent-monitor.sh --format json

# Compact (one line per agent)
./scripts/subagent-monitor.sh --format compact

# Watch mode (refresh every 3s)
./scripts/subagent-monitor.sh --watch 3

# Alert if any subagent runs > 15 minutes
./scripts/subagent-monitor.sh --alert-long 15

# Filter by model
./scripts/subagent-monitor.sh --filter-model opus

# Sort by label
./scripts/subagent-monitor.sh --sort label
```

## Output Examples

### Table

```
┌─────────────────────┬──────────────────┬─────────────┬────────────┬────────────┐
│ 🏷️  Label            │ 🤖 Model         │ 📈 Progress  │ ⏱️  Time    │ Status     │
├─────────────────────┼──────────────────┼─────────────┼────────────┼────────────┤
│ ram-monitor-skill   │ 🎭 Opus 4.6      │ 🟡 ~60%     │ ⏱️ 2m33s    │ ✅ Running  │
│ morning-briefing    │ 🎭 Opus 4.6      │ 🟡 ~80%     │ ⏱️ 2m45s    │ ✅ Running  │
│ create-website      │ 🎯 Sonnet 4.5    │ 🟡 ~40%     │ ⏳ 8m12s    │ ✅ Running  │
└─────────────────────┴──────────────────┴─────────────┴────────────┴────────────┘

📊 3 active subagent(s) • 🎭 2 Opus • 🎯 1 Sonnet • 🔧 0 Codex
```

### Emoji Legend

| Category | Emoji | Meaning |
|----------|-------|---------|
| Status | ✅ ⏸️ ❌ ✔️ | Running, Waiting, Error, Done |
| Model | 🎭 🎯 🔧 🪶 | Opus, Sonnet, Codex, Haiku |
| Progress | 🟢 🟡 🟠 ✅ | 0-33%, 34-66%, 67-99%, 100% |
| Runtime | ⚡ ⏱️ ⏳ ⚠️ | <1m, 1-5m, 5-15m, >15m |

### JSON

JSON stays machine-readable but includes an `emoji` object per subagent:

```json
{
  "timestamp": "2026-02-18T20:50:00Z",
  "total": 3,
  "by_model": { "opus": 2, "sonnet": 1, "codex": 0, "other": 0 },
  "subagents": [
    {
      "label": "ram-monitor-skill",
      "model": "anthropic/claude-opus-4-6",
      "model_alias": "opus",
      "model_friendly": "Opus 4.6",
      "progress_pct": 60,
      "runtime_sec": 153,
      "status": "running",
      "session_key": "agent:main:subagent:abc123",
      "emoji": { "status": "✅", "model": "🎭", "progress": "🟡", "runtime": "⏱️" }
    }
  ]
}
```

### Compact

```
✅ ram-monitor-skill [🎭 Opus 4.6] 🟡 60% ⏱️ 2m33s
✅ morning-briefing [🎭 Opus 4.6] 🟠 80% ⏱️ 2m45s
✅ create-website [🎯 Sonnet 4.5] 🟡 40% ⏳ 8m12s
---
📊 3 active
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `SUBAGENT_MONITOR_FORMAT` | `table` | Output format |
| `SUBAGENT_MONITOR_ALERT_LONG` | `10` | Alert threshold (minutes) |
| `SUBAGENT_MONITOR_WATCH_INTERVAL` | `5` | Watch refresh (seconds) |

## HEARTBEAT Integration

Add to your `HEARTBEAT.md`:

```markdown
## Monitor Subagents
- Run `subagent-monitor.sh --alert-long 15`
- If any alert → notify on Telegram
- If all OK → silence
```

## License

MIT
