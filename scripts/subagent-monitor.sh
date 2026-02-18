#!/usr/bin/env bash
# subagent-monitor.sh — Monitor active OpenClaw subagents
# Requires: openclaw CLI, jq
#
# Performance notes:
# - Emoji logic moved into single jq expression (was N shell function calls)
# - build_json does all enrichment in one jq pipeline
# - Reduced from ~15 jq calls to 3-4 total

set -euo pipefail

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

# Build enriched JSON — single jq pipeline does all enrichment + emoji assignment
build_json() {
  local now
  now=$(date +%s)
  local raw
  raw=$(openclaw sessions list --json 2>/dev/null || echo '[]')

  echo "$raw" | jq --argjson now "$now" \
    --arg filter "$FILTER_MODEL" \
    --arg sort_by "$SORT_BY" '
    # Filter to subagent sessions
    [.[] | select(.key | test("subagent"))] // [] |

    # Enrich each subagent
    [.[] | {
      label: (.label // (.key | split(":") | last | .[0:20])),
      model: (.model // "unknown"),
      session_key: .key,
      started_at: (.startedAt // .createdAt // 0),
      status: (.status // "running")
    } | . + {
      runtime_sec: (if .started_at > 0 then
        ($now - (if (.started_at | type) == "string" then
          (.started_at | split(".")[0] + "Z" | fromdateiso8601)
        else .started_at end))
      else 0 end),
      model_alias: (
        if (.model | test("opus")) then "opus"
        elif (.model | test("sonnet")) then "sonnet"
        elif (.model | test("codex")) then "codex"
        elif (.model | test("haiku")) then "haiku"
        else "other" end),
      model_friendly: (
        if (.model | test("opus-4-6|opus-4.6")) then "Opus 4.6"
        elif (.model | test("opus-4-5|opus-4.5")) then "Opus 4.5"
        elif (.model | test("opus")) then "Opus"
        elif (.model | test("sonnet-4-6|sonnet-4.6")) then "Sonnet 4.6"
        elif (.model | test("sonnet-4-5|sonnet-4.5")) then "Sonnet 4.5"
        elif (.model | test("sonnet")) then "Sonnet"
        elif (.model | test("codex")) then "Codex"
        else .model end)
    } | . + {
      progress_pct: (if .runtime_sec > 0 then ([(.runtime_sec * 100 / 900), 95] | min | floor) else null end)
    } | . + {
      emoji: {
        status: ({"running":"✅","waiting":"⏸️","error":"❌","failed":"❌","done":"✔️","completed":"✔️"}[.status] // "🔄"),
        model: ({"opus":"🎭","sonnet":"🎯","codex":"🔧","haiku":"🪶"}[.model_alias] // "🤖"),
        progress: (if .progress_pct == null then "🔄"
          elif .progress_pct <= 33 then "🟢"
          elif .progress_pct <= 66 then "🟡"
          elif .progress_pct < 100 then "🟠"
          else "✅" end),
        runtime: (if .runtime_sec < 60 then "⚡"
          elif .runtime_sec < 300 then "⏱️"
          elif .runtime_sec < 900 then "⏳"
          else "⚠️" end)
      }
    }] |

    # Apply model filter
    if $filter != "" then [.[] | select(.model_alias == $filter)] else . end |

    # Apply sort
    (if $sort_by == "model" then sort_by(.model_alias)
     elif $sort_by == "label" then sort_by(.label)
     else sort_by(-.runtime_sec) end) |

    # Build final output
    . as $subagents | {
      timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      total: ($subagents | length),
      by_model: {
        opus: [$subagents[] | select(.model_alias == "opus")] | length,
        sonnet: [$subagents[] | select(.model_alias == "sonnet")] | length,
        codex: [$subagents[] | select(.model_alias == "codex")] | length,
        other: [$subagents[] | select(.model_alias | test("opus|sonnet|codex") | not)] | length
      },
      subagents: $subagents
    }
  '
}

render_table() {
  local data="$1"
  local total
  total=$(echo "$data" | jq '.total')

  if (( total == 0 )); then
    echo "📭 No active subagents."
    return
  fi

  printf "┌─────────────────────┬──────────────────┬─────────────┬────────────┬────────────┐\n"
  printf "│ 🏷️  %-16s │ 🤖 %-13s │ 📈 %-8s │ ⏱️  %-7s │ %-9s │\n" "Label" "Model" "Progress" "Time" "Status"
  printf "├─────────────────────┼──────────────────┼─────────────┼────────────┼────────────┤\n"

  # Single jq call extracts all display data
  echo "$data" | jq -r '.subagents[] | [
    .label[0:16],
    .emoji.model, .model_friendly[0:12],
    .emoji.progress, (.progress_pct | tostring),
    .emoji.runtime, (.runtime_sec | tostring),
    .emoji.status, (.status | split("") | .[0:1] | .[0] | ascii_upcase) + (.status[1:])
  ] | @tsv' | \
  while IFS=$'\t' read -r label me model_friendly pe progress re runtime se status; do
    local prog
    if [[ "$progress" == "null" ]]; then
      prog="${pe} Running…"
    else
      prog="${pe} ~${progress}%"
    fi
    local rt="${re} $(fmt_duration "$runtime")"

    printf "│ %-19s │ %-16s │ %-11s │ %-10s │ %-10s │\n" \
      "$label" "${me} ${model_friendly}" "$prog" "$rt" "${se} ${status}"
  done

  printf "└─────────────────────┴──────────────────┴─────────────┴────────────┴────────────┘\n"

  # Summary — extract from already-computed data
  echo "$data" | jq -r '"
📊 \(.total) active subagent(s) • 🎭 \(.by_model.opus) Opus • 🎯 \(.by_model.sonnet) Sonnet • 🔧 \(.by_model.codex) Codex"'
}

render_compact() {
  local data="$1"
  local total
  total=$(echo "$data" | jq '.total')

  if (( total == 0 )); then
    echo "📭 No active subagents."
    return
  fi

  echo "$data" | jq -r '.subagents[] | "\(.emoji.status) \(.label) [\(.emoji.model) \(.model_friendly)] \(if .progress_pct == null then "Running…" else "\(.emoji.progress) \(.progress_pct)%" end) \(.emoji.runtime) \(.runtime_sec)s"' | \
  while IFS= read -r line; do
    # Extract runtime_sec from end for fmt_duration
    echo "$line"
  done

  echo "---"
  echo "📊 ${total} active"
}

check_alerts() {
  local data="$1"
  local threshold_sec=$(( ALERT_LONG * 60 ))

  echo "$data" | jq -r --argjson t "$threshold_sec" '
    [.subagents[] | select(.runtime_sec > $t)] |
    if length > 0 then
      "\n🚨 ALERT: \(length) subagent(s) running longer than \($t / 60 | floor)min:",
      (.[] | "  ⚠️  \(.label) [\(.model_friendly)] running for \(.runtime_sec)s")
    else empty end
  '
}

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
