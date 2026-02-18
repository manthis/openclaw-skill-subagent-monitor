#!/usr/bin/env bash
# subagent-monitor.sh — Monitor active OpenClaw subagents
# Requires: openclaw CLI, jq
set -euo pipefail

# Defaults (overridable via env)
FORMAT="${SUBAGENT_MONITOR_FORMAT:-table}"
ALERT_LONG="${SUBAGENT_MONITOR_ALERT_LONG:-10}"
WATCH_INTERVAL="${SUBAGENT_MONITOR_WATCH_INTERVAL:-5}"
SORT_BY="time"
FILTER_MODEL=""
WATCH_MODE=false

usage() {
  cat <<EOF
Usage: subagent-monitor.sh [OPTIONS]

Options:
  --format [table|json|compact]   Output format (default: table)
  --watch [seconds]               Watch mode with refresh interval (default: 5)
  --alert-long [minutes]          Alert if runtime > threshold (default: 10)
  --sort [time|model|label]       Sort order (default: time)
  --filter-model [sonnet|opus|codex]  Filter by model
  -h, --help                      Show this help

Environment variables:
  SUBAGENT_MONITOR_FORMAT         Default format
  SUBAGENT_MONITOR_ALERT_LONG     Default alert threshold (minutes)
  SUBAGENT_MONITOR_WATCH_INTERVAL Default watch interval (seconds)
EOF
  exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)   FORMAT="${2:-table}"; shift 2 ;;
    --watch)    WATCH_MODE=true; [[ "${2:-}" =~ ^[0-9]+$ ]] && { WATCH_INTERVAL="$2"; shift; }; shift ;;
    --alert-long) ALERT_LONG="${2:-10}"; shift 2 ;;
    --sort)     SORT_BY="${2:-time}"; shift 2 ;;
    --filter-model) FILTER_MODEL="${2:-}"; shift 2 ;;
    -h|--help)  usage ;;
    *)          echo "Unknown option: $1"; usage ;;
  esac
done

# Emoji helpers
emoji_status() {
  case "$1" in
    running)   echo "✅" ;;
    waiting)   echo "⏸️" ;;
    error|failed) echo "❌" ;;
    done|completed) echo "✔️" ;;
    *)         echo "🔄" ;;
  esac
}

emoji_model() {
  case "$1" in
    opus)   echo "🎭" ;;
    sonnet) echo "🎯" ;;
    codex)  echo "🔧" ;;
    haiku)  echo "🪶" ;;
    *)      echo "🤖" ;;
  esac
}

emoji_progress() {
  local pct="$1"
  if [[ "$pct" == "null" ]]; then
    echo "🔄"
  elif (( pct <= 33 )); then
    echo "🟢"
  elif (( pct <= 66 )); then
    echo "🟡"
  elif (( pct < 100 )); then
    echo "🟠"
  else
    echo "✅"
  fi
}

emoji_runtime() {
  local s="$1"
  if (( s < 60 )); then
    echo "⚡"
  elif (( s < 300 )); then
    echo "⏱️"
  elif (( s < 900 )); then
    echo "⏳"
  else
    echo "⚠️"
  fi
}

# Format seconds to human readable
fmt_duration() {
  local s="$1"
  if (( s >= 3600 )); then
    printf "%dh%dm%ds" $((s/3600)) $((s%3600/60)) $((s%60))
  elif (( s >= 60 )); then
    printf "%dm%ds" $((s/60)) $((s%60))
  else
    printf "%ds" "$s"
  fi
}

# Fetch subagent data via openclaw CLI
fetch_data() {
  local raw
  raw=$(openclaw sessions list --json 2>/dev/null || echo '[]')
  echo "$raw" | jq -r '
    [.[] | select(.key | test("subagent"))] // []
  ' 2>/dev/null || echo '[]'
}

