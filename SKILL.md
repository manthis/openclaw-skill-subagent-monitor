# Skill: Subagent Monitor

Monitor active OpenClaw subagents with real-time status, model info, progress estimation, and alerts.

## Commands

### `subagent-monitor.sh`

Monitor active subagents.

**Arguments:**
| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--format` | `table`, `json`, `compact` | `table` | Output format |
| `--watch` | `[seconds]` | `5` | Watch mode with refresh |
| `--alert-long` | `[minutes]` | `10` | Alert if runtime exceeds threshold |
| `--sort` | `time`, `model`, `label` | `time` | Sort order |
| `--filter-model` | `sonnet`, `opus`, `codex` | — | Filter by model family |

**Environment variables:**
- `SUBAGENT_MONITOR_FORMAT` — default format
- `SUBAGENT_MONITOR_ALERT_LONG` — alert threshold in minutes
- `SUBAGENT_MONITOR_WATCH_INTERVAL` — watch refresh in seconds

**Dependencies:** `openclaw` CLI, `jq`

## Usage Examples

```bash
# Quick check
./scripts/subagent-monitor.sh

# JSON for scripting
./scripts/subagent-monitor.sh --format json

# Watch mode
./scripts/subagent-monitor.sh --watch 3

# Alert on long-running (>15min)
./scripts/subagent-monitor.sh --alert-long 15

# Filter Opus only, sort by label
./scripts/subagent-monitor.sh --filter-model opus --sort label
```

## Integration

Use in HEARTBEAT.md to auto-check subagent health:

```markdown
## Monitor Subagents
- Run `subagent-monitor.sh --alert-long 15`
- If any alert → notify on Telegram
- If all OK → silence
```

## Progress Estimation

Progress is estimated heuristically (no native API):
- Based on elapsed time vs assumed 15min timeout
- Capped at 95% (never shows 100% while running)
- Shows "Running…" if no estimate possible
