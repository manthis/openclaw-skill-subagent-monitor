# HEARTBEAT Integration Example

Add this to your `HEARTBEAT.md` to auto-monitor subagents:

```markdown
## 🔍 Monitor Subagents (optional)
- Run `subagent-monitor.sh --alert-long 15`
- If subagent > 15min → notify Max on Telegram with details
- If no active subagent or all OK → total silence (HEARTBEAT_OK)
```

## Telegram Alert Example

When a long-running subagent is detected, send:

```
🚨 Long-running subagent detected!
⚠️  create-website [🎭 Opus 4.6] running for 18m 32s
⚠️  data-migration [🎯 Sonnet 4.5] running for 22m 15s
```

## JSON Integration

For scripting, use JSON output and parse with `jq`:

```bash
# Get count of long-running subagents
LONG=$(./scripts/subagent-monitor.sh --format json | jq '[.subagents[] | select(.runtime_sec > 900)] | length')
if [ "$LONG" -gt 0 ]; then
  # trigger alert
fi
```