# Build enriched JSON
build_json() {
  local now
  now=$(date +%s)
  local sessions
  sessions=$(fetch_data)

  local count
  count=$(echo "$sessions" | jq 'length')

  local subagents="[]"
  if (( count > 0 )); then
    subagents=$(echo "$sessions" | jq --argjson now "$now" '
      [.[] | {
        label: (.label // (.key | split(":") | last | .[0:20])),
        model: (.model // "unknown"),
        session_key: .key,
        started_at: (.startedAt // .createdAt // 0),
        status: (if .status then .status else "running" end)
      } | . + {
        runtime_sec: (if .started_at > 0 then ($now - (.started_at | if type == "string" then (. | split(".")[0] + "Z" | fromdateiso8601) else . end)) else 0 end),
        model_alias: (
          if (.model | test("opus")) then "opus"
          elif (.model | test("sonnet")) then "sonnet"
          elif (.model | test("codex")) then "codex"
          elif (.model | test("haiku")) then "haiku"
          else "other" end
        ),
        model_friendly: (
          if (.model | test("opus-4-6|opus-4.6")) then "Opus 4.6"
          elif (.model | test("opus-4-5|opus-4.5")) then "Opus 4.5"
          elif (.model | test("opus")) then "Opus"
          elif (.model | test("sonnet-4-6|sonnet-4.6")) then "Sonnet 4.6"
          elif (.model | test("sonnet-4-5|sonnet-4.5")) then "Sonnet 4.5"
          elif (.model | test("sonnet")) then "Sonnet"
          elif (.model | test("codex")) then "Codex"
          else .model end
        )
      } | . + {
        progress_pct: (if .runtime_sec > 0 then ([(.runtime_sec * 100 / 900), 95] | min | floor) else null end)
      } | . + {
        emoji: {
          status: (if .status == "running" then "✅" elif .status == "waiting" then "⏸️" elif (.status == "error" or .status == "failed") then "❌" else "🔄" end),
          model: (if .model_alias == "opus" then "🎭" elif .model_alias == "sonnet" then "🎯" elif .model_alias == "codex" then "🔧" elif .model_alias == "haiku" then "🪶" else "🤖" end),
          progress: (if .progress_pct == null then "🔄" elif .progress_pct <= 33 then "🟢" elif .progress_pct <= 66 then "🟡" elif .progress_pct < 100 then "🟠" else "✅" end),
          runtime: (if .runtime_sec < 60 then "⚡" elif .runtime_sec < 300 then "⏱️" elif .runtime_sec < 900 then "⏳" else "⚠️" end)
        }
      }]
    ' 2>/dev/null || echo '[]')
  fi

  # Apply model filter
  if [[ -n "$FILTER_MODEL" ]]; then
    subagents=$(echo "$subagents" | jq --arg f "$FILTER_MODEL" '
      [.[] | select(.model_alias == $f)]
    ')
  fi

  # Apply sort
  case "$SORT_BY" in
    time)  subagents=$(echo "$subagents" | jq 'sort_by(-.runtime_sec)') ;;
    model) subagents=$(echo "$subagents" | jq 'sort_by(.model_alias)') ;;
    label) subagents=$(echo "$subagents" | jq 'sort_by(.label)') ;;
  esac

  local total
  total=$(echo "$subagents" | jq 'length')

  local by_model
  by_model=$(echo "$subagents" | jq '{
    opus: [.[] | select(.model_alias == "opus")] | length,
    sonnet: [.[] | select(.model_alias == "sonnet")] | length,
    codex: [.[] | select(.model_alias == "codex")] | length,
    other: [.[] | select(.model_alias | test("opus|sonnet|codex") | not)] | length
  }')

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson total "$total" \
    --argjson by_model "$by_model" \
    --argjson subagents "$subagents" \
    '{timestamp: $ts, total: $total, by_model: $by_model, subagents: $subagents}'
}

# Render table
render_table() {
  local data="$1"
  local total
  total=$(echo "$data" | jq '.total')

  if (( total == 0 )); then
    echo "📭 No active subagents."
    return
  fi

  # Header
  printf "┌─────────────────────┬──────────────────┬─────────────┬────────────┬────────────┐\n"
  printf "│ 🏷️  %-16s │ 🤖 %-13s │ 📈 %-8s │ ⏱️  %-7s │ %-9s │\n" "Label" "Model" "Progress" "Time" "Status"
  printf "├─────────────────────┼──────────────────┼─────────────┼────────────┼────────────┤\n"

  echo "$data" | jq -r '.subagents[] | [.label, .model_friendly, .model_alias, (.progress_pct | tostring), (.runtime_sec | tostring), .status] | @tsv' | \
  while IFS=$'\t' read -r label model_friendly model_alias progress runtime status; do
    label="${label:0:16}"

    # Model with emoji
    local me
    me=$(emoji_model "$model_alias")
    local model_str="${me} ${model_friendly:0:12}"

    # Progress with emoji
    local pe prog
    pe=$(emoji_progress "$progress")
    if [[ "$progress" == "null" ]]; then
      prog="${pe} Running…"
    else
      prog="${pe} ~${progress}%"
    fi

    # Runtime with emoji
    local re rt
    re=$(emoji_runtime "$runtime")
    rt="${re} $(fmt_duration "$runtime")"

    # Status with emoji
    local se
    se=$(emoji_status "$status")
    local status_str="${se} ${status^}"

    printf "│ %-19s │ %-16s │ %-11s │ %-10s │ %-10s │\n" "$label" "$model_str" "$prog" "$rt" "$status_str"
  done

  printf "└─────────────────────┴──────────────────┴─────────────┴────────────┴────────────┘\n"

  # Summary
  local opus sonnet codex
  opus=$(echo "$data" | jq '.by_model.opus')
  sonnet=$(echo "$data" | jq '.by_model.sonnet')
  codex=$(echo "$data" | jq '.by_model.codex')
  echo ""
  echo "📊 ${total} active subagent(s) • 🎭 ${opus} Opus • 🎯 ${sonnet} Sonnet • 🔧 ${codex} Codex"
}

# Render compact
render_compact() {
  local data="$1"
  local total
  total=$(echo "$data" | jq '.total')

  if (( total == 0 )); then
    echo "📭 No active subagents."
    return
  fi

  echo "$data" | jq -r '.subagents[] | [.status, .label, .model_alias, .model_friendly, (.progress_pct | tostring), (.runtime_sec | tostring)] | @tsv' | \
  while IFS=$'\t' read -r status label model_alias model_friendly progress runtime; do
    local se me pe re
    se=$(emoji_status "$status")
    me=$(emoji_model "$model_alias")
    pe=$(emoji_progress "$progress")
    re=$(emoji_runtime "$runtime")

    local prog_str
    if [[ "$progress" == "null" ]]; then
      prog_str="Running…"
    else
      prog_str="${pe} ${progress}%"
    fi

    echo "${se} ${label} [${me} ${model_friendly}] ${prog_str} ${re} $(fmt_duration "$runtime")"
  done

  echo "---"
  echo "📊 ${total} active"
}

# Check for long-running alerts
check_alerts() {
  local data="$1"
  local threshold_sec=$(( ALERT_LONG * 60 ))

  local alerts
  alerts=$(echo "$data" | jq --argjson t "$threshold_sec" '
    [.subagents[] | select(.runtime_sec > $t)]
  ')

  local count
  count=$(echo "$alerts" | jq 'length')

  if (( count > 0 )); then
    echo ""
    echo "🚨 ALERT: ${count} subagent(s) running longer than ${ALERT_LONG}min:"
    echo "$alerts" | jq -r '.[] | "  ⚠️  \(.label) [\(.model_friendly)] running for \(.runtime_sec)s"'
  fi
}

# Main render
render() {
  local data
  data=$(build_json)

  case "$FORMAT" in
    json)    echo "$data" | jq '.' ;;
    compact) render_compact "$data" ;;
    *)       render_table "$data" ;;
  esac

  check_alerts "$data"
}

# Run
if $WATCH_MODE; then
  while true; do
    clear
    echo "🔍 Subagent Monitor (refresh: ${WATCH_INTERVAL}s) — $(date '+%H:%M:%S')"
    echo ""
    render
    sleep "$WATCH_INTERVAL"
  done
else
  render
fi
